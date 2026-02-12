# Virtual Network Subnet Configuration for Silk Flex

This readme describes how to configure a subnet to prepare for a Silk Flex deployment and offers a method to deploy that resource via PowerShell. The configuration provided in the example JSON files can be directly used with minor changes to suit your environment. The examples assume an existing VNET with the corresponding IP ranges is already created. It also assumes [appropriately configured network security groups](<../NSG Rule JSONs/README.md>) have been created to associate to the respective subnet.

---

## Prerequisites for Deploying the Flex Subnet
It's assumed you've established an authenticated powershell session to azure and are operating in that session for the entirety of this process. You can use `Connect-AzAccount` to establish that connection and would need to do this in each powershell session you operate out of.


## Example Configuration

This configuration example specifies all required elements for a flex subnet, including the Microsoft.Storage.Global and Microsoft.ContainerRegistry service endpoints where applicable. It assumes the required network security groups have been created and these subnets are being created in an existing VNET.

### Example Values to Change
The following values from the [smi-example-flex-subnet-configuration](smi-example-flex-subnet-configuration.json) or [umi-example-silk-cluster-subnet-configuration](umi-example-silk-cluster-subnet-configuration.json) can be updated according to your environment.

```json
    "vnet_resource_group_name": "example-vnet-rg",
    "vnet_name": "example-vnet",
    "nsg_resource_group_name": "example-nsg-rg",
        ...for each subnet updaate the name, ip range and associated nsg name values...
            "subnet_name": "example-flex-subnet",
            "subnet_ip_range": "10.0.5.128/28",
            "nsg_name": "example-flex-nsg",
        ...
```


### Static Example Values
The following values from the example subnet configuration files are constant for any Azure flex or management subnet deployment.<br>
`    "subnet_service_endpoint": ["Microsoft.Storage.Global", "Microsoft.ContainerRegistry"]`


## PowerShell Deployment

### SMI

#### Import the smi-example-flex-subnet-configuration.json Configuration into a PowerShell Object
This assumes the modified json file is in your working directory.  Update the `-Path` accordingly.
```powershell
$config = Get-Content -Path .\smi-example-flex-subnet-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

### UMI

#### Import the umi-example-silk-cluster-subnet-configuration.json Configuration into a PowerShell Object
This assumes the modified json file is in your working directory.  Update the `-Path` accordingly.
```powershell
$config = Get-Content -Path .\umi-example-silk-cluster-subnet-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

### Create the New Subnets
```powershell
foreach ($subnet in $config.subnet_config)
    {
        if($subnet.service_endpoint)
            {
                Get-AzVirtualNetwork -Name $config.vnet_name `
                                     -ResourceGroupName $config.vnet_resource_group_name |
                Add-AzVirtualNetworkSubnetConfig -Name $subnet.name `
                                                 -AddressPrefix $subnet.ip_range `
                                                 -ServiceEndpoint $subnet.service_endpoint `
                                                 -NetworkSecurityGroupId $(
                                                     Get-AzNetworkSecurityGroup `
                                                         -Name $subnet.nsg_name `
                                                         -ResourceGroupName $config.nsg_resource_group_name).Id |
                Set-AzVirtualNetwork
            }
        else
            {
                Get-AzVirtualNetwork -Name $config.vnet_name `
                                     -ResourceGroupName $config.vnet_resource_group_name |
                Add-AzVirtualNetworkSubnetConfig -Name $subnet.name `
                                                 -AddressPrefix $subnet.ip_range `
                                                 -NetworkSecurityGroupId $(
                                                     Get-AzNetworkSecurityGroup `
                                                         -Name $subnet.nsg_name `
                                                         -ResourceGroupName $config.nsg_resource_group_name).Id |
                Set-AzVirtualNetwork
            }

    }
```
