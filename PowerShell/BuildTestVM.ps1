param(
    [parameter(Mandatory)]
    [string] $rg,
    [parameter(Mandatory)]
    [string] $vmName,
    [parameter(Mandatory)]
    [string] $vnet,
    [parameter(Mandatory)]
    [string] $subNet,
    [parameter()]
    [string] $dataSubnet,
    [parameter()]
    [string] $subscriptionName = 'sales-azure',
    [parameter()]
    [string] $size = 'Standard_D32s_v4',
    [parameter()]
    [switch] $Windows,
    [parameter(Mandatory)]
    [int] $zone
)

Get-AzSubscription -SubscriptionName $subscriptionName | Set-AzContext

# Get location data 
$pipName = $vmName + '-pip'
$rgData = Get-AzResourceGroup -ResourceGroupName $rg

# create a PIP
$pip = Get-AzPublicIpAddress -ResourceGroupName $rg -Name $pipName -ErrorAction SilentlyContinue

if (!$pip) {
    Write-Host -ForegroundColor yellow "-- Public IP not found, setting one up for use..."
    $pip = New-AzPublicIpAddress -Name $pipName -ResourceGroupName $rg -Location $rgData.Location -Sku Standard -AllocationMethod Static -Zone $zone
}

# Create Data interface(s)
$nic1Name = $vmName + '-mgmt'
$nic1subnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name $vnet | Get-AzVirtualNetworkSubnetConfig | where-object {$_.name -eq $subNet}
$mgmtNic = New-AzNetworkInterface -Subnet $nic1subnet -Name $nic1Name -ResourceGroupName $rg -Location $rgData.Location -EnableAcceleratedNetworking -PublicIpAddress $pip

if ($dataSubnet) {
    Write-Host '-- Adding Data interface --'
    $nic2Name = $vmName + '-data'
    $nic2subnet = Get-AzVirtualNetwork -ResourceGroupName $rg -Name $vnet | Get-AzVirtualNetworkSubnetConfig | where-object {$_.name -eq $dataSubnet}
    $dataNic = New-AzNetworkInterface -Subnet $nic2subnet -Name $nic2Name -ResourceGroupName $rg -Location $rgData.Location -EnableAcceleratedNetworking
}

# Create the user credential
$password = ConvertTo-SecureString "NeedF13x1234" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $password)

# create the VM config
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize $size -Zone $zone

if ($Windows) {
    Write-Host '-- Setting OS for Windows --'
    $vmConfig | Set-AzVMOperatingSystem -Windows -ComputerName $vmName -Credential $cred 
    $vmConfig | Set-AzVMSourceImage -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-datacenter-gensecond" -Version "latest"
} else {
    Write-Host '-- Setting OS for Linux --'
    $vmConfig | Set-AzVMOperatingSystem -Linux -ComputerName $vmName -Credential $cred
    $vmConfig | Set-AzVMSourceImage -PublisherName "Canonical" -Offer "0001-com-ubuntu-server-focal" -Skus "20_04-lts" -Version "latest"
}
$vmConfig | Add-AzVMNetworkInterface -Id $mgmtNic.Id

if ($dataSubnet) {
    $vmConfig.NetworkProfile.NetworkInterfaces[0].Primary = $true
    $vmConfig | Add-AzVMNetworkInterface -Id $dataNic.Id
}

# Create a VM using the abov config
New-AzVm -ResourceGroupName $rg -Location $rgData.Location -Zone $zone -VM $vmConfig



