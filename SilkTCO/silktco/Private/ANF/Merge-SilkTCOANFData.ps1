function Merge-SilkTCOANFData {
    param (
        [Parameter(Mandatory)]
        [array] $anflist,
        [Parameter()]
        [array] $costs
    )

    $newarray = @()

    # every row carries the same columns so pool/volume/snapshot rows stack in one csv,
    # same shape as the rds report
    function New-AnfRow {
        $o = New-Object psobject
        $cols = @(
            'RecordType','NetAppAccount','PoolName','VolumeName','ResourceGroupName','Region','Zone',
            'ServiceLevel','QosType','ProvisionedGiB','ProvisionedTiB','ThroughputCeilingMiBps',
            'AssignedThroughputMiBps','UtilizedThroughputMiBps','ProtocolTypes','NetworkFeatures',
            'CoolAccess','CoolnessPeriodDays','IsLargeVolume','SnapshotPolicy','ReplicationEndpointType',
            'ReplicationSchedule','Encryption','AllocatedToVolumesGiB','StrandedGiB','PoolUtilizationPct',
            'SnapshotCount','Days','ListRateGiBMonthUSD',
            'ProvisionedCostPeriodUSD','ProvisionedCostMonthlyUSD',
            'ActualCostPeriodUSD','ActualCostMonthlyUSD','CostVariancePct',
            'ApportionedCostPeriodUSD','ApportionedCostMonthlyUSD','CostNotes','Created'
        )
        foreach ($c in $cols) { $o | Add-Member -MemberType NoteProperty -Name $c -Value $null }
        return $o
    }

    foreach ($item in $anflist) {

        # backup vaults are their own thing, one row and move on
        if ($item.IsBackupVault) {
            $backups = @($item.Backups)
            $row = New-AnfRow
            $row.RecordType = 'BackupVault'
            $row.NetAppAccount = $item.NetAppAccount
            $row.PoolName = $item.BackupVault
            $row.ResourceGroupName = $item.ResourceGroupName
            $row.Region = $item.Region
            $row.SnapshotCount = $backups.Count
            if ($backups) {
                $sz = ($backups | Measure-Object -Property Size -Sum).Sum
                if ($sz) { $row.ProvisionedGiB = [Math]::Round($sz / 1GB, 2) }
            }
            $newarray += $row
            continue
        }

        $poolCost = $null
        if ($costs) {
            $poolCost = $costs | Where-Object { $_.ResourceId -eq $item.ResourceId } | Select-Object -First 1
        }

        # --- pool row: this is where the money actually lands ---
        $row = New-AnfRow
        $row.RecordType = 'Pool'
        $row.NetAppAccount = $item.NetAppAccount
        $row.PoolName = $item.PoolName
        $row.ResourceGroupName = $item.ResourceGroupName
        $row.Region = $item.Region
        $row.ServiceLevel = $item.ServiceLevel
        $row.QosType = $item.QosType
        $row.ProvisionedGiB = $item.ProvisionedGiB
        $row.ProvisionedTiB = $item.ProvisionedTiB
        $row.ThroughputCeilingMiBps = $item.ThroughputCeilingMiBps
        $row.UtilizedThroughputMiBps = $item.UtilizedThroughputMiBps
        $row.CoolAccess = $item.CoolAccess
        $row.Encryption = $item.EncryptionType
        $row.AllocatedToVolumesGiB = $item.AllocatedToVolumesGiB
        $row.StrandedGiB = $item.StrandedGiB
        $row.PoolUtilizationPct = $item.PoolUtilizationPct
        $row.SnapshotCount = @($item.Volumes | ForEach-Object { @($_.Snapshots).Count } | Measure-Object -Sum).Sum
        if ($poolCost) {
            $row.Days = $poolCost.Days
            $row.ListRateGiBMonthUSD = $poolCost.ListRateGiBMonthUSD
            $row.ProvisionedCostPeriodUSD = $poolCost.ProvisionedCostPeriodUSD
            $row.ProvisionedCostMonthlyUSD = $poolCost.ProvisionedCostMonthlyUSD
            $row.ActualCostPeriodUSD = $poolCost.ActualCostPeriodUSD
            $row.ActualCostMonthlyUSD = $poolCost.ActualCostMonthlyUSD
            $row.CostVariancePct = $poolCost.CostVariancePct
            $row.CostNotes = $poolCost.CostNotes
        }
        $newarray += $row

        # --- volume rows ---
        foreach ($v in @($item.Volumes)) {
            $vrow = New-AnfRow
            $vrow.RecordType = 'Volume'
            $vrow.NetAppAccount = $item.NetAppAccount
            $vrow.PoolName = $item.PoolName
            $vrow.VolumeName = $v.VolumeName
            $vrow.ResourceGroupName = $item.ResourceGroupName
            $vrow.Region = $v.Location
            $vrow.Zone = $v.Zone
            $vrow.ServiceLevel = $v.ServiceLevel
            $vrow.QosType = $item.QosType
            $vrow.ProvisionedGiB = $v.ProvisionedGiB
            $vrow.ProvisionedTiB = [Math]::Round($v.ProvisionedGiB / 1024, 4)
            $vrow.ThroughputCeilingMiBps = $v.ThroughputCeilingMiBps
            $vrow.AssignedThroughputMiBps = $v.AssignedThroughputMiBps
            $vrow.ProtocolTypes = $v.ProtocolTypes
            $vrow.NetworkFeatures = $v.NetworkFeatures
            $vrow.CoolAccess = $v.CoolAccess
            $vrow.CoolnessPeriodDays = $v.CoolnessPeriodDays
            $vrow.IsLargeVolume = $v.IsLargeVolume
            $vrow.SnapshotPolicy = $v.SnapshotPolicy
            $vrow.ReplicationEndpointType = $v.ReplicationEndpointType
            $vrow.ReplicationSchedule = $v.ReplicationSchedule
            $vrow.Encryption = $v.EncryptionKeySource
            $vrow.SnapshotCount = @($v.Snapshots).Count

            # anf bills the pool, so anything here is a derived share, not a billed figure.
            # kept in its own column so an estimate never sits next to a real number.
            if ($poolCost -and $item.ProvisionedGiB -gt 0) {
                $vrow.Days = $poolCost.Days
                $fraction = $v.ProvisionedGiB / $item.ProvisionedGiB

                # prefer the billed figure, fall back to the rate card
                if ($poolCost.ActualCostMonthlyUSD) {
                    $vrow.ApportionedCostPeriodUSD = [Math]::Round($fraction * $poolCost.ActualCostPeriodUSD, 4)
                    $vrow.ApportionedCostMonthlyUSD = [Math]::Round($fraction * $poolCost.ActualCostMonthlyUSD, 2)
                } elseif ($poolCost.ProvisionedCostMonthlyUSD) {
                    $vrow.ApportionedCostPeriodUSD = [Math]::Round($fraction * $poolCost.ProvisionedCostPeriodUSD, 4)
                    $vrow.ApportionedCostMonthlyUSD = [Math]::Round($fraction * $poolCost.ProvisionedCostMonthlyUSD, 2)
                    $vrow.CostNotes = 'apportioned from list price'
                }
            }

            $newarray += $vrow

            # --- snapshot rows. count + date only: ARM exposes no size on an anf snapshot,
            # that only comes from the VolumeSnapshotSize metric which we deliberately skip
            foreach ($s in @($v.Snapshots)) {
                $srow = New-AnfRow
                $srow.RecordType = 'Snapshot'
                $srow.NetAppAccount = $item.NetAppAccount
                $srow.PoolName = $item.PoolName
                $srow.VolumeName = $v.VolumeName
                $srow.ResourceGroupName = $item.ResourceGroupName
                $srow.Region = $v.Location
                $srow.SnapshotPolicy = ($s.Name -split '/')[-1]
                $srow.Created = $s.Created
                $srow.CostNotes = 'snapshot capacity not available without metrics'
                $newarray += $srow
            }
        }
    }

    return $newarray
}
