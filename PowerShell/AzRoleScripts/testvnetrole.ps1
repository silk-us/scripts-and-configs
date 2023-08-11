param(
    [parameter()]
    [string] $name
)

$actions = @(
    "Microsoft.Network/virtualNetworks/read"
    "Microsoft.Network/virtualNetworks/write"
    "Microsoft.Network/virtualNetworks/join/action"
    "Microsoft.Network/virtualNetworks/peer/action"
    "Microsoft.Network/virtualNetworks/subnets/read"
    "Microsoft.Network/virtualNetworks/subnets/write"
    "Microsoft.Network/virtualNetworks/subnets/joinLoadBalancer/action"
    "Microsoft.Network/virtualNetworks/subnets/join/action"
    "Microsoft.Network/virtualNetworks/subnets/joinViaServiceEndpoint/action"
    "Microsoft.Network/networkSecurityGroups/read"
    "Microsoft.Network/networkSecurityGroups/write"
    "Microsoft.Network/networkSecurityGroups/join/action"
    "Microsoft.Network/networkInterfaces/read"
    "Microsoft.Network/networkInterfaces/write"
    "Microsoft.Network/networkInterfaces/join/action"
    "Microsoft.Network/networkInterfaces/effectiveRouteTable/action"
    "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action" 
)

$role = Get-AzRoleDefinition -Name $name

$missing = @()

foreach ($i in $actions) {
    $actionCheck = $role.Actions | Where-Object {$_ -eq $i}
    if (!$actionCheck) {
        $missing += $i
    }
}

if ($missing) {
    $message = 'The following required actions are absent from the role:'
    $message
    $missing
} else {
    return 'All role action requirements are met'
}

