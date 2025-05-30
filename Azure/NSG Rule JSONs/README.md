# Example Method for Flex NSG Deployment

This readme offers a method to deploy an NSG and configure it's rules to prepare for a Silk Flex deployment.  The configuration provided in the example json can be directly used with minor changes to suit your environment.  The rules in the example configuration assume limited access within the scope of the VNET is permissible.


## prerequisites for deploying the Flex NSG
It's assumed you've established an authenticated powershell session to azure and are operating in that session for the entirety of this process. You can use `Connect-AzAccount` to establish that connection and would need to do this in each powershell session you operate out of.


## example configuration changes
The first three values from the [example-flex-nsg-configuration](example-flex-nsg-configuration.json) can be updated according to your environment.


`    "resource_group_name": "flex-example",`


`    "location": "eastus",`


`    "nsg_name": "flex-example-nsg",`


## powershell deployment
### import the modified example-flex-nsg-configuration.json configuration into a powershell object
This assumes the modified json file is in your working directory.  Update the path accordingly.
```powershell
$config = Get-Content -Path .\example-flex-nsg-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

### create the new network security group (nsg)
```powershell
New-AzNetworkSecurityGroup `
  -Name $config.nsg_name `
  -ResourceGroupName $config.resource_group_name `
  -Location $config.location
```

### add rules to the new nsg
```powershell
$nsg = Get-AzNetworkSecurityGroup `
          -Name $config.nsg_name `
          -ResourceGroupName $config.resource_group_name

$config.securityRules | % {
  $azrule = $_;
  $nsg |
    Add-AzNetworkSecurityRuleConfig `
      -Name $azrule.name `
      -Description $azrule.properties.description `
      -Protocol $azrule.properties.protocol `
      -SourcePortRange $azrule.properties.sourcePortRange `
      -DestinationPortRange $azrule.properties.destinationPortRange `
      -SourceAddressPrefix $azrule.properties.sourceAddressPrefix `
      -DestinationAddressPrefix $azrule.properties.destinationAddressPrefix `
      -Access $azrule.properties.access `
      -Priority $azrule.properties.priority `
      -Direction $azrule.properties.direction
      };
  $nsg | Set-AzNetworkSecurityGroup
```
