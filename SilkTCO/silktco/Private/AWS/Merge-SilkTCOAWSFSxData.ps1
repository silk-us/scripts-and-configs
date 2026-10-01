function Merge-SilkTCOAWSFSxData {
    param (
        [Parameter(Mandatory)]
        [array] $fslist,
        [Parameter(Mandatory)]
        [array] $metrics,
        [Parameter()]
        [array] $costs
    )

    $newarray = @()

    foreach ($fs in $fslist) {
        $fsId = $fs.FileSystemId
        $rows = @($metrics | Where-Object { $_.FileSystemId -eq $fsId })
        if (-not $rows) { continue }

        # fsx bills the filesystem, not the volume. rather than spread an estimate across
        # every volume row we put the whole thing on the first row and null the rest -
        # same trick the ec2 merge uses for VMCostUSD. column still sums correctly.
        $fsCompute = $null
        $fsStorage = $null
        if ($costs) {
            $computeMatch = $costs | Where-Object { $_.ResourceId -eq $fsId -and $_.MeterCategory -eq 'Compute' }
            $storageMatch = $costs | Where-Object { $_.ResourceId -eq $fsId -and $_.MeterCategory -eq 'Storage' }
            if ($computeMatch) { $fsCompute = ($computeMatch | Measure-Object -Property Cost -Sum).Sum }
            if ($storageMatch) { $fsStorage = ($storageMatch | Measure-Object -Property Cost -Sum).Sum }
        }

        $first = $true
        foreach ($r in $rows) {
            $obj = New-Object psobject
            $obj | Add-Member -MemberType NoteProperty -Name VMName -Value $r."FS name"
            $obj | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $r.ResourceGroup
            $obj | Add-Member -MemberType NoteProperty -Name Zone -Value $r."FS Zone"
            $obj | Add-Member -MemberType NoteProperty -Name VMSize -Value $r."FS size"
            $obj | Add-Member -MemberType NoteProperty -Name DiskName -Value $r."Volume Name"
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadMB -Value $r."ReadMBps-avg"
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteMB -Value $r."WriteMBps-avg"
            $obj | Add-Member -MemberType NoteProperty -Name DiskReadIOPS -Value $r."ReadIOPS-avg"
            $obj | Add-Member -MemberType NoteProperty -Name DiskWriteIOPS -Value $r."WriteIOPS-avg"
            $obj | Add-Member -MemberType NoteProperty -Name DiskCostUSD -Value $(if ($first) { $fsStorage } else { $null })
            $obj | Add-Member -MemberType NoteProperty -Name VMCostUSD -Value $(if ($first) { $fsCompute } else { $null })
            $obj | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $r.VolumeSizeGB
            $obj | Add-Member -MemberType NoteProperty -Name "Disk SKU" -Value 'ONTAP'
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $r.TieringPolicy
            $obj | Add-Member -MemberType NoteProperty -Name "Disk Class" -Value 'SSD+CapacityPool'
            $obj | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $r.ProvisionedIOPS
            $obj | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $r.ThroughputCapacityMBps
            $obj | Add-Member -MemberType NoteProperty -Name "Region" -Value $r.Region
            # always-on managed service, nothing was actually measured so dont imply 100
            $obj | Add-Member -MemberType NoteProperty -Name "UptimePercentage" -Value 'N/A'
            $obj | Add-Member -MemberType NoteProperty -Name Days -Value $r.Days
            $newarray += $obj

            $first = $false
        }
    }

    return $newarray
}
