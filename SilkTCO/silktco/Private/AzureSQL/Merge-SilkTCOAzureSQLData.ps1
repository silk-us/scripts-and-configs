function Merge-SilkTCOAzureSQLData {
    param (
        [Parameter(Mandatory)]
        [array] $sqllist,
        [Parameter()]
        [array] $metrics,
        [Parameter()]
        [array] $costs
    )

    $newarray = @()

    # every record type gets the same columns so six different resource shapes still
    # stack into one csv, same approach as the rds report
    function New-SqlRow {
        $o = New-Object psobject
        $cols = @(
            'RecordType','ResourceName','ParentName','ResourceGroupName','ResourceGroupTag',
            'Region','Zone','Engine','EngineVersion','Tier','SkuName','Family','Capacity',
            'CapacityUnit','MemoryGB','StorageProvisionedGB','StorageUsedGB','StorageReservedGB',
            'StoragePctAvg','StoragePctMax','ProvisionedIOPS','StorageAutoGrow','LicenseType',
            'ZoneRedundant','HAMode','HAState','BackupRedundancy','BackupRetentionDays',
            'ElasticPoolName','ServiceObjective','ReadReplicas','HAReplicas','IsServerless',
            'ServerlessMinCapacity','AutoPauseDelayMinutes','ReplicationRole','Status',
            'CPUPctAvg','CPUPctMax','MemoryPctAvg','MemoryPctMax','DTUPctAvg','DTUPctMax',
            'IOPctAvg','IOPctMax','LogWritePctAvg','LogWritePctMax','WorkersPctAvg','SessionsPctAvg',
            'IOPSAvg','IOPSMax','ReadIOPSAvg','ReadIOPSMax','WriteIOPSAvg','WriteIOPSMax',
            'ReadMBpsAvg','WriteMBpsAvg','ConnectionsAvg','ConnectionsMax','MetricsAvailable','MetricsMissing',
            'ComputeCostPeriodUSD','LicenseCostPeriodUSD','StorageCostPeriodUSD','BackupCostPeriodUSD','OtherCostPeriodUSD',
            'TotalCostPeriodUSD','TotalCostMonthlyUSD','Days','CostNotes','ResourceId'
        )
        foreach ($c in $cols) { $o | Add-Member -MemberType NoteProperty -Name $c -Value $null }
        return $o
    }

    # copy a value over only if the source actually carries that property
    function Copy-IfPresent {
        param($source, $target, [string] $name, [string] $as)
        if (-not $as) { $as = $name }
        $prop = $source.psobject.Properties[$name]
        if ($prop -and $null -ne $prop.Value) { $target.$as = $prop.Value }
    }

    foreach ($res in $sqllist) {
        $row = New-SqlRow

        foreach ($f in 'RecordType','ResourceName','ParentName','ResourceGroupName','ResourceGroupTag',
                       'Region','Zone','Engine','EngineVersion','Tier','SkuName','Family','Capacity',
                       'CapacityUnit','MemoryGB','StorageProvisionedGB','ProvisionedIOPS','StorageAutoGrow',
                       'LicenseType','ZoneRedundant','HAMode','HAState','BackupRedundancy',
                       'BackupRetentionDays','ElasticPoolName','ServiceObjective','ReadReplicas',
                       'HAReplicas','IsServerless','ServerlessMinCapacity','AutoPauseDelayMinutes',
                       'ReplicationRole','Status','ResourceId') {
            Copy-IfPresent -source $res -target $row -name $f
        }

        $m = $null
        if ($metrics) { $m = $metrics | Where-Object { $_.ResourceId -eq $res.ResourceId } | Select-Object -First 1 }
        if ($m) {
            foreach ($f in 'StorageUsedGB','StorageReservedGB','StoragePctAvg','StoragePctMax',
                           'CPUPctAvg','CPUPctMax','MemoryPctAvg','MemoryPctMax','DTUPctAvg','DTUPctMax',
                           'IOPctAvg','IOPctMax','LogWritePctAvg','LogWritePctMax','WorkersPctAvg',
                           'SessionsPctAvg','IOPSAvg','IOPSMax','ReadIOPSAvg','ReadIOPSMax',
                           'WriteIOPSAvg','WriteIOPSMax','ReadMBpsAvg','WriteMBpsAvg',
                           'ConnectionsAvg','ConnectionsMax','MetricsAvailable','MetricsMissing','Days') {
                Copy-IfPresent -source $m -target $row -name $f
            }
        }

        $c = $null
        if ($costs) { $c = $costs | Where-Object { $_.ResourceId -eq $res.ResourceId } | Select-Object -First 1 }
        if ($c) {
            foreach ($f in 'ComputeCostPeriodUSD','LicenseCostPeriodUSD','StorageCostPeriodUSD','BackupCostPeriodUSD',
                           'OtherCostPeriodUSD','TotalCostPeriodUSD','TotalCostMonthlyUSD',
                           'CostNotes','Days') {
                Copy-IfPresent -source $c -target $row -name $f
            }
        }

        $newarray += $row
    }

    # billed resources discovery never returned - emit them so the csv accounts for
    # every dollar of sql spend, not just the spend we found an inventory row for
    foreach ($c in @($costs | Where-Object { $_.UnmatchedResourceName })) {
        $row = New-SqlRow
        $row.RecordType = 'UnmatchedCost'
        $row.ResourceName = $c.UnmatchedResourceName
        $row.ResourceId = $c.ResourceId
        if ($c.ResourceId -match '/resourceGroups/([^/]+)/') { $row.ResourceGroupName = $Matches[1] }
        if ($c.ResourceId -match '/providers/Microsoft\.([^/]+)/') { $row.Engine = $Matches[1] }
        foreach ($f in 'ComputeCostPeriodUSD','LicenseCostPeriodUSD','StorageCostPeriodUSD','BackupCostPeriodUSD',
                       'OtherCostPeriodUSD','TotalCostPeriodUSD','TotalCostMonthlyUSD','CostNotes','Days') {
            Copy-IfPresent -source $c -target $row -name $f
        }
        $newarray += $row
    }

    return $newarray
}
