param(
    [string]$ServerInstance = 'localhost',

    [string]$OutputPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# need the gallery SqlServer module, not the old SQLPS one
if (-not (Get-Module SqlServer -ListAvailable)) {
    Write-Host 'SqlServer module not found, installing for current user...'
    Install-Module SqlServer -Scope CurrentUser -AllowClobber -Force
}
Import-Module SqlServer

# same as sql1.sql - first result set is per file, second is rollup
$query = @'
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
'@

$sqlArgs = @{
    ServerInstance = $ServerInstance
    # InputFile      = Join-Path $PSScriptRoot 'sql1.sql'
    Query          = $query
    OutputAs       = 'DataSet'
    QueryTimeout   = 0
}
if ((Get-Command Invoke-Sqlcmd).Parameters.ContainsKey('TrustServerCertificate')) {
    $sqlArgs.TrustServerCertificate = $true
}

# no creds passed = windows auth as whoever is running this
Write-Host "Collecting storage from $ServerInstance as $env:USERDOMAIN\$env:USERNAME ..."
$ds = Invoke-Sqlcmd @sqlArgs -Verbose

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$prefix = Join-Path $OutputPath "DbStorage_$($ServerInstance -replace '[\\:,]', '_')_$stamp"
$junk = 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'

$ds.Tables[0] | Select-Object * -ExcludeProperty $junk | Export-Csv "${prefix}_Files.csv" -NoTypeInformation
$ds.Tables[1] | Select-Object * -ExcludeProperty $junk | Export-Csv "${prefix}_Rollup.csv" -NoTypeInformation

Write-Host "Wrote ${prefix}_Files.csv"
Write-Host "Wrote ${prefix}_Rollup.csv"
