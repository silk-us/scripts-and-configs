# Azure Resources for Silk Deployments

This directory contains configuration templates, tools, and documentation to support Silk Data Pod and Flex deployments on Microsoft Azure. The resources provided here help prepare Azure environments with the proper networking, security, permissions, and validation to ensure successful Silk deployments.

---

## Table of Contents

### [NSG Rule JSONs](./NSG%20Rule%20JSONs)
Contains example Network Security Group (NSG) configurations for Silk Flex deployments. Includes JSON templates for both Flex-specific NSGs and Silk cluster NSGs with pre-configured security rules that allow the necessary traffic within the scope of your VNET while maintaining security best practices.

### [Resource Availability Check](./Resource%20Availability%20Check)
Provides the `Test-SilkResourceDeployment` PowerShell module that validates whether your Silk Data Pod deployment requirements can be met in your Azure environment. This tool models Azure resources, checks for region/zone VM SKU support, validates quota limits, and tests actual capacity by deploying test VMs with the same constraints Silk Flex orchestrates.

### [Role JSONs](./Role%20JSONs)
Contains example Azure RBAC role definitions with minimum required permissions for Silk Flex deployments using User Managed Identities. Includes separate roles for deployment operators and User Managed Identities (UMI) with granular permissions scoped to resource groups, subscriptions, VNETs, and NSGs to follow the principle of least privilege.

### [UMI](./UMI)
Contains a readme detailing the requirement of a User Managed Identity deployment.


### [VNET Subnet JSONs](./VNET%20Subnet%20JSONs)
Provides example subnet configuration templates for deploying Silk Flex subnets within existing Azure Virtual Networks. Includes all required service endpoints (Microsoft.Storage.Global and Microsoft.ContainerRegistry) and guidance for associating appropriately configured NSGs to the subnet.
