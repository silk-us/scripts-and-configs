function New-SilkTCOAWSRDSMetrics {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter(Mandatory)]
        [array] $rdslist
    )

    $StartDate = (Get-Date).ToUniversalTime().AddDays(-($days + $offsetDays))
    $EndDate = (Get-Date).ToUniversalTime().AddDays(-$offsetDays)

    $requiredModules = @('AWS.Tools.RDS', 'AWS.Tools.CloudWatch')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    $thelist = @()
    $periodSeconds = ($EndDate - $StartDate).TotalSeconds

    # pull one AWS/RDS metric for a db, returns the single datapoint (or $null)
    function Get-RDSMetric {
        param(
            [string]   $DBId,
            [string]   $MetricName,
            [string[]] $Stats
        )
        try {
            $dim = New-Object Amazon.CloudWatch.Model.Dimension
            $dim.Name = 'DBInstanceIdentifier'
            $dim.Value = $DBId

            $m = Get-CWMetricStatistic -Namespace 'AWS/RDS' -MetricName $MetricName `
                -Dimension $dim -StartTime $StartDate -EndTime $EndDate `
                -Period ([int]$periodSeconds) -Statistic $Stats -ErrorAction SilentlyContinue

            if ($m.Datapoints -and $m.Datapoints.Count -gt 0) {
                return $m.Datapoints[0]
            }
        } catch {
            Write-Verbose "-> metric $MetricName not available for $DBId" -Verbose
        }
        return $null
    }

    foreach ($db in $rdslist) {
        $dbId = $db.DBInstanceIdentifier
        Write-Verbose "-> Gathering info for RDS - $dbId ($($db.Engine))" -Verbose

        # region/zone off the instance placement
        $zone = $db.AvailabilityZone
        $region = if ($zone) { $zone -replace '[a-z]$', '' } else { 'N/A' }

        # resource group equivalent from tags
        $rgTag = ($db.TagList | Where-Object { $_.Key -eq 'ResourceGroup' -or $_.Key -eq 'Project' -or $_.Key -eq 'Environment' }).Value
        $resourceGroup = if ($rgTag) { $rgTag } else { 'N/A' }

        # --- capacity comes straight off the db instance object ---
        $allocatedGB = $db.AllocatedStorage
        $maxAllocGB = if ($db.MaxAllocatedStorage) { $db.MaxAllocatedStorage } else { 'N/A' }
        $storageType = $db.StorageType
        $provIops = if ($db.Iops) { $db.Iops } else { 'N/A' }
        $storageThroughput = if ($db.StorageThroughput) { $db.StorageThroughput } else { 'N/A' }

        # --- used capacity + perf comes from cloudwatch ---
        # free space: avg gives typical, min gives the high water mark of used
        $freeDp = Get-RDSMetric -DBId $dbId -MetricName 'FreeStorageSpace' -Stats @('Average', 'Minimum')
        $freeAvgGB = if ($freeDp) { [Math]::Round($freeDp.Average / 1GB, 2) } else { $null }
        $freeMinGB = if ($freeDp) { [Math]::Round($freeDp.Minimum / 1GB, 2) } else { $null }
        $usedAvgGB = if ($null -ne $freeAvgGB) { [Math]::Round($allocatedGB - $freeAvgGB, 2) } else { $null }
        $usedPeakGB = if ($null -ne $freeMinGB) { [Math]::Round($allocatedGB - $freeMinGB, 2) } else { $null }

        # perf metrics - grab avg + max so we can size to peak
        $readIops = Get-RDSMetric -DBId $dbId -MetricName 'ReadIOPS' -Stats @('Average', 'Maximum')
        $writeIops = Get-RDSMetric -DBId $dbId -MetricName 'WriteIOPS' -Stats @('Average', 'Maximum')
        $readTput = Get-RDSMetric -DBId $dbId -MetricName 'ReadThroughput' -Stats @('Average', 'Maximum')
        $writeTput = Get-RDSMetric -DBId $dbId -MetricName 'WriteThroughput' -Stats @('Average', 'Maximum')
        $readLat = Get-RDSMetric -DBId $dbId -MetricName 'ReadLatency' -Stats @('Average', 'Maximum')
        $writeLat = Get-RDSMetric -DBId $dbId -MetricName 'WriteLatency' -Stats @('Average', 'Maximum')
        $queue = Get-RDSMetric -DBId $dbId -MetricName 'DiskQueueDepth' -Stats @('Average', 'Maximum')
        $cpu = Get-RDSMetric -DBId $dbId -MetricName 'CPUUtilization' -Stats @('Average', 'Maximum')
        $mem = Get-RDSMetric -DBId $dbId -MetricName 'FreeableMemory' -Stats @('Average')

        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name "DB name" -Value $dbId
        $o | Add-Member -MemberType NoteProperty -Name "DB Zone" -Value $zone
        $o | Add-Member -MemberType NoteProperty -Name "DB Class" -Value $db.DBInstanceClass
        $o | Add-Member -MemberType NoteProperty -Name "Engine" -Value $db.Engine
        $o | Add-Member -MemberType NoteProperty -Name "EngineVersion" -Value $db.EngineVersion
        $o | Add-Member -MemberType NoteProperty -Name "MultiAZ" -Value $db.MultiAZ
        $o | Add-Member -MemberType NoteProperty -Name "StorageType" -Value $storageType
        $o | Add-Member -MemberType NoteProperty -Name "AllocatedStorageGB" -Value $allocatedGB
        $o | Add-Member -MemberType NoteProperty -Name "MaxAllocatedStorageGB" -Value $maxAllocGB
        $o | Add-Member -MemberType NoteProperty -Name "ProvisionedIOPS" -Value $provIops
        $o | Add-Member -MemberType NoteProperty -Name "StorageThroughputMBps" -Value $storageThroughput
        $o | Add-Member -MemberType NoteProperty -Name "UsedStorageGB-avg" -Value $usedAvgGB
        $o | Add-Member -MemberType NoteProperty -Name "UsedStorageGB-peak" -Value $usedPeakGB
        $o | Add-Member -MemberType NoteProperty -Name "FreeStorageGB-avg" -Value $freeAvgGB
        $o | Add-Member -MemberType NoteProperty -Name "FreeStorageGB-min" -Value $freeMinGB
        $o | Add-Member -MemberType NoteProperty -Name "ReadIOPS-avg" -Value $(if ($readIops) { [Math]::Round($readIops.Average, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ReadIOPS-max" -Value $(if ($readIops) { [Math]::Round($readIops.Maximum, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteIOPS-avg" -Value $(if ($writeIops) { [Math]::Round($writeIops.Average, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteIOPS-max" -Value $(if ($writeIops) { [Math]::Round($writeIops.Maximum, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ReadThroughputMBps-avg" -Value $(if ($readTput) { [Math]::Round($readTput.Average / 1MB, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ReadThroughputMBps-max" -Value $(if ($readTput) { [Math]::Round($readTput.Maximum / 1MB, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteThroughputMBps-avg" -Value $(if ($writeTput) { [Math]::Round($writeTput.Average / 1MB, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteThroughputMBps-max" -Value $(if ($writeTput) { [Math]::Round($writeTput.Maximum / 1MB, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ReadLatencyMs-avg" -Value $(if ($readLat) { [Math]::Round($readLat.Average * 1000, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ReadLatencyMs-max" -Value $(if ($readLat) { [Math]::Round($readLat.Maximum * 1000, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteLatencyMs-avg" -Value $(if ($writeLat) { [Math]::Round($writeLat.Average * 1000, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "WriteLatencyMs-max" -Value $(if ($writeLat) { [Math]::Round($writeLat.Maximum * 1000, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "DiskQueueDepth-avg" -Value $(if ($queue) { [Math]::Round($queue.Average, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "DiskQueueDepth-max" -Value $(if ($queue) { [Math]::Round($queue.Maximum, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "CPUUtilization-avg" -Value $(if ($cpu) { [Math]::Round($cpu.Average, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "CPUUtilization-max" -Value $(if ($cpu) { [Math]::Round($cpu.Maximum, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "FreeableMemoryGB-avg" -Value $(if ($mem) { [Math]::Round($mem.Average / 1GB, 2) } else { $null })
        $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $resourceGroup
        $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $region
        $o | Add-Member -MemberType NoteProperty -Name "Days" -Value $days
        $o | Add-Member -MemberType NoteProperty -Name "DBInstanceIdentifier" -Value $dbId

        $thelist += $o
    }

    return $thelist
}
