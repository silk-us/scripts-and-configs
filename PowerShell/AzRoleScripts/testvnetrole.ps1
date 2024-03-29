param(
    [parameter(Mandatory)]
    [string] $name
)

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

