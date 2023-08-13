param(
    [parameter(Mandatory)]
    [string] $vmName,
    [parameter(Mandatory)]
    [string] $ResourceGroupName,
    [parameter()]
    [string] $vnetResourceGroupName = $ResourceGroupName,
    [parameter(Mandatory)]
    [string] $vnetName,
    [parameter(Mandatory)]
    [string] $subnetName
)

# Set the new nid names
$nic1Name = $vmName + '_data1'

# Store the VM and stats as vars
$myVM = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroupName
$myVMStatus = Get-AzVM -Name $vmName -ResourceGroupName $resourceGroupName -status

# Check that the VM is powered off, power it off
if ($myVMStatus.Statuses[-1].DisplayStatus -eq 'VM running') {
    write-host "VM is powered on currently, it needs to be powered off."
    break
}

# Create VMNic
$data1subnet = Get-AzVirtualNetwork -ResourceGroupName $vnetResourceGroupName -Name $vnetName | Get-AzVirtualNetworkSubnetConfig | where-object {$_.name -eq $subnetName}

$data1nic = New-AzNetworkInterface -Subnet $data1subnet -Name $nic1Name -ResourceGroupName $ResourceGroupName -Location $myVM.Location -EnableAcceleratedNetworking

# Add NICs to the VM meta
$myVM | Add-AzVMNetworkInterface -id $data1nic.id

# Set the first NIC to primary (required with miltiple interfaces)
$myVM.NetworkProfile.NetworkInterfaces[0].Primary = $true

# Update the VM with the apended meta
$myVM | Update-AzVM
