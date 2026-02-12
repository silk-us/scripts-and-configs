# Azure RBAC Roles for Silk Flex Deployments

This readme offers a method to generate roles required for a Silk Flex Azure Marketplace deployment and ongoing operation for an environment using User Managed Identities. The role definition JSON files can be used to create the roles with minimal changes which adapt them to your environment. The role assignments will also be outlined in this readme.

---

## Create Roles

### Prerequisites for Deploying the Roles
It's assumed you've established an authenticated powershell session to azure and are operating in that session for the entirety of this process. You can use `Connect-AzAccount` to establish that connection and would need to do this in each powershell session you operate out of.


### Example Configuration Changes
The following values from any of the role json can be updated according to your environments values.
`  "name": "example-silk-umi-nsg-role",`
The assignable scopes will vary but update the resource accordingly.
```json
  "assignableScopes": [
    "/subscriptions/YOUR-SUBSCRIPTION-ID/resourceGroups/example-network-resource-group"
  ]
```

### PowerShell Deployment

#### Create Azure Role from Modified JSON
Update `-InputFile` parameter value with path to the appropriately modified json.  Repeat this for each role needed to be created in preparation for the flex deployment.
```powershell
New-AzRoleDefinition -InputFile .\example....json
```

---

## Role Assignments

### Operator Roles
If the user performing the deployment has owner access to the empty Resource Group which the Silk Flex deployment will target or has higher privilege then no roles need to be created or assigned to the operator.  The operator roles are only required for the deployment, these roles allow only the necessary access is granted to the operator.
- [Deployment Resource Group Role](example-silk-deployment-operator-flex-rg-role.json)
  - Created with the assignable scope of the empty Resource Group.
  - Assigned to the deployment operator on the empty Resource Group.
- [Deployment Subscription Role](example-silk-deployment-operator-subscription-role.json)
  - Created with the assignable scope of the Subscription which the target Resource Group is created.
  - Assigned to the scope of the Subscription which the target Resource Group is created.
- [Deployment VNET Resource Group Role](example-silk-deployment-operator-vnet-role.json)
  - Created with the assignable scope of the Resource Group that the VNET will be/has been created.
  - Assigned to the scope of the Resource Group that the VNET will be/has been created.

### User Managed Identity Roles
If the deployment will use a User Managed Identity instead of the default System Managed Identity these roles can be created and assigned to the UMI to allow only the required actions to the environment.
- [UMI Flex Resource Group Role](example-silk-umi-flex-rg-role.json)
  - Created with the assignable scope of the empty Flex Resource Group.
  - Assigned to the UMI on the empty Flex Resource Group.
- [UMI NSG Role](example-silk-umi-nsg-role.json)
  - Created with the assignable scope of the Resource Group that the NSGs will be/have been created.
  - Assigned to the UMI on each of the NSG resources and the NSG resource group.
- [UMI VNET Role](example-silk-umi-vnet-role.json)
  - Created with the assignable scope of the Resource Group that the VNET will be/has been created.
  - Assigned to the UMI on the VNET resource.
- [UMI Subscription Logs Role](example-silk-umi-subscription-logs-role.json)
  - Created with the assignable scope of the Subscription which the target Resource Group is created.
  - Assigned to the UMI on the subscription.
- [UMI Object Role](example-silk-umi-object-role.json) - (Optional)
  - Created with the assignable scope of the UMI object resource.
  - Assigned to the UMI on the UMI object resource itself.
  - Grants permissions for the User Managed Identity to assign itself to new Flex instances during the upgrade process.
