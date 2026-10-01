Function Export-SilkTCOAWSRDS {
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int] $days = 1,
        [Parameter()]
        [ValidateRange(0, 365)]
        [int] $offsetDays = 1,
        [Parameter()]
        [string] $region,
        [Parameter()]
        [string] $inputFile,
        [Parameter()]
        [string] $TagKey,
        [Parameter()]
        [string] $TagValue,
        [Parameter()]
        [switch] $allDBs
    )

    # build params for the discovery call
    $rdsListParams = @{}
    if ($region) { $rdsListParams['Region'] = $region }
    if ($inputFile) { $rdsListParams['inputFile'] = $inputFile }
    if ($TagKey) { $rdsListParams['TagKey'] = $TagKey }
    if ($TagValue) { $rdsListParams['TagValue'] = $TagValue }
    if ($allDBs) { $rdsListParams['allDBs'] = $true }

    $rdslist = New-SilkTCOAWSRDSList @rdsListParams

    if (-not $rdslist) {
        Write-Warning "No RDS instances found for the given filters."
        return
    }

    $metrics = New-SilkTCOAWSRDSMetrics -rdslist $rdslist -days $days -offsetDays $offsetDays -Verbose

    # pass region if we have it, otherwise let cost func auto-detect
    if ($region) {
        $costs = New-SilkTCOAWSRDSCostArray -rdslist $rdslist -region $region -days $days -Verbose
    } else {
        $costs = New-SilkTCOAWSRDSCostArray -rdslist $rdslist -days $days -Verbose
    }

    # pull snapshots + lineage and fold them into the same report
    $snapRegion = @{}
    if ($region) { $snapRegion['region'] = $region }
    $snapshots = New-SilkTCOAWSRDSSnapshotList @snapRegion -liveIds $rdslist.DBInstanceIdentifier

    # heads up on orphaned snaps - source db is gone but storage still bills. they wont show on an instance row
    $orphans = @($snapshots | Where-Object { $_.Orphaned })
    if ($orphans) {
        $orphanGB = ($orphans | Measure-Object -Property SizeGB -Sum).Sum
        Write-Warning "$($orphans.Count) orphaned snapshot(s) found (source instance deleted), ~$orphanGB GB still billing and not tied to any live instance."
    }

    $report = Merge-SilkTCOAWSRDSData -rdslist $rdslist -metrics $metrics -costs $costs -snapshots $snapshots

    $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'AWS-RDS' -PassThru }
    $report | Export-Csv -Path ".\SilkTCO_RDS_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
}
