function Merge-SilkTCOAzureData {
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

    # 2dp, but leave a missing value missing instead of letting Round turn it into 0
    function Format-SilkMetric {
        param($value)
        $vals = @($value | Where-Object { $null -ne $_ })
        if (-not $vals.Count) { return $null }
        return [Math]::Round((($vals | Measure-Object -Average).Average), 2)
    }

    foreach ($vm in $vmlist) {
        $vmname = $vm.Name
        $rgname = $vm.ResourceGroupName
        $vmId = $vm.id
        $diskmetrics = $metrics | Where-Object { $_."VM Name" -eq $vmname -and $_.ResourceGroup -eq $rgname }
        $vmskucost = $costs | Where-Object { $_.ResourceName -eq $vmname -and $_.MeterCategory -eq "Virtual Machines" -and $_.ResourceId -eq $vmId}
        # $vmcost = $vmskucost.Cost
        # sum it - more than one line comes back as an array and lands in the csv as System.Object[]
        $vmcost = if ($vmskucost) { [Math]::Round((($vmskucost | Measure-Object -Property Cost -Sum).Sum), 4) } else { $null }

        if ($breakoutVMs) {
            Write-Verbose "---> Breaking out VM: $vmname" -Verbose
            $obj = [PSCustomObject] @{
                VMName              = $vmname
                ResourceGroupName   = $rgname
                Zone               = $vm.Zones -join ","
                VMSize              = $vm.HardwareProfile.VmSize
                DiskName            = $null
                DiskReadMB          = $null
                DiskWriteMB         = $null
                DiskReadIOPS        = $null
                DiskWriteIOPS       = $null
                DiskCostUSD         = $null
                VMCostUSD           = $vmcost
                "DiskSizeGB"        = $null
                "Disk SKU"          = $null
                "Disk Tier"         = $null
                "Disk Class"        = $null
                "Disk IOPS"         = $null
                "Disk MBps"         = $null
                "Region"            = $null 
                "UptimePercentage"  = $null
                Days                = $null
            }
            $newarray += $obj
            $vmcost = $null
        } 
        
        foreach ($d in $diskmetrics) {

            # Write-Verbose "-> Processing disk $($d.'disk name') for VM $($vmname)" -Verbose
            # $azDisk = Get-AzDisk -ResourceGroupName $rgname -Name $d."disk name"
            $drg = ($d.ResourceGroup).ToLower()
            $diskcost = $costs | Where-Object { $_.ResourceName -eq $d."disk name" -and $_.MeterCategory -eq "Storage" -and $_.ResourceId -match $drg}

            $obj = [PSCustomObject] @{
                VMName              = $vmname
                ResourceGroupName   = $rgname
                Zone                = $vm.Zones -join ","
                VMSize              = $vm.HardwareProfile.VmSize
                DiskName            = $d."disk name"
                DiskReadMB          = Format-SilkMetric $d."CompositeDiskReadBytes/sec-avg"
                DiskWriteMB         = Format-SilkMetric $d."CompositeDiskWriteBytes/sec-avg"
                DiskReadIOPS        = Format-SilkMetric $d."CompositeDiskReadOperations/Sec-avg"
                DiskWriteIOPS       = Format-SilkMetric $d."CompositeDiskWriteOperations/Sec-avg"
                DiskCostUSD         = $(if ($diskcost) { [Math]::Round((($diskcost | Measure-Object -Property Cost -Sum).Sum), 4) } else { $null })
                VMCostUSD           = $vmcost
                "DiskSizeGB"        = $d.DiskSizeGB
                "Disk SKU"          = $d.DiskSKU
                "Disk Tier"         = $d."Disk Class"
                "Disk Class"        = $d."Disk Tier"
                "Disk IOPS"         = $d."Disk IOPS"
                "Disk MBps"         = $d."Disk MBps"
                "Region"            = $d.Region 
                "UptimePercentage"  = $d.UptimePercentage 
                Days                = $d.Days
            }
            $newarray += $obj
        }
    } 
    return $newarray
}


