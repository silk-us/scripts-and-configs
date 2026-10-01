function New-SilkTCOAWSFSxMetrics {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter(Mandatory)]
        [array] $fslist
    )

    $StartDate = (Get-Date).ToUniversalTime().AddDays(-($days + $offsetDays))
    $EndDate = (Get-Date).ToUniversalTime().AddDays(-$offsetDays)

    $requiredModules = @('AWS.Tools.FSx', 'AWS.Tools.CloudWatch')
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

    # build a CW dimension from a simple name/value hash
    function New-FSxDimension {
        param([hashtable] $pairs)
        $dims = @()
        foreach ($k in $pairs.Keys) {
            $d = New-Object Amazon.CloudWatch.Model.Dimension
            $d.Name = $k
            $d.Value = $pairs[$k]
            $dims += $d
        }
        return $dims
    }

    # pull one AWS/FSx metric. NOTE the DataRead/Write* metrics are SUM counters, not gauges -
    # asking for Average over one big bucket gives you the avg of the datapoints, not a rate.
    # so we take Sum and divide by the window ourselves.
    function Get-FSxMetric {
        param(
            [hashtable] $Dimensions,
            [string]    $MetricName,
            [string[]]  $Stats = @('Sum')
        )
        try {
            $m = Get-CWMetricStatistic -Namespace 'AWS/FSx' -MetricName $MetricName `
                -Dimension (New-FSxDimension $Dimensions) -StartTime $StartDate -EndTime $EndDate `
                -Period ([int]$periodSeconds) -Statistic $Stats -ErrorAction SilentlyContinue

            if ($m.Datapoints -and $m.Datapoints.Count -gt 0) {
                return $m.Datapoints[0]
            }
        } catch {
            Write-Verbose "-> metric $MetricName not available" -Verbose
        }
        return $null
    }

    foreach ($fs in $fslist) {
        $fsId = $fs.FileSystemId
        $ontap = $fs.OntapConfiguration

        $nameTag = ($fs.Tags | Where-Object { $_.Key -eq 'Name' }).Value
        $fsName = if ($nameTag) { $nameTag } else { $fsId }

        Write-Verbose "-> Gathering info for FSx ONTAP - $fsName ($fsId)" -Verbose

        # gen2 (SINGLE_AZ_2 / MULTI_AZ_2) scales out by HA pair. throughput and ssd capacity
        # are both PER PAIR, so reading ThroughputCapacity alone understates a multi pair box.
        $haPairs = if ($ontap.HAPairs) { $ontap.HAPairs } else { 1 }
        $tputPerPair = if ($ontap.ThroughputCapacityPerHAPair) { $ontap.ThroughputCapacityPerHAPair } else { $ontap.ThroughputCapacity }
        $totalThroughputMBps = $tputPerPair * $haPairs

        $provIops = if ($ontap.DiskIopsConfiguration.Iops) { $ontap.DiskIopsConfiguration.Iops } else { 'N/A' }
        $iopsMode = if ($ontap.DiskIopsConfiguration.Mode) { $ontap.DiskIopsConfiguration.Mode.Value } else { 'N/A' }

        # zone - single-az has one subnet, multi-az tells us which one is preferred
        $zone = 'N/A'
        try {
            if ($ontap.PreferredSubnetId) {
                $zone = (Get-EC2Subnet -SubnetId $ontap.PreferredSubnetId -ErrorAction SilentlyContinue).AvailabilityZone
            } elseif ($fs.SubnetIds) {
                $zone = (Get-EC2Subnet -SubnetId $fs.SubnetIds[0] -ErrorAction SilentlyContinue).AvailabilityZone
            }
        } catch {
            Write-Verbose "-> could not resolve AZ for $fsId" -Verbose
        }
        if (-not $zone) { $zone = 'N/A' }
        $region = if ($zone -ne 'N/A') { $zone -replace '[a-z]$', '' } else { 'N/A' }

        $rgTag = ($fs.Tags | Where-Object { $_.Key -eq 'ResourceGroup' -or $_.Key -eq 'Project' -or $_.Key -eq 'Environment' }).Value
        $resourceGroup = if ($rgTag) { $rgTag } else { 'N/A' }

        # --- where the data actually sits. with AUTO tiering most of it ends up in the
        # capacity pool at roughly a sixth of ssd price, so pricing StorageCapacity alone
        # gets both the capacity and the bill wrong.
        $ssdUsedGB = $null
        $poolUsedGB = $null
        $ssdDp = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; StorageTier = 'SSD'; DataType = 'All' } -MetricName 'StorageUsed' -Stats @('Average')
        if ($ssdDp) { $ssdUsedGB = [Math]::Round($ssdDp.Average / 1GB, 2) }
        $poolDp = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; StorageTier = 'STANDARD_CAPACITY_POOL'; DataType = 'All' } -MetricName 'StorageUsed' -Stats @('Average')
        if ($poolDp) { $poolUsedGB = [Math]::Round($poolDp.Average / 1GB, 2) }

        # filesystem wide perf. sum/period gives us a real rate
        $readBytes = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId } -MetricName 'DataReadBytes' -Stats @('Sum')
        $writeBytes = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId } -MetricName 'DataWriteBytes' -Stats @('Sum')
        $readOps = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId } -MetricName 'DataReadOperations' -Stats @('Sum')
        $writeOps = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId } -MetricName 'DataWriteOperations' -Stats @('Sum')

        $fsReadMBps = if ($readBytes) { [Math]::Round(($readBytes.Sum / $periodSeconds) / 1MB, 2) } else { $null }
        $fsWriteMBps = if ($writeBytes) { [Math]::Round(($writeBytes.Sum / $periodSeconds) / 1MB, 2) } else { $null }
        $fsReadIops = if ($readOps) { [Math]::Round($readOps.Sum / $periodSeconds, 2) } else { $null }
        $fsWriteIops = if ($writeOps) { [Math]::Round($writeOps.Sum / $periodSeconds, 2) } else { $null }

        $vols = @($fs.SilkVolumes)
        if (-not $vols) {
            # no volumes carved out yet, still emit the filesystem so it shows in the bill
            $vols = @($null)
        }

        foreach ($v in $vols) {
            $volId = if ($v) { $v.VolumeId } else { 'N/A' }
            $volName = if ($v) { $v.Name } else { 'N/A' }
            $volConf = if ($v) { $v.OntapConfiguration } else { $null }

            # newer api gives SizeInBytes, older only SizeInMegabytes
            $volSizeGB = 'N/A'
            if ($volConf) {
                if ($volConf.SizeInBytes) {
                    $volSizeGB = [Math]::Round($volConf.SizeInBytes / 1GB, 2)
                } elseif ($volConf.SizeInMegabytes) {
                    $volSizeGB = [Math]::Round($volConf.SizeInMegabytes / 1024, 2)
                }
            }

            $tiering = if ($volConf.TieringPolicy.Name) { $volConf.TieringPolicy.Name.Value } else { 'N/A' }
            $coolDays = if ($volConf.TieringPolicy.CoolingPeriod) { $volConf.TieringPolicy.CoolingPeriod } else { 'N/A' }
            $svmId = if ($volConf.StorageVirtualMachineId) { $volConf.StorageVirtualMachineId } else { 'N/A' }
            $storageEff = if ($null -ne $volConf.StorageEfficiencyEnabled) { $volConf.StorageEfficiencyEnabled } else { 'N/A' }

            # per volume perf if the metric exists for this generation, else fall back to fs wide
            $vReadMBps = $fsReadMBps
            $vWriteMBps = $fsWriteMBps
            $vReadIops = $fsReadIops
            $vWriteIops = $fsWriteIops
            $perfScope = 'FileSystem'

            if ($v) {
                $vrb = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; VolumeId = $volId } -MetricName 'DataReadBytes' -Stats @('Sum')
                if ($vrb) {
                    $perfScope = 'Volume'
                    $vwb = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; VolumeId = $volId } -MetricName 'DataWriteBytes' -Stats @('Sum')
                    $vro = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; VolumeId = $volId } -MetricName 'DataReadOperations' -Stats @('Sum')
                    $vwo = Get-FSxMetric -Dimensions @{ FileSystemId = $fsId; VolumeId = $volId } -MetricName 'DataWriteOperations' -Stats @('Sum')

                    $vReadMBps = [Math]::Round(($vrb.Sum / $periodSeconds) / 1MB, 2)
                    $vWriteMBps = if ($vwb) { [Math]::Round(($vwb.Sum / $periodSeconds) / 1MB, 2) } else { $null }
                    $vReadIops = if ($vro) { [Math]::Round($vro.Sum / $periodSeconds, 2) } else { $null }
                    $vWriteIops = if ($vwo) { [Math]::Round($vwo.Sum / $periodSeconds, 2) } else { $null }
                }
            }

            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name "FS name" -Value $fsName
            $o | Add-Member -MemberType NoteProperty -Name "FS Zone" -Value $zone
            $o | Add-Member -MemberType NoteProperty -Name "FS size" -Value "ONTAP-$($totalThroughputMBps)MBps-$($ontap.DeploymentType.Value)"
            $o | Add-Member -MemberType NoteProperty -Name "DeploymentType" -Value $ontap.DeploymentType.Value
            $o | Add-Member -MemberType NoteProperty -Name "HAPairs" -Value $haPairs
            $o | Add-Member -MemberType NoteProperty -Name "ThroughputCapacityMBps" -Value $totalThroughputMBps
            $o | Add-Member -MemberType NoteProperty -Name "SSDCapacityGB" -Value $fs.StorageCapacity
            $o | Add-Member -MemberType NoteProperty -Name "SSDUsedGB" -Value $ssdUsedGB
            $o | Add-Member -MemberType NoteProperty -Name "CapacityPoolUsedGB" -Value $poolUsedGB
            $o | Add-Member -MemberType NoteProperty -Name "ProvisionedIOPS" -Value $provIops
            $o | Add-Member -MemberType NoteProperty -Name "IOPSMode" -Value $iopsMode
            $o | Add-Member -MemberType NoteProperty -Name "Volume Name" -Value $volName
            $o | Add-Member -MemberType NoteProperty -Name "VolumeId" -Value $volId
            $o | Add-Member -MemberType NoteProperty -Name "VolumeSizeGB" -Value $volSizeGB
            $o | Add-Member -MemberType NoteProperty -Name "TieringPolicy" -Value $tiering
            $o | Add-Member -MemberType NoteProperty -Name "CoolingPeriodDays" -Value $coolDays
            $o | Add-Member -MemberType NoteProperty -Name "StorageEfficiency" -Value $storageEff
            $o | Add-Member -MemberType NoteProperty -Name "SVM" -Value $svmId
            $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $resourceGroup
            $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $region
            $o | Add-Member -MemberType NoteProperty -Name "Days" -Value $days
            $o | Add-Member -MemberType NoteProperty -Name "PerfScope" -Value $perfScope
            $o | Add-Member -MemberType NoteProperty -Name "ReadMBps-avg" -Value $vReadMBps
            $o | Add-Member -MemberType NoteProperty -Name "WriteMBps-avg" -Value $vWriteMBps
            $o | Add-Member -MemberType NoteProperty -Name "ReadIOPS-avg" -Value $vReadIops
            $o | Add-Member -MemberType NoteProperty -Name "WriteIOPS-avg" -Value $vWriteIops
            $o | Add-Member -MemberType NoteProperty -Name "FileSystemId" -Value $fsId

            $thelist += $o
        }
    }

    return $thelist
}
