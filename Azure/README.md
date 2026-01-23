# Azure Resources for Silk Deployments

This directory contains configuration templates, tools, and documentation to support Silk Data Pod and Flex deployments on Microsoft Azure. The resources provided here help prepare Azure environments with the proper networking, security, permissions, and validation to ensure successful Silk deployments.

---

## User Managed Identity (UMI) Deployment Guide

Silk Flex deployments on Azure can utilize either a System Managed Identity (SMI) or a User Managed Identity (UMI).

### UMI vs SMI Deployments

**System Managed Identity (SMI)** deployments allow Silk Flex to create and manage networking resources (NSGs, subnets) automatically during deployment with broader permissions.

**User Managed Identity (UMI)** deployments require managed identity, associated roles and role assignments along with all networking infrastructure to be pre-created.

### Required Infrastructure for UMI Deployments

UMI deployments require the following resources to be created before initiating the Silk Flex marketplace deployment:

#### 1. Network Security Groups (NSGs)
Network Security Groups control traffic to the Flex management and Silk cluster subnets. The example JSON configurations define the required security rules for proper operation.

**Required NSGs:**
- **Flex Subnet NSG** - Controls access to the Flex management subnet ([example-flex-nsg-configuration.json](./NSG%20Rule%20JSONs/example-flex-nsg-configuration.json))
- **Silk Cluster Subnet NSGs** - Controls access to all cluster subnets (external data, internal, external management) ([example-silk-cluster-nsg-configuration.json](./NSG%20Rule%20JSONs/example-silk-cluster-nsg-configuration.json))

**Configuration Requirements:**
- Security rules allowing required traffic within VNET scope
- Proper priority ordering and rule directionality
- CIDR ranges matching your subnet configuration

Detailed configuration specifications and deployment methods are available in the [NSG Rule JSONs README](./NSG%20Rule%20JSONs/README.md).

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

Example configuration: [umi-example-silk-cluster-subnet-configuration.json](./VNET%20Subnet%20JSONs/umi-example-silk-cluster-subnet-configuration.json)

Detailed configuration specifications and deployment methods are available in the [VNET Subnet JSONs README](./VNET%20Subnet%20JSONs/README.md).

#### 3. User Managed Identity
A User Managed Identity must be created in Azure that will be assigned to the Silk Flex deployment. This identity will be used by Flex to interact with Azure resources during and after deployment.

**Configuration Requirements:**
- Created in the same Azure region as the deployment
- Resource ID must be provided during Flex marketplace deployment
- Must have appropriate RBAC roles assigned (see next section)

#### 4. Custom RBAC Roles and Assignments
Custom Azure RBAC roles must be created and assigned to the User Managed Identity with minimum required permissions for Flex operation.

**Required Roles:**
- **UMI Resource Group Role** - Permissions to create and manage compute resources in the target resource group ([example-silk-umi-resourcegroup-role.json](./Role%20JSONs/example-silk-umi-resourcegroup-role.json))
- **UMI NSG Role** - Read and write permissions on Network Security Groups ([example-silk-umi-nsg-role.json](./Role%20JSONs/example-silk-umi-nsg-role.json))
- **UMI VNET Role** - Subnet join and read permissions on the Virtual Network ([example-silk-umi-vnet-role.json](./Role%20JSONs/example-silk-umi-vnet-role.json))
- **UMI Subscription Logs Role** - Activity log read permissions at the subscription level ([example-silk-umi-subscription-logs-role.json](./Role%20JSONs/example-silk-umi-subscription-logs-role.json))

**Assignment Requirements:**
- **UMI Resource Group Role** → Assigned to UMI on the empty target resource group
- **UMI NSG Role** → Assigned to UMI on each NSG resource
- **UMI VNET Role** → Assigned to UMI on the VNET resource
- **UMI Subscription Logs Role** → Assigned to UMI on the subscription

Detailed role definitions and assignment guidance are available in the [Role JSONs README](./Role%20JSONs/README.md).

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

---

## Table of Contents

### [NSG Rule JSONs](./NSG%20Rule%20JSONs)
Contains example Network Security Group (NSG) configurations for Silk Flex deployments. Includes JSON templates for both Flex-specific NSGs and Silk cluster NSGs with pre-configured security rules that allow the necessary traffic within the scope of your VNET while maintaining security best practices.

### [Resource Availability Check](./Resource%20Availability%20Check)
Provides the `Test-SilkResourceDeployment` PowerShell module that validates whether your Silk Data Pod deployment requirements can be met in your Azure environment. This tool models Azure resources, checks for region/zone VM SKU support, validates quota limits, and tests actual capacity by deploying test VMs with the same constraints Silk Flex orchestrates.

### [Role JSONs](./Role%20JSONs)
Contains example Azure RBAC role definitions with minimum required permissions for Silk Flex deployments using User Managed Identities. Includes separate roles for deployment operators and User Managed Identities (UMI) with granular permissions scoped to resource groups, subscriptions, VNETs, and NSGs to follow the principle of least privilege.

### [VNET Subnet JSONs](./VNET%20Subnet%20JSONs)
Provides example subnet configuration templates for deploying Silk Flex subnets within existing Azure Virtual Networks. Includes all required service endpoints (Microsoft.Storage.Global and Microsoft.ContainerRegistry) and guidance for associating appropriately configured NSGs to the subnet.
