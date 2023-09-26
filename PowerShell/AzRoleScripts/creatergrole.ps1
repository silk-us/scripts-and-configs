param(
    [parameter(Mandatory)]
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
    "Microsoft.Authorization/locks/read"
    "Microsoft.Authorization/locks/write"
    "Microsoft.Authorization/locks/delete"
    "Microsoft.Compute/availabilitySets/read"
    "Microsoft.Compute/availabilitySets/write"
    "Microsoft.Compute/availabilitySets/delete"
    "Microsoft.Compute/availabilitySets/vmSizes/read"
    "Microsoft.Compute/disks/read"
    "Microsoft.Compute/disks/write"
    "Microsoft.Compute/disks/delete"
    "Microsoft.Compute/disks/beginGetAccess/action"
    "Microsoft.Compute/disks/endGetAccess/action"
    "Microsoft.Compute/images/read"
    "Microsoft.Compute/images/write"
    "Microsoft.Compute/images/delete"
    "Microsoft.Compute/proximityPlacementGroups/read"
    "Microsoft.Compute/proximityPlacementGroups/write"
    "Microsoft.Compute/proximityPlacementGroups/delete"
    "Microsoft.Compute/virtualMachines/read"
    "Microsoft.Compute/virtualMachines/write"
    "Microsoft.Compute/virtualMachines/delete"
    "Microsoft.Compute/virtualMachines/start/action"
    "Microsoft.Compute/virtualMachines/powerOff/action"
    "Microsoft.Compute/virtualMachines/redeploy/action"
    "Microsoft.Compute/virtualMachines/restart/action"
    "Microsoft.Compute/virtualMachines/deallocate/action"
    "Microsoft.Compute/virtualMachines/runCommand/action"
    "Microsoft.Compute/virtualMachines/runCommand/action"
    "Microsoft.Compute/virtualMachines/performMaintenance/action"
    "Microsoft.Network/loadBalancers/read"
    "Microsoft.Network/networkSecurityGroups/delete"
    "Microsoft.Network/networkSecurityGroups/read"
    "Microsoft.Network/networkSecurityGroups/write"
    "Microsoft.Network/networkSecurityGroups/join/action"
    "Microsoft.Network/networkInterfaces/read"
    "Microsoft.Network/networkInterfaces/write"
    "Microsoft.Network/networkInterfaces/delete"
    "Microsoft.Network/networkInterfaces/join/action"
    "Microsoft.Network/networkInterfaces/ipconfigurations/join/action"
    "Microsoft.Resources/subscriptions/resourcegroups/read"
    "Microsoft.Storage/storageAccounts/joinPerimeter/action"
    "Microsoft.Storage/storageAccounts/delete"
    "Microsoft.Storage/storageAccounts/read"
    "Microsoft.Storage/storageAccounts/listServiceSas/action"
    "Microsoft.Storage/storageAccounts/listAccountSas/action"
    "Microsoft.Storage/storageAccounts/write"
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write" 
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete" 
)

$rolescope.Name = $name
$rolescope.IsCustom = $true
$rolescope.Description = $description
$rolescope.Actions = $actions
$rolescope.AssignableScopes = $scope

$rolescope | write-verbose

New-AzRoleDefinition -Role $rolescope
