function Merge-SilkTCOAWSRDSData {
    param (
        [Parameter(Mandatory)]
        [array] $rdslist,
        [Parameter(Mandatory)]
        [array] $metrics,
        [Parameter()]
        [array] $costs,
        [Parameter()]
        [array] $snapshots
    )

    $newarray = @()

    foreach ($db in $rdslist) {
        $dbId = $db.DBInstanceIdentifier
        $m = $metrics | Where-Object { $_.DBInstanceIdentifier -eq $dbId }

        # match up costs by db identifier - compute + storage
        if ($costs) {
            $computeMatch = $costs | Where-Object { $_.ResourceId -eq $dbId -and $_.MeterCategory -eq 'Compute' }
            $storageMatch = $costs | Where-Object { $_.ResourceId -eq $dbId -and $_.MeterCategory -eq 'Storage' }
            $instanceCost = if ($computeMatch) { ($computeMatch | Measure-Object -Property Cost -Sum).Sum } else { $null }
            $storageCost = if ($storageMatch) { ($storageMatch | Measure-Object -Property Cost -Sum).Sum } else { $null }
        } else {
            $instanceCost = $null
            $storageCost = $null
        }

        # roll up this instance's snapshots into a few summary columns
        $snapsForDb = @()
        if ($snapshots) { $snapsForDb = @($snapshots | Where-Object { $_.SourceInstance -eq $dbId }) }

        $manualCount = @($snapsForDb | Where-Object { $_.Class -eq 'manual' }).Count
        $autoCount   = @($snapsForDb | Where-Object { $_.SnapshotType -eq 'automated' }).Count
        $copyCount   = @($snapsForDb | Where-Object { $_.IsCopy }).Count
        $snapSize    = if ($snapsForDb) { ($snapsForDb | Measure-Object -Property SizeGB -Sum).Sum } else { 0 }
        $newest      = if ($snapsForDb) { ($snapsForDb | Sort-Object Created -Descending | Select-Object -First 1).Created } else { $null }

        # compact lineage string, e.g. "silktco-snaptest-01[manual]; silktco-snaptest-01-copy[copy<-silktco-snaptest-01]"
        $snapDetail = if ($snapsForDb) {
            (($snapsForDb | ForEach-Object {
                if ($_.IsCopy) { "$($_.SnapshotName)[copy<-$($_.CopiedFromName)]" }
                else { "$($_.SnapshotName)[$($_.Class)]" }
            }) -join '; ')
        } else { $null }

        $obj = New-Object psobject
        $obj | Add-Member -MemberType NoteProperty -Name RecordType -Value 'Instance'
        $obj | Add-Member -MemberType NoteProperty -Name DBName -Value $dbId
        $obj | Add-Member -MemberType NoteProperty -Name SourceInstance -Value $null
        $obj | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $m.ResourceGroup
        $obj | Add-Member -MemberType NoteProperty -Name Zone -Value $m."DB Zone"
        $obj | Add-Member -MemberType NoteProperty -Name DBClass -Value $m."DB Class"
        $obj | Add-Member -MemberType NoteProperty -Name Engine -Value $m.Engine
        $obj | Add-Member -MemberType NoteProperty -Name EngineVersion -Value $m.EngineVersion
        $obj | Add-Member -MemberType NoteProperty -Name MultiAZ -Value $m.MultiAZ
        $obj | Add-Member -MemberType NoteProperty -Name StorageType -Value $m.StorageType
        $obj | Add-Member -MemberType NoteProperty -Name AllocatedStorageGB -Value $m.AllocatedStorageGB
        $obj | Add-Member -MemberType NoteProperty -Name MaxAllocatedStorageGB -Value $m.MaxAllocatedStorageGB
        $obj | Add-Member -MemberType NoteProperty -Name UsedStorageGBavg -Value $m."UsedStorageGB-avg"
        $obj | Add-Member -MemberType NoteProperty -Name UsedStorageGBpeak -Value $m."UsedStorageGB-peak"
        $obj | Add-Member -MemberType NoteProperty -Name ProvisionedIOPS -Value $m.ProvisionedIOPS
        $obj | Add-Member -MemberType NoteProperty -Name StorageThroughputMBps -Value $m.StorageThroughputMBps
        $obj | Add-Member -MemberType NoteProperty -Name ReadIOPSavg -Value $m."ReadIOPS-avg"
        $obj | Add-Member -MemberType NoteProperty -Name ReadIOPSmax -Value $m."ReadIOPS-max"
        $obj | Add-Member -MemberType NoteProperty -Name WriteIOPSavg -Value $m."WriteIOPS-avg"
        $obj | Add-Member -MemberType NoteProperty -Name WriteIOPSmax -Value $m."WriteIOPS-max"
        $obj | Add-Member -MemberType NoteProperty -Name ReadMBpsavg -Value $m."ReadThroughputMBps-avg"
        $obj | Add-Member -MemberType NoteProperty -Name ReadMBpsmax -Value $m."ReadThroughputMBps-max"
        $obj | Add-Member -MemberType NoteProperty -Name WriteMBpsavg -Value $m."WriteThroughputMBps-avg"
        $obj | Add-Member -MemberType NoteProperty -Name WriteMBpsmax -Value $m."WriteThroughputMBps-max"
        $obj | Add-Member -MemberType NoteProperty -Name ReadLatencyMsavg -Value $m."ReadLatencyMs-avg"
        $obj | Add-Member -MemberType NoteProperty -Name WriteLatencyMsavg -Value $m."WriteLatencyMs-avg"
        $obj | Add-Member -MemberType NoteProperty -Name DiskQueueDepthavg -Value $m."DiskQueueDepth-avg"
        $obj | Add-Member -MemberType NoteProperty -Name DiskQueueDepthmax -Value $m."DiskQueueDepth-max"
        $obj | Add-Member -MemberType NoteProperty -Name CPUUtilavg -Value $m."CPUUtilization-avg"
        $obj | Add-Member -MemberType NoteProperty -Name CPUUtilmax -Value $m."CPUUtilization-max"
        $obj | Add-Member -MemberType NoteProperty -Name FreeableMemoryGBavg -Value $m."FreeableMemoryGB-avg"
        $obj | Add-Member -MemberType NoteProperty -Name InstanceCostUSD -Value $instanceCost
        $obj | Add-Member -MemberType NoteProperty -Name StorageCostUSD -Value $storageCost
        $obj | Add-Member -MemberType NoteProperty -Name SnapshotCount -Value $snapsForDb.Count
        $obj | Add-Member -MemberType NoteProperty -Name ManualSnapshots -Value $manualCount
        $obj | Add-Member -MemberType NoteProperty -Name AutomatedSnapshots -Value $autoCount
        $obj | Add-Member -MemberType NoteProperty -Name SnapshotCopies -Value $copyCount
        $obj | Add-Member -MemberType NoteProperty -Name SnapshotTotalSizeGB -Value $snapSize
        $obj | Add-Member -MemberType NoteProperty -Name NewestSnapshot -Value $newest
        $obj | Add-Member -MemberType NoteProperty -Name SnapshotDetail -Value $snapDetail
        $obj | Add-Member -MemberType NoteProperty -Name Region -Value $m.Region
        $obj | Add-Member -MemberType NoteProperty -Name Days -Value $m.Days
        $newarray += $obj
    }

    # also emit one row per snapshot so they show up individually, not just as instance summary cols.
    # orphaned snaps (source db gone) get listed here too.
    if ($snapshots) {
        $cols = if ($newarray.Count) { $newarray[0].psobject.Properties.Name } else { @() }
        foreach ($s in $snapshots) {
            $row = New-Object psobject
            foreach ($c in $cols) { $row | Add-Member -MemberType NoteProperty -Name $c -Value $null }
            $row.RecordType = 'Snapshot'
            $row.DBName = $s.SnapshotName
            $row.SourceInstance = $s.SourceInstance
            $row.Engine = $s.Engine
            $row.AllocatedStorageGB = $s.SizeGB
            $row.NewestSnapshot = $s.Created
            # type + lineage in one cell: 'manual' / 'automated' / 'copy<-parent'
            $row.SnapshotDetail = if ($s.IsCopy) { "copy<-$($s.CopiedFromName)" } else { $s.Class }
            $newarray += $row
        }
    }

    return $newarray
}
