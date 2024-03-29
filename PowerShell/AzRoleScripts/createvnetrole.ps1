param(
    [parameter(Mandatory)]
    [string] $name = "flex-vnet-contributor",
    [parameter()]
    [string] $description = 'Needed permissions for Silk Flex to operate inside an existing Resource Group'

)

$azcontext = Get-AzContext
$scope = [System.Collections.ArrayList]@()
$scopestring = "/subscriptions/" + $azcontext.Subscription
$scope.Add($scopestring)

# $rolescope = New-Object psobject    
$rolescope = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition

$actions = @(
    "Microsoft.Network/virtualNetworks/read"
    "Microsoft.Network/virtualNetworks/write"
    "Microsoft.Network/virtualNetworks/subnets/read"
    "Microsoft.Network/virtualNetworks/subnets/write"
    "Microsoft.Network/virtualNetworks/subnets/join/action"
    "Microsoft.Network/networkSecurityGroups/read"
    "Microsoft.Network/networkSecurityGroups/write"
    "Microsoft.Network/networkInterfaces/read"
    "Microsoft.Network/networkInterfaces/write"
    "Microsoft.Network/networkInterfaces/join/action"
    "Microsoft.Network/networkInterfaces/delete"
    "Microsoft.Network/virtualNetworks/peer/action"
    "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read"
    "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write"
)

$rolescope.Name = $name
$rolescope.IsCustom = $true
$rolescope.Description = $description
$rolescope.Actions = $actions
$rolescope.AssignableScopes = $scope

$rolescope | write-verbose

New-AzRoleDefinition -Role $rolescope

