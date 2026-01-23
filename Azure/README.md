# Azure Resources for Silk Deployments

This directory contains configuration templates, tools, and documentation to support Silk Data Pod and Flex deployments on Microsoft Azure. The resources provided here help prepare Azure environments with the proper networking, security, permissions, and validation to ensure successful Silk deployments.

---

## User Managed Identity (UMI) Deployment Guide

Silk Flex deployments on Azure can utilize either a System Managed Identity (SMI) or a User Managed Identity (UMI). UMI deployments provide enhanced security and control by allowing you to pre-create and pre-configure all Azure resources with specific role-based access controls before the Flex deployment begins.

### UMI vs SMI Deployments

**System Managed Identity (SMI)** deployments allow Silk Flex to create and manage networking resources (NSGs, subnets) automatically during deployment with broader permissions.

**User Managed Identity (UMI)** deployments require manual pre-creation of all networking infrastructure, providing:
- **Principle of least privilege** - granular permission scoping to specific resources
- **Enhanced security** - pre-validated networking configuration before deployment
- **Greater control** - explicit approval of all network configurations and security rules
- **Compliance** - meets stricter organizational security requirements

### Prerequisites for UMI Deployments

Before beginning a UMI deployment, ensure you have:
1. An authenticated Azure PowerShell session (`Connect-AzAccount`)
2. Appropriate permissions to create resources in the target subscription and resource groups
3. An existing Virtual Network (VNET) with available IP address space
4. An empty resource group where the Silk Flex cluster will be deployed

### UMI Deployment Process

UMI deployments require pre-creation of resources in the following order:

#### 1. Create Network Security Groups (NSGs)
Network Security Groups must be created first as they are required when creating subnets.

**Required NSGs:**
- **Flex Subnet NSG** - Controls access to the Flex management subnet
- **Silk Cluster Subnet NSGs** - Controls access to cluster subnets (external data, internal, external management)

**Process:**
1. Review the [NSG Rule JSONs README](./NSG%20Rule%20JSONs/README.md) for detailed deployment instructions
2. Modify the appropriate example JSON configuration:
   - [example-flex-nsg-configuration.json](./NSG%20Rule%20JSONs/example-flex-nsg-configuration.json) for Flex subnet NSG
   - [example-silk-cluster-nsg-configuration.json](./NSG%20Rule%20JSONs/example-silk-cluster-nsg-configuration.json) for Silk cluster subnet NSGs
3. Update resource group names, Azure regions, cluster numbers, and CIDR ranges
4. Deploy using the PowerShell commands provided in the NSG Rule JSONs README

#### 2. Create Virtual Network Subnets
After NSGs are created, configure and create all required subnets within your existing VNET.

**Required Subnets:**
- **Flex Subnet** - Hosts the Flex management infrastructure
- **Silk Cluster Subnets** - External data (2x), internal (2x), and external management subnets

**Process:**
1. Review the [VNET Subnet JSONs README](./VNET%20Subnet%20JSONs/README.md) for detailed deployment instructions
2. Modify the appropriate example JSON configuration:
   - [umi-example-silk-cluster-subnet-configuration.json](./VNET%20Subnet%20JSONs/umi-example-silk-cluster-subnet-configuration.json) for UMI deployments
3. Update VNET details, subnet names, IP ranges, and associated NSG names
4. Ensure required service endpoints are configured (`Microsoft.Storage.Global`, `Microsoft.ContainerRegistry`)
5. Deploy using the PowerShell commands provided in the VNET Subnet JSONs README

#### 3. Create User Managed Identity
Create the User Managed Identity that will be used by the Silk Flex deployment.

**Process:**
```powershell
$umi = New-AzUserAssignedIdentity -ResourceGroupName "<resource-group-name>" `
                                   -Name "<umi-name>" `
                                   -Location "<azure-region>"
```

Save the UMI resource ID and client ID for use during the Flex deployment.

#### 4. Create and Assign Custom RBAC Roles
Create custom Azure RBAC roles with minimum required permissions and assign them to the User Managed Identity.

**Required UMI Roles:**
- **UMI Resource Group Role** - Permissions on the target (empty) resource group where Flex will deploy
- **UMI NSG Role** - Read/write permissions on each Network Security Group
- **UMI VNET Role** - Subnet join and read permissions on the Virtual Network
- **UMI Subscription Logs Role** - Activity log read permissions at the subscription level

**Process:**
1. Review the [Role JSONs README](./Role%20JSONs/README.md) for detailed instructions
2. For each required role:
   - Modify the example JSON (update `name` and `assignableScopes` values)
   - Create the role: `New-AzRoleDefinition -InputFile .\example-role.json`
   - Assign the role to your UMI at the appropriate scope using the Azure Portal or PowerShell

**Role Assignment Scopes:**
- **UMI Resource Group Role** → Assigned to UMI on the empty resource group
- **UMI NSG Role** → Assigned to UMI on each NSG resource
- **UMI VNET Role** → Assigned to UMI on the VNET resource
- **UMI Subscription Logs Role** → Assigned to UMI on the subscription

Detailed role definitions and assignment instructions are available in the [Role JSONs README](./Role%20JSONs/README.md).

#### 5. Validate Resource Availability (Optional but Recommended)
Before attempting the Flex deployment, validate that your Azure environment can support the required VM SKUs and capacity.

**Process:**
1. Review the [Resource Availability Check README](./Resource%20Availability%20Check/readme.md)
2. Use the `Test-SilkResourceDeployment` PowerShell module to validate:
   - VM SKU availability in target regions and availability zones
   - Sufficient quota limits for required resources
   - Actual deployment capacity through test VM creation

#### 6. Deploy Silk Flex with UMI
With all pre-requisite resources created, proceed with the Silk Flex Azure Marketplace deployment:

1. Navigate to the Silk Flex offering in Azure Marketplace
2. Configure the deployment to use your User Managed Identity:
   - Select "User Managed Identity" as the identity type
   - Provide the resource ID of the UMI created in step 3
3. Specify the pre-created subnets during the deployment configuration
4. Complete the deployment form and deploy

The Flex deployment will use the UMI and pre-created networking resources rather than creating them automatically.

### UMI Deployment Summary

**What Gets Pre-Created:**
- Network Security Groups with configured security rules
- Virtual Network subnets with service endpoints and NSG associations
- User Managed Identity with custom RBAC role assignments

**What Flex Creates:**
- Virtual Machines (Silk nodes)
- Managed Disks
- Network Interfaces
- Load Balancers
- Other compute and storage resources within the target resource group

**Benefits:**
- Enhanced security through least privilege access
- Pre-validated networking configuration
- Explicit control over network security rules
- Compliance with strict organizational policies

For detailed step-by-step instructions, JSON examples, and PowerShell commands for each component, refer to the linked README files in each subdirectory.

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
