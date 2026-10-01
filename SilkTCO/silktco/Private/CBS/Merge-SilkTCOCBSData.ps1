function Merge-SilkTCOCBSData {
    param (
        [Parameter(Mandatory)]
        $arrayData,
        [Parameter()]
        $azureCost
    )

    $newarray = @()

    function New-CbsRow {
        $o = New-Object psobject
        $cols = @(
            'RecordType','ArrayName','ObjectName','Model','PurityVersion','ManagedResourceGroup',
            'ProvisionedGiB','PhysicalGiB','UniqueGiB','SnapshotsGiB','DataReduction','TotalReduction',
            'ThinProvisioning','UsableCapacityTiB','ControllerVMSizes','ControllerVMCount',
            'BackingDiskCount','BackingDiskGiB','DeployedDiskIOPSCeiling','DeployedDiskMBpsCeiling',
            'CostBucket','ResourceType','MeterCategory','PublisherType','CostPeriodUSD','CostMonthlyUSD',
            'MappedVolumes','ConnectionCount','CostNotes'
        )
        foreach ($c in $cols) { $o | Add-Member -MemberType NoteProperty -Name $c -Value $null }
        return $o
    }

    $a = $arrayData.Array
    $infra = if ($azureCost) { $azureCost.Infrastructure } else { $null }
    $lines = if ($azureCost) { @($azureCost.CostLines) } else { @() }

    # --- array summary. capacity, reduction and the whole azure bill in one row ---
    $row = New-CbsRow
    $row.RecordType = 'Array'
    $row.ArrayName = $a.ArrayName
    $row.ObjectName = $a.ArrayName
    $row.Model = $a.Model
    $row.PurityVersion = $a.PurityVersion
    $row.UsableCapacityTiB = $a.UsableCapacityTiB
    $row.ProvisionedGiB = $(if ($a.TotalProvisionedTiB) { [Math]::Round($a.TotalProvisionedTiB * 1024, 2) } else { $null })
    $row.PhysicalGiB = $(if ($a.TotalPhysicalTiB) { [Math]::Round($a.TotalPhysicalTiB * 1024, 2) } else { $null })
    $row.UniqueGiB = $(if ($a.UniqueTiB) { [Math]::Round($a.UniqueTiB * 1024, 2) } else { $null })
    $row.SnapshotsGiB = $(if ($a.SnapshotsTiB) { [Math]::Round($a.SnapshotsTiB * 1024, 2) } else { $null })
    $row.DataReduction = $a.DataReduction
    $row.TotalReduction = $a.TotalReduction
    $row.ThinProvisioning = $a.ThinProvisioning

    if ($infra) {
        $row.ManagedResourceGroup = $infra.ManagedResourceGroup
        $row.ControllerVMSizes = $infra.ControllerVMSizes
        $row.ControllerVMCount = $infra.ControllerVMCount
        $row.BackingDiskCount = $infra.BackingDiskCount
        $row.BackingDiskGiB = $infra.BackingDiskGiB
        $row.DeployedDiskIOPSCeiling = $infra.DeployedDiskIOPSCeiling
        $row.DeployedDiskMBpsCeiling = $infra.DeployedDiskMBpsCeiling
    }

    if ($lines) {
        $row.CostPeriodUSD = [Math]::Round((($lines | Measure-Object -Property CostPeriod -Sum).Sum), 2)
        $row.CostMonthlyUSD = [Math]::Round((($lines | Measure-Object -Property CostMonthly -Sum).Sum), 2)
        $row.CostBucket = 'AllBuckets'
    }

    $notes = @()
    if ($azureCost -and -not $azureCost.MarketplaceLicenseDetected) {
        $notes += 'no marketplace license charge in azure - infra only, license may be billed by Pure directly'
    }
    if (-not $azureCost) {
        $notes += 'azure cost not collected - array data only'
    }
    $row.CostNotes = $(if ($notes) { $notes -join '; ' } else { $null })
    $newarray += $row

    # --- one row per cost bucket so the blob line is visible on its own ---
    foreach ($g in ($lines | Group-Object Bucket)) {
        $brow = New-CbsRow
        $brow.RecordType = 'AzureCost'
        $brow.ArrayName = $a.ArrayName
        $brow.ObjectName = $g.Name
        $brow.ManagedResourceGroup = $(if ($infra) { $infra.ManagedResourceGroup } else { $null })
        $brow.CostBucket = $g.Name
        $brow.ResourceType = (($g.Group.ResourceType | Sort-Object -Unique) -join '; ')
        $brow.MeterCategory = (($g.Group.MeterCategory | Sort-Object -Unique) -join '; ')
        $brow.PublisherType = (($g.Group.PublisherType | Sort-Object -Unique) -join '; ')
        $brow.CostPeriodUSD = [Math]::Round((($g.Group | Measure-Object -Property CostPeriod -Sum).Sum), 2)
        $brow.CostMonthlyUSD = [Math]::Round((($g.Group | Measure-Object -Property CostMonthly -Sum).Sum), 2)
        if ($g.Name -eq 'BlobStorage') {
            $brow.CostNotes = 'cbs lands data in blob - scales with physical (post reduction) capacity'
        }
        $newarray += $brow
    }

    # --- volumes ---
    foreach ($v in @($arrayData.Volumes)) {
        $vrow = New-CbsRow
        $vrow.RecordType = 'Volume'
        $vrow.ArrayName = $a.ArrayName
        $vrow.ObjectName = $v.VolumeName
        $vrow.ProvisionedGiB = $v.ProvisionedGiB
        $vrow.PhysicalGiB = $v.TotalPhysicalGiB
        $vrow.UniqueGiB = $v.UniqueGiB
        $vrow.SnapshotsGiB = $v.SnapshotsGiB
        $vrow.DataReduction = $v.DataReduction
        if ($v.Destroyed) { $vrow.CostNotes = 'destroyed - still consuming space until eradicated' }
        $newarray += $vrow
    }

    # --- host mappings, so cbs volumes can be tied back to vms in the other reports ---
    foreach ($h in @($arrayData.Hosts)) {
        $hrow = New-CbsRow
        $hrow.RecordType = 'Host'
        $hrow.ArrayName = $a.ArrayName
        $hrow.ObjectName = $h.HostName
        $hrow.MappedVolumes = $h.MappedVolumes
        $hrow.ConnectionCount = $h.ConnectionCount
        $newarray += $hrow
    }

    # --- protection groups ---
    foreach ($pg in @($arrayData.ProtectionGroups)) {
        $prow = New-CbsRow
        $prow.RecordType = 'ProtectionGroup'
        $prow.ArrayName = $a.ArrayName
        $prow.ObjectName = $pg.GroupName
        $prow.SnapshotsGiB = $pg.SnapshotsGiB
        $prow.PhysicalGiB = $pg.TotalPhysicalGiB
        $prow.ConnectionCount = $pg.VolumeCount
        $newarray += $prow
    }

    return $newarray
}
