param(
    [parameter(Mandatory)]
    [string] $filename
)

$importData = Get-Content $filename | ConvertFrom-Json

foreach ($vg in $importData.volumeGroups) {
    if (!(Get-SDPVolumeGroup -name $vg.name)) {
        New-SDPVolumeGroup -name $vg.name -enableDeDuplication $vg.is_dedupe -Description $vg.description 
    } else {
        Write-Host -ForegroundColor yellow "-- Volume group" $vg.name "Already exists --"
    }
}

foreach ($hg in $importData.hostGroups) {
    if (!(Get-SDPHostGroup -name $hg.name)) {
        New-SDPHostGroup -name $hg.name -allowDifferentHostTypes $hg.allow_different_host_types 
    } else {
        Write-Host -ForegroundColor yellow "-- Hostgroup " $hg.name "Already exists --"
    }
}

foreach ($h in $importData.hosts) {
    if (!(Get-SDPHost -name $h.name)) {
        Set-SDPHostIqn -hostName $h.name -iqn $h.iqn
        if ($h.hostGroupName) {
            New-SDPHost -name $h.name -type $h.type -hostGroupName $h.hostGroupName
        } else {
            New-SDPHost -name $h.name -type $h.type
        }
        Set-SDPHostIqn -hostName $h.name -iqn $h.iqn
    } else {
        Write-Host -ForegroundColor yellow "-- Host" $h.name "Already exists --"
    }
}

foreach ($v in $importData.volumes) {
    if (!(Get-SDPVolume -name $v.name)) {
        New-SDPVolume -name $v.name -sizeInGB ($v.size / (1024 * 1024)) -VolumeGroupName $v.volume_group_name 
    } else {
        Write-Host -ForegroundColor yellow "-- Volume" $v.name "Already exists --"
    }
}

foreach ($hm in $importData.hostMaps) {
    New-SDPHostMapping -hostName $hm.hostName -volumeName $hm.volumeName
}

foreach ($hgm in $importData.hostGroupMaps) {
    New-SDPHostGroupMapping -hostGroupName $hgm.hostName -volumeName $hgm.volumeName
}