# Example Script for automated deployment of volumes using the SDP module. 

param(
    [parameter(mandatory)]
    [string] $name,
    [parameter(mandatory)]
    [int] $DataSizeInGB,
    [parameter(mandatory)]
    [int] $LogSizeInGB,
    [parameter()]
    [int] $TempDBSizeInGB,
    [parameter()]
    [int] $BackupSizeInGB,
    [parameter()]
    [string] $iqn,
    [parameter()]
    [string] $iqnHostName
)

# Create the host
New-SDPHost -name $name -type Windows

# Create the volume group
$vgname = $name + '-vg'
New-SDPVolumeGroup -name $vgname

# Create the volumes
# Data
$volname = $name + '-Data'
New-SDPVolume -VolumeGroupName $vgname -sizeInGB $DataSizeInGB -name $volname

#Logs
$volname = $name + '-Logs'
New-SDPVolume -VolumeGroupName $vgname -sizeInGB $LogSizeInGB -name $volname

#TempDB
if ($TempDBSizeInGB) {
    $volname = $name + '-TempDB'
    New-SDPVolume -VolumeGroupName $vgname -sizeInGB $TempDBSizeInGB -name $volname
}

#Backup
if ($BackupSizeInGB) {
    $volname = $name + '-Backup'
    New-SDPVolume -VolumeGroupName $vgname -sizeInGB $BackupSizeInGB -name $volname
}

# Map em
$vols = Get-SDPVolumeGroup -name $vgname | Get-SDPVolume
$vols | ForEach-Object {New-SDPHostMapping -volumeName $_.name -hostName $name}

# Add host connection information
if (!$iqn) {
    if (!$iqnHostName) {
        $hostiqn = 'iqn.1991-05.com.microsoft:' + $name.ToLower()
    } else {
        $hostiqn = 'iqn.1991-05.com.microsoft:' + $iqnHostName.ToLower()
    }
} else {
    $hostiqn = $iqn.ToLower()
}

Set-SDPHostIqn -iqn $hostiqn -hostName $name
