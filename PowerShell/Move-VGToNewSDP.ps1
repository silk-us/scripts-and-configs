param(
    [parameter(Mandatory)]
    $volumeGroupName
)

<#
    .SYNOPSIS
    This script is for moving volume groups, host objects, and mapping concerns to a remote SDP. 

    .EXAMPLE 
    First, log into the local and remote array. You MUST specify '-k2context remote' for the remote array or the script will error out without doing anything. 

    So, prior to running this script, connect to both local and remote SDPs:

    Connect-SDP -server {local SDP IP address} -credential $admincreds
    Connect-SDP -server {remote SDP IP address} -credential $admincreds -k2context remote

    Move-VGToNewSDP.ps1 -volumeGroupName SQL01-vg

    .DESCRIPTION

    .NOTES
    Authored by J.R. Phillips (GitHub: JayAreP)

#>

Write-Verbose "-- This operation is disruptive to any hosts mapped to volumes in this volume group." -Verbose
Write-Verbose "-- Please ensure the host has offlined or unmounted the volumes." -Verbose
Write-Verbose "-- Any existing replication sessions will be removed as part of the move." -Verbose
Write-Verbose "-- No data is destroyed on the source SDP. Host mappings are removed though." -Verbose
Pause

$sdpModule = Get-Module sdp
if ($sdpModule.Version -lt "1.5.5") {
    $errormsg = 'SDP PowerShell SDK required to be 1.5.5 or higher.'
    return $errormsg | Write-Error
}

# check PSVersion

if ($psversiontable.PSEdition -ne 'Core') {
    $errormsg = 'Please use PowerSHell version 7 or greater to run this script.'
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

# grab the volume group information and mappings
Write-Verbose 'SOURCE > Grab the volume group information and mappings' -verbose 

$vg = Get-SDPVolumeGroup -name $volumeGroupName
$vgVols = $vg | Get-SDPVolume
$hostMaps = @()
foreach ($v in $vgVols) {
    $hm = Get-SDPHostMapping -volumeName $v.name
    $hostMaps += $hm
}

$vg = Get-SDPVolumeGroup -name $volumeGroupName
$vgVols = $vg | Get-SDPVolume
$hostGroupMaps = @()
foreach ($v in $vgVols) {
    $hm = Get-SDPHostGroupMapping -volumeName $v.name
    $hostGroupMaps += $hm
}

# Get host list
Write-Verbose 'SOURCE > Get host list' -Verbose

$hostlist = @()
foreach ($h in $hostMaps) {
    $hostId = ConvertFrom-SDPObjectPrefix -Object $h.host -getId
    $hostObj = Get-SDPHost -id $hostId
    $hostlist += $hostObj
}
$hostlist = $hostlist | Sort-Object name -Unique

$hostGroupList = @()
foreach ($h in $hostGroupMaps) {
    $hostId = ConvertFrom-SDPObjectPrefix -Object $h.host -getId
    $hostObj = Get-SDPHostGroup -id $hostId
    $hostGroupList += $hostObj
}
$hostGroupList = $hostGroupList | Sort-Object name -Unique

# Remove existing host mappings for the volume group. 
Write-Verbose 'SOURCE > Remove existing host mappings for the volume group.' -Verbose

$hostMapArray = @()
foreach ($h in $hostMaps) {
    $hostId = ConvertFrom-SDPObjectPrefix -Object $h.host -getId
    $hostObj = Get-SDPHost -id $hostId
    $volId = ConvertFrom-SDPObjectPrefix -Object $h.volume -getId
    $volObj = Get-SDPVolume -id $volId
    $o = new-object psobject
    $o | Add-Member -MemberType NoteProperty -Name 'host' -Value $hostObj.name
    $o | Add-Member -MemberType NoteProperty -Name 'volume' -Value $volObj.name 
    $hostMapArray += $o
    Remove-SDPHostMapping -id $h.id
}

$hostGroupMapArray = @()
foreach ($h in $hostGroupMaps) {
    $hostId = ConvertFrom-SDPObjectPrefix -Object $h.host -getId
    $hostObj = Get-SDPHostGroup -id $hostId
    $volId = ConvertFrom-SDPObjectPrefix -Object $h.volume -getId
    $volObj = Get-SDPVolume -id $volId
    $o = new-object psobject
    $o | Add-Member -MemberType NoteProperty -Name 'host' -Value $hostObj.name
    $o | Add-Member -MemberType NoteProperty -Name 'volume' -Value $volObj.name 
    $hostGroupMapArray += $o
    Remove-SDPHostMapping -id $h.id
}
 
# Generate net-new replication sessions for the volume group.

Write-Verbose 'SOURCE > Checking for existing replication session...' -Verbose

if ($vg.replication_sessions) {
    Write-Verbose 'SOURCE --> Session exists. Generating new snapshot.' -Verbose
    $replicationSessionID = ConvertFrom-SDPObjectPrefix -Object $vg.replication_sessions -getId
    $session = Get-SDPReplicationSessions -id $replicationSessionID
    if ($session.target_exposure -ne 'Mapped - Not Exposed') {
        $errormsg = 'The specified replication session is set for Read Only, please reconfigure for Mapped.'
        return $errormsg | Write-Error
    } else {
        # $snapshotName = $volumeGroupName + (Get-Random -Maximum 9999)
        # New-SDPVolumeGroupSnapshot -volumeGroupName $volumeGroupName -name $snapshotName -replicationSession $session.name -retentionPolicyName Replication_Retention
        New-SDPReplicationVolumeGroupSnapshot -volumeGroupName $volumeGroupName -replicationSession $session.name 
        $session = Get-SDPReplicationSessions -name $session.name
        $repSessionName = $session.name
    }
} else {
    Write-Verbose 'SOURCE --> Generate new replication sessions for the volume group.' -Verbose
    [string]$vgprefix = $vg.id
    $repSessionName = $vgprefix + "-rep-" + (get-random)
    New-SDPReplicationSession -name $repSessionName -volumeGroupName $volumeGroupName -replicationPeerName $peerArray.name -retentionPolicyName Replication_Retention -externalRetentionPolicyName Replication_Retention -RPO 1200 -mapped | Start-SDPReplicationSession -ErrorAction SilentlyContinue | Out-Null
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

# New remote VG and volume array
Write-Verbose 'TARGET > Aligning remote volumes with local volumes.' -Verbose

$volArray = @()
foreach ($v in $vgVols) {
    $volRef = ConvertTo-SDPObjectPrefix -ObjectID $v.id -ObjectPath volumes
    $repVol = Get-SDPReplicationPeerVolumes | Where-Object {$_.local_volume.ref -eq $volRef}
    $o = new-object psobject
    $o | Add-Member -MemberType NoteProperty -Name 'local' -Value $v.name
    $o | Add-Member -MemberType NoteProperty -Name 'remote' -Value $repVol.name
    $volArray += $o
}

$vgRef = ConvertTo-SDPObjectPrefix -ObjectID $vg.id -ObjectPath volume_groups
$repVG = Get-SDPReplicationPeerVolumeGroups | Where-Object {$_.local_volume_group.ref -eq $vgRef}

# Once done, flip replication the other way <-- maybe not required? Lets just stop it for now.
Write-Verbose 'SOURCE > Data moved, removing replication session...' -Verbose

Get-SDPReplicationSessions -name $repSessionName | Suspend-SDPReplicationSession -wait | Out-Null
Get-SDPReplicationSessions -name $repSessionName | Stop-SDPReplicationSession -wait | Out-Null
Get-SDPReplicationSessions -name $repSessionName | Remove-SDPReplicationSession | Out-Null

# Create the host objects and IQNs on remote array
Write-Verbose 'TARGET > Create the host objects and IQNs on remote array.' -Verbose 

foreach ($h in $hostlist) {
    $remoteHost = Get-SDPHost -name $h.name -k2context remote
    if (!$remoteHost) {
        $hostIqn = Get-SDPHostIqn -hostName $h.name
        New-SDPHost -name $h.name -type $h.Type -k2context remote
        Set-SDPHostIqn -hostName $h.name -iqn $hostIqn.iqn -k2context remote
    }
}

foreach ($hg in $hostGroupList) {
    $remoteHostGroup = Get-SDPHostGroup -name $hg.name -k2context remote
    if (!$remoteHostGroup) {
        New-SDPHostGroup -name $hg.name -k2context remote
        $hostGroupHosts = Get-SDPHostGroup -name $hg.name | Get-SDPHost
        foreach ($hgh in $hostGroupHosts) {
            $hostIqn = $hgh | Get-SDPHostIqn
            New-SDPHost -name $hgh.name -type $hgh.Type -hostGroupName $hg.name -k2context remote
            Set-SDPHostIqn -hostName $hgh.name -iqn $hostIqn.iqn -k2context remote
        }
    }
}

# Rename those volumes.
Write-Verbose 'TARGET > Renaming the volumes on target SDP.' -Verbose

foreach ($i in $volArray) {
    $rVol = Get-SDPVolume -name $i.remote -k2context remote
    $rVol | Set-SDPVolume -name $i.local -k2context remote 
}

Write-Verbose "TARGET --> Renaming volume group to $volumeGroupName" -Verbose

# $rvg = Get-SDPVolumeGroup -name $repVG.name -k2context remote
# $rvg | Set-SDPVolumeGroup -name $volumeGroupName -enableDeDuplication $rvg.is_dedup -k2context remote

# Map those new hosts to the new volumes
Write-Verbose 'TARGET > Mapping target volumes to new target host object.' -Verbose

foreach ($hm in $hostMapArray) {
    New-SDPHostMapping -hostName $hm.host -volumeName $hm.volume -k2context remote | Out-Null
    $hm
}

foreach ($hm in $hostGroupMapArray) {
    New-SDPHostGroupMapping -hostGroupName $hm.host -volumeName $hm.volume -k2context remote | Out-Null
    $hm
}

# All done, provide helpful mapping command
$data01ports = Get-SDPSystemNetPorts -port_type dataport -k2context remote | Where-Object {$_.name -like "*01"}
$sessionsPer = [math]::truncate(24 / $data01ports.Count)
$nodeAddress = '"' + $remoteSDP.iscsi_qualified_target_name + '"'
foreach ($d in $data01ports) {
    $netPortRef = ConvertTo-SDPObjectPrefix -ObjectPath "system/net_ports" -ObjectID $d.id
    $netIPPort = Get-SDPSystemNetIps -k2context remote| Where-Object {$_.net_port.ref -eq $netPortRef}
    $cnodeIpAddress = $netIPPort.ip_address
    $message = "Connect-SilkCNode -SessionCount $sessionsPer -nodeAddress $nodeAddress -cnodeIP $cnodeIpAddress"
    Write-Host $message -ForegroundColor yellow
}
Write-Host "-- or --" -ForegroundColor yellow
$netPortRef = ConvertTo-SDPObjectPrefix -ObjectPath "system/net_ports" -ObjectID $data01ports[0].id
$netIPPort = Get-SDPSystemNetIps -k2context remote| Where-Object {$_.net_port.ref -eq $netPortRef}
$cnodeIpAddress = $netIPPort.ip_address
$message = "iscsiadm -m discovery -t sendtargets -p $cnodeIpAddress"
Write-Host $message -ForegroundColor yellow
$message = "iscsiadm -m node --login"
Write-Host $message -ForegroundColor yellow
$message = "sudo iscsiadm -m node -T $nodeAddress -o update -n node.session.nr_sessions -v $sessionsPer"
Write-Host $message -ForegroundColor yellow
$message = "iscsiadm -m node --login"
Write-Host $message -ForegroundColor yellow
