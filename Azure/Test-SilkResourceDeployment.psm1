

function Test-SilkResourceDeployment
    {

        <#
            .SYNOPSIS
                Tests Azure VM SKU availability for Silk Infrastructure deployments by deploying test resources.

            .DESCRIPTION
                This function validates that required Azure VM SKUs and resources are available for Silk Infrastructure
                deployments by creating test VMs and resources. It performs comprehensive SKU availability checking,
                quota validation, and actual deployment testing to ensure successful production deployments.

                The function supports multiple parameter sets for different deployment scenarios:
                - JSON Configuration: Use a configuration file for all parameters
                - Friendly Names: Use descriptive names for CNode/MNode selection
                - Explicit SKUs: Specify exact Azure VM SKUs for advanced scenarios
                - Cleanup Only: Remove previously created test resources

                Complete Test Environment Creation:
                - Virtual Network with isolated management subnet and Network Security Group
                - CNode VMs (Control Nodes) - minimum 2, maximum 8 for cluster management
                - MNode/DNode VMs (Media/Data Nodes) based on specified storage capacities
                - Availability Sets for high availability testing
                - Comprehensive progress tracking and resource validation
                - SKU support validation across availability zones
                - Quota availability checking for all resource types
                - Optional cleanup functionality to remove all created resources

                Silk Infrastructure Components:
                - CNodes: Control nodes that manage the overall Silk cluster operations and coordination
                - MNodes: Media nodes that coordinate data operations and storage management
                - DNodes: Data nodes that store and serve data (deployed as part of MNode groups)

                Function Version: 1.97.9-1.0.0
                Supporting Silk SDP configurations from version 1.97.9

            .PARAMETER SubscriptionId
                Azure Subscription ID where resources will be deployed.
                This parameter overrides JSON configuration values if provided.
                Example: "12345678-1234-1234-1234-123456789012"

            .PARAMETER ResourceGroupName
                Azure Resource Group name where test resources will be deployed.
                The resource group must already exist in the specified subscription.
                This parameter overrides JSON configuration values if provided.
                Example: "silk-test-rg"

            .PARAMETER Region
                Azure region for resource deployment. Must be a valid Azure region name.
                This parameter overrides JSON configuration values if provided.
                Common examples: "eastus", "westus2", "northeurope", "eastasia"

            .PARAMETER Zone
                Azure Availability Zone for resource placement. Use "Zoneless" for regions without zones.
                Valid values: "1", "2", "3", "Zoneless"
                This parameter overrides JSON configuration values if provided.

            .PARAMETER ConfigurationJson
                Path to JSON configuration file as formatted by the Silk deployment checklist containing all deployment parameters.
                When specified, parameters are loaded from this file unless overridden by command line parameters.
                Example: "C:\configs\silk-deployment.json"

            .PARAMETER CNodeFriendlyName
                Friendly name for CNode SKU selection using descriptive categories:
                - "Increased_Logical_Capacity" (Standard_E64s_v5) - High memory SKU, most commonly used due to increased capacity capabilities and cost effectiveness
                - "Read_Cache_Enabled" (Standard_L64s_v3) - High-speed local SSD storage for read-intensive workloads
                - "No_Increased_Logical_Capacity" (Standard_D64s_v5) - Basic compute SKU, uncommonly used in favor of the increased logical capacity configuration

            .PARAMETER CNodeSku
                Explicit Azure VM SKU for CNode VMs when using direct SKU specification.
                Alternative to CNodeFriendlyName for advanced scenarios requiring specific SKU control.
                Valid values: "Standard_E64s_v5", "Standard_L64s_v3", "Standard_D64s_v5"

            .PARAMETER CNodeCount
                Number of CNode VMs to deploy. Silk Infrastructure requires minimum 2 CNodes for cluster quorum,
                maximum 8 CNodes for optimal cluster management. Range: 2-8

            .PARAMETER MnodeSizeLsv3
                Array of MNode storage capacities for Lsv3 series SKUs (older generation with proven stability).
                Valid values correspond to physical storage capacity in TiB:
                - "19.5" TiB (Standard_L8s_v3)  - 8 vCPU, 64 GB RAM, local NVMe storage
                - "39.1" TiB (Standard_L16s_v3) - 16 vCPU, 128 GB RAM, local NVMe storage
                - "78.2" TiB (Standard_L32s_v3) - 32 vCPU, 256 GB RAM, local NVMe storage
                Example: @("19.5", "39.1") for mixed capacity deployment

            .PARAMETER MnodeSizeLaosv4
                Array of MNode storage capacities for Laosv4 series SKUs (newer generation with higher density).
                Valid values correspond to physical storage capacity in TiB:
                - "14.67" TiB (Standard_L2aos_v4)  - 2 vCPU, latest storage technology
                - "29.34" TiB (Standard_L4aos_v4)  - 4 vCPU, latest storage technology
                - "58.67" TiB (Standard_L8aos_v4)  - 8 vCPU, latest storage technology
                - "88.01" TiB (Standard_L12aos_v4) - 12 vCPU, latest storage technology
                - "117.35" TiB (Standard_L16aos_v4) - 16 vCPU, latest storage technology
                Example: @("14.67", "29.34") for cost-optimized mixed capacity deployment

            .PARAMETER MnodeSku
                Array of explicit Azure VM SKUs for MNode/DNode VMs when using direct SKU specification.
                Alternative to size-based selection for advanced scenarios requiring specific SKU control.
                Valid Lsv3 SKUs: "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3"
                Valid Laosv4 SKUs: "Standard_L2aos_v4", "Standard_L4aos_v4", "Standard_L8aos_v4", "Standard_L12aos_v4", "Standard_L16aos_v4"

            .PARAMETER MNodeCount
                Number of MNode instances when using explicit SKU specification (MnodeSku parameter).
                Range: 1-4

            .PARAMETER DisableCleanup
                Switch parameter to disable automatic cleanup of test resources after deployment validation.
                When specified, test resources remain in Azure for manual inspection or extended testing.
                Resources must be manually removed or cleaned up using -RunCleanupOnly parameter.

            .PARAMETER RunCleanupOnly
                Switch parameter to only perform cleanup operations, removing all previously created test resources.
                Identifies and removes all resources created by previous test runs based on resource name prefix.
                Use this to clean up resources from failed deployments or when cleanup was disabled.

            .PARAMETER IPRangeCIDR
                CIDR notation for VNet and subnet IP address range used for network isolation.
                This parameter overrides JSON configuration values if provided.
                Default: "10.0.0.0/24" (provides 254 usable IP addresses)
                Example: "192.168.1.0/24" for custom network ranges

            .PARAMETER VMImageOffer
                Azure Marketplace image offer for VM operating system.
                Default: "0001-com-ubuntu-server-jammy" (Ubuntu 22.04 LTS)
                Advanced parameter - modify only if specific OS requirements exist.

            .PARAMETER VMImagePublisher
                Azure Marketplace image publisher for VM operating system.
                Default: "Canonical" (official Ubuntu publisher)
                Advanced parameter - modify only if using non-Ubuntu images.

            .PARAMETER VMImageSku
                Azure Marketplace image SKU for VM operating system.
                If not specified, automatically selects the latest available SKU with Gen2 preference.
                Advanced parameter - function auto-detects best available SKU for most scenarios.

            .PARAMETER VMImageVersion
                Azure Marketplace image version for VM operating system.
                Default: "latest" (automatically uses most recent image version)
                Advanced parameter - specify only if specific image version required for compliance.

            .PARAMETER ResourceNamePrefix
                Prefix used for all created Azure resource names to enable easy identification and cleanup.
                Default: "sdp-test" (creates names like "sdp-test-cnode-01", "sdp-test-vnet")
                Modify for multiple parallel test deployments or organizational naming standards.

            .PARAMETER VMInstanceCredential
                PowerShell credential object containing username and password for VM local administrator account.
                Default: Username "azureuser" with secure password for testing purposes.
                Used for VM deployment - SSH key authentication not implemented in test scenarios.

            .PARAMETER Testing
                Switch parameter to enable testing mode with reduced VM sizes and instance counts.
                When enabled: Uses 2 vCPU SKUs instead of production 64 vCPU, 1 DNode per MNode instead of 16.
                Significantly reduces deployment time and costs for faster testing iterations.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCount 2 -MnodeSizeLaosv4 @("14.67","29.34") -Testing -Verbose

                Tests deployment with 2 CNodes using high-memory SKUs and 2 MNode groups with Laosv4 storage capacities.
                Uses testing mode for faster deployment with reduced VM sizes and verbose output for detailed progress tracking.

            .EXAMPLE
                Test-SilkResourceDeployment -ConfigurationJson "C:\configs\silk-deployment.json" -Testing -Verbose

                Uses JSON configuration file for all deployment parameters with testing mode enabled and verbose output.
                All parameters are loaded from the JSON file unless overridden by command line parameters.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -RunCleanupOnly

                Performs cleanup-only operation, removing all test resources created by previous runs in the specified resource group.
                Uses the standard resource name prefix "sdp-test" to identify and remove test resources.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-prod-rg" -Region "westus2" -Zone "2" -CNodeSku "Standard_E64s_v5" -CNodeCount 4 -MNodeSku @("Standard_L16s_v3","Standard_L32s_v3") -MNodeCount 2 -DisableCleanup

                Advanced deployment using explicit SKUs: 4 CNodes with E64s_v5 SKU and 2 MNode groups with mixed L-series SKUs.
                Disables automatic cleanup so resources remain for extended testing or manual validation.

            .INPUTS
                Command line parameters or JSON configuration file containing deployment specifications.
                Supports both individual parameter specification and bulk configuration via JSON import.

            .OUTPUTS
                Console output with comprehensive deployment status information, resource validation results,
                SKU availability reports, quota validation summaries, and deployment progress tracking.
                No objects are returned to the pipeline - all output is informational console display.

            .NOTES
                Function Version: 1.97.9-1.0.0
                Supporting Silk SDP configurations from version 1.97.9
                Author: Silk Cloud Infrastructure Team

                Requirements:
                - Azure PowerShell module (Az) with valid authentication
                - Contributor or equivalent permissions in target subscription and resource group
                - Target resource group must exist prior to deployment

                Resource Management:
                - Creates resources with configurable prefix for easy identification (default: "sdp-test")
                - All VMs deployed with network isolation (no internet access) for security
                - Progress tracking shows real-time deployment status for all resource types
                - Comprehensive validation ensures all resources are properly deployed and functional
                - Zero-padded VM naming convention (01, 02, etc.) for consistent resource organization

                Testing Features:
                - Testing mode reduces VM sizes and counts for faster deployment and lower costs
                - Supports both production and testing SKU configurations
                - Automatic cleanup option to remove test resources after validation

                Validation Capabilities:
                - SKU availability checking across specified availability zones
                - Quota validation for all resource types before deployment
                - Real-time deployment status tracking and error reporting
                - Post-deployment resource validation and status reporting

            .LINK
                https://docs.microsoft.com/en-us/azure/virtual-machines/
        #>

        [CmdletBinding()]
        param
            (
                # Azure Subscription ID where test resources will be deployed
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false, HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [ValidateNotNullOrEmpty()]
                [string]
                $SubscriptionId,

                # Azure Resource Group name where test resources will be deployed
                # Resource group must already exist in the specified subscription
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false, HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceGroupName,

                # Azure region for resource deployment - must be a valid Azure region name
                # Common examples: eastus, westus2, northeurope, eastasia
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false, HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [ValidateNotNullOrEmpty()]
                [string]
                $Region,

                # Azure Availability Zone for resource placement (1, 2, 3, or Zoneless for regions without zones)
                # Use "Zoneless" for regions that do not support availability zones
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false, HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [ValidateNotNullOrEmpty()]
                [string]
                $Zone,

                # Path to JSON configuration file containing all deployment parameters
                # When specified, all parameters are loaded from file unless overridden by command line
                # Enables simplified deployment management and repeatability
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $true, HelpMessage = "Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\\configs\\silk-deployment.json")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $true, HelpMessage = "Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\\configs\\silk-deployment.json")]
                [string]
                $ConfigurationJson,

                # Friendly name for CNode SKU selection using descriptive categories
                # Increased_Logical_Capacity (Standard_E64s_v5) - Most common, high memory
                # Read_Cache_Enabled (Standard_L64s_v3) - High-speed local SSD storage
                # No_Increased_Logical_Capacity (Standard_D64s_v5) - Basic compute, rarely used
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
                [ValidateSet("Increased_Logical_Capacity", "Read_Cache_Enabled", "No_Increased_Logical_Capacity")]
                [string]
                $CNodeFriendlyName,

                # Explicit Azure VM SKU for CNode VMs when using direct SKU specification
                # Standard_E64s_v5 (default) - High memory, Standard_L64s_v3 - SSD storage, Standard_D64s_v5 - Basic compute
                # Alternative to CNodeFriendlyName for advanced scenarios requiring specific SKU control
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [ValidateSet("Standard_D64s_v5", "Standard_L64s_v3", "Standard_E64s_v5")]
                [string]
                $CNodeSku,

                # Number of CNode VMs to deploy (range: 2-8)
                # Silk Infrastructure requires minimum 2 CNodes for cluster quorum, maximum 8 for optimal management
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = "Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity.")]
                [ValidateRange(2, 8)]
                [ValidateNotNullOrEmpty()]
                [int]
                $CNodeCount,

                # Array of MNode storage capacities for Lsv3 series SKUs (older generation, proven stability)
                # Valid values: "19.5" (L8s_v3), "39.1" (L16s_v3), "78.2" (L32s_v3) TiB capacity
                # Example: @("19.5", "39.1") for mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",  Mandatory = $true, HelpMessage = "Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",    Mandatory = $true, HelpMessage = "Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                 Mandatory = $true, HelpMessage = "Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [ValidateSet("19.5", "39.1", "78.2")]
                [ValidateCount(1, 4)]
                [string[]]
                $MnodeSizeLsv3,

                # Array of MNode storage capacities for Laosv4 series SKUs (newer generation, higher density)
                # Valid values: "14.67" (L2aos_v4), "29.34" (L4aos_v4), "58.67" (L8aos_v4), "88.01" (L12aos_v4), "117.35" (L16aos_v4) TiB capacity
                # Example: @("14.67", "29.34") for cost-optimized mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = "Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = "Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true, HelpMessage = "Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity.")]
                [ValidateCount(1, 4)]
                [ValidateSet("14.67", "29.34", "58.67", "88.01", "117.35")]
                [string[]]
                $MnodeSizeLaosv4,

                # Array of explicit Azure VM SKUs for MNode/DNode VMs when using direct SKU specification
                # Lsv3 SKUs: Standard_L8s_v3, Standard_L16s_v3, Standard_L32s_v3
                # Laosv4 SKUs: Standard_L2aos_v4, Standard_L4aos_v4, Standard_L8aos_v4, Standard_L12aos_v4, Standard_L16aos_v4
                # Alternative to size-based selection for advanced scenarios requiring specific SKU control
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = "Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = "Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB).")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true, HelpMessage = "Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB).")]
                [ValidateSet("Standard_L2aos_v4", "Standard_L4aos_v4", "Standard_L8aos_v4", "Standard_L12aos_v4", "Standard_L16aos_v4", "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3")]
                [string[]]
                $MNodeSku,

                # Number of MNode instances when using explicit SKU specification (range: 1-4)
                # Determines how many DNode VMs are deployed per MNode configuration
                # Production typically uses 1 MNode per capacity requirement
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = "Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = "Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true, HelpMessage = "Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy.")]
                [ValidateRange(1, 4)]
                [ValidateNotNullOrEmpty()]
                [int]
                $MNodeCount,

                # Switch to disable automatic cleanup of test resources after deployment validation
                # When specified, resources remain in Azure for manual inspection or extended testing
                # Resources must be manually removed or cleaned up using -RunCleanupOnly parameter
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Switch]
                $DisableCleanup,

                # Switch to only perform cleanup operations, removing all previously created test resources
                # Identifies and removes resources based on resource name prefix (default: "sdp-test")
                # Use this to clean up resources from failed deployments or when cleanup was disabled
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true, HelpMessage = "Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $true, HelpMessage = "Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group")]
                [Switch]
                $RunCleanupOnly,

                # CIDR notation for VNet and subnet IP address range used for network isolation
                # Default: "10.0.0.0/24" (provides 254 usable IP addresses)
                # Overrides JSON configuration values when specified via command line
                [Parameter(HelpMessage = "Specify VNet CIDR range for network isolation. Example: 10.0.0.0/24")]
                [ValidateNotNullOrEmpty()]
                [string]
                $IPRangeCIDR,

                # Azure Marketplace image offer for VM operating system
                # Default: "0001-com-ubuntu-server-jammy" (Ubuntu 22.04 LTS)
                # Advanced parameter - modify only if specific OS requirements exist
                [Parameter(HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageOffer = "0001-com-ubuntu-server-jammy",

                # Azure Marketplace image publisher for VM operating system
                # Default: "Canonical" (official Ubuntu publisher)
                # Advanced parameter - modify only if using non-Ubuntu images
                [Parameter(HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImagePublisher = "Canonical",

                # Azure Marketplace image SKU for VM operating system
                # If not specified, automatically selects latest available SKU with Gen2 preference
                # Advanced parameter - function auto-detects best available SKU for most scenarios
                [Parameter(HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [string]
                $VMImageSku,

                # Azure Marketplace image version for VM operating system
                # Default: "latest" (automatically uses most recent image version)
                # Advanced parameter - specify only if specific image version required for compliance
                [Parameter(HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageVersion = "latest",

                # Prefix used for all created Azure resource names to enable easy identification and cleanup
                # Default: "sdp-test" (creates names like "sdp-test-cnode-01", "sdp-test-vnet")
                # Modify for multiple parallel test deployments or organizational naming standards
                [Parameter(HelpMessage = "Resource name prefix for easy identification and cleanup. Default: sdp-test. Example: my-test (creates my-test-cnode-01, my-test-vnet)")]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceNamePrefix = "sdp-test",

                # PowerShell credential object for VM local administrator account
                # Default: Username "azureuser" with secure password for testing purposes
                # Used for VM deployment - SSH key authentication not implemented in test scenarios
                [Parameter(HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [ValidateNotNullOrEmpty()]
                [pscredential]
                $VMInstanceCredential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "azureuser", (ConvertTo-SecureString 'sdpD3ploym3ntT3$t' -AsPlainText -Force)),

                # Switch to enabled Creation of a resource group by the given resource group name
                # The resource group must NOT already exist
                # When specified, a resource group is created for the test deployment and deleted
                # the -RunCleanupOnly parameter can not be used to clean up resource groups you will have to manually delete them
                [Parameter(ParameterSetName = 'ConfigurationJson',              Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Switch]
                $CreateResourceGroup,

                # Switch to enable testing mode with reduced VM sizes and instance counts
                # When enabled: Uses 2 vCPU SKUs instead of production 64 vCPU, 1 DNode per MNode instead of 16
                # Significantly reduces deployment time and costs for faster testing iterations
                [Parameter(HelpMessage = "Enable testing mode with reduced VM sizes and instance counts.")]
                [Switch]
                $Testing
            )

        # This block is used to provide optional one-time pre-processing for the function.
        begin
            {


                # ===============================================================================
                # Azure Authentication and Module Validation
                # ===============================================================================
                # Ensure that the Az module is available and the user is authenticated to Azure
                try
                    {
                        # Optional: Uncomment these lines if you want to enforce Az module installation
                        # if (-not (Get-Module -Name Az -ListAvailable))
                        #     {
                        #         Write-Error "Az module is not installed. Please install the Az module to use this function."
                        #         return
                        #     }
                        # Import-Module Az -Force

                        # Verify that the user is authenticated to Azure
                        if (-not (Get-AzContext))
                            {
                                Write-Error "You are not logged in to Azure. Please log in using Connect-AzAccount."
                                return
                            }
                    }
                catch
                    {
                        Write-Error $("An error occurred while importing the Az module or checking the Azure context: {0}" -f $_)
                        return
                    }

                # ===============================================================================
                # JSON Configuration Processing
                # ===============================================================================
                # Load deployment configuration from JSON file if specified
                # Command line parameters take precedence over JSON values
                if ($ConfigurationJson)
                    {
                        # Load and parse the JSON configuration file
                        $ConfigImport = Get-Content -Path $ConfigurationJson | ConvertFrom-Json

                        # Override JSON values with command line parameters if provided
                        # This allows selective override of JSON config while preserving other values

                        if (!$SubscriptionId)
                            {
                                $SubscriptionId = $ConfigImport.azure_environment.subscription_id
                            } `
                        else
                            {
                                Write-Warning -Message $("Subscription ID parameter is set to '{0}', ignoring subscription ID in JSON configuration." -f $SubscriptionId)
                            }

                        if (!$ResourceGroupName)
                            {
                                $ResourceGroupName = $ConfigImport.azure_environment.resource_group_name
                            } `
                        else
                            {
                                Write-Warning -Message $("Resource Group Name parameter is set to '{0}', ignoring resource group name in JSON configuration." -f $ResourceGroupName)
                            }

                        if(!$Region)
                            {
                                $Region = $ConfigImport.azure_environment.region
                            } `
                        else
                            {
                                Write-Warning -Message $("Region parameter is set to '{0}', ignoring region in JSON configuration." -f $Region)
                            }

                        if(!$Zone)
                            {
                                $Zone = $ConfigImport.azure_environment.zone
                            } `
                        else
                            {
                                Write-Warning -Message $("Zone parameter is set to '{0}', ignoring zone in JSON configuration." -f $Zone)
                            }

                        # identify cnode count
                        $CNodeCount = $ConfigImport.sdp.c_node_count
                    }


                # ===============================================================================
                # Validate provided environment information is accurate
                # ===============================================================================
                try
                    {
                        # Check subscription ID
                        $subscriptionCheck = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
                        Write-Verbose -Message $("Subscription '{0}' was identified with the ID '{1}'." -f $subscriptionCheck.Name, $subscriptionCheck.Id)

                        # check the current context
                        $currentContext = Get-AzContext
                        if ($currentContext.Subscription.Id -ne $SubscriptionId)
                            {
                                Write-Warning -Message $("Current context is set to subscription '{0}', switching to '{1}'." -f $currentContext.Subscription.Id, $SubscriptionId)

                                # Set the context to the specified subscription
                                Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
                            }

                        # if the Create Resource group switch is used
                        if($CreateResourceGroup)
                            {
                                # Create resource group if it does not exist
                                try
                                    {
                                        $CreatedResourceGroup = $false
                                        if(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)
                                            {
                                                Write-Verbose -Message $("Do not use '-CreateResourceGroup' switch. Resource group '{0}' already exists in subscription '{1}'." -f $ResourceGroupName, $subscriptionCheck.Name)
                                                return
                                            }
                                        Write-Verbose -Message $("Creating resource group '{0}' in subscription '{1}'." -f $ResourceGroupName, $subscriptionCheck.Name)
                                        New-AzResourceGroup -Name $ResourceGroupName -Location $Region -ErrorAction Stop -Confirm:$false | Out-Null
                                        $CreatedResourceGroup = $true
                                    }
                                catch
                                    {
                                        Write-Verbose -Message $("Failed to create resource group '{0}' in subscription '{1}': {2}" -f $ResourceGroupName, $subscriptionCheck.Name, $_.Exception.Message)
                                        return
                                    }
                            }

                        # Check for resource group
                        $resourceGroupCheck = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
                        Write-Verbose -Message $("Resource group '{0}' was identified in the subscription {1}." -f $resourceGroupCheck.ResourceGroupName, $subscriptionCheck.Name)

                        # Check region and get supported SKUs
                        $locationSupportedSKU = Get-AzComputeResourceSku -Location $Region -ErrorAction Stop

                        # Check zone availability
                        if ($Zone -notin $locationSupportedSKU.LocationInfo.Zones)
                            {
                                Write-Error -Message $("The specified zone '{0}' is not available in the region '{1}'." -f $Zone, $Region)
                                return
                            }
                        elseif ($Zone -eq "Zoneless" -and $locationSupportedSKU.LocationInfo.Zones.Count -ne 0)
                            {
                                Write-Error -Message $("The specified region '{0}' has availability zones {1}, but 'Zoneless' was specified." -f ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique), (($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique) -join ", "))
                                return
                            }
                        elseif ($Zone -eq "Zoneless")
                            {
                                Write-Verbose -Message $("Zoneless is a valid zone selection for the specified region '{0}'." -f ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique))
                            }
                        else
                            {
                                Write-Verbose -Message $("The specified zone '{0}' is available in the region '{1}' with zones {2}." -f $Zone, ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique), (($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique) -join ", "))
                            }
                    } `
                catch
                    {
                        Write-Error -Message "Failed to validate environment information: $_"
                        return
                    }

                # Do not run the rest of begin block if cleanup only
                if ($RunCleanupOnly)
                    {
                        return
                    }

                # ===============================================================================
                # CNode SKU Configuration Object
                # ===============================================================================
                # Maps friendly CNode names to their corresponding Azure VM SKUs
                # CNode Types:
                # - Standard_D*_v5: Basic compute, minimal memory (No_Increased_Logical_Capacity)
                # - Standard_L*_v3: High-speed local SSD storage (Read_Cache_Enabled)
                # - Standard_E*_v5: High memory, most commonly used (Increased_Logical_Capacity)

                # Production CNode SKU Configuration
                # Actual production deployments use 64 vCPU SKUs for high performance
                $cNodeSizeObject = @(
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "v5"; QuotaFamily = "Standard Dsv5 Family vCPUs"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "v3"; QuotaFamily = "Standard Lsv3 Family vCPUs"; cNodeFriendlyName = "Read_Cache_Enabled"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "v5"; QuotaFamily = "Standard Esv5 Family vCPUs"; cNodeFriendlyName = "Increased_Logical_Capacity"}
                                    )

                if ($Testing)
                    {
                        Write-Verbose -Message "Running in testing mode, using reduced CNode configuration for faster deployment."
                        $cNodeSizeObject = @(
                                                [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 2; vmSkuSuffix = "s_v5"; QuotaFamily = "Standard Dsv5 Family vCPUs"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                                                [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 2; vmSkuSuffix = "s_v3"; QuotaFamily = "Standard Lsv3 Family vCPUs"; cNodeFriendlyName = "Read_Cache_Enabled"};
                                                [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 2; vmSkuSuffix = "s_v5"; QuotaFamily = "Standard Esv5 Family vCPUs"; cNodeFriendlyName = "Increased_Logical_Capacity"}
                                            )
                    }

                # Output current CNode size object configuration
                foreach ($cNodeSize in $cNodeSizeObject)
                    {
                        Write-Verbose -Message $("CNode SKU: {0}{1}{2} with friendly name '{3}'" -f $cNodeSize.vmSkuPrefix, $cNodeSize.vCPU, $cNodeSize.vmSkuSuffix, $cNodeSize.cNodeFriendlyName)
                    }

                # ===============================================================================
                # MNode/DNode SKU Configuration Object
                # ===============================================================================
                # Maps storage capacity to Azure VM SKUs for MNode groups and their associated DNodes
                # Each MNode manages a group of DNodes providing specific storage capacity
                #
                # Lsv3 Series (NVMe SSD storage - older generation, proven stability):
                # - 19.5 TiB: Standard_L8s_v3  (8 vCPU, 64 GB RAM, local NVMe storage)
                # - 39.1 TiB: Standard_L16s_v3 (16 vCPU, 128 GB RAM, local NVMe storage)
                # - 78.2 TiB: Standard_L32s_v3 (32 vCPU, 256 GB RAM, local NVMe storage)
                #
                # Laosv4 Series (newer generation with higher density and efficiency):
                # - 14.67 TiB: Standard_L2aos_v4  (2 vCPU, latest storage technology)
                # - 29.34 TiB: Standard_L4aos_v4  (4 vCPU, latest storage technology)
                # - 58.67 TiB: Standard_L8aos_v4  (8 vCPU, latest storage technology)
                # - 88.01 TiB: Standard_L12aos_v4 (12 vCPU, latest storage technology)
                # - 117.35 TiB: Standard_L16aos_v4 (16 vCPU, latest storage technology)

                # Production MNode/DNode SKU Configuration
                # Actual production deployments use 16 DNodes per MNode for high availability
                $mNodeSizeObject = @(
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5;    QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1;    QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2;    QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35;  QuotaFamily = "Standard Laosv4 Family vCPUs"}
                                    )

                if ($Testing)
                    {
                        Write-Verbose -Message "Running in testing mode, using reduced MNode/DNode configuration for faster deployment."
                        $mNodeSizeObject = @(
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35;   QuotaFamily = "Standard Laosv4 Family vCPUs"}
                                            )
                    }

                # Output current MNode/DNode size object configuration
                foreach($mNodeSizedetail in $mNodeSizeObject)
                    {
                        Write-Verbose -Message $("MNode Physical Size {0} TiB configuration has {1} DNodes using SKU: {2}{3}{4}" -f $mNodeSizedetail.PhysicalSize, $mNodeSizedetail.dNodeCount, $mNodeSizedetail.vmSkuPrefix, $mNodeSizedetail.vCPU, $mNodeSizedetail.vmSkuSuffix)
                    }


                # ===============================================================================
                # IP Range Configuration
                # ===============================================================================
                # Set IP space for the VNet and subnet if not provided by importing from JSON
                # configuration or using generic default value
                if (!$IPRangeCIDR -and $ConfigImport -and $ConfigImport.cluster.ip_range)
                    {
                        $IPRangeCIDR = $ConfigImport.cluster.ip_range
                    }
                elseif (!$IPRangeCIDR -and !$ConfigImport.cluster.ip_range)
                    {
                        $IPRangeCIDR = "10.0.0.0/24"
                    }

                Write-Verbose -Message "Using IP range: $IPRangeCIDR for VNet and subnet configuration."


                # ===============================================================================
                # SKU Configuration Identification and Validation
                # ===============================================================================
                # Set MNode size from parameter values when not using JSON configuration
                if (!$MNodeSize -and $ConfigImport)
                    {
                        $MNodeSize = $ConfigImport.sdp.m_node_sizes
                    } `
                elseif ($MnodeSizeLsv3)
                    {
                        $MNodeSize = $MnodeSizeLsv3
                    } `
                elseif ($MnodeSizeLaosv4)
                    {
                        $MNodeSize = $MnodeSizeLaosv4
                    }

                if ($MNodeSize)
                    {
                        Write-Verbose -Message ("MNode size(s) identified: {0}" -f ($MNodeSize -join ", "))
                    }

                # Identify and validate CNode SKU configuration based on provided parameters
                if (!$CNodeCount -and !$CNodeFriendlyName -and !$CNodeSku -and $MnodeSize)
                    {
                        # MNode-only deployment scenario - no CNode configuration required
                        Write-Verbose -Message "MNode-only deployment mode - CNode configuration skipped."
                        $cNodeObject = $null
                    } `
                elseif ($CNodeCount -and ($CNodeFriendlyName -eq "Read_Cache_Enabled" -or $ConfigImport.sdp.read_cache_enabled))
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "Read_Cache_Enabled" }
                    } `
                elseif ($CNodeCount -and ($CNodeFriendlyName -eq "Increased_Logical_Capacity" -or $ConfigImport.sdp.increased_logical_capacity))
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "Increased_Logical_Capacity" }
                    } `
                elseif ($CNodeCount -and ($CNodeFriendlyName -eq "No_Increased_Logical_Capacity" -or (!$ConfigImport.sdp.increased_logical_capacity -and !$ConfigImport.sdp.read_cache_enabled)))
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "No_Increased_Logical_Capacity" }
                    } `
                elseif ($CNodeCount -and $CNodeSku)
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $CNodeSku }
                    } `
                else
                    {
                        Write-Error "Configuration is not valid. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters (MnodeSizeLsv3/MnodeSizeLaosv4/MNodeSku), or both."
                        return
                    }

                if ($cNodeObject)
                    {
                        Write-Verbose -Message ("Identified CNode SKU: {0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix)
                    }

                # Initialize MNode object list to hold configuration for each MNode type
                $mNodeObject = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

                # Identify MNode SKU details based on configuration
                if ($MNodeSize)
                    {
                        $MNodeSize | % { $nodeSize = $_; $mNodeObject.Add($($mNodeSizeObject | Where-Object { $_.PhysicalSize -eq $nodeSize })) }
                    } `
                elseif ($MNodeCount -and $MNodeSku)
                    {
                        for ($node = 1; $node -le $MNodeCount; $node++)
                            {
                                $mNodeObject.Add($($mNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $MNodeSku }))
                            }
                    } `
                elseif ($CNodeCount -and !$MnodeSizeLsv3 -and !$MnodeSizeLaosv4 -and !$MNodeSku)
                    {
                        # CNode-only deployment scenario - no MNode configuration required
                        Write-Verbose -Message "CNode-only deployment mode - no MNode resources will be created."
                    } `
                elseif (!$CNodeCount -and !$MnodeSizeLsv3 -and !$MnodeSizeLaosv4 -and !$MNodeSku)
                    {
                        Write-Error "No valid configuration specified. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters (MnodeSizeLsv3/MnodeSizeLaosv4/MNodeSku), or both."
                        return
                    }

                # Create unique MNode object list to avoid duplicates and detail MNode configurations
                if ($MNodeSize)
                    {
                        # Create unique MNode object list to avoid duplicates
                        $mNodeObjectUnique = New-Object System.Collections.Generic.List[PSCustomObject]
                        $mNodeObject | % { if(-not $mNodeObjectUnique.Contains($_)) { $mNodeObjectUnique.Add($_) } }

                        foreach ($mNodeDetail in $mNodeObject)
                            {
                                Write-Verbose -Message $("MNode Physical Size {0} TiB configuration has {1} DNodes using SKU: {2}{3}{4}" -f $mNodeDetail.PhysicalSize, $mNodeDetail.dNodeCount, $mNodeDetail.vmSkuPrefix, $mNodeDetail.vCPU, $mNodeDetail.vmSkuSuffix)
                            }
                    }


                # ===============================================================================
                # Compute SKU Location and Zone Support Validation
                # ===============================================================================
                # Verify that selected SKUs are supported in the target region and availability zone
                if ($cNodeObject)
                    {
                        $cNodeSupportedSKU = $locationSupportedSKU | Where-Object Name -eq $("{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix)
                        if (!$cNodeSupportedSKU)
                            {
                                Write-Error "Unable to identify location for CNode SKU: {0}{1}{2} in region: {3}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix, $Region
                                return
                            } `
                        elseif ($cNodeSupportedSKU -and $Zone -eq "Zoneless")
                            {
                                Write-Verbose -Message $("CNode SKU: {0} is supported in region: {1} without zones." -f $cNodeSupportedSKU.Name, $cNodeSupportedSKU.LocationInfo.Location)
                            } `
                        elseif ($cNodeSupportedSKU -and $cNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                            {
                                Write-Verbose -Message $("CNode SKU: {0} is supported in the target zone {1} in region: {2}. All supported zones: {3}" -f $cNodeSupportedSKU.Name, $Zone, $cNodeSupportedSKU.LocationInfo.Location, ($cNodeSupportedSKU.LocationInfo.Zones -join ", "))
                            } `
                        elseif ($cNodeSupportedSKU -and $cNodeSupportedSKU.LocationInfo.Zones -notcontains $Zone)
                            {
                                Write-Verbose -Message $("CNode SKU: {0} is not supported in the target zone {1} in region: {2}. It is supported in zones: {3}" -f $cNodeSupportedSKU.Name, $Zone, $cNodeSupportedSKU.LocationInfo.Location, ($cNodeSupportedSKU.LocationInfo.Zones -join ", "))
                            } `
                        else
                            {
                                Write-Warning -Message $("Unable to determine regional support for CNode SKU: {0} in region: {1}." -f $cNodeSupportedSKU.Name, $cNodeSupportedSKU.LocationInfo.Location)
                            }
                    }

                if ($MNodeSize)
                    {
                        foreach ($supportedMNodeSKU in $mNodeObjectUnique)
                            {
                                $mNodeSupportedSKU = $locationSupportedSKU | Where-Object Name -eq $("{0}{1}{2}" -f $supportedMNodeSKU.vmSkuPrefix, $supportedMNodeSKU.vCPU, $supportedMNodeSKU.vmSkuSuffix)
                                if (!$mNodeSupportedSKU)
                                    {
                                        Write-Error "Unable to identify regional support for MNode SKU: {0}{1}{2} in region: {3}" -f $supportedMNodeSKU.vmSkuPrefix, $supportedMNodeSKU.vCPU, $supportedMNodeSKU.vmSkuSuffix, $Region
                                        return
                                    } `
                                elseif ($mNodeSupportedSKU -and $Zone -eq "Zoneless")
                                    {
                                        Write-Verbose -Message $("MNode SKU: {0} is supported in region: {1} without zones." -f $mNodeSupportedSKU.Name, $mNodeSupportedSKU.LocationInfo.Location)
                                    } `
                                elseif ($mNodeSupportedSKU -and $mNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                    {
                                        Write-Verbose -Message $("MNode SKU: {0} is supported in the target zone {1} in region: {2}. All supported zones: {3}" -f $mNodeSupportedSKU.Name, $Zone, $mNodeSupportedSKU.LocationInfo.Location, ($mNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                    } `
                                elseif ($mNodeSupportedSKU -and $mNodeSupportedSKU.LocationInfo.Zones -notcontains $Zone)
                                    {
                                        Write-Verbose -Message $("MNode SKU: {0} is not supported in the target zone {1} in region: {2}. It is supported in zones: {3}" -f $mNodeSupportedSKU.Name, $Zone, $mNodeSupportedSKU.LocationInfo.Location, ($mNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                    }
                                else
                                    {
                                        Write-Warning "Unable to determine regional support for MNode SKU: {0} in region: {1}." -f $mNodeSupportedSKU.Name, $mNodeSupportedSKU.LocationInfo.Location
                                    }
                            }
                    }


                # ===============================================================================
                # quota check
                try
                    {
                        $computeQuotaUsage = Get-AzVMUsage -Location $Region -ErrorAction SilentlyContinue

                        $availabilitySetCount = 0
                        $totalVMCount = 0
                        $totalvCPUCount = 0

                        $insufficientQuota = $false

                        # Check if CNodeSize is within the available quota
                        if($cNodeObject)
                            {
                                # increment for generic quota checks
                                $availabilitySetCount += 1
                                $totalVMCount += $CNodeCount
                                $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount
                                $totalvCPUCount += $cNodevCPUCount

                                # Check if CNodeSize is within the available quota
                                $cNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }
                                if (($cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue) -lt $cNodevCPUCount)
                                    {
                                        $quotaErrorMessage = "{0} {1}" -f $("Insufficient vCPU quota available for CNode SKU: {0}{1}{2}. Required: {3} -> Limit: {4}, Consumed: {5}, Available: {6}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix, $cNodevCPUCount, $cNodeSKUFamilyQuota.Limit, $cNodeSKUFamilyQuota.CurrentValue, ($cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue)), $quotaErrorMessage
                                        Write-Warning $quotaErrorMessage
                                        $insufficientQuota = $true
                                    } `
                                else
                                    {
                                        Write-Verbose -Message $("Sufficient vCPU quota available for CNode SKU: {0}{1}{2}. Required: {3} -> Limit: {4}, Consumed: {5}, Available: {6}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix, $cNodevCPUCount, $cNodeSKUFamilyQuota.Limit, $cNodeSKUFamilyQuota.CurrentValue, ($cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue))
                                    }
                            }

                        # check for quota for mnodes
                        if($MNodeSize)
                            {

                                # increment the number of availability sets for MNodes
                                foreach($mNodeAvailablitySet in $mNodeObject)
                                    {
                                        $availabilitySetCount += 1
                                    }

                                $mNodeFamilyCount = $mNodeObject | Group-Object -Property QuotaFamily
                                $mNodeInstanceCount = $MNodeSize | Group-Object | Select-Object Name, Count

                                foreach ($mNodeFamily in $mNodeFamilyCount)
                                    {
                                        # total mnode vcpu count
                                        foreach ($mNodeType in $mNodeObjectUnique)
                                            {
                                                $totalVMCount += $mNodeType.dNodeCount * $($mNodeInstanceCount | ? Name -eq $mNodeType.PhysicalSize).Count
                                                $mNodeFamilyvCPUCount += $mNodeType.vCPU * $mNodeType.dNodeCount * $($mNodeInstanceCount | ? Name -eq $mNodeType.PhysicalSize).Count
                                                $totalvCPUCount += $mNodeFamilyvCPUCount
                                            }

                                        # Check if MNodeSize is within the available quota
                                        $mNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeFamily.Name }
                                        if (($mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue) -lt $mNodeFamilyvCPUCount)
                                            {
                                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient vCPU quota available for MNode SKU: {0} of SKU Family: {1}. Required: {2} -> Limit: {3}, Consumed: {4}, Available: {5}" -f $(($mNodeFamily.group | % { "{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix }) -join ', '), $mNodeFamily.Name, $mNodeFamilyvCPUCount, $mNodeSKUFamilyQuota.Limit, $mNodeSKUFamilyQuota.CurrentValue, ($mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue)), $quotaErrorMessage
                                                Write-Warning $quotaErrorMessage
                                                $insufficientQuota = $true
                                            } `
                                        else
                                            {
                                                Write-Verbose -Message $("Sufficient vCPU quota available for MNode SKU {0} of Family: {1}. Required: {2} -> Limit: {3}, Consumed: {4}, Available: {5}" -f $(($mNodeFamily.group | % { "{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix }) -join ', '), $mNodeFamily.Name, $mNodeFamilyvCPUCount, $mNodeSKUFamilyQuota.Limit, $mNodeSKUFamilyQuota.CurrentValue, ($mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue))
                                            }
                                    }
                            }

                        # check general quota values
                        # check vm quota
                        $totalVMQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Virtual Machines" }
                        if($totalVMCount -gt ($totalVMQuota.Limit - $totalVMQuota.CurrentValue))
                            {
                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient VM quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVMCount, $totalVMQuota.Limit, $totalVMQuota.CurrentValue, ($totalVMQuota.Limit - $totalVMQuota.CurrentValue)), $quotaErrorMessage
                                Write-Warning $quotaErrorMessage
                                $insufficientQuota = $true
                            } `
                        else
                            {
                                Write-Verbose $("Sufficient VM quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVMCount, $totalVMQuota.Limit, $totalVMQuota.CurrentValue, ($totalVMQuota.Limit - $totalVMQuota.CurrentValue))
                            }

                        # check regional vcpu quota
                        $totalVCPUQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Total Regional vCPUs" }
                        if($totalVCPUCount -gt ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue))
                            {
                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient vCPU quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVCPUCount, $totalVCPUQuota.Limit, $totalVCPUQuota.CurrentValue, ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue)), $quotaErrorMessage
                                Write-Warning $quotaErrorMessage
                                $insufficientQuota = $true
                            } `
                        else
                            {
                                Write-Verbose $("Sufficient vCPU quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVCPUCount, $totalVCPUQuota.Limit, $totalVCPUQuota.CurrentValue, ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue))
                            }

                        # check availability set quota
                        $totalAvailabilitySetQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Availability Sets" }
                        if($totalAvailabilitySetCount -gt ($totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue))
                            {
                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient Availability Set quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalAvailabilitySetCount, $totalAvailabilitySetQuota.Limit, $totalAvailabilitySetQuota.CurrentValue, ($totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue)), $quotaErrorMessage
                                Write-Warning $quotaErrorMessage
                                $insufficientQuota = $true
                            } `
                        else
                            {
                                Write-Verbose $("Sufficient Availability Set quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalAvailabilitySetCount, $totalAvailabilitySetQuota.Limit, $totalAvailabilitySetQuota.CurrentValue, ($totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue))
                            }

                        if($insufficientQuota)
                            {
                                Write-Error $quotaErrorMessage
                                return
                            }
                        else
                            {
                                Write-Verbose "All required quotas are available for the specified CNode and MNode configurations."
                            }

                    } `
                catch
                    {
                        Write-Error "Error occurred while checking compute quota: $_"
                    }


                # ===============================================================================
                # VM Image SKU Discovery and Selection
                # ===============================================================================
                # Automatically detect the best available Ubuntu image SKU for the target region
                # Prioritizes Gen2 VMs for better performance, with fallback to alternative offers
                if (-not $VMImageSku)
                    {
                        # Query Azure for available VM image SKUs in the target region
                        try
                            {
                                $availableSkus = Get-AzVMImageSku -Location $Region -PublisherName $VMImagePublisher -Offer $VMImageOffer -ErrorAction Stop

                                if ($availableSkus)
                                    {
                                        # Prioritize Gen2 SKUs for better performance and features
                                        # Gen2 VMs support UEFI, larger memory, and Intel Optane DC persistent memory
                                        $VMImageSku = $availableSkus |
                                            Sort-Object Skus -Descending |
                                            Where-Object { $_.Skus -match "gen2" } |
                                            Select-Object -First 1 -ExpandProperty Skus

                                        # Fallback to latest available SKU if no Gen2 found
                                        if (-not $VMImageSku)
                                            {
                                                $VMImageSku = $availableSkus |
                                                    Sort-Object Skus -Descending |
                                                    Select-Object -First 1 -ExpandProperty Skus
                                            }
                                    } `
                                else
                                    {
                                        Write-Warning $("No SKUs found for offer '{0}' from publisher '{1}' in region '{2}'. Trying alternative Ubuntu offers..." -f $VMImageOffer, $VMImagePublisher, $Region)

                                        # Fallback to alternative Ubuntu image offers if primary offer fails
                                        # These offers provide different Ubuntu versions and availability patterns
                                        $alternativeOffers = @("0001-com-ubuntu-server-jammy", "0001-com-ubuntu-server-noble", "UbuntuServer")
                                        foreach ($offer in $alternativeOffers)
                                            {
                                                # Skip the current offer if it's the same as already attempted
                                                if ($offer -ne $VMImageOffer)
                                                    {
                                                        try
                                                            {
                                                                $availableSkus = Get-AzVMImageSku -Location $Region -PublisherName $VMImagePublisher -Offer $offer -ErrorAction Stop
                                                                if ($availableSkus)
                                                                    {
                                                                        $VMImageOffer = $offer
                                                                        # Apply same Gen2 preference to alternative offers
                                                                        $VMImageSku = $availableSkus |
                                                                            Sort-Object Skus -Descending |
                                                                            Where-Object { $_.Skus -match "gen2" } |
                                                                            Select-Object -First 1 -ExpandProperty Skus

                                                                        if (-not $VMImageSku)
                                                                            {
                                                                                $VMImageSku = $availableSkus |
                                                                                    Sort-Object Skus -Descending |
                                                                                    Select-Object -First 1 -ExpandProperty Skus
                                                                            }
                                                                        Write-Host $("Using alternative offer: {0} with SKU: {1}" -f $offer, $VMImageSku)
                                                                        break
                                                                    }
                                                            } `
                                                        catch
                                                            {
                                                                # Continue to next alternative offer if this one fails
                                                                continue
                                                            }
                                                    }
                                            }
                                    }
                            } `
                        catch
                            {
                                Write-Warning $("Failed to get VM image SKUs: {0}. Trying Ubuntu image alias as fallback..." -f $_.Exception.Message)
                                # Fallback: Use Ubuntu image alias which should work in most regions
                                $VMImagePublisher = "Canonical"
                                $VMImageOffer = "Ubuntu2204"  # This is an image alias that should work
                                $VMImageSku = "latest"
                                $VMImageVersion = "latest"
                            }
                    }
                # Get the specified image version
                if ($VMImageOffer -eq "Ubuntu2204" -or $VMImageOffer -eq "Ubuntu2404" -or $VMImageOffer -eq "UbuntuLTS")
                    {
                        # For image aliases, we don't need to call Get-AzVMImage
                        $vMImage = [PSCustomObject]@{
                                                        PublisherName = $VMImagePublisher
                                                        Offer = $VMImageOffer
                                                        Skus = $VMImageSku
                                                        Version = $VMImageVersion
                                                    }
                    } `
                else
                    {
                        $vMImage = Get-AzVMImage -Location $Region -PublisherName $VMImagePublisher -Offer $VMImageOffer -Skus $VMImageSku -Version $VMImageVersion
                    }

                # if !$VMImage
                if (-not $vMImage)
                    {
                        Write-Error $("The specified VM image '{0}' from publisher '{1}' with SKU '{2}' and version '{3}' is not available in the region '{4}'." -f $VMImageOffer, $VMImagePublisher, $VMImageSku, $VMImageVersion, $Region)
                        return
                    }


                # ===============================================================================
                # Deployment Configuration Summary
                # ===============================================================================
                Write-Verbose -Message "=== Silk Azure Deployment Configuration ==="
                Write-Verbose -Message $("Subscription ID: {0}" -f $SubscriptionId)
                Write-Verbose -Message $("Resource Group: {0}" -f $ResourceGroupName)
                Write-Verbose -Message $("Deployment Region: {0}" -f $Region)
                Write-Verbose -Message $("Availability Zone: {0}" -f $Zone)
                Write-Verbose -Message $("Resource Name Prefix: {0}" -f $ResourceNamePrefix)
                Write-Verbose -Message $("Network CIDR Range: {0}" -f $IPRangeCIDR)
                Write-Verbose -Message $("VM Image: {0}" -f $VMImageOffer)

                if ($CNodeCount -gt 0)
                    {
                        Write-Verbose -Message $("CNode Count: {0}" -f $CNodeCount)
                    } `
                else
                    {
                        Write-Verbose -Message "CNode Count: 0 (MNode-only deployment)"
                    }

                if ($mNodeObject -and $mNodeObject.Count -gt 0)
                    {
                        $mNodeSizeDisplay = ($mNodeObject | ForEach-Object { $_.PhysicalSize }) -join ", "
                        Write-Verbose -Message $("MNode Configuration: {0} TiB" -f $mNodeSizeDisplay)
                    }

                # identify total dnodes
                if($mNodeSize)
                    {
                        $totalDNodes = ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum
                    }
                else
                    {
                        $totalDNodes = 0
                    }

                if ($CNodeCount -gt 0 -and $totalDNodes -gt 0)
                    {
                        $totalVMs = $CNodeCount + $totalDNodes
                        Write-Verbose -Message $("Total VMs to Deploy: {0} ({1} CNodes + {2} DNodes)" -f $totalVMs, $CNodeCount, $totalDNodes)
                    } `
                elseif ($CNodeCount -gt 0 -and $totalDNodes -eq 0)
                    {
                        $totalVMs = $CNodeCount
                        Write-Verbose -Message $("Total VMs to Deploy: {0} (CNode-only: {1})" -f $totalVMs, $CNodeCount)
                    } `
                else
                    {
                        $totalVMs = $totalDNodes
                        Write-Verbose -Message $("Total VMs to Deploy: {0} (MNode-only: {1} DNodes)" -f $totalVMs, $totalDNodes)
                    }

                if ($Testing) {
                    Write-Verbose -Message "Testing Mode: ENABLED (reduced VM sizes for faster deployment)"
                } else {
                    Write-Verbose -Message "Testing Mode: DISABLED (production VM sizes)"
                }
                Write-Verbose -Message "=========================================="
            }

        # This block is used to provide record-by-record processing for the function.
        process
            {
                # if run cleanup only, skip the process code
                if($RunCleanupOnly)
                    {
                        # If we're only running cleanup, we can skip the rest of the process code
                        return
                    }


                # ===============================================================================
                # Virtual Network Infrastructure Creation
                # ===============================================================================
                # Creates a completely isolated network environment for testing VM deployments
                # This ensures no accidental internet access and validates Azure resource availability
                try
                    {
                        # -----------------------------------------------------------------------
                        # Network Security Group (NSG) Configuration
                        # -----------------------------------------------------------------------
                        # Create restrictive security rules for complete network isolation
                        # These rules deny ALL traffic to ensure test VMs have no network access

                        # Deny all outbound traffic (blocks internet access and inter-VM communication)
                        $nSGDenyAllOutboundRule = New-AzNetworkSecurityRuleConfig `
                                                    -Name "DenyAllOutbound" `
                                                    -Description "Deny All Outbound Traffic" `
                                                    -Access Deny `
                                                    -Protocol * `
                                                    -Direction Outbound `
                                                    -Priority 100 `
                                                    -SourceAddressPrefix * `
                                                    -SourcePortRange * `
                                                    -DestinationAddressPrefix * `
                                                    -DestinationPortRange *

                        # Deny all inbound traffic (blocks external access to VMs)
                        $nSGDenyAllInboundRule = New-AzNetworkSecurityRuleConfig `
                                                    -Name "DenyAllInbound" `
                                                    -Description "Deny All Inbound Traffic" `
                                                    -Access Deny `
                                                    -Protocol * `
                                                    -Direction Inbound `
                                                    -Priority 100 `
                                                    -SourceAddressPrefix * `
                                                    -SourcePortRange * `
                                                    -DestinationAddressPrefix * `
                                                    -DestinationPortRange *

                        # Create the Network Security Group with restrictive rules
                        $nSG = New-AzNetworkSecurityGroup `
                                -ResourceGroupName $ResourceGroupName `
                                -Location $Region `
                                -Name $("{0}-nsg" -f $ResourceNamePrefix) `
                                -SecurityRules $nSGDenyAllOutboundRule, $nSGDenyAllInboundRule

                        Write-Verbose -Message $("✓ Network Security Group '{0}' created with isolation rules:" -f $nSG.Name)

                        # -----------------------------------------------------------------------
                        # Security Rule Validation and Verbose Output
                        # -----------------------------------------------------------------------
                        # Display detailed security rule information for transparency and validation
                        $verboseInboundRule = $nSG.SecurityRules | Where-Object Direction -eq 'Inbound'
                        $verboseOutboundRule = $nSG.SecurityRules | Where-Object Direction -eq 'Outbound'

                        Write-Verbose -Message $("  - Inbound Rule: '{0}' - {1} traffic from source '{2}' ports '{3}' to destination '{4}' ports '{5}' protocol '{6}' [Priority: {7}]" -f $verboseInboundRule.Name, $verboseInboundRule.Access, ($verboseInboundRule.SourceAddressPrefix -join ','), ($verboseInboundRule.SourcePortRange -join ','), ($verboseInboundRule.DestinationAddressPrefix -join ','), ($verboseInboundRule.DestinationPortRange -join ','), $verboseInboundRule.Protocol, $verboseInboundRule.Priority)
                        Write-Verbose -Message $("  - Outbound Rule: '{0}' - {1} traffic from source '{2}' ports '{3}' to destination '{4}' ports '{5}' protocol '{6}' [Priority: {7}]" -f $verboseOutboundRule.Name, $verboseOutboundRule.Access, ($verboseOutboundRule.SourceAddressPrefix -join ','), ($verboseOutboundRule.SourcePortRange -join ','), ($verboseOutboundRule.DestinationAddressPrefix -join ','), ($verboseOutboundRule.DestinationPortRange -join ','), $verboseOutboundRule.Protocol, $verboseOutboundRule.Priority)

                        Write-Verbose -Message "  - Security Impact: Complete network isolation - NO traffic allowed in any direction"

                        # -----------------------------------------------------------------------
                        # Subnet Configuration
                        # -----------------------------------------------------------------------
                        # Create management subnet with the restrictive NSG applied
                        # This subnet will contain all test VMs with no network connectivity
                        $mGMTSubnet = New-AzVirtualNetworkSubnetConfig `
                                        -Name $("{0}-mgmt-subnet" -f $ResourceNamePrefix) `
                                        -AddressPrefix $IPRangeCIDR `
                                        -NetworkSecurityGroup $nSG

                        Write-Verbose -Message $("✓ Management subnet '{0}' configured with address range {1}" -f $mGMTSubnet.Name, ($mGMTSubnet.AddressPrefix -join ','))

                        $vNET = New-AzVirtualNetwork `
                                    -ResourceGroupName $ResourceGroupName `
                                    -Location $Region `
                                    -Name $("{0}-vnet" -f $ResourceNamePrefix) `
                                    -AddressPrefix $IPRangeCIDR `
                                    -Subnet $mGMTSubnet #, $storageSubnet

                        Write-Verbose -Message $("✓ Virtual Network '{0}' created with address space {1}" -f $vNET.Name, $IPRangeCIDR)
                        Write-Verbose -Message "✓ Network isolation configured: All VMs will be deployed with NO network access"

                        $mGMTSubnetID = $vNET.Subnets | Where-Object { $_.Name -eq $mGMTSubnet.Name } | Select-Object -ExpandProperty Id

                        # create proximity placement group to add created availablity sets to
                        # Collect all VM SKUs that will be deployed for PPG intent
                        $vmSizes = @()

                        # Add CNode SKU if cnodes will be deployed
                        if ($cNodeObject)
                            {
                                $cNodeVMSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix
                                $vmSizes += $cNodeVMSku
                            }

                        # Add MNode SKUs if MNodes will be deployed
                        if($mNodeSize)
                            {
                                foreach ($mNode in $mNodeObject)
                                    {
                                        $mNodeVMSku = "{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix
                                        if ($vmSizes -notcontains $mNodeVMSku)
                                            {
                                                $vmSizes += $mNodeVMSku
                                            }
                                    }
                            }

                        # create proximity placement group including VMsizes if Zoneless
                        if($Zone -ne "Zoneless")
                            {
                                Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' with zone '{1}' and VM sizes: {2}" -f $Region, $Zone, ($vmSizes -join ", "))
                                $proximityPlacementGroup = New-AzProximityPlacementGroup `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Location $Region `
                                                            -Zone $Zone `
                                                            -Name $("{0}-ppg" -f $ResourceNamePrefix) `
                                                            -ProximityPlacementGroupType "Standard" `
                                                            -IntentVMSize $vmSizes
                            } `
                        else
                            {
                                Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' without zones" -f $Region)
                                $proximityPlacementGroup = New-AzProximityPlacementGroup `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Location $Region `
                                                            -Name $("{0}-ppg" -f $ResourceNamePrefix) `
                                                            -ProximityPlacementGroupType "Standard"
                            }

                        Write-Verbose -Message $("✓ Proximity Placement Group '{0}' created" -f $proximityPlacementGroup.Name)

                    }
                catch
                    {
                        Write-Error $("An error occurred while creating shared resource group infrastructure: {0}" -f $_)
                        return
                    }

                # create vm instances
                try
                    {
                        # Clean up any old jobs before starting deployment to better track jobs related to the active run
                        Write-Verbose -Message "Cleaning up any existing background jobs..."
                        Get-Job | Remove-Job -Force
                        Write-Verbose -Message "All existing jobs have been removed."


                        # Calculate total VMs for progress tracking
                        $totalDNodes = ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum
                        if ($CNodeCount -gt 0)
                            {
                                $totalVMs = $CNodeCount + $totalDNodes
                            } `
                        else
                            {
                                $totalVMs = $totalDNodes
                            }

                        # Start main VM creation progress
                        Write-Progress `
                            -Status "Initializing VM Deployment" `
                            -CurrentOperation "Starting VM deployment process..." `
                            -PercentComplete 0 `
                            -Activity "VM Deployment" `
                            -Id 1

                        if($CNodeCount)
                            {
                                # Update progress for availability set creation
                                Write-Progress `
                                    -Status "Creating CNode Infrastructure" `
                                    -CurrentOperation "Creating CNode availability set..." `
                                    -PercentComplete 2 `
                                    -Activity "VM Deployment" `
                                    -Id 1

                                # create an availability set for the c-node group
                                $cNodeAvailabilitySet = New-AzAvailabilitySet `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Name $("{0}-cnode-avset" -f $ResourceNamePrefix) `
                                                            -Location $Region `
                                                            -ProximityPlacementGroupId $proximityPlacementGroup.Id `
                                                            -Sku "Aligned" `
                                                            -PlatformFaultDomainCount 3 `
                                                            -PlatformUpdateDomainCount 20

                                Write-Verbose -Message $("✓ CNode availability set '{0}' created." -f $cNodeAvailabilitySet.Name)
                            }

                        # CNode creation phase with updated progress
                        Write-Progress `
                            -Status "Creating CNodes" `
                            -CurrentOperation $("Preparing to create {0} CNode VMs..." -f $CNodeCount) `
                            -PercentComplete 5 `
                            -Activity "VM Deployment" `
                            -Id 1

                        for ($cNode = 1; $cNode -le $CNodeCount; $cNode++)
                            {
                                # Calculate CNode SKU for display
                                $currentCNodeSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix

                                # Update sub-progress for CNode creation
                                Write-Progress `
                                    -Status $("Creating CNode {0} of {1} ({2})" -f $cNode, $CNodeCount, $currentCNodeSku) `
                                    -CurrentOperation $("Configuring CNode {0} with SKU {1}..." -f $cNode, $currentCNodeSku) `
                                    -PercentComplete $(($cNode / $CNodeCount) * 100) `
                                    -Activity "CNode Creation" `
                                    -ParentId 1 `
                                    -Id 2

                                # create the cnode management NIC
                                $cNodeMGMTNIC = New-AzNetworkInterface `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -Location $Region `
                                                    -Name $("{0}-cnode-mgmt-nic-{1:D2}" -f $ResourceNamePrefix, $cNode) `
                                                    -SubnetId $mGMTSubnetID

                                Write-Verbose -Message $("✓ CNode {0} management NIC '{1}' successfully created with IP '{2}'" -f $cNode, $cNodeMGMTNIC.Name, $cNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)

                                # create the cnode vm configuration
                                # Use availability sets when not using zones
                                $cNodeConfig = New-AzVMConfig `
                                                -VMName $("{0}-cnode-{1:D2}" -f $ResourceNamePrefix, $cNode) `
                                                -VMSize $("{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix) `
                                                -AvailabilitySetId $cNodeAvailabilitySet.Id

                                # set operating system details
                                $cNodeConfig = Set-AzVMOperatingSystem `
                                                -VM $cNodeConfig `
                                                -Linux `
                                                -ComputerName $("{0}-cnode-{1:D2}" -f $ResourceNamePrefix, $cNode) `
                                                -Credential $VMInstanceCredential `
                                                -DisablePasswordAuthentication:$false

                                # set the cnode vm image
                                if ($VMImageOffer -eq "Ubuntu2204" -or $VMImageOffer -eq "Ubuntu2404" -or $VMImageOffer -eq "UbuntuLTS")
                                    {
                                        # Use image alias for Ubuntu
                                        $cNodeConfig = Set-AzVMSourceImage `
                                                        -VM $cNodeConfig `
                                                        -Image $VMImageOffer
                                    } `
                                else
                                    {
                                        # Use traditional publisher/offer/sku/version
                                        $cNodeConfig = Set-AzVMSourceImage `
                                                        -VM $cNodeConfig `
                                                        -PublisherName $vMImage.PublisherName `
                                                        -Offer $vMImage.Offer `
                                                        -Skus $vMImage.Skus `
                                                        -Version $vMImage.Version
                                    }

                                # set the cnode vm os disk
                                $cNodeConfig = Set-AzVMOSDisk `
                                                -VM $cNodeConfig `
                                                -CreateOption FromImage `
                                                -DeleteOption "Delete"

                                # set the cnode vm diagnostics
                                $cNodeConfig = Set-AzVMBootDiagnostic `
                                                -VM $cNodeConfig `
                                                -Disable:$true

                                # Add the management NIC to the cnode vm configuration
                                $cNodeConfig = Add-AzVMNetworkInterface `
                                                -VM $cNodeConfig `
                                                -Id $cNodeMGMTNIC.Id `
                                                -Primary:$true `
                                                -DeleteOption "Delete"

                                try
                                    {
                                        $cNodeJob = New-AzVM `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -VM $cNodeConfig `
                                                        -AsJob

                                        Write-Verbose -Message $("✓ CNode {0} VM creation job started successfully" -f $cNode)
                                    } `
                                catch
                                    {
                                        Write-Error $("✗ Failed to start CNode {0} VM creation: {1}" -f $cNode, $_.Exception.Message)
                                    }
                            }

                        if ($cNodeAvailabilitySet)
                            {
                                # get the cnode availability set to assess its state
                                $cNodeAvailabilitySetComplete = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $("{0}-cNode-avset" -f $ResourceNamePrefix)
                                Write-Verbose -Message $("✓ CNode availability set '{0}' created with {1} CNodes." -f $cNodeAvailabilitySetComplete.Name, $cNodeAvailabilitySetComplete)
                                Write-Verbose -Message $("✓ CNode availability set '{0}' is assigned to proximity placement group '{1}'." -f $cNodeAvailabilitySetComplete.Name, $proximityPlacementGroup.Name)
                           }

                        # Clean up CNode creation sub-progress bar as this phase is complete
                        Write-Progress -Activity "CNode Creation" -Id 2 -Completed

                        $dNodeStartCount = 0
                        $currentMNode = 0
                        foreach ($mNode in $mNodeObject)
                            {
                                $currentMNode++

                                # Calculate MNode SKU and physical size for display
                                $currentMNodeSku = "{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix
                                $currentMNodePhysicalSize = $mNode.PhysicalSize

                                # create availability set for current mNode
                                $mNodeAvailabilitySet = New-AzAvailabilitySet `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Location $Region `
                                                            -Name $("{0}-mNode-{1}-avset" -f $ResourceNamePrefix, $currentMNode) `
                                                            -Sku "Aligned" `
                                                            -PlatformFaultDomainCount 3 `
                                                            -PlatformUpdateDomainCount 20

                                Write-Verbose -Message $("✓ Availability Set '{0}' created" -f $mNodeAvailabilitySet.Name)

                                # Update main progress for MNode group
                                $processedCNodes = $CNodeCount
                                $processedDNodes = $dNodeStartCount
                                $totalProcessed = $processedCNodes + $processedDNodes
                                $mainPercentComplete = [Math]::Min([Math]::Round(($totalProcessed / $totalVMs) * 100), 90)

                                Write-Progress `
                                    -Status $("Processing MNode Group {0} of {1} - {2} TiB ({3})" -f $currentMNode, $mNodeObject.Count, $currentMNodePhysicalSize, $currentMNodeSku) `
                                    -CurrentOperation $("Creating {0} DNodes for {1} TiB MNode..." -f $mNode.dNodeCount, $currentMNodePhysicalSize) `
                                    -PercentComplete $mainPercentComplete `
                                    -Activity "VM Deployment" `
                                    -Id 1

                                for ($dNode = 1; $dNode -le $mNode.dNodeCount; $dNode++)
                                    {
                                        # Update sub-progress for DNode creation
                                        Write-Progress `
                                            -Status $("Creating DNode {0} of {1} - {2} TiB ({3})" -f $dNode, $mNode.dNodeCount, $currentMNodePhysicalSize, $currentMNodeSku) `
                                            -CurrentOperation $("Configuring DNode {0} with SKU {1}..." -f ($dNode + $dNodeStartCount), $currentMNodeSku) `
                                            -PercentComplete $(($dNode / $mNode.dNodeCount) * 100) `
                                            -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) `
                                            -ParentId 1 `
                                            -Id 3

                                        # set dnode number to use for naming
                                        $dNodeNumber = $dNode + $dNodeStartCount

                                        # create the dnode management
                                        $dNodeMGMTNIC = New-AzNetworkInterface `
                                                            -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -Name $("{0}-dnode-{1:D2}-mgmt-nic" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -SubnetId $mGMTSubnetID

                                        Write-Verbose -Message $("✓ DNode {0} management NIC '{1}' successfully created with IP '{2}'" -f $dNodeNumber, $dNodeMGMTNIC.Name, $dNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)

                                        # create the dnode vm configuration
                                        $dNodeConfig = New-AzVMConfig `
                                                        -VMName $("{0}-dnode-{1:D2}" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -VMSize $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix) `
                                                        -AvailabilitySetId $mNodeAvailabilitySet.Id

                                        # set operating system details
                                        $dNodeConfig = Set-AzVMOperatingSystem `
                                                        -VM $dNodeConfig `
                                                        -Linux `
                                                        -ComputerName $("{0}-dnode-{1:D2}" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -Credential $VMInstanceCredential `
                                                        -DisablePasswordAuthentication:$false

                                        # set the dnode vm image
                                        if ($VMImageOffer -eq "Ubuntu2204" -or $VMImageOffer -eq "Ubuntu2404" -or $VMImageOffer -eq "UbuntuLTS")
                                            {
                                                # Use image alias for Ubuntu
                                                $dNodeConfig = Set-AzVMSourceImage `
                                                                -VM $dNodeConfig `
                                                                -Image $VMImageOffer
                                            } `
                                        else
                                            {
                                                # Use traditional publisher/offer/sku/version
                                                $dNodeConfig = Set-AzVMSourceImage `
                                                                -VM $dNodeConfig `
                                                                -PublisherName $vMImage.PublisherName `
                                                                -Offer $vMImage.Offer `
                                                                -Skus $vMImage.Skus `
                                                                -Version $vMImage.Version
                                            }

                                        # set the dnode vm os disk
                                        $dNodeConfig = Set-AzVMOSDisk `
                                                        -VM $dNodeConfig `
                                                        -CreateOption FromImage `
                                                        -DeleteOption "Delete"

                                        # set the dnode vm diagnostics
                                        $dNodeConfig = Set-AzVMBootDiagnostic `
                                                        -VM $dNodeConfig `
                                                        -Disable:$true

                                        # Add the management NIC to the dnode vm configuration
                                        $dNodeConfig = Add-AzVMNetworkInterface `
                                                        -VM $dNodeConfig `
                                                        -Id $dNodeMGMTNIC.Id `
                                                        -Primary:$true `
                                                        -DeleteOption "Delete"

                                        # Update sub-progress for VM creation
                                        Write-Progress `
                                            -Status $("Creating DNode {0} VM ({1})..." -f $dNode, $currentMNodeSku) `
                                            -CurrentOperation $("Starting VM creation job for DNode {0} with SKU {1}..." -f $dNodeNumber, $currentMNodeSku) `
                                            -PercentComplete $(($dNode / $mNode.dNodeCount) * 100) `
                                            -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) `
                                            -ParentId 1 `
                                            -Id 3

                                        try
                                            {
                                                $dNodeJob = New-AzVM `
                                                                -ResourceGroupName $ResourceGroupName `
                                                                -Location $Region `
                                                                -VM $dNodeConfig `
                                                                -AsJob

                                                Write-Verbose -Message $("✓ DNode {0} VM creation job started successfully" -f $dNodeNumber)
                                            } `
                                        catch
                                            {
                                                Write-Error $("✗ Failed to start DNode {0} VM creation: {1}" -f $dNodeNumber, $_.Exception.Message)
                                            }
                                    }

                                # Clean up this MNode group's sub-progress bar as it's complete
                                Write-Progress -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) -Id 3 -Completed

                                $dNodeStartCount += $mNode.dNodeCount
                            }


                        # Validate all network interfaces were created successfully
                        Write-Verbose -Message $("✓ All network interfaces created successfully: {0} total NICs" -f (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }).Count)

                        # Wait for all VMs to be created - Final phase of VM deployment
                        $allVMJobs = Get-Job

                        # Update main progress to show completion phase and immediately show monitoring sub-progress
                        Write-Progress `
                            -Status "VM Creation Jobs Submitted - Monitoring Deployment" `
                            -CurrentOperation "Waiting for all VMs to be deployed..." `
                            -PercentComplete 95 `
                            -Activity "VM Deployment" `
                            -Id 1

                        # Immediately start VM deployment monitoring sub-progress
                        Write-Progress `
                            -Status "Monitoring VM Deployment" `
                            -CurrentOperation $("Waiting for {0} VMs to deploy..." -f $allVMJobs.Count) `
                            -PercentComplete 0 `
                            -Activity "VM Deployment Monitoring" `
                            -ParentId 1 `
                            -Id 4

                        # Initial status check to show immediate progress
                        $currentVMJobs = Get-Job
                        $completedJobs = $currentVMJobs | Where-Object { $_.State -ne 'Running' }
                        $runningJobs = $currentVMJobs | Where-Object { $_.State -eq 'Running' }
                        $initialCompletionPercent = [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100)

                        # Update sub-progress immediately with current status
                        Write-Progress `
                            -Status $("VM Deployment: {0}%" -f $initialCompletionPercent) `
                            -CurrentOperation $("Monitoring {0} running VMs..." -f $runningJobs.Count) `
                            -PercentComplete $initialCompletionPercent `
                            -Activity "VM Deployment Monitoring" `
                            -ParentId 1 `
                            -Id 4

                        do
                            {
                                # Regular monitoring interval
                                Start-Sleep -Seconds 3
                                $currentVMJobs = Get-Job
                                $completedJobs = $currentVMJobs | Where-Object { $_.State -ne 'Running' }
                                $runningJobs = $currentVMJobs | Where-Object { $_.State -eq 'Running' }
                                $failedJobs = $currentVMJobs | Where-Object { $_.State -eq 'Failed' }
                                $completionPercent = [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100)

                                # Check for failed jobs and display their errors
                                if ($failedJobs.Count -gt 0)
                                    {
                                        foreach ($failedJob in $failedJobs)
                                            {
                                                $jobError = Receive-Job -Job $failedJob 2>&1 | Out-String
                                                Write-Error $("VM Creation Job Failed: {0} - Error: {1}" -f $failedJob.Name, $jobError)
                                            }
                                    }

                                # Update sub-progress for VM deployment
                                Write-Progress `
                                    -Status $("VM Deployment: {0}%" -f $completionPercent) `
                                    -CurrentOperation $("Waiting for {0} remaining VMs to deploy..." -f $runningJobs.Count) `
                                    -PercentComplete $completionPercent `
                                    -Activity "VM Deployment Monitoring" `
                                    -ParentId 1 `
                                    -Id 4
                            } `
                        while
                            (
                                $currentVMJobs.State -contains 'Running'
                            )

                        # Final progress updates
                        Write-Progress `
                            -Status "VM Deployment Complete" `
                            -CurrentOperation "All VMs have been successfully deployed" `
                            -PercentComplete 100 `
                            -Activity "VM Deployment Monitoring" `
                            -ParentId 1 `
                            -Id 4

                        Write-Progress `
                            -Status "VM Deployment Complete" `
                            -CurrentOperation "All VMs have been deployed successfully" `
                            -PercentComplete 100 `
                            -Activity "VM Deployment" `
                            -Id 1

                        Start-Sleep -Seconds 2

                        # Complete sub-progress bars
                        Write-Progress `
                            -Activity "VM Deployment Monitoring" `
                            -Id 4 `
                            -Completed

                    }
                catch
                    {
                        Write-Warning -Message $("Error occurred while creating VMs: {0}" -f $_)
                    }

                # clean up jobs
                Get-Job | Remove-Job -Force | Out-Null

                # Comprehensive resource validation and reporting
                Write-Host "`n=== Post-Deployment Validation ===" -ForegroundColor Cyan

                # Get all deployed resources for validation
                $deployedVMs = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                $deployedNICs = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                $deployedVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                $deployedNSG = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                # Create deployment report
                $deploymentReport = @()

                # Build CNode deployment report
                for ($cNode = 1; $cNode -le $CNodeCount; $cNode++)
                    {
                        $expectedVMName = "$ResourceNamePrefix-cnode-{0:D2}" -f $cNode
                        $expectedNICName = "$ResourceNamePrefix-cnode-mgmt-nic-{0:D2}" -f $cNode

                        $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                        $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                        # Calculate CNode SKU for reporting
                        $reportCNodeSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix

                        # Determine availability set status
                        $cNodeAvSetName = "$ResourceNamePrefix-cnode-avset"
                        $avSetStatus = if ($vm -and $vm.AvailabilitySetReference) { "CNode AvSet" } else { "Not Assigned" }

                        $deploymentReport +=  [PSCustomObject]@{
                                                                    ResourceType = "CNode"
                                                                    GroupNumber = "CNode Group"
                                                                    NodeNumber = $cNode
                                                                    VMName = $expectedVMName
                                                                    ExpectedSKU = $reportCNodeSku
                                                                    DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                                                                    VMStatus = if ($vm) { "✓ Deployed" } else { "✗ Failed" }
                                                                    NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                    AvailabilitySet = $avSetStatus
                                                                }
                    }

                # Build DNode deployment report
                $dNodeStartCount = 0
                $currentMNode = 0
                foreach ($mNode in $mNodeObject)
                    {
                        $currentMNode++
                        $currentMNodePhysicalSize = $mNode.PhysicalSize
                        $reportMNodeSku = "{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix

                        for ($dNode = 1; $dNode -le $mNode.dNodeCount; $dNode++)
                            {
                                $dNodeNumber = $dNode + $dNodeStartCount
                                $expectedVMName = "$ResourceNamePrefix-dnode-{0:D2}" -f $dNodeNumber
                                $expectedNICName = "$ResourceNamePrefix-dnode-{0:D2}-mgmt-nic" -f $dNodeNumber

                                $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                                $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                                # Determine availability set status for DNode
                                $mNodeAvSetName = "$ResourceNamePrefix-mNode-$currentMNode-avset"
                                $avSetStatus = if ($vm -and $vm.AvailabilitySetReference) { "MNode $currentMNode AvSet" } else { "Not Assigned" }

                                $deploymentReport +=   [PSCustomObject]@{
                                                                            ResourceType = "DNode"
                                                                            GroupNumber = $("MNode {0} ({1} TiB)" -f $currentMNode, $currentMNodePhysicalSize)
                                                                            NodeNumber = $dNodeNumber
                                                                            VMName = $expectedVMName
                                                                            ExpectedSKU = $reportMNodeSku
                                                                            DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                                                                            VMStatus = if ($vm) { "✓ Deployed" } else { "✗ Failed" }
                                                                            NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                            AvailabilitySet = $avSetStatus
                                                                        }
                            }

                        $dNodeStartCount += $mNode.dNodeCount
                    }

                # ===============================================================================
                # SKU Support and Quota Availability Report
                # ===============================================================================
                Write-Host "`n=== SKU Support and Quota Availability Report ===" -ForegroundColor Cyan

                # CNode SKU Support Report
                if($cNodeObject)
                    {
                        $cNodeSkuName = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix
                        $cNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $cNodeSkuName }

                        Write-Host "`nCNode SKU Support:" -ForegroundColor Yellow
                        Write-Host $("  SKU: {0}" -f $cNodeSkuName)
                        Write-Host $("  Region: {0}" -f $Region)
                        if ($cNodeSupportedSKU)
                            {
                                if ($Zone -eq "Zoneless")
                                    {
                                        Write-Host "  Zone Support: ✓ Supported (Zoneless deployment)" -ForegroundColor Green
                                    }
                                elseif ($cNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                    {
                                        Write-Host $("  Zone Support: ✓ Supported in target zone {0}" -f $Zone) -ForegroundColor Green
                                        Write-Host $("  All Available Zones: {0}" -f ($cNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                    }
                                elseif ($cNodeSupportedSKU.LocationInfo.Zones -notcontains $Zone)
                                    {
                                        Write-Host $("  Zone Support: ⚠ Not supported in target zone {0}" -f $Zone) -ForegroundColor Yellow
                                        Write-Host $("  Available Zones: {0}" -f ($cNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                    }
                                else
                                    {
                                        Write-Host "  Zone Support: ⚠ Unable to determine" -ForegroundColor Yellow
                                    }
                            }
                        else
                            {
                                Write-Host "  Region Support: ✗ Not supported in region" -ForegroundColor Red
                            }

                        # CNode Quota Information
                        if ($computeQuotaUsage)
                            {
                                $cNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }
                                $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount
                                Write-Host $("  Quota Family: {0}" -f $cNodeObject.QuotaFamily)
                                if ($cNodeSKUFamilyQuota)
                                    {
                                        $availableQuota = $cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue
                                        if ($availableQuota -ge $cNodevCPUCount)
                                            {
                                                Write-Host $("  vCPU Quota: ✓ Sufficient (Required: {0}, Available: {1}/{2})" -f $cNodevCPUCount, $availableQuota, $cNodeSKUFamilyQuota.Limit) -ForegroundColor Green
                                            }
                                        else
                                            {
                                                Write-Host $("  vCPU Quota: ✗ Insufficient (Required: {0}, Available: {1}/{2})" -f $cNodevCPUCount, $availableQuota, $cNodeSKUFamilyQuota.Limit) -ForegroundColor Red
                                            }
                                    }
                                else
                                    {
                                        Write-Host "  vCPU Quota: ⚠ Unable to determine" -ForegroundColor Yellow
                                    }
                            }
                    }

                # MNode SKU Support Report
                if($MNodeSize -and $mNodeObjectUnique)
                    {
                        foreach ($mNodeType in $mNodeObjectUnique)
                            {
                                $mNodeSkuName = "{0}{1}{2}" -f $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix
                                $mNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $mNodeSkuName }

                                Write-Host $("`n{0} x MNode SKU Support ({1} TiB):" -f $(($mNodeInstanceCount | Where-Object { $_.Name -eq $mNodeType.PhysicalSize }).Count), $mNodeType.PhysicalSize) -ForegroundColor Yellow
                                Write-Host $("  SKU: {0}" -f $mNodeSkuName)
                                Write-Host $("  Region: {0}" -f $Region)
                                if ($mNodeSupportedSKU)
                                    {
                                        if ($Zone -eq "Zoneless")
                                            {
                                                Write-Host "  Zone Support: ✓ Supported (Zoneless deployment)" -ForegroundColor Green
                                            }
                                        elseif ($mNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                            {
                                                Write-Host $("  Zone Support: ✓ Supported in target zone {0}" -f $Zone) -ForegroundColor Green
                                                Write-Host $("  All Available Zones: {0}" -f ($mNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                            }
                                        elseif ($mNodeSupportedSKU.LocationInfo.Zones -notcontains $Zone)
                                            {
                                                Write-Host $("  Zone Support: ⚠ Not supported in target zone {0}" -f $Zone) -ForegroundColor Yellow
                                                Write-Host $("  Available Zones: {0}" -f ($mNodeSupportedSKU.LocationInfo.Zones -join ", "))
                                            }
                                        else
                                            {
                                                Write-Host "  Zone Support: ⚠ Unable to determine" -ForegroundColor Yellow
                                            }
                                    }
                                else
                                    {
                                        Write-Host "  Region Support: ✗ Not supported in region" -ForegroundColor Red
                                    }

                                # MNode Quota Information
                                if ($computeQuotaUsage)
                                    {
                                        $mNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeType.QuotaFamily }
                                        $mNodeInstanceCount = $MNodeSize | Group-Object | Select-Object Name, Count
                                        $mNodevCPUCount = $mNodeType.vCPU * $mNodeType.dNodeCount * ($mNodeInstanceCount | Where-Object { $_.Name -eq $mNodeType.PhysicalSize }).Count
                                        Write-Host $("  Quota Family: {0}" -f $mNodeType.QuotaFamily)
                                        if ($mNodeSKUFamilyQuota)
                                            {
                                                $availableQuota = $mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue
                                                if ($availableQuota -ge $mNodevCPUCount)
                                                    {
                                                        Write-Host $("  vCPU Quota: ✓ Sufficient (Required: {0}, Available: {1}/{2})" -f $mNodevCPUCount, $availableQuota, $mNodeSKUFamilyQuota.Limit) -ForegroundColor Green
                                                    }
                                                else
                                                    {
                                                        Write-Host $("  vCPU Quota: ✗ Insufficient (Required: {0}, Available: {1}/{2})" -f $mNodevCPUCount, $availableQuota, $mNodeSKUFamilyQuota.Limit) -ForegroundColor Red
                                                    }
                                            }
                                        else
                                            {
                                                Write-Host "  vCPU Quota: ⚠ Unable to determine" -ForegroundColor Yellow
                                            }
                                    }
                            }
                    }

                # Quota Summary
                if ($computeQuotaUsage)
                    {
                        Write-Host "`nQuota Summary:" -ForegroundColor Yellow

                        # Total VM Quota
                        $totalVMQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Virtual Machines" }
                        if ($totalVMQuota)
                            {
                                $totalVMCount = $CNodeCount + (($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum)
                                $availableVMQuota = $totalVMQuota.Limit - $totalVMQuota.CurrentValue
                                if ($availableVMQuota -ge $totalVMCount)
                                    {
                                        Write-Host $("  Total VMs: ✓ Sufficient (Required: {0}, Available: {1}/{2})" -f $totalVMCount, $availableVMQuota, $totalVMQuota.Limit) -ForegroundColor Green
                                    }
                                else
                                    {
                                        Write-Host $("  Total VMs: ✗ Insufficient (Required: {0}, Available: {1}/{2})" -f $totalVMCount, $availableVMQuota, $totalVMQuota.Limit) -ForegroundColor Red
                                    }
                            }

                        # Total Regional vCPU Quota
                        $totalVCPUQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Total Regional vCPUs" }
                        if ($totalVCPUQuota)
                            {
                                $totalvCPUCount = 0
                                if ($cNodeObject) { $totalvCPUCount += $cNodeObject.vCPU * $CNodeCount }
                                if ($mNodeObject) { $totalvCPUCount += ($mNodeObject | ForEach-Object { $_.vCPU * $_.dNodeCount } | Measure-Object -Sum).Sum }
                                $availableVCPUQuota = $totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue
                                if ($availableVCPUQuota -ge $totalvCPUCount)
                                    {
                                        Write-Host $("  Total vCPUs: ✓ Sufficient (Required: {0}, Available: {1}/{2})" -f $totalvCPUCount, $availableVCPUQuota, $totalVCPUQuota.Limit) -ForegroundColor Green
                                    }
                                else
                                    {
                                        Write-Host $("  Total vCPUs: ✗ Insufficient (Required: {0}, Available: {1}/{2})" -f $totalvCPUCount, $availableVCPUQuota, $totalVCPUQuota.Limit) -ForegroundColor Red
                                    }
                            }

                        # Availability Sets Quota
                        $totalAvailabilitySetQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Availability Sets" }
                        if ($totalAvailabilitySetQuota)
                            {
                                $totalAvailabilitySetCount = 0
                                if ($cNodeObject) { $totalAvailabilitySetCount += 1 }
                                if ($mNodeObjectUnique) { $totalAvailabilitySetCount += $mNodeObjectUnique.Count }
                                $availableAvSetQuota = $totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue
                                if ($availableAvSetQuota -ge $totalAvailabilitySetCount)
                                    {
                                        Write-Host $("  Availability Sets: ✓ Sufficient (Required: {0}, Available: {1}/{2})" -f $totalAvailabilitySetCount, $availableAvSetQuota, $totalAvailabilitySetQuota.Limit) -ForegroundColor Green
                                    }
                                else
                                    {
                                        Write-Host $("  Availability Sets: ✗ Insufficient (Required: {0}, Available: {1}/{2})" -f $totalAvailabilitySetCount, $availableAvSetQuota, $totalAvailabilitySetQuota.Limit) -ForegroundColor Red
                                    }
                            }
                    }

                # Display the deployment report table
                Write-Host "`n=== VM Deployment Report ===" -ForegroundColor Cyan

                # CNode Report
                $cNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "CNode" }

                if ($cNodeReport)
                    {
                        $cNodeExpectedSku = $cNodeReport[0].ExpectedSKU
                        Write-Host $("`nCNode Deployment Status (Expected SKU: {0}):" -f $cNodeExpectedSku) -ForegroundColor Yellow
                        $cNodeReport | Format-Table -Property  @(
                                                                    @{Label="Node"; Expression={$("CNode {0}" -f $_.NodeNumber)}; Width=12},
                                                                    @{Label="VM Name"; Expression={$_.VMName}; Width=25},
                                                                    @{Label="Deployed SKU"; Expression={$_.DeployedSKU}; Width=18},
                                                                    @{Label="VM Status"; Expression={$_.VMStatus}; Width=12},
                                                                    @{Label="NIC Status"; Expression={$_.NICStatus}; Width=12},
                                                                    @{Label="Availability Set"; Expression={$_.AvailabilitySet}; Width=18}
                                                                ) -AutoSize
                    }

                # DNode Report by MNode Group
                $mNodeGroups = $deploymentReport | Where-Object { $_.ResourceType -eq "DNode" } | Group-Object GroupNumber

                foreach ($group in $mNodeGroups)
                    {
                        $mNodeExpectedSku = $group.Group[0].ExpectedSKU
                        Write-Host $("`n{0} DNode Deployment Status (Expected SKU: {1}):" -f $group.Name, $mNodeExpectedSku) -ForegroundColor Yellow
                        $group.Group | Format-Table -Property  @(
                                                                    @{Label="Node"; Expression={$("DNode {0}" -f $_.NodeNumber)}; Width=12},
                                                                    @{Label="VM Name"; Expression={$_.VMName}; Width=25},
                                                                    @{Label="Deployed SKU"; Expression={$_.DeployedSKU}; Width=18},
                                                                    @{Label="VM Status"; Expression={$_.VMStatus}; Width=12},
                                                                    @{Label="NIC Status"; Expression={$_.NICStatus}; Width=12},
                                                                    @{Label="Availability Set"; Expression={$_.AvailabilitySet}; Width=18}
                                                                ) -AutoSize
                    }

                # Silk Component Summary
                Write-Host "`n=== Silk Component Summary ===" -ForegroundColor Cyan

                # Calculate CNode statistics
                $cNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "CNode" }
                $successfulCNodes = ($cNodeReport | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                $cNodeSummaryLabel = if ($cNodeReport)
                                        {
                                            $cNodeReport[0].ExpectedSKU
                                        }
                                    else
                                        {
                                            "Unknown"
                                        }

                # Calculate DNode statistics by MNode group
                $dNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "DNode" }
                $mNodeGroups = $dNodeReport | Group-Object GroupNumber

                # Create summary table
                $silkSummary = @()

                # Add CNode summary
                $silkSummary +=    [PSCustomObject]@{
                                                        Component = "CNode"
                                                        DeployedCount = $successfulCNodes
                                                        ExpectedCount = $CNodeCount
                                                        SKU = $cNodeSummaryLabel
                                                        Status = if ($successfulCNodes -eq $CNodeCount) { "✓ Complete" } else { "⚠ Partial" }
                                                    }

                # Add MNode/DNode summary for each group
                foreach ($group in $mNodeGroups)
                    {
                        $groupSuccessful = ($group.Group | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                        $groupExpected = $group.Group.Count
                        $groupSku = $group.Group[0].ExpectedSKU
                        $groupName = $group.Name.Replace("MNode ", "M").Replace(" TiB)", "TB)")

                        $silkSummary +=    [PSCustomObject]@{
                                                                Component = $groupName
                                                                DeployedCount = $groupSuccessful
                                                                ExpectedCount = $groupExpected
                                                                SKU = $groupSku
                                                                Status = if ($groupSuccessful -eq $groupExpected) { "✓ Complete" } else { "⚠ Partial" }
                                                            }
                    }

                # Display the summary table
                $silkSummary |
                    Format-Table -Property @(
                                                @{Label="Silk Component"; Expression={$_.Component}; Width=20},
                                                @{Label="Deployed"; Expression={$_.DeployedCount}; Width=10},
                                                @{Label="Expected"; Expression={$_.ExpectedCount}; Width=10},
                                                @{Label="VM SKU"; Expression={$_.SKU}; Width=20},
                                                @{Label="Status"; Expression={$_.Status}; Width=15}
                                            ) -AutoSize

                # Infrastructure Summary
                Write-Host "`n=== Infrastructure Summary ===" -ForegroundColor Cyan
                $totalExpectedVMs = $CNodeCount + ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum
                $successfulVMs = ($deploymentReport | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                $failedVMs = ($deploymentReport | Where-Object { $_.VMStatus -eq "✗ Failed" }).Count

                Write-Host "Virtual Network: " -NoNewline
                if ($deployedVNet)
                    {
                        Write-Host $("✓ {0}" -f $deployedVNet.Name) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "✗ Not Found" -ForegroundColor Red
                    }

                Write-Host "Network Security Group: " -NoNewline
                if ($deployedNSG)
                    {
                        Write-Host $("✓ {0}" -f $deployedNSG.Name) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "✗ Not Found" -ForegroundColor Red
                    }

                # Proximity Placement Group and Availability Sets Summary
                $deployedPPG = Get-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -Name "$ResourceNamePrefix-ppg" -ErrorAction SilentlyContinue
                Write-Host "Proximity Placement Group: " -NoNewline
                if ($deployedPPG)
                    {
                        Write-Host $("✓ {0} (Standard)" -f $deployedPPG.Name) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "✗ Not Found" -ForegroundColor Red
                    }

                $deployedAvailabilitySets = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                Write-Host "Availability Sets: " -NoNewline
                if ($deployedAvailabilitySets)
                    {
                        $avSetNames = ($deployedAvailabilitySets.Name | Sort-Object) -join ", "
                        Write-Host $("✓ {0} sets ({1})" -f $deployedAvailabilitySets.Count, $avSetNames) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "✗ Not Found" -ForegroundColor Red
                    }

                Write-Host $("Expected VMs: {0}" -f $totalExpectedVMs)
                Write-Host "Successfully Deployed VMs: " -NoNewline
                if ($successfulVMs -eq $totalExpectedVMs)
                    {
                        Write-Host $("{0}" -f $successfulVMs) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host $("{0}" -f $successfulVMs) -ForegroundColor Yellow
                    }

                if ($failedVMs -gt 0)
                    {
                        Write-Host "Failed VM Deployments: " -NoNewline
                        Write-Host $("{0}" -f $failedVMs) -ForegroundColor Red
                    }

                Write-Host $("Total Network Interfaces: {0}" -f $deployedNICs.Count)

                # Overall Status
                Write-Host "`n=== Overall Deployment Status ===" -ForegroundColor Cyan

                if ($successfulVMs -eq $totalExpectedVMs -and $deployedVNet -and $deployedNSG)
                    {
                        Write-Host "✓ DEPLOYMENT SUCCESSFUL - All resources deployed correctly!" -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "⚠ DEPLOYMENT ISSUES DETECTED - Review the report above for details" -ForegroundColor Yellow
                    }

                Write-Progress -Id 1 -Completed

                Start-Sleep -Seconds 2

                if (!$DisableCleanup)
                    {
                        Write-Verbose -Message $("Deployment completed. Resources have been created in the resource group: {0}." -f $ResourceGroupName)

                        Read-Host -Prompt "Press Enter to continue with cleanup or Ctrl+C to exit without cleanup."
                    }
            }
        end
            {
                if ( $RunCleanupOnly -or !$DisableCleanup )
                    {
                        # Start main cleanup progress
                        Write-Progress `
                            -Status "Initializing Resource Cleanup" `
                            -CurrentOperation "Preparing to clean up all deployed resources..." `
                            -PercentComplete 0 `
                            -Activity "Resource Cleanup" `
                            -Id 5

                        # Clean up resources

                        # clean up deployed test VMs
                        if (Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -Match $ResourceNamePrefix })
                            {
                                # Update main progress for VM cleanup phase (VMs = 50% of total cleanup)
                                Write-Progress `
                                    -Status "Cleaning Up Virtual Machines" `
                                    -CurrentOperation "Removing test VMs from resource group..." `
                                    -PercentComplete 10 `
                                    -Activity "Resource Cleanup" `
                                    -Id 5

                                # Start VM cleanup sub-progress
                                Write-Progress `
                                    -Status "Removing Virtual Machines" `
                                    -CurrentOperation "Submitting VM removal jobs..." `
                                    -PercentComplete 0 `
                                    -Activity "VM Cleanup" `
                                    -ParentId 5 `
                                    -Id 6

                                $vmsToRemove = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                                $totalVMs = $vmsToRemove.Count

                                $currentVMCount = 0

                                # Remove all cnode virtual machines in the resource group
                                $vmsToRemove |
                                    ForEach-Object `
                                        {
                                            $currentVMCount++

                                            # Update sub-progress for each VM
                                            Write-Progress `
                                                -Status $("Removing VM {0} of {1}" -f $currentVMCount, $totalVMs) `
                                                -CurrentOperation $("Removing virtual machine: {0}..." -f $_.Name) `
                                                -PercentComplete $(($currentVMCount / $totalVMs) * 50) `
                                                -Activity "VM Cleanup" `
                                                -ParentId 5 `
                                                -Id 6

                                            Write-Verbose -Message $("Removing virtual machine: {0} in resource group: {1}" -f $_.Name, $ResourceGroupName);

                                            Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $_.Name -Force:$true -AsJob | Out-Null
                                        }

                                # Update sub-progress for waiting phase
                                Write-Progress `
                                    -Status "Waiting for VM Removal Completion" `
                                    -CurrentOperation $("Waiting for all {0} virtual machines to be removed..." -f $totalVMs) `
                                    -PercentComplete 50 `
                                    -Activity "VM Cleanup" `
                                    -ParentId 5 `
                                    -Id 6

                                # Wait for all VM removal jobs to complete
                                Write-Verbose -Message "Waiting for all virtual machines to be removed..."

                                $vmJobs = Get-Job

                                # Initialize progress with jobs submitted
                                Write-Progress `
                                    -Status "VM Removal Progress: 0%" `
                                    -CurrentOperation $("All {0} VM removal jobs submitted, monitoring completion..." -f $vmJobs.Count) `
                                    -PercentComplete 0 `
                                    -Activity "VM Cleanup" `
                                    -ParentId 5 `
                                    -Id 6

                                do
                                    {
                                        Start-Sleep -Seconds 2
                                        $currentVMJobs = Get-Job
                                        $completedVMJobs = $currentVMJobs | Where-Object { $_.State -ne 'Running' }

                                        # VM sub-progress: Calculate actual completion percentage
                                        $vmCompletionPercent = [Math]::Round(($completedVMJobs.Count / $vmJobs.Count) * 100)

                                        # Update main progress during VM cleanup (10% to 50% - VMs represent 50% of total)
                                        $mainProgressPercent = 10 + [Math]::Round(($completedVMJobs.Count / $vmJobs.Count) * 40)

                                        Write-Progress `
                                            -Status $("Cleaning Up Virtual Machines - {0}%" -f $vmCompletionPercent) `
                                            -CurrentOperation $("VM cleanup in progress: {0} VMs remaining..." -f ($vmJobs.Count - $completedVMJobs.Count)) `
                                            -PercentComplete $mainProgressPercent `
                                            -Activity "Resource Cleanup" `
                                            -Id 5

                                        Write-Progress `
                                            -Status $("VM Removal Progress: {0}%" -f $vmCompletionPercent) `
                                            -CurrentOperation $("Waiting for {0} remaining VM removal jobs..." -f ($vmJobs.Count - $completedVMJobs.Count)) `
                                            -PercentComplete $vmCompletionPercent `
                                            -Activity "VM Cleanup" `
                                            -ParentId 5 `
                                            -Id 6
                                    } `
                                while ($currentVMJobs.State -contains 'Running')

                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "All virtual machines have been removed."

                                # Complete VM cleanup sub-progress
                                Write-Progress `
                                    -Activity "VM Cleanup" `
                                    -Id 6 `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        if (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -Match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (NICs = next 15% after VMs)
                                Write-Progress -Id 5 -Activity "Cleaning up test resources..." -Status "Removing network interfaces..." -PercentComplete 55

                                # Start NIC cleanup sub-progress
                                Write-Progress -Id 7 `
                                -ParentId 5 `
                                -Activity "Network Interface Cleanup" `
                                -Status "Identifying network interfaces to remove..." `
                                -PercentComplete 0

                                # Get all NICs to remove
                                $nicsToRemove = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                                $totalNICs = $nicsToRemove.Count

                                Write-Progress `
                                    -Id 7 `
                                    -ParentId 5 `
                                    -Activity "Network Interface Cleanup" `
                                    -Status $("Found {0} network interfaces to remove" -f $totalNICs) `
                                    -PercentComplete 10

                                # Remove all network interfaces in the resource group
                                $nicCount = 0
                                $nicsToRemove |
                                    ForEach-Object `
                                        {
                                            $nicCount++

                                            $nicProgress = [math]::Round((($nicCount / $totalNICs) * 60) + 10)

                                            Write-Progress `
                                                -Id 7 `
                                                -ParentId 5 `
                                                -Activity "Network Interface Cleanup" `
                                                -Status $("Removing NIC: {0} ({1} of {2})" -f $_.Name, $nicCount, $totalNICs) `
                                                -PercentComplete $nicProgress

                                            Write-Host $("Removing network interface: {0} in resource group: {1}" -f $_.Name, $ResourceGroupName);

                                            Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $_.Name -Force:$true -AsJob | Out-Null
                                        }

                                # Wait for all NIC removal jobs to complete before proceeding
                                Write-Progress `
                                    -Id 7 `
                                    -ParentId 5 `
                                    -Activity "Network Interface Cleanup" `
                                    -Status "Waiting for all NIC removal jobs to complete..." `
                                    -PercentComplete 80

                                Write-Verbose -Message "Waiting for all network interfaces to be removed..."
                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "All network interfaces have been removed."

                                Write-Progress `
                                    -Id 7 `
                                    -ParentId 5 `
                                    -Activity "Network Interface Cleanup" `
                                    -Status "Network interface cleanup completed" `
                                    -PercentComplete 100

                                Start-Sleep -Milliseconds 500

                                Write-Progress `
                                    -Id 7 `
                                    -Activity "Network Interface Cleanup" `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }


                        # Start VNet removal job
                        if (Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (VNet = next 15% after Storage)
                                Write-Progress `
                                    -Id 5 `
                                    -Activity "Cleaning up test resources..." `
                                    -Status "Removing virtual network..." `
                                    -PercentComplete 85

                                # Start VNet cleanup sub-progress
                                Write-Progress `
                                    -Id 9 `
                                    -ParentId 5 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Status "Identifying virtual network to remove..." `
                                    -PercentComplete 0

                                $foundVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }

                                Write-Progress `
                                    -Id 9 `
                                    -ParentId 5 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Status $("Removing virtual network: {0}" -f $foundVNet.Name) `
                                    -PercentComplete 25

                                Write-Verbose -Message $("Starting removal of virtual network: {0}" -f $foundVNet.Name)

                                Write-Progress `
                                    -Id 9 `
                                    -ParentId 5 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Status "Executing VNet removal..." `
                                    -PercentComplete 50

                                $foundVNet | Remove-AzVirtualNetwork -Force:$true -AsJob | Out-Null

                                Write-Progress `
                                    -Id 9 `
                                    -ParentId 5 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Status "Waiting for VNet removal to complete..." `
                                    -PercentComplete 75

                                Get-Job | Wait-Job | Out-Null

                                Write-Verbose -Message "Virtual Network resource cleanup completed."

                                Write-Progress `
                                    -Id 9 `
                                    -ParentId 5 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Status "Virtual network cleanup completed" `
                                    -PercentComplete 100

                                Start-Sleep -Milliseconds 500

                                Write-Progress `
                                    -Id 9 `
                                    -Activity "Virtual Network Cleanup" `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Start Availability Sets removal
                        $availabilitySets = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                        if ($availabilitySets)
                            {
                                # Update main cleanup progress (Availability Sets = 85-90%)
                                Write-Progress `
                                    -Id 5 `
                                    -Activity "Cleaning up test resources..." `
                                    -Status "Removing availability sets..." `
                                    -PercentComplete 85

                                # Start Availability Sets cleanup sub-progress
                                Write-Progress `
                                    -Id 11 `
                                    -ParentId 5 `
                                    -Activity "Availability Sets Cleanup" `
                                    -Status "Identifying availability sets to remove..." `
                                    -PercentComplete 0

                                foreach ($avSet in $availabilitySets) {
                                    Write-Progress `
                                        -Id 11 `
                                        -ParentId 5 `
                                        -Activity "Availability Sets Cleanup" `
                                        -Status $("Removing Availability Set: {0}" -f $avSet.Name) `
                                        -PercentComplete 25

                                    Write-Verbose -Message $("Starting removal of availability set: {0}" -f $avSet.Name)

                                    Write-Progress `
                                        -Id 11 `
                                        -ParentId 5 `
                                        -Activity "Availability Sets Cleanup" `
                                        -Status "Executing availability set removal..." `
                                        -PercentComplete 50

                                    $avSet | Remove-AzAvailabilitySet -Force:$true -AsJob | Out-Null

                                    Write-Progress `
                                        -Id 11 `
                                        -ParentId 5 `
                                        -Activity "Availability Sets Cleanup" `
                                        -Status "Waiting for availability set removal to complete..." `
                                        -PercentComplete 75

                                    Get-Job | Wait-Job | Out-Null
                                }

                                Write-Verbose -Message "Availability Sets resource cleanup completed."

                                Write-Progress `
                                    -Id 11 `
                                    -ParentId 5 `
                                    -Activity "Availability Sets Cleanup" `
                                    -Status "Availability sets cleanup completed" `
                                    -PercentComplete 100

                                Start-Sleep -Milliseconds 500

                                Write-Progress `
                                    -Id 11 `
                                    -Activity "Availability Sets Cleanup" `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Start Proximity Placement Group removal
                        $proximityPlacementGroups = Get-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                        if ($proximityPlacementGroups)
                            {
                                # Update main cleanup progress (PPG = 90-95%)
                                Write-Progress `
                                    -Id 5 `
                                    -Activity "Cleaning up test resources..." `
                                    -Status "Removing proximity placement groups..." `
                                    -PercentComplete 90

                                # Start PPG cleanup sub-progress
                                Write-Progress `
                                    -Id 12 `
                                    -ParentId 5 `
                                    -Activity "Proximity Placement Group Cleanup" `
                                    -Status "Identifying proximity placement groups to remove..." `
                                    -PercentComplete 0

                                foreach ($ppg in $proximityPlacementGroups) {
                                    Write-Progress `
                                        -Id 12 `
                                        -ParentId 5 `
                                        -Activity "Proximity Placement Group Cleanup" `
                                        -Status $("Removing PPG: {0}" -f $ppg.Name) `
                                        -PercentComplete 25

                                    Write-Verbose -Message $("Starting removal of proximity placement group: {0}" -f $ppg.Name)

                                    Write-Progress `
                                        -Id 12 `
                                        -ParentId 5 `
                                        -Activity "Proximity Placement Group Cleanup" `
                                        -Status "Executing PPG removal..." `
                                        -PercentComplete 50

                                    $ppg | Remove-AzProximityPlacementGroup -Force:$true -AsJob | Out-Null

                                    Write-Progress `
                                        -Id 12 `
                                        -ParentId 5 `
                                        -Activity "Proximity Placement Group Cleanup" `
                                        -Status "Waiting for PPG removal to complete..." `
                                        -PercentComplete 75

                                    Get-Job | Wait-Job | Out-Null
                                }

                                Write-Verbose -Message "Proximity Placement Groups resource cleanup completed."

                                Write-Progress `
                                    -Id 12 `
                                    -ParentId 5 `
                                    -Activity "Proximity Placement Group Cleanup" `
                                    -Status "Proximity placement groups cleanup completed" `
                                    -PercentComplete 100

                                Start-Sleep -Milliseconds 500

                                Write-Progress `
                                    -Id 12 `
                                    -Activity "Proximity Placement Group Cleanup" `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Start NSG removal job
                        if (Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (NSG = final 5% before completion)
                                Write-Progress `
                                    -Id 5 `
                                    -Activity "Cleaning up test resources..." `
                                    -Status "Removing network security group..." `
                                    -PercentComplete 95

                                # Start NSG cleanup sub-progress
                                Write-Progress `
                                    -Id 10 `
                                    -ParentId 5 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Status "Identifying network security group to remove..." `
                                    -PercentComplete 0

                                $foundNSG = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }

                                Write-Progress `
                                    -Id 10 `
                                    -ParentId 5 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Status $("Removing NSG: {0}" -f $foundNSG.Name) `
                                    -PercentComplete 25

                                Write-Verbose -Message $("Starting removal of network security group: {0}" -f $foundNSG.Name)

                                Write-Progress `
                                    -Id 10 `
                                    -ParentId 5 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Status "Executing NSG removal..." `
                                    -PercentComplete 50

                                $foundNSG | Remove-AzNetworkSecurityGroup -Force:$true -AsJob | Out-Null

                                Write-Progress `
                                    -Id 10 `
                                    -ParentId 5 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Status "Waiting for NSG removal to complete..." `
                                    -PercentComplete 75

                                Get-Job | Wait-Job | Out-Null

                                Write-Verbose -Message "Network Security Group resource cleanup completed."

                                Write-Progress `
                                    -Id 10 `
                                    -ParentId 5 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Status "Network security group cleanup completed" `
                                    -PercentComplete 100

                                Start-Sleep -Milliseconds 500

                                Write-Progress `
                                    -Id 10 `
                                    -Activity "Network Security Group Cleanup" `
                                    -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Final cleanup completion
                        Write-Progress `
                            -Id 5 `
                            -Activity "Cleaning up test resources..." `
                            -Status "All cleanup operations completed" `
                            -PercentComplete 100

                        Start-Sleep -Milliseconds 500

                        Write-Progress `
                            -Id 5 `
                            -Activity "Cleaning up test resources..." `
                            -Completed
                    }

                if($CreateResourceGroup -and $CreatedResourceGroup)
                    {
                        # Start resource group cleanup progress
                        Write-Progress `
                            -Status "Removing Resource Group" `
                            -CurrentOperation $("Removing resource group: {0}..." -f $ResourceGroupName) `
                            -PercentComplete 0 `
                            -Activity "Resource Group Cleanup" `
                            -Id 13

                        Write-Verbose -Message $("Removing resource group: {0}" -f $ResourceGroupName)

                        # Update progress during removal
                        Write-Progress `
                            -Status "Removing Resource Group" `
                            -CurrentOperation "Executing resource group removal..." `
                            -PercentComplete 50 `
                            -Activity "Resource Group Cleanup" `
                            -Id 13

                        Remove-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop -Confirm:$false

                        Write-Verbose -Message "Resource group removal completed."

                        # Complete resource group cleanup progress
                        Write-Progress `
                            -Status "Resource group removal completed" `
                            -CurrentOperation "Resource group cleanup finished" `
                            -PercentComplete 100 `
                            -Activity "Resource Group Cleanup" `
                            -Id 13

                        Start-Sleep -Milliseconds 500

                        Write-Progress `
                            -Id 13 `
                            -Activity "Resource Group Cleanup" `
                            -Completed
                    }
                Write-Host "Cleanup process completed." -ForegroundColor Green
            }
    }



Export-ModuleMember -Function Test-SilkResourceDeployment

