param(
    [parameter(Mandatory)]
    [string] $name,
    [parameter()]
    [switch] $showActions
)

$actions = @(
    "Microsoft.Authorization/locks/delete"
    "Microsoft.Authorization/locks/read"
    "Microsoft.Authorization/locks/write"
    "Microsoft.Compute/availabilitySets/delete"
    "Microsoft.Compute/availabilitySets/read"
    "Microsoft.Compute/availabilitySets/vmSizes/read"
    "Microsoft.Compute/availabilitySets/write"
    "Microsoft.Compute/disks/beginGetAccess/action"
    "Microsoft.Compute/disks/delete"
    "Microsoft.Compute/disks/endGetAccess/action"
    "Microsoft.Compute/disks/read"
    "Microsoft.Compute/disks/write"
    "Microsoft.Compute/images/delete"
    "Microsoft.Compute/images/read"
    "Microsoft.Compute/images/write"
    "Microsoft.Compute/proximityPlacementGroups/delete"
    "Microsoft.Compute/proximityPlacementGroups/read"
    "Microsoft.Compute/proximityPlacementGroups/write"
    "Microsoft.Compute/virtualMachines/deallocate/action"
    "Microsoft.Compute/virtualMachines/delete"
    "Microsoft.Compute/virtualMachines/performMaintenance/action"
    "Microsoft.Compute/virtualMachines/powerOff/action"
    "Microsoft.Compute/virtualMachines/read"
    "Microsoft.Compute/virtualMachines/redeploy/action"
    "Microsoft.Compute/virtualMachines/restart/action"
    "Microsoft.Compute/virtualMachines/runCommand/action"
    "Microsoft.Compute/virtualMachines/start/action"
    "Microsoft.Compute/virtualMachines/write"
    "Microsoft.Network/loadBalancers/read"
    "Microsoft.Network/networkInterfaces/delete"
    "Microsoft.Network/networkInterfaces/ipconfigurations/join/action"
    "Microsoft.Network/networkInterfaces/join/action"
    "Microsoft.Network/networkInterfaces/read"
    "Microsoft.Network/networkInterfaces/write"
    "Microsoft.Network/networkSecurityGroups/delete"
    "Microsoft.Network/networkSecurityGroups/join/action"
    "Microsoft.Network/networkSecurityGroups/read"
    "Microsoft.Network/networkSecurityGroups/write"
    "Microsoft.Network/virtualNetworks/delete"
    "Microsoft.Resources/subscriptions/resourcegroups/read"
    "Microsoft.Storage/storageAccounts/blobServices/containers/read"
    "Microsoft.Storage/storageAccounts/blobServices/containers/write"
    "Microsoft.Storage/storageAccounts/delete"
    "Microsoft.Storage/storageAccounts/joinPerimeter/action"
    "Microsoft.Storage/storageAccounts/listAccountSas/action"
    "Microsoft.Storage/storageAccounts/listServiceSas/action"
    "Microsoft.Storage/storageAccounts/read"
    "Microsoft.Storage/storageAccounts/write"
)

$dataActions = @(
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write"
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete"
)

if ($showActions) {
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "Actions" -Value $actions
    $o | Add-Member -MemberType NoteProperty -Name "dataActions" -Value $dataActions
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

foreach ($i in $dataActions) {
    $actionCheck = $role.dataActions | Where-Object {$_ -eq $i}
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

