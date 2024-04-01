#!/bin/bash

# March 20, 2024
# Flex version: v1.50.77

#set -ex

# enable for high verbosity
# shellcheck disable=SC2198
if [ "${@: -1}" == "-v" ]; then
    set -x
fi

#-----------------------------------------------------------------------------------------------
# actions and data actions for role defenitions
# the following functions get called only if no directory of 'role_defention/' exists in the same dir as the script'
#-----------------------------------------------------------------------------------------------
get_new_vent_role_actions(){
   echo "\"Microsoft.Network/networkInterfaces/effectiveRouteTable/action\", \
    \"Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action\", \
    \"Microsoft.Network/virtualNetworks/read\", \
    \"Microsoft.Network/virtualNetworks/write\", \
    \"Microsoft.Network/virtualNetworks/join/action\", \
    \"Microsoft.Network/virtualNetworks/subnets/read\", \
    \"Microsoft.Network/virtualNetworks/subnets/write\", \
    \"Microsoft.Network/virtualNetworks/subnets/delete\", \
    \"Microsoft.Network/virtualNetworks/subnets/join/action\", \
    \"Microsoft.Network/virtualNetworks/peer/action\", \
    \"Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/read\", \
    \"Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/write\", \
    \"Microsoft.Network/virtualNetworks/VirtualNetworkPeerings/delete\""
}



get_min_perms_role_actions(){
    echo "\"Microsoft.Authorization/locks/delete\", \
    \"Microsoft.Authorization/locks/read\", \
    \"Microsoft.Authorization/locks/write\", \
    \"Microsoft.Compute/availabilitySets/delete\", \
    \"Microsoft.Compute/availabilitySets/read\", \
    \"Microsoft.Compute/availabilitySets/vmSizes/read\", \
    \"Microsoft.Compute/availabilitySets/write\", \
    \"Microsoft.Compute/disks/beginGetAccess/action\", \
    \"Microsoft.Compute/disks/delete\", \
    \"Microsoft.Compute/disks/endGetAccess/action\", \
    \"Microsoft.Compute/disks/read\", \
    \"Microsoft.Compute/disks/write\", \
    \"Microsoft.Compute/images/delete\", \
    \"Microsoft.Compute/images/read\", \
    \"Microsoft.Compute/images/write\", \
    \"Microsoft.Compute/proximityPlacementGroups/delete\", \
    \"Microsoft.Compute/proximityPlacementGroups/read\", \
    \"Microsoft.Compute/proximityPlacementGroups/write\", \
    \"Microsoft.Compute/virtualMachines/deallocate/action\", \
    \"Microsoft.Compute/virtualMachines/delete\", \
    \"Microsoft.Compute/virtualMachines/performMaintenance/action\", \
    \"Microsoft.Compute/virtualMachines/powerOff/action\", \
    \"Microsoft.Compute/virtualMachines/read\", \
    \"Microsoft.Compute/virtualMachines/redeploy/action\", \
    \"Microsoft.Compute/virtualMachines/restart/action\", \
    \"Microsoft.Compute/virtualMachines/runCommand/action\", \
    \"Microsoft.Compute/virtualMachines/start/action\", \
    \"Microsoft.Compute/virtualMachines/write\", \
    \"Microsoft.Network/loadBalancers/read\", \
    \"Microsoft.Network/networkInterfaces/delete\", \
    \"Microsoft.Network/networkInterfaces/ipconfigurations/join/action\", \
    \"Microsoft.Network/networkInterfaces/join/action\", \
    \"Microsoft.Network/networkInterfaces/read\", \
    \"Microsoft.Network/networkInterfaces/write\", \
    \"Microsoft.Network/networkSecurityGroups/delete\", \
    \"Microsoft.Network/networkSecurityGroups/join/action\", \
    \"Microsoft.Network/networkSecurityGroups/read\", \
    \"Microsoft.Network/networkSecurityGroups/write\", \
    \"Microsoft.Network/virtualNetworks/delete\", \
    \"Microsoft.Resources/subscriptions/resourcegroups/read\", \
    \"Microsoft.Storage/storageAccounts/blobServices/containers/read\", \
    \"Microsoft.Storage/storageAccounts/blobServices/containers/write\", \
    \"Microsoft.Storage/storageAccounts/delete\", \
    \"Microsoft.Storage/storageAccounts/joinPerimeter/action\", \
    \"Microsoft.Storage/storageAccounts/listAccountSas/action\", \
    \"Microsoft.Storage/storageAccounts/listServiceSas/action\", \
    \"Microsoft.Storage/storageAccounts/read\", \
    \"Microsoft.Storage/storageAccounts/write\""
}


get_min_perms_role_data_actions(){
    echo "\"Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read\", \
    \"Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write\", \
    \"Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete\""
}


get_existing_vnet_role_actions(){
    echo "\"Microsoft.Network/virtualNetworks/read\", \
    \"Microsoft.Network/virtualNetworks/write\", \
    \"Microsoft.Network/virtualNetworks/join/action\", \
    \"Microsoft.Network/virtualNetworks/subnets/read\", \
    \"Microsoft.Network/virtualNetworks/subnets/write\", \
    \"Microsoft.Network/virtualNetworks/subnets/delete\", \
    \"Microsoft.Network/virtualNetworks/subnets/join/action\", \
    \"Microsoft.Network/networkSecurityGroups/join/action\", \
    \"Microsoft.Network/networkInterfaces/join/action\", \
    \"Microsoft.Network/networkInterfaces/effectiveRouteTable/action\", \
    \"Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action\""
}


Help()
{
     USAGE="Usage: $0 --operation --umiRgName --umiName [--flexRG --flexVmName --location
     --roleName --subscriptionId] [--help]"
     echo "Syntax: $USAGE"
     echo "Parameters description:"
     echo "operation                         The Intended operation to do, supported operations are [create, assign ,unassign, delete, delete-role]"
     echo "umiRgName                         The resource group name that will/is contain the UMI."
     echo "umiName                           The name of the user Managed Identity."
     echo "flexRG                            The name of the resource group that FLEX is deployed in."
     echo "flexVmName                        The name of FLEX VM."
     echo "location                          Location of the RG which will include the user managed identity."
     echo "roleName                          if 'delete-role' operation, then this param should contain the role name."
     echo "subscriptionId                    Subscription ID for AZURE."
     echo "Examples:                          "
     echo "   Create User Managed Identity and Relevant Roles (Roles won't be assigned in this operation):"
     echo "       $0 --operation create --umiRgName \"test-umi-rg\" --umiName  \"test-umi-managed-identity\" --location \"eastus\""
     echo
     echo "   Assign User Managed Identity to FLEX:"
     echo "       $0 --operation assign --umiRgName \"test-umi-rg\" --umiName  \"test-umi-managed-identity\" --flexRG \"example-flex-deployment-rg\" --flexVmName \"example-flex-deployment-vm-name\""
     echo
     echo "   Assign a User Managed Identity Role to an RG:"
     echo "       $0 --operation assign-role --roleName \"custom-role-name\"  --umiRgName \"test-umi-rg\" --umiName  \"test-umi-managed-identity\" --flexRG \"example-flex-deployment-rg\""
     echo
     echo "   Remove assignment of a User Managed Identity from FLEX:"
     echo "       $0 --operation unassign --umiRgName \"test-umi-rg\" --umiName  \"test-umi-managed-identity\" --flexRG \"example-flex-deployment-rg\" --flexVmName \"example-flex-deployment-vm-name\""
     echo
     echo "   Delete User Managed Identity and its Resource Group:"
     echo "       $0 --operation delete --umiRgName \"test-umi-rg\" "
     echo
     echo "   Delete Custom Role:"
     echo "       $0 --operation delete-role --roleName \"custom-role-name\" "
     echo
     echo "In order to create and assign A User Managed Identity to a FLEX VM The Following steps should be done:"
     echo "       1. $0 --operation create ..."
     echo "       2. $0 --operation assign ..."
     echo "       3. $0 --operation assign-role ... for every role"
     echo "       4. Manually Remove System Assigned Identity, this can be done either from UI or by executing the following command:"
     echo "               az vm identity remove -g \"flexVmRG\" -n \"flexVmName\" --identities '[system]'"
     echo
     echo "Please note that some operations may take some time in order to take effect."

}

# Get the directory of the script
script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
roleDefenitionFilePath="$script_dir/roles_defenition/"
# Default values
operation=""
umiName=""
umiRgName=""
flexRG=""
flexVmName=""
location="EastUS"
roleName=""
subscriptionId="ed901d49-a834-434b-ab45-05d719f6f14b"


create_user_assigned_identity(){
  if az group show --name "$umiRgName" &>/dev/null; then
      echo "The resource group '$umiRgName' already exists."
      echo "Skipping resource group creation"
  else
      echo "Creating resource group '$umiName'..."
      az group create --name "$umiRgName" --location "$location"
  fi
  user_managed_identity_exists=$(az identity list -g "$umiRgName" | jq '.[].name' | grep "$umiName")

  if [[ -z "$user_managed_identity_exists" ]]; then
      echo "Creating User Managed Identity '$umiName'..."
      az identity create -g "$umiRgName" -n "$umiName"
  else
      echo "The User Managed Identity '$umiName' already exists."
      echo "Skipping creation."
  fi
}


assign_role_to_rg(){
  umi_principalId=$(az identity show -g "$umiRgName" -n "$umiName" | jq '.principalId' | tr -d '"')
  scope="/subscriptions/$subscriptionId/resourceGroups/$flexRG"
  az role assignment create --assignee-principal-type "ServicePrincipal" --assignee-object-id "$umi_principalId" --role "$roleName" --scope "$scope"

}

assign_user_assigned_identity(){
  umi_id="/subscriptions/$subscriptionId/resourcegroups/$umiRgName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$umiName"

  az vm identity assign -g "$flexRG" -n "$flexVmName" --identities "$umi_id"
  user_assigned_identities=$(az vm identity show -g "$flexRG" -n "$flexVmName"| jq '.userAssignedIdentities')

  if echo "$user_assigned_identities" | grep -qw "$umi_id"; then
      echo "Identity $umi_id is assigned!!"
  fi

}


unassign_user_assigned_identity_assignment(){
  umi_id="/subscriptions/$subscriptionId/resourcegroups/$umiRgName/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$umiName"
  echo "Will remove $umi_id"
  user_assigned_identities=$(az vm identity show -g "$flexRG" -n "$flexVmName" | jq '.userAssignedIdentities')

  if echo "$user_assigned_identities" | grep -qw "$umi_id"; then
      echo "Identity $umi_id is assigned, therefore will be removed"
      az vm identity remove -g "$flexRG" -n "$flexVmName" --identities "$umi_id"
  else
      echo "$umi_id is not assigned to the VM"
  fi
}

delete_user_assigned_identity_assignment(){
  az group delete --name "$umiRgName" --yes
}


create_role_for_flex() {
    echo "Creating Minimum permissions role for flex RG"
    minimum_permissions_role_name="$umiName-min-perms-role-$guid"
    echo "Checking if a role with the name '$minimum_permissions_role_name' exists."
    if [[ -n $(echo "$existing_roles" | jq '.[]') ]]; then
        # The role already exists, so you can update it if needed
        echo "The custom role '$minimum_permissions_role_name' deleting and recreating"
        delete_role "$minimum_permissions_role_name"
    fi

    min_perms_role_actions=$(cat "$roleDefenitionFilePath/min_perms_flex_role_actions.txt" || get_min_perms_role_actions)
    min_perms_role_data_actions=$(cat "$roleDefenitionFilePath/min_perms_flex_role_data_actions.txt" || get_min_perms_role_data_actions)

    # shellcheck disable=SC2046
    az role definition create --role-definition '{
    "Name": "'"$minimum_permissions_role_name"'",
    "Description": "Role for testing min permissions for each release",
    "Actions": [
        '"$min_perms_role_actions"'
    ],
    "NotActions": [],
    "DataActions": [
        '"$min_perms_role_data_actions"'
    ],
    "NotDataActions": [],
    "AssignableScopes": [
      "'"/subscriptions/$subscriptionId"'"
    ]
  }' > /dev/null


  role_exists=$(az role definition list --subscription "$subscriptionId" --name "$minimum_permissions_role_name"| jq -r '.[].roleName')
  if [[  -z "$role_exists"  ]] ; then
      echo "The Role '$minimum_permissions_role_name' wasn't created"
  else
      echo "The Role '$minimum_permissions_role_name' exists"
      echo "You can Assign this role to the FLEX VM if you wish to"
  fi

}

create_role_for_existing_vnet() {
    echo "create min permissions role for existing vnet RG"
    # shellcheck disable=SC2034
    existing_vnet_min_perms_role="$umiName-existing-vnet-min-perms-role-$guid"
    existing_roles=$(az role definition list --subscription "$subscriptionId" --name "$existing_vnet_min_perms_role")
    echo "Checking if a role with the name '$existing_vnet_min_perms_role' exists."
    if [[ -n $(echo "$existing_roles" | jq '.[]') ]]; then
        # The role already exists, so you can update it if needed
        echo "The custom role '$existing_vnet_min_perms_role' deleting and recreating"
        delete_role "$existing_vnet_min_perms_role"
    fi

    echo "creating new role $existing_vnet_min_perms_role"
    # The role doesn't exist, so you can create it

    existing_vnet_role_actions=$(cat "$roleDefenitionFilePath/min_perms_customer_role_actions.txt" || get_existing_vnet_role_actions)

    # shellcheck disable=SC2046
    az role definition create --role-definition '{
    "Name": "'"$existing_vnet_min_perms_role"'",
    "Description": "Role for testing min permissions for each release",
    "Actions": [
        '"$existing_vnet_role_actions"'
    ],
    "NotActions": [],
    "DataActions": [],
    "NotDataActions": [],
    "AssignableScopes": [
      "'"/subscriptions/$subscriptionId"'"
    ]
    }' > /dev/null


  role_exists=$(az role definition list --subscription "$subscriptionId" --name "$existing_vnet_min_perms_role"| jq -r '.[].roleName')
  if [[  -z "$role_exists"  ]] ; then
      echo "The Role '$existing_vnet_min_perms_role' wasn't created"
  else
      echo "The Role '$existing_vnet_min_perms_role' was created successfully"
      echo "You can Assign this role to the existing Vnet if you wish to"
  fi
}

create_role_for_new_vnet() {
    echo "create min permissions role for new vnet(VNET created by FLEX)"
    # shellcheck disable=SC2034
    new_vnet_min_perms_role="$umiName-new-vnet-min-perms-role-$guid"
    existing_roles=$(az role definition list --subscription "$subscriptionId" --name "$new_vnet_min_perms_role")
    echo "Checking if a role with the name '$new_vnet_min_perms_role' exists."
    if [[ -n $(echo "$existing_roles" | jq '.[]') ]]; then
        # The role already exists, so you can update it if needed
        echo "The custom role '$new_vnet_min_perms_role' deleting and recreating"
        delete_role "$new_vnet_min_perms_role"
    fi

    echo "creating new role $new_vnet_min_perms_role"
    # The role doesn't exist, so you can create it

    new_vnet_role_actions=$(cat "$roleDefenitionFilePath/new_vnet_role_actions.txt" || get_new_vent_role_actions)
    # shellcheck disable=SC2046
    az role definition create --role-definition '{
    "Name": "'"$new_vnet_min_perms_role"'",
    "Description": "Role for testing min permissions for each release",
    "Actions": [
        '"$new_vnet_role_actions"'
    ],
    "NotActions": [],
    "DataActions": [],
    "NotDataActions": [],
    "AssignableScopes": [
      "'"/subscriptions/$subscriptionId"'"
    ]
    }' > /dev/null


  role_exists=$(az role definition list --subscription "$subscriptionId" --name "$new_vnet_min_perms_role"| jq -r '.[].roleName')
  if [[  -z "$role_exists"  ]] ; then
      echo "The Role '$new_vnet_min_perms_role' wasn't created"
  else
      echo "The Role '$new_vnet_min_perms_role' was created successfully"
      echo "You can Assign this role to the existing Vnet if you wish to"
  fi
}

delete_role(){
    role_name=$1
    echo "deleting role $role_name if exists"
    if [[ "$(az role definition list --name "$role_name")" != "[]" ]];then
        # Delete the role
        echo "Role '$role_name', will delete it..."
        az role definition delete --name "$role_name"
        echo "Role '$role_name' deleted successfully."
    else
        echo "Role '$role_name' does not exist."
    fi
}


### Define paremeters if override in the command line #####
while [ $# -gt 0 ]; do

   if [[ $1 == *"--help"* ]]; then
        Help
        exit 0
   elif [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare "$param"="$2"
        echo "$param=$2"
   fi

  shift
done
# Validate required options based on the operation
case $operation in
  create)
    if [[ -z $umiName || -z $umiRgName ]]; then
      echo "Missing required options for 'create' operation."
      exit 1
    fi
    ;;
  assign | unassign)
    if [[ -z $umiName || -z $umiRgName || -z $flexRG || -z $flexVmName ]]; then
      echo "Missing required options for '$operation' operation."
      exit 1
    fi
    ;;
  assign-role )
    if [[ -z $umiName || -z $umiRgName || -z $flexRG || -z $roleName ]]; then
      echo "Missing required options for '$operation' operation."
      exit 1
    fi
    ;;
  delete )
    if [[ -z $umiRgName ]]; then
      echo "Missing required options for '$operation' operation."
      exit 1
    fi
    ;;
  delete-role )
    if [[ -z $roleName ]]; then
      echo "Missing required options for '$operation' operation."
      exit 1
    fi
    ;;
  *)
    echo "Invalid operation: $operation"
    Help
    exit 1
    ;;
esac


# Perform the desired operation based on the provided options
# Add your code here...

# Example operations based on the provided options
case $operation in
  create)
    echo "Creating UMI $umiName in $umiRgName..."
    create_user_assigned_identity
    random_hex=$(openssl rand -hex 2)
    export guid="$random_hex"
    # after creating the User Managed Identity the roles will be created but NOT assigned!!
    # Its the responsibility of the user to assign the Roles if he wishes to
    # the generated roles will have a 4-digits hex in the suffix to ensure its uniqueness
    create_role_for_flex
    create_role_for_new_vnet
    create_role_for_existing_vnet
    ;;
  assign)
    echo "Assigning UMI $umiName in $umiRgName to Flex VM $flexVmName in $flexRG..."
    assign_user_assigned_identity
    ;;
  assign-role)
    echo "Assigning UMI $umiName in $umiRgName to Flex VM $flexVmName in $flexRG..."
    assign_role_to_rg
    ;;
  delete)
    echo "Deleting UMI $umiName in $umiRgName..."
    delete_user_assigned_identity_assignment
    ;;
  unassign)
    echo "Unassigning UMI $umiName in $umiRgName from Flex VM $flexVmName in $flexRG..."
    unassign_user_assigned_identity_assignment
    ;;
  delete-role)
    # Since the script has the ability to create Roles after creating the User Managed Identity
    # its only common since for the script to have the ability to delete such roles
    echo "Deleting Role '$roleName'..."
    delete_role "$roleName"
    ;;
esac
