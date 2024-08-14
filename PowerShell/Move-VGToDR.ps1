param(
    [parameter(Mandatory)]
    [string] $volumeGroupName,
    [parameter()]
    [string] $remoteHostName
)

<#
    .SYNOPSIS
    This script is for moving a replication session to the remote peer. 

    .EXAMPLE 
    First, log into the local and remote array. You MUST specify '-k2context remote' for the remote array or the script will error out without doing anything. 

    So, prior to running this script, connect to both local and remote SDPs:

    Connect-SDP -server {local SDP IP address} -credential $admincreds
    Connect-SDP -server {remote SDP IP address} -credential $admincreds -k2context remote

    Move-VGToDR.ps1 -volumeGroupName SQL01-vg -remoteHost SQLDR01

    .DESCRIPTION

    .NOTES
    Authored by J.R. Phillips (GitHub: JayAreP)

#>

$sdpModule = Get-Module sdp
if ($sdpModule.Version -lt "1.5.0") {
    $errormsg = 'SDP PowerShell SDK required to be 1.5.0 or higher.'
    return $errormsg | Write-Error
}

# test both local and remote variables

$localSDP = Get-SDPSystemState -ErrorAction SilentlyContinue
if (!$localSDP) {
    $errormsg = 'Cannot reach the local SDP, please connect to local SDP using "Connect-SDP" first'
    return $errormsg | Write-Error
}

$remoteSDP = Get-SDPSystemState -k2context remote -ErrorAction SilentlyContinue
if (!$remoteSDP) {
    $errormsg = 'Cannot reach the remote SDP, please connect to local SDP using "Connect-SDP -k2context remote" first'
    return $errormsg | Write-Error
}

$peerArray = Get-SDPReplicationPeerArray | Where-Object {$_.system_id -eq $remoteSDP.system_id}
if (!$peerArray) {
    $errormsg = 'No replication peer discovered for the remote SDP, please establish a peer via the UI or by using New-SDPReplicationPeerArray'
    return $errormsg | Write-Error
}

$vg = Get-SDPVolumeGroup -name $volumeGroupName
if (!$vg) {
    $errormsg = 'No Volume Group with that name present on the array. Please check that you are logged into the correct array. '
    return $errormsg | Write-Error
}

Write-Verbose 'SOURCE > Checking for existing replication session...' -Verbose

if ($vg.replication_sessions) {
    Write-Verbose 'SOURCE --> Session exists. Generating new snapshot.' -Verbose
    $replicationSessionID = ConvertFrom-SDPObjectPrefix -Object $vg.replication_sessions -getId
    $session = Get-SDPReplicationSessions -id $replicationSessionID
    # $snapshotName = $volumeGroupName + (Get-Random -Maximum 9999)
    # New-SDPVolumeGroupSnapshot -volumeGroupName $volumeGroupName -name $snapshotName -replicationSession $session.name -retentionPolicyName Replication_Retention
    New-SDPReplicationVolumeGroupSnapshot -volumeGroupName $volumeGroupName replicationSession $session.name 
    $session = Get-SDPReplicationSessions -name $session.name
    $repSessionName = $session.name
} 

# Monitor replication effort.
Write-Verbose 'SOURCE > Monitor replication effort' -Verbose

$repSession = Get-SDPReplicationSessions -name $repSessionName
while ($repSession.current_snapshot_progress -lt 100) {
    $activityString = "Replicating VG " + $volumeGroupName + " - Remaining: " + $repSession.estimated_remaining_time
    Write-Progress -PercentComplete $repSession.current_snapshot_progress -Activity $activityString
    $repSession = Get-SDPReplicationSessions -name $repSessionName
    Start-Sleep -Seconds 2
}

Write-Progress -Completed -Activity $activityString

Start-Sleep -Seconds 4

Write-Verbose 'TARGET > Aligning remote volumes with local volumes.' -Verbose

$vgRef = ConvertTo-SDPObjectPrefix -ObjectID $vg.id -ObjectPath volume_groups
$repVG = Get-SDPReplicationPeerVolumeGroups | Where-Object {$_.local_volume_group.ref -eq $vgRef}
$remoteVG = Get-SDPVolumeGroup -id $repVG.remote_volume_group_id -k2context remote
$remoteSession = Get-SDPReplicationSessions -k2context remote -remote_replication_session_id $session.id

Write-Verbose 'SOURCE > Data moved, reversing replication session...' -Verbose

Get-SDPReplicationSessions -name $repSessionName | Suspend-SDPReplicationSession -wait | Out-Null
$remoteSession | Switch-SDPReplicationSession -k2context remote -wait | Out-Null
$remoteSession | Start-SDPReplicationSession -k2context remote | Out-Null
$remoteVols = $remoteVG | Get-SDPVolume -k2context remote
$remoteVols | Set-SDPVolume -ReadWrite -k2context remote

if ($remoteHostName) {
    foreach ($i in $remoteVols) {
        New-SDPHostMapping -k2context remote -hostName $remoteHostName -volumeName $i.name
    }
}
