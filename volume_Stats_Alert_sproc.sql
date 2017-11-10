USE DBAHound;
go

/*
USE DBAHound;
GO

CREATE TABLE [dbo].[VolumeStats](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[volume_mount_point] [nvarchar](512) NULL,
	[file_system_type] [nvarchar](512) NULL,
	[logical_volume_name] [nvarchar](512) NULL,
	[Total_Size] [float] NULL,
	[Available_Size] [float] NULL,
	[Space_Free] [float] NULL,
	[DateTimeStamp] [datetime2](7) NULL,
 CONSTRAINT [PK_VolumeStats] PRIMARY KEY CLUSTERED 
(	[ID] ASC)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
*/

CREATE PROCEDURE usp_GetVolumeStats
@Threshold int
AS
BEGIN

if object_id('tempdb..#VolumeStats') is not null begin drop table #VolumeStats end;
Create table #VolumeStats
(ID int identity(1,1),
volume_mount_point nvarchar(512),
file_system_type nvarchar(512),
logical_volume_name nvarchar(512),
Total_Size float,
Available_Size float,
Space_Free float,
DateTimePerformed datetime2
)


DECLARE @TimeStamp datetime2 = getdate()
DECLARE VolumeInfo cursor
FOR 
SELECT DISTINCT vs.volume_mount_point, vs.file_system_type, 
vs.logical_volume_name, CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
CONVERT(DECIMAL(18,2), vs.available_bytes/1073741824.0) AS [Available Size (GB)],  
CONVERT(DECIMAL(18,2), vs.available_bytes * 1. / vs.total_bytes * 100.) AS [Space Free %],
@TimeStamp
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs

DECLARE @volume nvarchar(512),@file_system_type nvarchar(512),@logical_name nvarchar(512)
DECLARE @TotalSize float,@AvailableSize float, @percent float
DECLARE @MyTime datetime2

OPEN VolumeInfo

FETCH NEXT FROM VolumeInfo INTO @volume,@file_system_type,@logical_name,@TotalSize,@AvailableSize,@percent,@MyTime
WHILE (@@FETCH_STATUS <> -1)
BEGIN

if @percent > 20 
BEGIN
    INSERT INTO dbo.VolumeStats(volume_mount_point,file_system_type,logical_volume_name,Total_Size,Available_Size,Space_Free,DateTimeStamp)
    values(@volume,@file_system_type,@logical_name,@TotalSize,@AvailableSize,@percent,@TimeStamp)
    insert into #VolumeStats(volume_mount_point,file_system_type,logical_volume_name,Total_Size,Available_Size,Space_Free,DateTimePerformed)
    VALUES(@volume,@file_system_type,@logical_name,@TotalSize,@AvailableSize,@percent,@TimeStamp)
END
else
BEGIN
    INSERT INTO dbo.VolumeStats(volume_mount_point,file_system_type,logical_volume_name,Total_Size,Available_Size,Space_Free,DateTimeStamp)
    values(@volume,@file_system_type,@logical_name,@TotalSize,@AvailableSize,@percent,@TimeStamp)

END

FETCH NEXT FROM VolumeInfo INTO @volume,@file_system_type,@logical_name,@TotalSize,@AvailableSize,@percent,@Mytime
END
CLOSE VolumeInfo
DEALLOCATE VolumeInfo

if (SELECT COUNT(*) FROM #VolumeStats) > 0
DECLARE @tableHTML  NVARCHAR(MAX) ;  
  
SET @tableHTML =  
    N'<h2>Server: ' + @@SERVERNAME + '</h2>' +
    N'<H3>Drive Space Alert</H3>' +  
    N'<table border="1">' +  
    N'<tr><th>Volume</th><th>File Sytem Type</th>' +  
    N'<th>Logical Name</th><th>Total Size</th><th>Available Size</th>' +  
    N'<th>Percent Free</th></tr>' +  
    CAST ( ( SELECT
			 td = v.volume_mount_point,  '',
			 td = v.file_system_type, '',
			 td = v.logical_volume_name, '',
			 td = convert(varchar(8),v.Total_Size), '',
			 td = convert(varchar(8),v.Available_Size), '',
			 td = convert(varchar(8),v.Space_Free), ''
			from #VolumeStats v
			order by v.volume_mount_point
              FOR XML PATH('tr'), TYPE   
    ) AS NVARCHAR(MAX) ) +  
    N'</table>' ;  
  
BEGIN
--select * from #VolumeStats
if @percent < @Threshold
BEGIN
    EXEC msdb.dbo.sp_send_dbmail  
	   @recipients = 'managed.sql@sparkhound.com',  
	   @body = @tableHTML, 
	   @importance = 'HIGH', 
	   @body_format ='HTML',
	   @subject = 'Volume Size Report' ;  
END
END
END;