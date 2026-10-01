<#
    .SYNOPSIS
    Pulls Azure Monitor metrics for managed SQL resources.

    .DESCRIPTION
    Each resource type publishes a different metric set, so the map below is per namespace.

    Worth knowing before comparing any of this to an RDS report: Azure SQL Database and
    Elastic Pool report IO as a PERCENTAGE OF THE SERVICE TIER LIMIT (physical_data_read_percent,
    log_write_percent), not as absolute IOPS or MB/s. Managed Instance and the PostgreSQL /
    MySQL flexible servers do give absolute figures. So the IOPS columns are only populated
    for the types that can actually produce them - a blank is a genuine gap, not a zero.
#>

function New-SilkTCOAzureSQLMetrics {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter(Mandatory)]
        [array] $sqllist
    )

    if (-not (Install-SilkTCOModule -Name 'Az.Monitor')) {
        throw "Az.Monitor is required for SQL metrics and could not be installed."
    }

    $StartDate = (Get-Date).ToUniversalTime().AddDays(-($days + $offsetDays))
    $EndDate = (Get-Date).ToUniversalTime().AddDays(-$offsetDays)

    # azure monitor only takes real grains (PT1H, P1D, ...). dont build one out of $days -
    # a 30 day 'grain' isnt a thing and the call just fails.
    $timegrain = if ($days -le 2) { '01:00:00' } else { '1.00:00:00' }

    $thelist = @()

    # metric -> output column, per namespace. Peak means also pull a Maximum pass.
    # Column is the literal output name for a non-peak metric. Peak metrics get Avg and
    # Max appended. Agg is the aggregation azure actually publishes - storage is Maximum
    # only, asking it for Average just returns nothing.
    $metricMap = @{
        'Microsoft.Sql/servers/databases' = @(
            @{ Metric = 'cpu_percent';                Column = 'CPUPct';          Peak = $true }
            @{ Metric = 'dtu_consumption_percent';    Column = 'DTUPct';          Peak = $true }
            @{ Metric = 'storage';                    Column = 'StorageUsedGB';   Peak = $false; Agg = 'Maximum'; Divide = 1GB }
            @{ Metric = 'storage_percent';            Column = 'StoragePct';      Peak = $true }
            @{ Metric = 'physical_data_read_percent'; Column = 'IOPct';           Peak = $true }
            @{ Metric = 'log_write_percent';          Column = 'LogWritePct';     Peak = $true }
            @{ Metric = 'workers_percent';            Column = 'WorkersPctAvg';   Peak = $false }
            @{ Metric = 'sessions_percent';           Column = 'SessionsPctAvg';  Peak = $false }
        )
        'Microsoft.Sql/servers/elasticPools' = @(
            @{ Metric = 'cpu_percent';                Column = 'CPUPct';          Peak = $true }
            @{ Metric = 'storage_percent';            Column = 'StoragePct';      Peak = $true }
            @{ Metric = 'allocated_data_storage';     Column = 'StorageUsedGB';   Peak = $false; Agg = 'Maximum'; Divide = 1GB }
        )
        'Microsoft.Sql/managedInstances' = @(
            @{ Metric = 'avg_cpu_percent';            Column = 'CPUPct';          Peak = $true }
            @{ Metric = 'storage_space_used_mb';      Column = 'StorageUsedGB';   Peak = $false; Agg = 'Average'; Divide = 1024 }
            @{ Metric = 'reserved_storage_mb';        Column = 'StorageReservedGB'; Peak = $false; Agg = 'Average'; Divide = 1024 }
            @{ Metric = 'io_requests';                Column = 'IOPS';            Peak = $true }
            @{ Metric = 'io_bytes_read';              Column = 'ReadMBpsAvg';     Peak = $false; Divide = 1MB }
            @{ Metric = 'io_bytes_written';           Column = 'WriteMBpsAvg';    Peak = $false; Divide = 1MB }
        )
        'Microsoft.DBforPostgreSQL/flexibleServers' = @(
            @{ Metric = 'cpu_percent';                Column = 'CPUPct';          Peak = $true }
            @{ Metric = 'memory_percent';             Column = 'MemoryPct';       Peak = $true }
            @{ Metric = 'storage_used';               Column = 'StorageUsedGB';   Peak = $false; Agg = 'Maximum'; Divide = 1GB }
            @{ Metric = 'storage_percent';            Column = 'StoragePct';      Peak = $true }
            @{ Metric = 'read_iops';                  Column = 'ReadIOPS';        Peak = $true }
            @{ Metric = 'write_iops';                 Column = 'WriteIOPS';       Peak = $true }
            @{ Metric = 'read_throughput';            Column = 'ReadMBpsAvg';     Peak = $false; Divide = 1MB }
            @{ Metric = 'write_throughput';           Column = 'WriteMBpsAvg';    Peak = $false; Divide = 1MB }
            @{ Metric = 'active_connections';         Column = 'Connections';     Peak = $true }
        )
        'Microsoft.DBforMySQL/flexibleServers' = @(
            @{ Metric = 'cpu_percent';                Column = 'CPUPct';          Peak = $true }
            @{ Metric = 'memory_percent';             Column = 'MemoryPct';       Peak = $true }
            @{ Metric = 'storage_used';               Column = 'StorageUsedGB';   Peak = $false; Agg = 'Maximum'; Divide = 1GB }
            @{ Metric = 'storage_percent';            Column = 'StoragePct';      Peak = $true }
            @{ Metric = 'io_consumption_percent';     Column = 'IOPct';           Peak = $true }
            @{ Metric = 'active_connections';         Column = 'Connections';     Peak = $true }
        )
    }

    # one metric, one aggregation. rolls the datapoints up ourselves rather than trusting
    # a single bucket - .Data comes back as an array and indexing it blind bites you
    function Get-SilkSqlMetric {
        param(
            [string] $ResourceId,
            [string] $MetricName,
            [string] $Aggregation
        )
        try {
            $m = Get-AzMetric -ResourceId $ResourceId -MetricName $MetricName -TimeGrain $timegrain `
                -StartTime $StartDate -EndTime $EndDate -AggregationType $Aggregation `
                -WarningAction SilentlyContinue -ErrorAction Stop

            $vals = @($m.Data | ForEach-Object { $_.$Aggregation } | Where-Object { $null -ne $_ })
            if (-not $vals.Count) { return $null }

            if ($Aggregation -eq 'Maximum') {
                return ($vals | Measure-Object -Maximum).Maximum
            }
            return ($vals | Measure-Object -Average).Average
        } catch {
            Write-Verbose "-> metric $MetricName not available" -Verbose
        }
        return $null
    }

    foreach ($res in $sqllist) {
        $ns = $res.MetricNamespace

        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $res.ResourceId
        $o | Add-Member -MemberType NoteProperty -Name Days -Value $days

        # managed databases have no metrics of their own, they ride on the instance
        if (-not $ns -or -not $metricMap.ContainsKey($ns)) {
            $o | Add-Member -MemberType NoteProperty -Name MetricsAvailable -Value $false
            $thelist += $o
            continue
        }

        Write-Verbose "-> Gathering metrics for $($res.RecordType) - $($res.ResourceName)" -Verbose

        $gotAny = $false
        $missing = @()

        foreach ($def in $metricMap[$ns]) {
            $divide = if ($def.Divide) { $def.Divide } else { 1 }
            $primaryAgg = if ($def.Agg) { $def.Agg } else { 'Average' }
            $fallbackAgg = if ($primaryAgg -eq 'Average') { 'Maximum' } else { 'Average' }

            $val = Get-SilkSqlMetric -ResourceId $res.ResourceId -MetricName $def.Metric -Aggregation $primaryAgg
            # some metrics only publish one aggregation and which one isnt always obvious,
            # so try the other before calling it missing
            if ($null -eq $val) {
                $val = Get-SilkSqlMetric -ResourceId $res.ResourceId -MetricName $def.Metric -Aggregation $fallbackAgg
            }

            # non-peak metrics use Column verbatim, peak ones get Avg/Max appended
            $avgName = if ($def.Peak) { "$($def.Column)Avg" } else { $def.Column }

            if ($null -ne $val) {
                $gotAny = $true
                $o | Add-Member -MemberType NoteProperty -Name $avgName -Value ([Math]::Round(($val / $divide), 2)) -Force
            } else {
                $missing += $def.Metric
                $o | Add-Member -MemberType NoteProperty -Name $avgName -Value $null -Force
            }

            if ($def.Peak) {
                $max = Get-SilkSqlMetric -ResourceId $res.ResourceId -MetricName $def.Metric -Aggregation 'Maximum'
                if ($null -ne $max) {
                    $gotAny = $true
                    $o | Add-Member -MemberType NoteProperty -Name "$($def.Column)Max" -Value ([Math]::Round(($max / $divide), 2)) -Force
                } else {
                    $o | Add-Member -MemberType NoteProperty -Name "$($def.Column)Max" -Value $null -Force
                }
            }
        }

        $o | Add-Member -MemberType NoteProperty -Name MetricsAvailable -Value $gotAny
        $o | Add-Member -MemberType NoteProperty -Name MetricsMissing -Value $(if ($missing) { $missing -join ', ' } else { $null })
        $thelist += $o
    }

    return $thelist
}
