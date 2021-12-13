<#
 The example IP math function. 
 Example use: Add-IPAddressSpace -ip 10.1.0.192 -increment 10 
 Returns a classed [IPAddress] object for the address of 10.1.0.202
#>
function Add-IPAddressSpace {
    param(
        [Parameter(Mandatory)]
        [IPAddress] $ip,
        [Parameter(Mandatory)]
        [int] $increment
    )

    $ipup = 16777216 * $increment
    [ipaddress]$ipMath = $ip.Address + $ipup

    return $ipMath
}
 
# Declare vnet and subnet name for the az powershell query.
$vnetName = 'shared-vnet-demo3'
$subnetName = 'example-26'

# Build a subnet query however you like, for example:
$subnet = Get-AzVirtualNetwork -Name $vnetName | Get-AzVirtualNetworkSubnetConfig -Name $subnetName
[IPAddress] $subnetspace = $subnet.AddressPrefix.split('/')[0]

# Apply the IP math function
$interfaceAddress = Add-IPAddressSpace -ip $subnetspace.IPAddressToString -increment 10

# [IPAddress]$interfaceAddress is now ready to express. For example grab the IP string value by expressing $interfaceAddress.IPAddressToString
return $interfaceAddress

