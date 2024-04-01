param(
    [parameter(Mandatory)]
    [string] $name = "flex-vnet-contributor",
    [parameter()]
    [string] $description = 'Needed permissions for Silk Flex to operate inside an existing Resource Group',
    [parameter()]
    [switch] $existing

)

$azcontext = Get-AzContext
$scope = [System.Collections.ArrayList]@()
$scopestring = "/subscriptions/" + $azcontext.Subscription
$scope.Add($scopestring)

# $rolescope = New-Object psobject    
$rolescope = New-Object Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition

if ($existing) {
    $actions = @(
        "Microsoft.Network/virtualNetworks/read"
        "Microsoft.Network/virtualNetworks/write"
        "Microsoft.Network/virtualNetworks/join/action"
        "Microsoft.Network/virtualNetworks/subnets/read"
        "Microsoft.Network/virtualNetworks/subnets/write"
        "Microsoft.Network/virtualNetworks/subnets/delete"
        "Microsoft.Network/virtualNetworks/subnets/join/action"
        "Microsoft.Network/networkSecurityGroups/join/action"
        "Microsoft.Network/networkInterfaces/join/action"
        "Microsoft.Network/networkInterfaces/effectiveRouteTable/action"
        "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action"
    )
} else {
    $actions = @(
        "Microsoft.Network/networkInterfaces/effectiveRouteTable/action"
        "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action"
        "Microsoft.Network/virtualNetworks/read"
        "Microsoft.Network/virtualNetworks/write"
        "Microsoft.Network/virtualNetworks/join/action"
        "Microsoft.Network/virtualNetworks/subnets/read"
        "Microsoft.Network/virtualNetworks/subnets/write"
        "Microsoft.Network/virtualNetworks/subnets/delete"
        "Microsoft.Network/virtualNetworks/subnets/join/action"
        "Microsoft.Network/virtualNetworks/peer/action"
        "Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/read"
        "Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/write"
        "Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/delete"
    )
}

$rolescope.Name = $name
$rolescope.IsCustom = $true
$rolescope.Description = $description
$rolescope.Actions = $actions
$rolescope.AssignableScopes = $scope

$rolescope | write-verbose

New-AzRoleDefinition -Role $rolescope

