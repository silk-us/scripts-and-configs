function New-SilkTCOAWSVMMetrics {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter(Mandatory)]
        [array] $vmlist
    )

    $StartDate = (Get-Date).ToUniversalTime().AddDays(-($days + $offsetDays))
    $EndDate = (Get-Date).ToUniversalTime().AddDays(-$offsetDays)

    # CloudTrail is no longer required - uptime calculation now uses CloudWatch metrics
    $requiredModules = @('AWS.Tools.EC2', 'AWS.Tools.CloudWatch')
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

    # EBS volume type to disk class mapping
    $diskClassMap = @{
        'gp2'      = 'SSD'
        'gp3'      = 'SSD'
        'io1'      = 'SSD'
        'io2'      = 'SSD'
        'st1'      = 'HDD'
        'sc1'      = 'HDD'
        'standard' = 'HDD'
    }

    foreach ($i in $vmlist) {
        $instanceId = $i.InstanceId
        $nameTag = ($i.Tags | Where-Object { $_.Key -eq 'Name' }).Value
        $vmName = if ($nameTag) { $nameTag } else { $instanceId }

        Write-Verbose "-> Gathering info for Instance - $vmName ($instanceId)" -Verbose

        $uptime = Get-AWSEC2Uptime -InstanceId $instanceId -vmList $vmlist -days $days -offsetDays $offsetDays -WarningAction SilentlyContinue

        # Get the region from placement
        $region = $i.Placement.AvailabilityZone -replace '[a-z]$', ''
        $zone = $i.Placement.AvailabilityZone

        # Get resource group equivalent from tags
        $rgTag = ($i.Tags | Where-Object { $_.Key -eq 'ResourceGroup' -or $_.Key -eq 'Project' -or $_.Key -eq 'Environment' }).Value
        $resourceGroup = if ($rgTag) { $rgTag } else { 'N/A' }

        # Try to get available memory from CloudWatch Agent metrics
        $vmstatavg = $null
        try {
            $memDimension = New-Object Amazon.CloudWatch.Model.Dimension
            $memDimension.Name = 'InstanceId'
            $memDimension.Value = $instanceId

            $memMetric = Get-CWMetricStatistic -Namespace 'CWAgent' -MetricName 'mem_available_percent' `
                -Dimension $memDimension -StartTime $StartDate -EndTime $EndDate `
                -Period ([int]$periodSeconds) -Statistic 'Average' -ErrorAction SilentlyContinue

            if ($memMetric.Datapoints -and $memMetric.Datapoints.Count -gt 0) {
                # mem_available_percent gives us a percentage; convert using instance memory
                # For now store the percentage - we'd need instance type specs for absolute GB
                $vmstatavg = $memMetric.Datapoints[0].Average
            }
        } catch {
            Write-Verbose "-> CloudWatch Agent memory metrics not available for $vmName" -Verbose
        }

        # Get attached EBS volumes
        $volumes = Get-EC2Volume -Filter @{
            Name   = 'attachment.instance-id'
            Values = @($instanceId)
        }

        if ($volumes) {
            foreach ($vol in $volumes) {
                $volumeId = $vol.VolumeId
                $volumeType = $vol.VolumeType.Value
                $diskClass = if ($diskClassMap.ContainsKey($volumeType)) { $diskClassMap[$volumeType] } else { $volumeType }

                Write-Verbose "---> Gathering metrics for volume $volumeId" -Verbose

                $dimension = New-Object Amazon.CloudWatch.Model.Dimension
                $dimension.Name = 'VolumeId'
                $dimension.Value = $volumeId

                $cwParams = @{
                    Namespace  = 'AWS/EBS'
                    Dimension  = $dimension
                    StartTime  = $StartDate
                    EndTime    = $EndDate
                    Period     = [int]$periodSeconds
                    Statistic  = 'Average'
                }

                # Collect EBS metrics
                $readBytes = $null
                $writeBytes = $null
                $readOps = $null
                $writeOps = $null

                try {
                    $readBytesMetric = Get-CWMetricStatistic @cwParams -MetricName 'VolumeReadBytes' -ErrorAction SilentlyContinue
                    if ($readBytesMetric.Datapoints) {
                        $readBytes = $readBytesMetric.Datapoints[0].Average / $periodSeconds
                    }
                } catch { }

                try {
                    $writeBytesMetric = Get-CWMetricStatistic @cwParams -MetricName 'VolumeWriteBytes' -ErrorAction SilentlyContinue
                    if ($writeBytesMetric.Datapoints) {
                        $writeBytes = $writeBytesMetric.Datapoints[0].Average / $periodSeconds
                    }
                } catch { }

                try {
                    $readOpsMetric = Get-CWMetricStatistic @cwParams -MetricName 'VolumeReadOps' -ErrorAction SilentlyContinue
                    if ($readOpsMetric.Datapoints) {
                        $readOps = $readOpsMetric.Datapoints[0].Average / $periodSeconds
                    }
                } catch { }

                try {
                    $writeOpsMetric = Get-CWMetricStatistic @cwParams -MetricName 'VolumeWriteOps' -ErrorAction SilentlyContinue
                    if ($writeOpsMetric.Datapoints) {
                        $writeOps = $writeOpsMetric.Datapoints[0].Average / $periodSeconds
                    }
                } catch { }

                # Calculate provisioned/baseline throughput (MB/s) based on volume type
                $diskThroughputMBps = switch ($volumeType) {
                    'gp3' {
                        # gp3 has configurable throughput (125-1000 MB/s)
                        if ($vol.Throughput) { $vol.Throughput } else { 125 }  # Default is 125 MB/s
                    }
                    'gp2' {
                        # gp2: Baseline of 3 IOPS/GB, burst to 3000 IOPS
                        # Throughput: 128-250 MB/s depending on volume size
                        # Under 170 GB: 128 MB/s, 170-334 GB scales to 250 MB/s, above 334 GB: 250 MB/s
                        if ($vol.Size -lt 170) { 128 }
                        elseif ($vol.Size -lt 334) { [Math]::Round(128 + (($vol.Size - 170) * 0.744), 2) }
                        else { 250 }
                    }
                    'io1' {
                        # io1: Throughput is 256 KB per provisioned IOPS (up to 1000 MB/s for <= 32 GiB volumes)
                        # Max throughput: 1000 MB/s (for volumes <= 32,000 IOPS)
                        $calculatedThroughput = [Math]::Round(($vol.Iops * 256) / 1024, 2)
                        [Math]::Min($calculatedThroughput, 1000)
                    }
                    'io2' {
                        # io2: Similar to io1 but supports up to 4000 MB/s
                        if ($vol.Throughput) { 
                            $vol.Throughput 
                        } else {
                            # Calculate based on IOPS: 256 KB per IOPS
                            $calculatedThroughput = [Math]::Round(($vol.Iops * 256) / 1024, 2)
                            [Math]::Min($calculatedThroughput, 4000)
                        }
                    }
                    'st1' {
                        # st1 (Throughput Optimized HDD): 40 MB/s per TB baseline, 500 MB/s max
                        # Burst: 250 MB/s per TB, 500 MB/s max
                        $baselineThroughput = ($vol.Size / 1024) * 40
                        [Math]::Min([Math]::Round($baselineThroughput, 2), 500)
                    }
                    'sc1' {
                        # sc1 (Cold HDD): 12 MB/s per TB baseline, 250 MB/s max
                        $baselineThroughput = ($vol.Size / 1024) * 12
                        [Math]::Min([Math]::Round($baselineThroughput, 2), 250)
                    }
                    'standard' {
                        # Magnetic (standard): ~40-90 MB/s
                        40
                    }
                    default { $null }
                }

                $o = New-Object psobject
                $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $vmName
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $zone
                $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.InstanceType.Value
                $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value $(if ($vmstatavg) { [Math]::Round($vmstatavg, 2) } else { 'N/A' })
                $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $volumeId
                $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $volumeType
                $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $vol.Size
                $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $volumeType
                $o | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value $diskClass
                $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $vol.Iops
                $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $diskThroughputMBps
                $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $resourceGroup
                $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $region
                $o | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $uptime.UptimePercentage
                $o | Add-Member -MemberType NoteProperty -Name "Days" -Value $days
                $o | Add-Member -MemberType NoteProperty -Name "CompositeDiskReadBytes/sec-avg" -Value $readBytes
                $o | Add-Member -MemberType NoteProperty -Name "CompositeDiskWriteBytes/sec-avg" -Value $writeBytes
                $o | Add-Member -MemberType NoteProperty -Name "CompositeDiskReadOperations/Sec-avg" -Value $readOps
                $o | Add-Member -MemberType NoteProperty -Name "CompositeDiskWriteOperations/Sec-avg" -Value $writeOps
                $o | Add-Member -MemberType NoteProperty -Name "DiskPaidBurstIOPS-avg" -Value 'N/A'
                $o | Add-Member -MemberType NoteProperty -Name "InstanceId" -Value $instanceId

                $thelist += $o
            }
        } else {
            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $vmName
            $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $zone
            $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.InstanceType.Value
            $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value $(if ($vmstatavg) { [Math]::Round($vmstatavg, 2) } else { 'N/A' })
            $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $resourceGroup
            $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $region
            $o | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $uptime.UptimePercentage
            $o | Add-Member -MemberType NoteProperty -Name "Days" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "InstanceId" -Value $instanceId

            $thelist += $o
        }
    }

    return $thelist
}
