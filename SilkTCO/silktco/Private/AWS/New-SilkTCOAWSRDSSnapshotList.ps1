function New-SilkTCOAWSRDSSnapshotList {
    param(
        [Parameter()]
        [string] $region,
        [Parameter()]
        [array] $liveIds
    )

    if (-not (Get-Module -Name AWS.Tools.RDS)) { Import-Module AWS.Tools.RDS -ErrorAction Stop }

    $p = @{}
    if ($region) { $p['Region'] = $region }

    # live instance ids let us spot orphaned snapshots (source db is gone)
    if (-not $liveIds) { $liveIds = (Get-RDSDBInstance @p).DBInstanceIdentifier }

    # default returns automated + manual. copies come back as manual with a source snap id
    $snaps = Get-RDSDBSnapshot @p

    $thelist = @()
    foreach ($s in $snaps) {
        $isCopy = [bool]$s.SourceDBSnapshotIdentifier
        # a copy is technically 'manual', we just call it out separately
        $class = if ($isCopy) { 'copy' } else { $s.SnapshotType }

        # SourceDBSnapshotIdentifier is a full arn, grab just the snap name for readability
        $copiedFromName = if ($isCopy) { ($s.SourceDBSnapshotIdentifier -split ':')[-1] } else { $null }

        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name SnapshotName -Value $s.DBSnapshotIdentifier
        $o | Add-Member -MemberType NoteProperty -Name SourceInstance -Value $s.DBInstanceIdentifier
        $o | Add-Member -MemberType NoteProperty -Name SourceInstanceResourceId -Value $s.DbiResourceId
        $o | Add-Member -MemberType NoteProperty -Name Class -Value $class
        $o | Add-Member -MemberType NoteProperty -Name SnapshotType -Value $s.SnapshotType
        $o | Add-Member -MemberType NoteProperty -Name IsCopy -Value $isCopy
        $o | Add-Member -MemberType NoteProperty -Name CopiedFrom -Value $s.SourceDBSnapshotIdentifier
        $o | Add-Member -MemberType NoteProperty -Name CopiedFromName -Value $copiedFromName
        $o | Add-Member -MemberType NoteProperty -Name SourceRegion -Value $s.SourceRegion
        $o | Add-Member -MemberType NoteProperty -Name Engine -Value $s.Engine
        $o | Add-Member -MemberType NoteProperty -Name SizeGB -Value $s.AllocatedStorage
        $o | Add-Member -MemberType NoteProperty -Name Encrypted -Value $s.Encrypted
        $o | Add-Member -MemberType NoteProperty -Name Created -Value $s.SnapshotCreateTime
        $o | Add-Member -MemberType NoteProperty -Name OriginalCreated -Value $s.OriginalSnapshotCreateTime
        $o | Add-Member -MemberType NoteProperty -Name Orphaned -Value ($s.DBInstanceIdentifier -notin $liveIds)

        $thelist += $o
    }

    return $thelist
}
