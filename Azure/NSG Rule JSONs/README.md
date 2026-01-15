# Example Method for Flex NSG Deployment

This readme offers a method to deploy an NSG and configure it's rules to prepare for a Silk Flex deployment.  The configuration provided in the example json can be directly used with minor changes to suit your environment.  The rules in the example configuration assume limited access within the scope of the VNET is permissible.


## prerequisites for deploying the Flex NSG
It's assumed you've established an authenticated powershell session to azure and are operating in that session for the entirety of this process. You can use `Connect-AzAccount` to establish that connection and would need to do this in each powershell session you operate out of.

## NSG Example Files Required Changes
### example flex nsg configuration changes
The first three values from the [example-flex-nsg-configuration](example-flex-nsg-configuration.json) can be updated according to your environment.
Update "resource_group_name", "azure_region", and the "name" of the NSG as needed.

```json
  "resource_group_name": "flex-example",
  "azure_region": "centralus",
  "nsg": [
    {
      "name": "flex-example-nsg",
...
```

### example Silk Cluster NSG configuration changes
The first three values from the [example-silk-cluster-nsg-configuration](example-silk-cluster-nsg-configuration.json) can be updated according to your environment.
Update "resource_group_name", "azure_region", "cluster_number", and each of the "cidr" values in the "subnet_config" hashtables to match your environments configuration.
```json
    "resource_group_name": "flex-example",
    "azure_region": "centralus",
    "cluster_number": "1234",
    "subnet_config":[
      {"string": "flex_subnet_cidr","cidr": "10.0.5.128/28"},
      {"string": "external_data_1_cidr","cidr": "10.0.4.0/25"},
      {"string": "external_data_2_cidr","cidr": "10.0.4.128/25"},
      {"string": "internal_1_cidr","cidr": "10.0.0.0/23"},
      {"string": "internal_2_cidr","cidr": "10.0.2.0/23"},
      {"string": "external_mgmt_cidr","cidr": "10.0.5.0/25"}
    ],
...
```


# powershell deployment
This assumes the modified json file is in your working directory.  Update the `-Path` accordingly.
## Flex Subnet NSG
### import the modified example-flex-nsg-configuration.json configuration into a powershell object
```powershell
$config = Get-Content -Path .\example-flex-nsg-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

## *OR*

## Silk Cluster Subnet NSGs
### import the modified example-silk-cluster-nsg-configuration.json configuration into a powershell object
```powershell
$config = Get-Content -Path .\example-silk-cluster-nsg-configuration.json -Raw | ConvertFrom-Json -Depth 100
```

## Powershell Command to Deploy from imported config
### create the new network security groups (nsg) and rules
```powershell
foreach ($nsg in $config.nsg)
    {
        New-AzNetworkSecurityGroup `
        -Name $(if($nsg.name -match "XXXX"){$nsg.name -replace "XXXX", $config.cluster_number}else{$nsg.name})`
        -ResourceGroupName $config.resource_group_name `
        -Location $config.azure_region `
        -OutVariable nsgObject

        $nsg.securityRules | % {
        $azrule = $_;
        $nsgObject |
            Add-AzNetworkSecurityRuleConfig `
            -Name $(if($azrule.name -match "XXXX"){$azrule.name -replace "XXXX", $config.cluster_number}else{$azrule.name})`
            -Description $(if($azrule.description){$azrule.description}else{$azrule.name -replace ".*XXXX-network(.*)", '$1' -replace '-', ' '}) `
            -Protocol $azrule.protocol `
            -SourcePortRange $azrule.sourcePortRange `
            -DestinationPortRange $azrule.destinationPortRange `
            -SourceAddressPrefix $(foreach($prefix in $azrule.SourceAddressPrefix){if($prefix -in $config.subnet_config.string){$($config.subnet_config | ? string -eq $prefix).cidr}else{$prefix}}) `
            -DestinationAddressPrefix $(foreach($prefix in $azrule.DestinationAddressPrefix){if($prefix -in $config.subnet_config.string){$($config.subnet_config | ? string -eq $prefix).cidr}else{$prefix}}) `
            -Access $azrule.access `
            -Priority $azrule.priority `
            -Direction $azrule.direction
            };
        $nsgObject | Set-AzNetworkSecurityGroup
    }
```
