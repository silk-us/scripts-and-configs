# Example Method for Flex Subnet Deployment

This readme offers a method to deploy and configure a subnet to prepare for a Silk Flex deployment.  The configuration provided in the example json can be directly used with minor changes to suit your environment.  The example is assuming it's being created in an existing VNET with the corresponding IP range available.  It's also assumed you've created an [appropriately configured NSG](<../NSG Rule JSONs/README.md>) to associate to this new subnet.

---
## prerequisites for deploying the Flex Subnet
It's assumed you've established an authenticated powershell session to azure and are operating in that session for the entirety of this process. You can use `Connect-AzAccount` to establish that connection and would need to do this in each powershell session you operate out of.


## example configuration changes
The following values from the [example-flex-subnet-configuration](example-flex-subnet-configuration.json) can be updated according to your environment.

`    "resource_group_name": "flex-example",`  
`    "vnet_name": "flex-example-vnet",`  
`    "subnet_name": "flex-example-subnet",`  
`    "subnet_ip_range": "10.0.5.0/28",`  
`    "nsg_name": "flex-example-nsg",`  
`    "nsg_resource_group_name": "flex-example-nsg-rg",`  


## powershell deployment
### import the example-flex-subnet-configuration.json configuration into a powershell object
This assumes the modified json file is in your working directory.  Update the `-Path` accordingly.
```powershell
$config = Get-Content -Path .\example-flex-subnet-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

### create the new network security group (nsg)
```powershell
Get-AzVirtualNetwork -Name $config.vnet_name `
                     -ResourceGroupName $config.resource_group_name |
    Add-AzVirtualNetworkSubnetConfig -Name $config.subnet_name `
                                     -AddressPrefix $config.subnet_ip_range `
                                     -NetworkSecurityGroupId $(
                                         Get-AzNetworkSecurityGroup `
                                             -Name $config.nsg_name `
                                             -ResourceGroupName $config.resource_group_name).Id |
    Set-AzVirtualNetwork
```
