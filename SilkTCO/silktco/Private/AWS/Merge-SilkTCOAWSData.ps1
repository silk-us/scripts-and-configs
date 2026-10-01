function Merge-SilkTCOAWSData {
    param (
        [Parameter(Mandatory)]
        [array] $vmlist,
        [Parameter(Mandatory)]
        [array] $metrics,
        [Parameter()]
        [array] $costs,
        [Parameter()]
        [switch] $breakoutVMs
    )

    $newarray = @()

    foreach ($vm in $vmlist) {
        $instanceId = $vm.InstanceId
        $nameTag = ($vm.Tags | Where-Object { $_.Key -eq 'Name' }).Value
        $vmName = if ($nameTag) { $nameTag } else { $instanceId }
        $zone = $vm.Placement.AvailabilityZone
        $vmSize = $vm.InstanceType.Value

        # Get resource group equivalent from tags
        $rgTag = ($vm.Tags | Where-Object { $_.Key -eq 'ResourceGroup' -or $_.Key -eq 'Project' -or $_.Key -eq 'Environment' }).Value
        $rgName = if ($rgTag) { $rgTag } else { 'N/A' }

        $diskmetrics = $metrics | Where-Object { $_.InstanceId -eq $instanceId }

        # Match VM compute costs - look for EC2 instance costs
        if ($costs) {
            $vmCostMatches = $costs | Where-Object { $_.ResourceId -eq $instanceId -and $_.MeterCategory -eq 'Compute' }
            $vmcost = if ($vmCostMatches) { 
                ($vmCostMatches | Measure-Object -Property Cost -Sum).Sum 
            } else { 
                $null 
            }
        } else {
            $vmcost = $null
        }

        if ($breakoutVMs) {
            Write-Verbose "---> Breaking out VM: $vmName" -Verbose
            $obj = New-Object psobject
            $obj | Add-Member -MemberType NoteProperty -Name VMName -Value $vmName
            $obj | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $rgName
            $obj | Add-Member -MemberType NoteProperty -Name Zone -Value $zone
            $obj | Add-Member -MemberType NoteProperty -Name VMSize -Value $vmSize
            $obj | Add-Member -MemberType NoteProperty -Name DiskName -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadMB -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteMB -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadIOPS -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteIOPS -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name DiskCostUSD -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name VMCostUSD -Value $vmcost
            $obj | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Disk SKU" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "Region" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $null
            $obj | Add-Member -MemberType NoteProperty -Name Days -Value $null
            $newarray += $obj
            $vmcost = $null
        }

        foreach ($d in $diskmetrics) {
            $volumeId = $d."Disk Name"

            # Match EBS volume costs
            if ($costs) {
                $diskcost = $costs | Where-Object { $_.ResourceId -eq $volumeId -and $_.MeterCategory -eq 'Storage' }
            } else {
                $diskcost = $null
            }

            # Convert bytes/sec to MB/sec
            $readMB = if ($d."CompositeDiskReadBytes/sec-avg") { [Math]::Round($d."CompositeDiskReadBytes/sec-avg" / 1MB, 2) } else { $null }
            $writeMB = if ($d."CompositeDiskWriteBytes/sec-avg") { [Math]::Round($d."CompositeDiskWriteBytes/sec-avg" / 1MB, 2) } else { $null }
            
            $obj = New-Object psobject
            $obj | Add-Member -MemberType NoteProperty -Name VMName -Value $vmName
            $obj | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $rgName
            $obj | Add-Member -MemberType NoteProperty -Name Zone -Value $zone
            $obj | Add-Member -MemberType NoteProperty -Name VMSize -Value $vmSize
            $obj | Add-Member -MemberType NoteProperty -Name DiskName -Value $d."Disk Name"
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadMB -Value $readMB
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteMB -Value $writeMB
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadIOPS -Value $(if ($d."CompositeDiskReadOperations/Sec-avg") { [Math]::Round($d."CompositeDiskReadOperations/Sec-avg", 2) } else { $null })
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteIOPS -Value $(if ($d."CompositeDiskWriteOperations/Sec-avg") { [Math]::Round($d."CompositeDiskWriteOperations/Sec-avg", 2) } else { $null })
            $obj | Add-Member -MemberType NoteProperty -Name DiskCostUSD -Value $(if ($diskcost) { $diskcost.Cost } else { $null })
            $obj | Add-Member -MemberType NoteProperty -Name VMCostUSD -Value $vmcost
            $obj | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $d.DiskSizeGB
            $obj | Add-Member -MemberType NoteProperty -Name "Disk SKU" -Value $d.DiskSKU
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $d."Disk Class"
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value $d."Disk Tier"
            $obj | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $d."Disk IOPS"
            $obj | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $d."Disk MBps"
            $obj | Add-Member -MemberType NoteProperty -Name "Region" -Value $d.Region
            $obj | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value $d.UptimePercentage
            $obj | Add-Member -MemberType NoteProperty -Name Days -Value $d.Days
            $newarray += $obj
        }
    }
    return $newarray
}
