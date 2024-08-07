param(
    [parameter()]
    [string] $name = "flex-rg-contributor-custom",
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

$rolescope.Name = $name
$rolescope.IsCustom = $true
$rolescope.Description = $description
$rolescope.Actions = $actions
$rolescope.DataActions = $dataActions
$rolescope.AssignableScopes = $scope

$rolescope | write-verbose

New-AzRoleDefinition -Role $rolescope
