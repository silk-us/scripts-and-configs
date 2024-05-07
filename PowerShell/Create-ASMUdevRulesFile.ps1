param(
    [string] $filename = '96-storage-asm.rules',
    [string] $volumeGroup,
    [string] $asmDiskName = 'asmdisk'
)

$asmString = 'ACTION=="add|change", ENV{DM_UUID}=="mpath-280b745{VOLUMEID}", SYMLINK+="oracleasm/{ASMKDISKNAME}", GROUP="oinstall", OWNER="oracle", MODE="0660"'

Write-Host -ForegroundColor yellow "Copy these lines to /etc/udev/rules.d/96-storage-asm.rules"`n

$volumes = Get-SDPVolumeGroup -name $volumeGroup | Get-SDPVolume
$disksequence = 1
foreach ($i in $volumes) {
    $asmdisk = $asmDiskName + $disksequence.ToString()
    $asmString.Replace('{VOLUMEID}',$i.scsi_sn).Replace('{ASMKDISKNAME}',$asmdisk) 
    $disksequence++
}

Write-Host -ForegroundColor yellow `n"Then run the following commands as root:"`n
Write-Host -ForegroundColor yellow "udevadm control --reload-rules"
Write-Host -ForegroundColor yellow "udevadm trigger --type=devices --action=change"`n

