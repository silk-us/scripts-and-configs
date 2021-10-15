param(
    [string] $vmname,
    [switch] $diskonly,
    [switch] $cleanup,
    [string] $availabilityZone
)

# Gather VM facts and snapshot the VM OS disk
$azvm = get-azvm -Name $vmname
$azdisk = Get-AzDisk -Name $azvm.StorageProfile.OsDisk.name

# Create the snapshot
$snapconfig = New-AzSnapshotConfig -SourceUri $azvm.StorageProfile.OsDisk.ManagedDisk.Id -Location $azdisk.Location -CreateOption empty -SkuName Standard_LRS


$now = get-date -Format yyyy-MM-dd-hhmmss # check this date format
$snapname = $azdisk.Name + '-' + $now

Write-Host "--- Creating snapshot $snapname"`n`n

$finalsnap = New-AzSnapshot -ResourceGroupName $azvm.ResourceGroupName -SnapshotName $snapname -Snapshot $snapconfig
$finalsnap

# Create a disk from that snapshot
if ($availabilityZone) {
    $snapDiskConfig = New-AzDiskConfig -Tier $azdisk.Tier -OsType $azdisk.OsType -DiskSizeGB $azdisk.DiskSizeGB -Location $azdisk.Location -HyperVGeneration $azdisk.HyperVGeneration -CreateOption copy -SourceResourceId $finalsnap.id -Zone $availabilityZone
} else {
    $snapDiskConfig = New-AzDiskConfig -Tier $azdisk.Tier -OsType $azdisk.OsType -DiskSizeGB $azdisk.DiskSizeGB -Location $azdisk.Location -HyperVGeneration $azdisk.HyperVGeneration -CreateOption copy -SourceResourceId $finalsnap.id
}
$diskName = $azvm.Name + '_' + (get-random)
Write-Host "--- Creating disk $diskName"`n`n
$snapDisk = New-AzDisk -ResourceGroupName $azvm.ResourceGroupName -DiskName $diskName -Disk $snapDiskConfig 

if ($diskonly) {
    if ($cleanup) {
        Write-Host "--- Deleting snapshot $snapname"`n`n
        Get-AzSnapshot -SnapshotName $snapname | Remove-AzSnapshot -Force
    }
    return $snapDisk
} else {
    # Now create the damn VM
    $newAzVMName = $diskName + '-vm'
    $newAzVMConfig = New-AzVMConfig -VMName $newAzVMName -VMSize $azvm.HardwareProfile.VmSize
    $newAzVMConfig = Set-AzVMBootDiagnostic -VM $newAzVMConfig -Disable
    $newAzVMConfig = Set-AzVMOSDisk -VM $newAzVMConfig -ManagedDiskId $snapDisk.Id -CreateOption Attach -Windows

    $azVMNic = Get-AzNetworkInterface -ResourceId $azvm.NetworkProfile.NetworkInterfaces[0].id

    # $azVMVnetName = $azVMNic.IpConfigurations[0].Subnet.id.Split('/')[-3]
    # $newAzVMvnet = Get-AzVirtualNetwork -Name $azVMVnetName -ResourceGroupName $azVM.ResourceGroupName

    $newAzVMnicName = $newAzVMName + '-nic'
    $newAzVMnic = New-AzNetworkInterface -Name $newAzVMnicName -ResourceGroupName $azvm.ResourceGroupName -Location $azvm.Location -SubnetId $azVMNic.IpConfigurations[0].Subnet.id

    $newAzVMConfig = Add-AzVMNetworkInterface -VM $newAzVMConfig -Id $newAzVMnic.Id

    $finalAzVM = New-AzVM -VM $newAzVMConfig -ResourceGroupName $azvm.ResourceGroupName -Location $azvm.Location
    if ($cleanup) {
        Get-AzSnapshot -SnapshotName $snapname | Remove-AzSnapshot -Force
    }
    return $finalAzVM
}


