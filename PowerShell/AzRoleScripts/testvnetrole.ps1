param(
    [parameter(Mandatory)]
    [string] $name,
    [parameter()]
    [switch] $existing,
    [parameter()]
    [switch] $showActions
)

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

if ($showActions) {
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "Actions" -Value $actions
    return $o
}

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

