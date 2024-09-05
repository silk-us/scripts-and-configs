

# Functions 
function getid {
    param(
        [PSCustomObject] $object,
        [string] $sub
    )

    $id = $object.$sub.ref.Split('/')[-1]
    return $id
}

# Export VolumeGroups
$exportVolumeGroups = @()
$allVolumeGroups = Get-SDPVolumeGroup | Where-Object {$_.name -notmatch 'INDEPENDENT_'} 
foreach ($vg in $allVolumeGroups) {
    $exportVolumeGroups += $vg
}

#export volumes
$allVolumes = Get-SDPVolume | Where-Object {$_.name -ne 'CTRL'}
$exportedVolumes = @()
foreach ($v in $allVolumes) {
    $vgid = getid -object $v -sub volume_group
    $vgName = ($exportVolumeGroups | Where-Object {$_.id -eq $vgid}).name   
    $v | Add-Member -MemberType NoteProperty -Name volume_group_name -Value $vgName
    $exportedVolumes += $v
}

# Export Hosts and IQNs 
$exportHosts = @()
$allHosts = Get-SDPHost
foreach ($h in $allHosts) {
    $hostIqn = ($h | Get-SDPHostIqn).iqn

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name name -Value $h.name
    $o | Add-Member -MemberType NoteProperty -Name type -Value $h.type
    $o | Add-Member -MemberType NoteProperty -Name iqn -Value $hostiqn

    if ($h.is_part_of_group) {
        $hgid = getid -object $h -sub host_group
        $hgname = (Get-SDPHostGroup -id $hgid).name
        $o | Add-Member -MemberType NoteProperty -Name hostGroupName -Value $hgname

    } else {
        $o | Add-Member -MemberType NoteProperty -Name hostGroupName -Value $null
    }

    $exportHosts += $o 
}

# Export HostGroups
$exportHostGroups = @()
$allhostGroups = Get-SDPHostGroup
foreach ($hg in $allhostGroups) {
    $exportHostGroups += $hg
}

# Export host Mappings
$exportHostMaps = @()
$allHostMaps = Get-SDPHostMapping | Where-Object {$_.host.ref -match '/hosts/'}
foreach ($hm in $allHostMaps) {
    $hostid = getid -object $hm -sub host
    $hostName = (Get-SDPHost -id $hostid).name
    $volid = getid -object $hm -sub volume
    $volumeName = (Get-SDPVolume -id $volid).name

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name hostName -Value $hostName
    $o | Add-Member -MemberType NoteProperty -Name volumeName -Value $volumeName
    
    $exportHostMaps += $o
}

# Export host group mappings
$exportHostGroupMaps = @()
$allHostGroupMaps = Get-SDPHostGroupMapping | Where-Object {$_.host.ref -match '/host_groups/'}
foreach ($hm in $allHostGroupMaps) {
    $hostid = getid -object $hm -sub host
    $hostName = (Get-SDPHostGroup -id $hostid).name
    $volid = getid -object $hm -sub volume
    $volumeName = (Get-SDPVolume -id $volid).name

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name hostName -Value $hostName
    $o | Add-Member -MemberType NoteProperty -Name volumeName -Value $volumeName

    $exportHostGroupMaps += $o
}

# Export snapshot schedule 
$exportSnapshotSchedule = @()
$allSnapScheds = Get-SDPSnapshotScheduler
foreach ($ss in $allSnapScheds) {
    $snapPath = "/snapshot_scheduler/" + $ss.id 
    $snapMap = Get-SDPSnapshotSchedulerMapping | where-object {$_.snapshot_scheduler.ref -match $snapPath}

    $retPolName = (Get-SDPRetentionPolicy -id (ConvertFrom-SDPObjectPrefix -Object $ss.retention_policy).objectid).name
    $vgName = (Get-SDPVolumeGroup -id (ConvertFrom-SDPObjectPrefix -Object $snapMap.volume_group).objectid).name

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name snapshotScheduleName -Value $ss.name
    $o | Add-Member -MemberType NoteProperty -Name retentionPolicyName -Value $retPolName
    $o | Add-Member -MemberType NoteProperty -Name volumeGroupName -Value $vgName
    $o | Add-Member -MemberType NoteProperty -Name minutes -Value $ss.time_interval_min
    
    $exportSnapshotSchedule += $o
}

# Create the export array
$exportArray = New-Object psobject
$exportArray | Add-Member -MemberType NoteProperty -Name volumeGroups -Value $exportVolumeGroups 
$exportArray | Add-Member -MemberType NoteProperty -Name volumes -Value $exportedVolumes
$exportArray | Add-Member -MemberType NoteProperty -Name hosts -Value $exportHosts
$exportArray | Add-Member -MemberType NoteProperty -Name hostGroups -Value $exportHostGroups
$exportArray | Add-Member -MemberType NoteProperty -Name hostMaps -Value $exportHostMaps
$exportArray | Add-Member -MemberType NoteProperty -Name hostGroupMaps -Value $exportHostGroupMaps
$exportArray | Add-Member -MemberType NoteProperty -Name snapshotSchedules -Value $exportSnapshotSchedule

$systemState = Get-SDPSystemState

$filename = $systemState.system_id + '-' + $systemState.system_time.ToString().split('.')[0] + '.json'

$exportArray | ConvertTo-Json -Depth 10 | Out-File $filename -force
