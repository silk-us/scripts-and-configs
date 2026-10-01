function New-SilkTCOAzureVMMetrics {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter(Mandatory)]
        [array] $vmlist
    )

    $StartDate = (Get-Date).AddDays(-($days + $offsetDays))
    $EndDate = (Get-Date).AddDays(-$offsetDays)


    $requiredModules = @('Az.Monitor')
    foreach ($module in $requiredModules) {
        if (-not (Install-SilkTCOModule -Name $module)) {
            throw "$module is needed for VM metrics and could not be installed."
        }
    }

    # Set up some of the output table and vars
    $thelist = @()
    $timegrain = $days.ToString() + ":" + "00" + ":" + "00" + ":" + '00'
    $timegrain | Write-Verbose

    $totalDiskSizeGB = 0
    $totalDiskIOPS = 0
    $totalDiskMBps = 0


    # Gather disk metrics. 
    $metrics = (
        'Composite Disk Read Bytes/sec',
        'Composite Disk Write Bytes/sec',
        'Composite Disk Read Operations/Sec',
        'Composite Disk Write Operations/Sec',
        'DiskPaidBurstIOPS'
    )

    # Set up the total vars for each disk metric. 
    foreach ($m in $metrics) {
        New-Variable -Name ($m.replace(' ', $null) + '-avg-total') -Value 0 -force
    }

    $date = Get-Date

    # loop through each VM
    foreach ($i in $vmlist) {
        Write-Verbose "-> Gathering info for VM - $($i.Name)" -Verbose

        $uptime = Get-AzVMUptime -VMName $i.name -ResourceGroupName $i.ResourceGroupName -vmList $vmlist -WarningAction SilentlyContinue

        # grab disk info for each VM
        $disklist = $i.StorageProfile.DataDisks
        try {
                $vmstatavg = Get-AzMetric -ResourceId $i.Id -TimeGrain $timegrain -StartTime $StartDate -EndTime $EndDate -MetricName 'Available Memory Bytes' -AggregationType Average -WarningAction SilentlyContinue
        } catch {
                Write-Verbose "-> Unable to gather VM metrics for $($i.Name)" -Verbose
                $vmstatavg = $null
        }

        if ($disklist) {
            foreach ($d in $disklist) {
                $diskInfo = Get-AzDisk -Name $d.Name -ResourceGroupName $i.ResourceGroupName
                $o = New-Object psobject

                $diskname = $diskInfo.Name

                # Collect desired info from VM and Disk queries
                $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
                try {
                    $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
                } catch {
                    $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
                }
                $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
                $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
                $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $diskInfo.Name
                $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $diskInfo.Sku.name
                # $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value $cost.armSkuName
                $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $diskInfo.DiskSizeGB
                $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $diskInfo.Sku.Tier
                $o | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value $diskInfo.Tier
                $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $diskInfo.DiskIOPSReadWrite
                $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $diskInfo.DiskMBpsReadWrite
                $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $diskInfo.ResourceGroupName
                $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $diskInfo.Location
                $o | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $uptime.UptimePercentage
                $o | Add-Member -MemberType NoteProperty -Name "Days" -Value $days
                
                $totalDiskSizeGB = $totalDiskSizeGB + $diskInfo.DiskSizeGB
                $totalDiskIOPS = $totalDiskIOPS + $diskInfo.DiskIOPSReadWrite
                $totalDiskMBps = $totalDiskMBps + $diskInfo.DiskMBpsReadWrite

                foreach ($m in $metrics) {
                    Write-Verbose "---> Gathering $m for $diskname --" -Verbose
                    $statavg = Get-AzMetric -ResourceId $diskInfo.Id -TimeGrain $timegrain -StartTime $date.AddDays(-$days) -EndTime $date -MetricName $m -AggregationType Average -WarningAction SilentlyContinue
                    $o | Add-Member -MemberType NoteProperty -Name ($m.replace(' ', $null) + '-avg') -Value $statavg.data.Average
                    if ($statavg.data.Average) {
                        New-Variable -Name ($m.replace(' ', $null) + '-avg-total') -Value ((Get-Variable -Name ($m.replace(' ', $null) + '-avg-total')).Value + $statavg.data.Average) -force
                    }
                }
                
                $thelist += $o
            } 
        } else {
            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
            try {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
            } catch {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
            }
            $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
            $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
            $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value 'N/A'
            # $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value $diskInfo.Tier
            $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Region" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $uptime.UptimePercentage
            $o | Add-Member -MemberType NoteProperty -Name "Days" -Value 'N/A'

            $thelist += $o
        }
    }

    return $thelist
}