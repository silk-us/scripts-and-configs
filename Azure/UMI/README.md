## User Managed Identity (UMI) Deployment Guide

Silk Flex deployments on Azure can utilize either a System Managed Identity (SMI) or a User Managed Identity (UMI).
For either deployment method, if the account used during the deployment can not have `owner` role assignment to the Resource Group these roles detail the minimum required permissions to deploy from the Azure marketplace:
- [resource-group-role](../Role%20JSONs/example-silk-deployment-operator-resource-group-role.json)
- [subscription-role](../Role%20JSONs/example-silk-deployment-operator-subscription-role.json)
- [vnet-resource-group-role](../Role%20JSONs/example-silk-deployment-operator-vnet-resource-group-role.json)

### UMI vs SMI Deployments

**System Managed Identity (SMI)** deployments allow Silk Flex to create and manage networking resources (NSGs, subnets) automatically during deployment with broader permissions.

**User Managed Identity (UMI)** deployments require managed identity, associated roles and role assignments along with all networking infrastructure to be pre-created.

### Required Infrastructure for UMI Deployments

UMI deployments require the following resources to be created before initiating the Silk Flex marketplace deployment:

#### 1. Network Security Groups (NSGs)
Network Security Groups control traffic to the Flex management and Silk cluster subnets. The example JSON configurations define the required security rules for proper operation.

**Required NSGs:**
- [**Flex Subnet NSG**](../NSG%20Rule%20JSONs/example-flex-nsg-configuration.json) - Controls access to the Flex management subnet
- [**Silk Cluster Subnet NSGs**](../NSG%20Rule%20JSONs/example-silk-cluster-nsg-configuration.json) - Controls access to all cluster subnets (external data, internal, external management)

**Configuration Requirements:**
- Security rules allowing required traffic within VNET scope
- Proper priority ordering and rule directionality
- CIDR ranges matching your subnet configuration
- Confirm that an outbound rule is added in the Flex NSG for these destinations: "Storage," "AzureCloud," and hub.clarity.silk.us (34.120.213.129).
- Allow HTTPs outbound internet traffic for these domains on the any additional firewalls (permanent access):
    - Azure domains:*.blob.core.windows.net, *.azure.com
    - Clarity domains: hub.clarity.silk.us (34.120.213.129)

Detailed configuration specifications and deployment methods are available in the [NSG Rule JSONs README](../NSG%20Rule%20JSONs/README.md).

#### 2. Virtual Network Subnets
All subnets required by the Silk cluster must be pre-created within an existing Virtual Network. These subnets must be configured with the appropriate service endpoints and associated with their corresponding NSGs.

**Required Subnets:**
- **Flex Subnet** - Hosts the Flex management infrastructure
- **External Data Subnets (2x)** - Handles client iscsi data traffic
- **Internal Subnets (2x)** - Handles inter-node cluster communication
- **External Management Subnet** - Hosts cluster management interfaces

**Configuration Requirements:**
- Proper IP address ranges for each subnet within the VNET
- Service endpoints: `Microsoft.Storage.Global` and `Microsoft.ContainerRegistry` on Flex and Management subnets
- NSG association for each subnet

Example configuration: [umi-example-silk-cluster-subnet-configuration.json](../VNET%20Subnet%20JSONs/umi-example-silk-cluster-subnet-configuration.json)

Detailed configuration specifications and deployment methods are available in the [VNET Subnet JSONs README](../VNET%20Subnet%20JSONs/README.md).

#### 3. User Managed Identity
A User Managed Identity must be created in Azure that will be assigned to the Silk Flex deployment. This identity will be used by Flex to interact with Azure resources during and after deployment.

```powershell-interactive
# Create a new User Managed Identity in Azure
$resourceGroupName = 'example-umi-resource-group'
$identityName = 'example-umi-object'
$location = 'new-flex-region'

# Create the User Managed Identity
New-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name $identityName -Location $location
```

**Configuration Requirements:**
- Created in the same Azure region as the deployment
- Resource ID must be provided during Flex marketplace deployment
- Must have appropriate RBAC roles assigned (see next section)

#### 4. Custom RBAC Roles and Assignments
Custom Azure RBAC roles must be created and assigned to the User Managed Identity with minimum required permissions for Flex operation.

**Required Roles:**
- [**UMI Flex Resource Group Role**](../Role%20JSONs/example-silk-umi-flex-rg-role.json) - Permissions to create and manage compute resources in the empty Flex resource group
- [**UMI NSG Role**](../Role%20JSONs/example-silk-umi-nsg-role.json) - Read and write permissions on Network Security Groups
- [**UMI NSG Resource Group Role**](../Role%20JSONs/example-silk-umi-nsg-rg-role.json) - Resource group level permissions for Network Security Groups
- [**UMI VNET Role**](../Role%20JSONs/example-silk-umi-vnet-role.json) - Subnet join and read permissions on the Virtual Network
- [**UMI Object Role**](../Role%20JSONs/example-silk-umi-object-role.json) - (Optional) - Grants permissions for the User Managed Identity (UMI) to assign itself to new Flex instances during the upgrade process.
- [**UMI Subscription Logs Role**](../Role%20JSONs/example-silk-umi-subscription-logs-role.json) - (Optional) - Activity log read permissions at the subscription level

**Assignment Requirements:**
- **UMI Flex Resource Group Role** → Assigned to UMI on the empty target resource group
- **UMI NSG Role** → Assigned to UMI on each NSG resource
- **UMI NSG Resource Group Role** → Assigned to UMI on the NSG resource group
- **UMI VNET Role** → Assigned to UMI on the VNET resource
- **UMI Object Role** → (Optional) - Assigned to UMI on the UMI object resource
- **UMI Subscription Logs Role** → (Optional) - Assigned to UMI on the subscription

Detailed role definitions and assignment guidance are available in the [Role JSONs README](../Role%20JSONs/README.md).

### Resource Creation Order

Resources must be created in this order due to dependencies:

1. **Network Security Groups** - Required before subnets can be created
2. **Virtual Network Subnets** - Required before Flex deployment and must reference NSGs
3. **User Managed Identity** - Required before role assignments
4. **RBAC Roles and Assignments** - Required before Flex deployment


### What Gets Pre-Created vs What Flex Creates

**Pre-Created for UMI:**
- All Network Security Groups with configured security rules
- All Virtual Network subnets with service endpoints and NSG associations
- User Managed Identity with custom RBAC role assignments

**Created by Flex:**
- Virtual Machines (Silk nodes)
- Managed Disks
- Network Interfaces
- Load Balancers
- Other compute and storage resources within the target resource group

For detailed configuration requirements, example JSON files, and deployment instructions for each component, refer to the linked README files in each subdirectory.
