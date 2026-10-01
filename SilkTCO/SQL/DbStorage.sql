SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#StorageUsage') IS NOT NULL DROP TABLE #StorageUsage;

CREATE TABLE #StorageUsage (
    DatabaseName  sysname,
    LogicalName   sysname,
    FileType      nvarchar(60),
    FileGroupName sysname NULL,
    SizeMB        decimal(18,2),
    UsedMB        decimal(18,2),
    FreeMB        decimal(18,2),
    PctUsed       decimal(5,2),
    Growth        varchar(30),
    MaxSize       varchar(30),
    PhysicalName  nvarchar(260)
);

DECLARE @db sysname, @sql nvarchar(max);

-- user dbs only, skip offline / no access
DECLARE db_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE database_id > 4
      AND state_desc = 'ONLINE'
      AND HAS_DBACCESS(name) = 1;

OPEN db_cur;
FETCH NEXT FROM db_cur INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'USE ' + QUOTENAME(@db) + N';
    INSERT INTO #StorageUsage
    SELECT DB_NAME(),
           f.name,
           f.type_desc,
           fg.name,
           f.size / 128.0,
           FILEPROPERTY(f.name, ''SpaceUsed'') / 128.0,
           (f.size - FILEPROPERTY(f.name, ''SpaceUsed'')) / 128.0,
           CAST(FILEPROPERTY(f.name, ''SpaceUsed'') * 100.0 / NULLIF(f.size, 0) AS decimal(5,2)),
           CASE WHEN f.is_percent_growth = 1 THEN CAST(f.growth AS varchar(10)) + ''%''
                ELSE CAST(f.growth / 128 AS varchar(10)) + '' MB'' END,
           CASE WHEN f.max_size = -1 THEN ''Unlimited''
                WHEN f.max_size = 268435456 THEN ''2 TB''
                ELSE CAST(f.max_size / 128 AS varchar(10)) + '' MB'' END,
           f.physical_name
    FROM sys.database_files f
    LEFT JOIN sys.filegroups fg ON f.data_space_id = fg.data_space_id;';

    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT 'Skipped ' + @db + ': ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM db_cur INTO @db;
END

CLOSE db_cur;
DEALLOCATE db_cur;

-- per file
SELECT *
FROM #StorageUsage
ORDER BY DatabaseName, FileType, LogicalName;

-- per db rollup
SELECT DatabaseName,
       SUM(CASE WHEN FileType = 'ROWS' THEN SizeMB END) AS DataSizeMB,
       SUM(CASE WHEN FileType = 'ROWS' THEN UsedMB END) AS DataUsedMB,
       SUM(CASE WHEN FileType = 'LOG'  THEN SizeMB END) AS LogSizeMB,
       SUM(CASE WHEN FileType = 'LOG'  THEN UsedMB END) AS LogUsedMB,
       SUM(SizeMB) AS TotalSizeMB,
       SUM(UsedMB) AS TotalUsedMB
FROM #StorageUsage
GROUP BY DatabaseName
ORDER BY TotalSizeMB DESC;
