

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
                - Existing Infrastructure: Validate CNode deployment capacity into existing Proximity Placement Group and Availability Set
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

                Existing Infrastructure Validation:
                When ProximityPlacementGroupName and AvailabilitySetName parameters are provided together,
                the function validates deployment capacity within existing Silk cluster infrastructure. This tests
                whether additional CNodes can be successfully deployed into an established PPG/AvSet configuration,
                validating SKU availability and capacity constraints. Only CNode-only deployments are supported
                with existing infrastructure validation.

                Silk Infrastructure Components:
                - CNodes: Control nodes that manage the overall Silk cluster operations and coordination
                - MNodes: Media nodes that coordinate data operations and storage management
                - DNodes: Data nodes that store and serve data (deployed as part of MNode groups)

                Function Version: 1.98.10-1.0.1
                Supporting Silk SDP configurations from version 1.98.10

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

            .PARAMETER ChecklistJSON
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
                maximum 8 CNodes for maximum performance. Range: 2-8
                Not used with existing infrastructure validation - use CNodeCountAdditional instead.

            .PARAMETER CNodeCountAdditional
                Number of additional CNode VMs to test for deployment capacity in existing infrastructure.
                Used only with ProximityPlacementGroupName and AvailabilitySetName parameters to validate
                whether additional CNodes can be deployed into an existing Silk cluster.
                Range: 1-6 (limited to ensure realistic expansion testing within Azure Availability Set constraints)
                Example: 2 (tests if 2 additional CNodes can be added to existing cluster infrastructure)

            .PARAMETER ProximityPlacementGroupName
                Name of an existing Proximity Placement Group to use for CNode deployment validation.
                When specified along with AvailabilitySetName, tests whether additional CNodes can be deployed
                into existing Silk cluster infrastructure. Both parameters must be specified together.
                This validates VM SKU availability and deployment capacity within an existing PPG/AvSet configuration.
                Only CNode-only deployment scenarios are supported with existing infrastructure validation.
                Example: "my-silk-cnode-ppg"

            .PARAMETER AvailabilitySetName
                Name of an existing Availability Set to use for CNode deployment validation.
                When specified along with ProximityPlacementGroupName, tests whether additional CNodes can be deployed
                into existing Silk cluster infrastructure. Both parameters must be specified together.
                This validates VM SKU availability and deployment capacity within an existing PPG/AvSet configuration.
                Only CNode-only deployment scenarios are supported with existing infrastructure validation.
                Example: "my-silk-cnode-avset"

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

            .PARAMETER NoHTMLReport
                Switch parameter to disable HTML report generation.
                By default, a comprehensive HTML report is generated summarizing deployment status,
                quota usage, SKU support, and resource validation results.

            .PARAMETER ReportOutputPath
                Path where the HTML report should be saved.
                Default: Current working directory with filename 'SilkDeploymentReport_[timestamp].html'
                HTML reports are generated by default unless -NoHTMLReport is specified.

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

            .PARAMETER CreateResourceGroup
                Switch parameter to enable creation of a resource group by the given resource group name.
                The resource group must NOT already exist. When specified, a resource group is created
                for the test deployment. Requires elevated role assignment permissions.
                Note: The -RunCleanupOnly parameter cannot clean up resource groups; manual deletion required.

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
                Used for VM deployment supplied out of necessity with no expectation to actually use the credential.

            .PARAMETER ZoneAlignmentSubscriptionId
                Azure Subscription ID for cross-subscription availability zone alignment comparison.
                When specified, the function identifies zone alignment between the deployment subscription and this
                given subscription, automatically adjusting deployment zone to ensure the closest representation of a production deployment that can be tested.
                Requires AvailabilityZonePeering Azure feature registration in both subscriptions.
                When using ChecklistJSON with different deployment subscription, this is automatically populated.
                This will always be reported on if available but will not align the deployment zone if the -DisableZoneAlignment switch parameter is specified.
                Example: "87654321-4321-4321-4321-210987654321"

            .PARAMETER DisableZoneAlignment
                Switch parameter to disable automatic availability zone alignment validation and adjustment.
                By default, zone alignment is performed when ZoneAlignmentSubscriptionId is specified or when using
                ChecklistJSON configuration with different deployment subscription. Use this switch to maintain the
                originally specified zone. Availability Zone alignment will still be reported on if available.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCount 2 -MnodeSizeLaosv4 @("14.67","29.34") -Verbose

                Tests deployment with 2 CNodes using high-memory SKUs and 2 MNode groups with Laosv4 storage capacities.
                Uses verbose output for detailed progress tracking.

            .EXAMPLE
                Test-SilkResourceDeployment -ChecklistJSON "C:\configs\silk-deployment.json"

                Uses JSON configuration file for all deployment parameters.
                All parameters are loaded from the JSON file unless overridden by command line parameters.
                Parameters that override these imported values are -SubscriptionId, -ResourceGroupName, -Region, -Zone, and -IPRangeCIDR.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -RunCleanupOnly

                Performs cleanup-only operation, removing all test resources created by previous runs in the specified resource group.
                Uses the standard resource name prefix "sdp-test" to identify and remove test resources.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-prod-rg" -Region "westus2" -Zone "2" -CNodeSku "Standard_E64s_v5" -CNodeCount 4 -MNodeSku @("Standard_L16s_v3","Standard_L32s_v3") -MNodeCount 2 -DisableCleanup

                Advanced deployment using explicit SKUs: 4 CNodes with E64s_v5 SKU and 2 MNode groups with mixed L-series SKUs.
                Disables automatic cleanup so resources remain for extended testing or manual validation.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -ZoneAlignmentSubscriptionId "87654321-4321-4321-4321-210987654321" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCount 2 -Verbose

                Tests deployment with cross-subscription zone alignment validation between deployment subscription and alignment subscription.
                Automatically adjusts deployment zone to ensure the closest representation of a production deployment that can be tested.
                Requires AvailabilityZonePeering feature registration in both subscriptions.

            .EXAMPLE
                Test-SilkResourceDeployment -ChecklistJSON "C:\configs\silk-deployment.json" -SubscriptionId "12345678-1234-1234-1234-123456789012" -DisableZoneAlignment -Verbose

                Loads configuration from JSON file but uses a different deployment subscription than specified in the JSON.
                Explicitly disables zone alignment to maintain original zone settings despite cross-subscription deployment scenario.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-prod-rg" -Region "eastus" -Zone "1" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCountAdditional 2 -ProximityPlacementGroupName "my-silk-cnode-ppg" -AvailabilitySetName "my-silk-cnode-avset" -Verbose

                Validates whether 2 additional CNodes can be deployed into existing Silk cluster infrastructure.
                Tests deployment capacity within the specified Proximity Placement Group and Availability Set.
                Useful for validating cluster expansion scenarios before actual production deployment.

            .INPUTS
                Command line parameters or JSON configuration file containing deployment specifications.
                Supports both individual parameter specification and bulk configuration via JSON import.

            .OUTPUTS
                Console output with comprehensive deployment status information, resource validation results,
                SKU availability reports, quota validation summaries (including adjusted deployment counts when
                quota is insufficient), and deployment progress tracking.
                Additionally, an HTML report is generated (unless -NoHTMLReport is specified) summarizing deployment status,
                quota usage, SKU support, and resource validation results. The report is saved to the path specified by -ReportOutputPath
                or defaults to the current working directory in the format 'SilkDeploymentReport_[timestamp].html'.
                No objects are returned to the pipeline; all output is informational console display and/or HTML report file.

            .NOTES
                Function Version: 1.97.9-1.0.1
                Supporting Silk SDP configurations from version 1.97.9
                Author: Silk Cloud Infrastructure Team

                Requirements:
                - Azure PowerShell module (Az) with valid authentication
                - Contributor or equivalent permissions in target subscription and resource group
                - Target resource group must exist prior to deployment (unless using -CreateResourceGroup requiring it does not already exist, and subscription level permissions are required)

                Resource Management:
                - Creates resources with configurable prefix for easy identification (default: "sdp-test")
                - All VMs deployed with network isolation (no access from the subnet) for security
                - Comprehensive validation ensures all resources are properly deployed and functional
                - Automatic cleanup to remove test resources after validation

                Reporting Features:
                - HTML report generation with comprehensive deployment status and validation results
                - Configurable report output path

                Validation Capabilities:
                - SKU availability checking across specified availability zones
                - Quota validation for all resource types with automatic calculation of maximum deployable resources
                - Partial deployment support when quota is insufficient, deploying as many VMs as quota allows
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
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012")]
                [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $SubscriptionId,

                # Azure Resource Group name where test resources will be deployed
                # Resource group must already exist in the specified subscription
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = "Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg")]
                [ValidatePattern('^[a-z][a-z0-9\-]{1,61}[a-z0-9]$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceGroupName,

                # Azure region for resource deployment - must be a valid Azure region name
                # Common examples: eastus, westus2, northeurope, eastasia
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = "Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia")]
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
                # if -ZoneAlignmentSubscriptionId specified, zone alignment will occur unless -DisableZoneAlignment is also specified
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = "Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support).")]
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
                [Parameter(ParameterSetName = 'ChecklistJSON',              Mandatory = $true, HelpMessage = "Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\\configs\\silk-deployment.json")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON", Mandatory = $true, HelpMessage = "Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\\configs\\silk-deployment.json")]
                [string]
                $ChecklistJSON,

                # Friendly name for CNode SKU selection using descriptive categories
                # Increased_Logical_Capacity (Standard_E64s_v5) - Most common, high memory
                # Read_Cache_Enabled (Standard_L64s_v3) - High-speed local SSD storage
                # No_Increased_Logical_Capacity (Standard_D64s_v5) - Basic compute, rarely used
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true, HelpMessage = "Choose CNode type: Increased_Logical_Capacity (Standard_E64s_v5), Read_Cache_Enabled (Standard_L64s_v3), or No_Increased_Logical_Capacity (Standard_D64s_v5).")]
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
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = "Choose CNode VM SKU: Standard_E64s_v5 (supports increased logical capacity), Standard_L64s_v3 (supports read cache), or Standard_D64s_v5 (basic CNode).")]
                [ValidateSet("Standard_D64s_v5", "Standard_L64s_v3", "Standard_E64s_v5")]
                [string]
                $CNodeSku,

                # Number of CNode VMs to deploy (range: 2-8)
                # Silk Infrastructure requires minimum 2 CNodes for pod resilience, supporting up to 8 for maximum performance
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

                # Number of additional CNodes to test in existing infrastructure (range: 1-6)
                # Used only with existing infrastructure validation to test cluster expansion capacity
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true, HelpMessage = $("Enter number of additional CNode VMs to test (1-6). Tests deployment capacity in existing cluster infrastructure."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true, HelpMessage = $("Enter number of additional CNode VMs to test (1-6). Tests deployment capacity in existing cluster infrastructure."))]
                [ValidateRange(1, 6)]
                [ValidateNotNullOrEmpty()]
                [int]
                $CNodeCountAdditional,

                # Existing Proximity Placement Group name to use for CNode deployment validation
                # When specified with AvailabilitySetName, validates VM deployment into existing infrastructure
                # This tests whether additional CNodes can be deployed into an existing Silk cluster infrastructure
                # Both ProximityPlacementGroupName and AvailabilitySetName must be specified together
                # Only CNode-only deployment scenarios are supported with existing infrastructure validation
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true, HelpMessage = $("Enter the name of an existing Proximity Placement Group to validate CNode deployment capacity. Example: my-silk-cnode-ppg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true, HelpMessage = $("Enter the name of an existing Proximity Placement Group to validate CNode deployment capacity. Example: my-silk-cnode-ppg"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $ProximityPlacementGroupName,

                # Existing Availability Set name to use for CNode deployment validation
                # When specified with ProximityPlacementGroupName, validates VM deployment into existing infrastructure
                # This tests whether additional CNodes can be deployed into an existing Silk cluster infrastructure
                # Both ProximityPlacementGroupName and AvailabilitySetName must be specified together
                # Only CNode-only deployment scenarios are supported with existing infrastructure validation
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true, HelpMessage = $("Enter the name of an existing Availability Set to validate CNode deployment capacity. Example: my-silk-cnode-avset"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true, HelpMessage = $("Enter the name of an existing Availability Set to validate CNode deployment capacity. Example: my-silk-cnode-avset"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $AvailabilitySetName,

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

                # Subscription ID to compare zone alignment against the deployment subscription *Requires AvailablityZonePeering feature to be registered*
                # When specified, the script ouputs the deployment region and zone alignment with this given subscription
                # Useful for validating zone support and alignment across multiple subscriptions
                # if using the json configuration file, this parameter is assumed to be the subscription in the configuration file
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012")]
                [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $ZoneAlignmentSubscriptionId,

                # Switch to disable zone alignment, by default  the script  will align the deployment zone with the either the -ZoneAlignmentSubscriptionId or the subscription in the json configuration file
                # Must provide -ZoneAlignmentSubscriptionId OR
                # Must provide the -ChecklistJSON configuration and specify a different -SubscriptionId
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided.")]
                [Switch]
                $DisableZoneAlignment,

                # Switch to disable HTML report generation
                # By default, a comprehensive HTML report is generated summarizing deployment status,
                # quota usage, SKU support, and resource validation results
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Disable HTML report generation. Reports are generated by default.")]
                [Switch]
                $NoHTMLReport,

                # Path where the HTML report should be saved
                # Default: Current working directory with filename 'SilkDeploymentReport_[timestamp].html'
                # HTML reports are generated by default unless -NoHTMLReport is specified
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [Parameter(HelpMessage = "Path where the HTML report should be saved. Defaults to current working directory.")]
                [ValidateNotNullOrEmpty()]
                [string]
                $ReportOutputPath = (Get-Location).Path,

                # Switch to disable automatic cleanup of test resources after deployment validation
                # When specified, resources remain in Azure for manual inspection or extended testing
                # Resources must be manually removed or cleaned up using -RunCleanupOnly parameter
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up.")]
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
                [Parameter(ParameterSetName = "Cleanup Only",               Mandatory = $true, HelpMessage = "Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group")]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON", Mandatory = $true, HelpMessage = "Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group")]
                [Switch]
                $RunCleanupOnly,

                # CIDR notation for VNet and subnet IP address range, will not be peered or exposed otherwise.
                # Default: "10.0.0.0/24" (provides 254 usable IP addresses)
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24")]
                [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $IPRangeCIDR,

                # Switch to enabled Creation of a resource group by the given resource group name
                # The resource group must NOT already exist
                # When specified, a resource group is created for the test deployment and deleted
                # the -RunCleanupOnly parameter can not be used to clean up resource groups you will have to manually delete them
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Advanced Option to create a resource group by the given name, requires elevated Role assignment.")]
                [Switch]
                $CreateResourceGroup,

                # Azure Marketplace image offer for VM operating system
                # Default: "0001-com-ubuntu-server-jammy" (Ubuntu 22.04 LTS)
                # Advanced parameter - modify only if specific OS requirements exist
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only")]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageOffer = "0001-com-ubuntu-server-jammy",

                # Azure Marketplace image publisher for VM operating system
                # Default: "Canonical" (official Ubuntu publisher)
                # Advanced parameter - modify only if using non-Ubuntu images
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only")]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImagePublisher = "Canonical",

                # Azure Marketplace image SKU for VM operating system
                # If not specified, automatically selects latest available SKU with Gen2 preference
                # Advanced parameter - function auto-detects best available SKU for most scenarios
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only")]
                [string]
                $VMImageSku,

                # Azure Marketplace image version for VM operating system
                # Default: "latest" (automatically uses most recent image version)
                # Advanced parameter - specify only if specific image version required for compliance
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements")]
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

                # Switch to enable Development Mode with reduced VM sizes and instance counts
                # When enabled: Uses 2 vCPU SKUs instead of production 64 vCPU, 1 DNode per MNode instead of 16
                # Significantly reduces deployment time and costs for faster testing iterations
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "Enable Development Mode with reduced VM sizes and instance counts.")]
                [Switch]
                $Development,

                # PowerShell credential object for VM local administrator account
                # Default: Username "azureuser" with secure password for testing purposes
                # Used for VM deployment - SSH key authentication not implemented in test scenarios
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = "PowerShell credential object to assign to VM local administrator account.")]
                [ValidateNotNullOrEmpty()]
                [pscredential]
                $VMInstanceCredential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "azureuser", (ConvertTo-SecureString 'sdpD3ploym3ntT3$t' -AsPlainText -Force))
            )

        begin
            {
                $StartTime = Get-Date
                Write-Verbose -Message $("=== Starting Silk Resource Deployment Test Script ===")
                Write-Verbose -Message $("Script started at: {0}" -f $StartTime.ToString("yyyy-MM-dd HH:mm:ss"))

                # ========================================================================================================
                # Existing Infrastructure Parameter Mapping
                # ========================================================================================================
                # Map CNodeCountAdditional to CNodeCount for existing infrastructure scenarios
                if($CNodeCountAdditional)
                    {
                        Write-Verbose -Message $("Existing infrastructure validation mode: Testing deployment of {0} additional CNode(s)" -f $CNodeCountAdditional)
                        $CNodeCount = $CNodeCountAdditional
                    }

                # Define required Azure PowerShell modules
                # Import only the specific modules needed instead of the entire Az module for faster loading
                $requiredModules = @(
                                        'Az.Accounts',      # Authentication & Context
                                        'Az.Resources',     # Resource Groups
                                        'Az.Compute',       # VMs, SKUs, Quota
                                        'Az.Network'        # Networking
                                    )

                # ===============================================================================
                # Azure Authentication and Module Validation
                # ===============================================================================
                # Comprehensive Azure PowerShell module management and user authentication
                # Ensures Az module is installed, imported, and user is properly authenticated
                try
                    {
                        Write-Verbose -Message $("=== Azure PowerShell Module Validation ===")

                        # Check for required Azure PowerShell modules (specific modules instead of entire Az)
                        $missingModules = @()

                        foreach ($module in $requiredModules)
                            {
                                $moduleAvailable = Get-Module -ListAvailable -Name $module
                                if (-not $moduleAvailable)
                                    {
                                        $missingModules += $module
                                    }
                            }

                        if ($missingModules.Count -gt 0)
                            {
                                Write-Warning -Message $("Missing Azure PowerShell modules: {0}. Attempting to install..." -f ($missingModules -join ', '))

                                # Check if running as administrator for module installation
                                $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                                $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

                                try
                                    {
                                        foreach ($module in $missingModules)
                                            {
                                                if ($isAdmin)
                                                    {
                                                        Write-Verbose -Message $("Installing {0} for all users (administrator privileges detected)..." -f $module)
                                                        Install-Module -Name $module -Repository PSGallery -Scope AllUsers -Force -AllowClobber -Confirm:$false -Verbose:$false
                                                    }
                                                else
                                                    {
                                                        Write-Verbose -Message $("Installing {0} for current user (no administrator privileges)..." -f $module)
                                                        Install-Module -Name $module -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -Confirm:$false -Verbose:$false
                                                    }
                                            }

                                        Write-Verbose -Message $("✓ Required Azure PowerShell modules installed successfully.")
                                    }
                                catch
                                    {
                                        Write-Error -Message $("Failed to install Azure PowerShell modules: {0}. Please install manually using 'Install-Module -Name {1} -Repository PSGallery -Scope CurrentUser'" -f $_.Exception.Message, ($missingModules -join ', '))
                                        return
                                    }
                            }
                        else
                            {
                                Write-Verbose -Message $("✓ All required Azure PowerShell modules {0} are available." -f ($requiredModules -join ', '))
                            }

                        # Check if any Az modules are already imported to avoid assembly conflicts
                        $azModulesImported = Get-Module -Name Az*
                        if ($azModulesImported.Count -eq 0)
                            {
                                Write-Verbose -Message $("Importing required Azure PowerShell modules {0}" -f ($requiredModules -join ', '))
                                try
                                    {

                                        $importedModules = @()
                                        foreach ($module in $requiredModules)
                                            {
                                                Write-Verbose -Message $("Importing {0}..." -f $module)
                                                $importedModule = Import-Module $module -PassThru -ErrorAction Stop
                                                $importedModules += $importedModule
                                            }

                                        if ($importedModules.Count -eq $requiredModules.Count)
                                            {
                                                Write-Verbose -Message $("✓ Required Azure PowerShell modules imported successfully.")
                                            }
                                    }
                                catch
                                    {
                                        Write-Error -Message $("Failed to import Azure PowerShell modules: {0}. Please restart PowerShell and try again." -f $_.Exception.Message)
                                        return
                                    }
                            }
                        else
                            {
                                $azCoreModule = $azModulesImported | Where-Object { $_.Name -eq 'Az' } | Select-Object -First 1
                                if ($azCoreModule)
                                    {
                                        Write-Verbose -Message $("✓ Azure PowerShell (Az) module is already imported (version {0})" -f $azCoreModule.Version)
                                    }
                                else
                                    {
                                        $moduleCount = $azModulesImported.Count
                                        Write-Verbose -Message $("✓ Azure PowerShell sub-modules are already imported ({0} modules loaded)" -f $moduleCount)
                                    }
                            }

                        # Suppress Azure PowerShell breaking change warnings for cleaner output
                        Write-Verbose -Message $("Configuring Azure PowerShell warning preferences...")
                        try
                            {
                                # Suppress breaking change warnings globally for this session
                                Set-Item -Path Env:SuppressAzurePowerShellBreakingChangeWarnings -Value $true -Force -ErrorAction SilentlyContinue

                                # Also suppress using PowerShell preference variable as a backup
                                if (Get-Variable -Name WarningPreference -ErrorAction SilentlyContinue)
                                    {
                                        $originalWarningPreference = $WarningPreference
                                        $WarningPreference = 'SilentlyContinue'
                                    }

                                Write-Verbose -Message $("✓ Azure PowerShell breaking change warnings suppressed for cleaner output.")
                            }
                        catch
                            {
                                Write-Verbose -Message $("Warning: Could not suppress Azure PowerShell breaking change warnings.")
                            }

                        # Verify Azure authentication status
                        Write-Verbose -Message $("Checking Azure authentication status...")
                        $currentAzContext = Get-AzContext
                        if (-not $currentAzContext)
                            {
                                Write-Warning -Message $("You are not authenticated to Azure. Attempting interactive authentication...")

                                try
                                    {
                                        # Attempt interactive authentication
                                        Write-Host "Opening Azure authentication dialog. Please complete the sign-in process..." -ForegroundColor Yellow
                                        $connectResult = Connect-AzAccount -ErrorAction Stop

                                        if ($connectResult)
                                            {
                                                $newContext = Get-AzContext
                                                Write-Verbose -Message $("✓ Successfully authenticated to Azure as '{0}' in tenant '{1}'" -f $newContext.Account.Id, $newContext.Tenant.Id)
                                            }
                                        else
                                            {
                                                Write-Error -Message "Azure authentication failed. Please run 'Connect-AzAccount' manually and try again."
                                                return
                                            }
                                    }
                                catch
                                    {
                                        Write-Error -Message $("Azure authentication failed: {0}. Please run 'Connect-AzAccount' manually and try again." -f $_.Exception.Message)
                                        return
                                    }
                            }
                        else
                            {
                                Write-Verbose -Message $("✓ Already authenticated to Azure as '{0}' in tenant '{1}'" -f $currentAzContext.Account.Id, $currentAzContext.Tenant.Id)

                                # Check if the current context is still valid
                                try
                                    {
                                        $testConnectionNull = Get-AzSubscription -SubscriptionId $currentAzContext.Subscription.Id -ErrorAction Stop
                                        Write-Verbose -Message $("✓ Azure authentication is valid and active.")
                                    }
                                catch
                                    {
                                        Write-Warning -Message $("Current Azure context appears to be expired. Attempting re-authentication...")
                                        try
                                            {
                                                $connectResult = Connect-AzAccount -ErrorAction Stop
                                                Write-Verbose -Message $("✓ Azure re-authentication successful.")
                                            }
                                        catch
                                            {
                                                Write-Error -Message $("Azure re-authentication failed: {0}. Please run 'Connect-AzAccount' manually and try again." -f $_.Exception.Message)
                                                return
                                            }
                                    }
                            }

                        Write-Verbose -Message $("=== Azure PowerShell Prerequisites Complete ===")

                        # Restore warning preference now that Azure module imports are complete
                        # This ensures script warnings (e.g., validation errors) are displayed properly
                        if (Get-Variable -Name originalWarningPreference -ErrorAction SilentlyContinue)
                            {
                                $WarningPreference = $originalWarningPreference
                                Write-Verbose -Message $("✓ PowerShell warning preference restored after Azure module initialization.")
                            }
                    } `
                catch
                    {
                        # Restore warning preference in case of error
                        if (Get-Variable -Name originalWarningPreference -ErrorAction SilentlyContinue)
                            {
                                $WarningPreference = $originalWarningPreference
                            }

                        Write-Error $("An error occurred during Azure PowerShell module validation or authentication: {0}" -f $_.Exception.Message)
                        $validationError = $true
                        return
                    }

                # ===============================================================================
                # JSON Configuration Processing
                # ===============================================================================
                # Load deployment configuration from JSON file if specified
                # Command line parameters take precedence over JSON values
                if ($ChecklistJSON)
                    {
                        # Load and parse the JSON configuration file
                        $ConfigImport = Get-Content -Path $ChecklistJSON | ConvertFrom-Json

                        # Override JSON values with command line parameters if provided
                        # This allows selective override of JSON config while preserving other values

                        if (!$SubscriptionId)
                            {
                                $SubscriptionId = $ConfigImport.azure_environment.subscription_id
                                Write-Verbose -Message $("Using subscription ID '{0}' from JSON configuration." -f $SubscriptionId)
                            } `
                        else
                            {
                                Write-Warning -Message $("Subscription ID parameter is set to '{0}', ignoring subscription ID '{1}' in JSON configuration." -f $SubscriptionId, $ConfigImport.azure_environment.subscription_id)
                            }

                        # Zone Alignment Configuration - Determines cross-subscription alignment requirements
                        # When deployment and JSON subscriptions differ, unless disabled will inherantly align availablity zones between deployment subscriptions and the identified or given zone alignment subscription
                        if (!$ZoneAlignmentSubscriptionId -and $SubscriptionId -ne $ConfigImport.azure_environment.subscription_id)
                            {
                                $ZoneAlignmentSubscriptionId = $ConfigImport.azure_environment.subscription_id
                                Write-Verbose -Message $("Availability Zone alignment check enabled: Using JSON subscription '{0}' for zone alignment comparison against deployment subscription '{1}'." -f $ZoneAlignmentSubscriptionId, $SubscriptionId)
                            } `
                        elseif (!$ZoneAlignmentSubscriptionId -and $SubscriptionId -eq $ConfigImport.azure_environment.subscription_id)
                            {
                                Write-Warning -Message $("Availability Zone alignment not required: Subscription ID parameter is: '{0}' matching the Checklist Imported Subscription ID: '{1}'." -f $ZoneAlignmentSubscriptionId, $ConfigImport.azure_environment.subscription_id)
                            }
                        elseif ($ZoneAlignmentSubscriptionId)
                            {
                                Write-Verbose -Message $("Availability Zone alignment check enabled: Using explicitly provided alignment subscription '{0}' for Availability Zone alignment comparison against deployment subscription '{1}'." -f $ZoneAlignmentSubscriptionId, $SubscriptionId)
                            }
                        else
                            {
                                Write-Verbose -Message $("Availability Zone alignment check skipped: No alignment subscription specified - deployment will use original zone '{0}' in region '{1}'." -f $Zone, $Region)
                            }

                        if (!$ResourceGroupName)
                            {
                                $ResourceGroupName = $ConfigImport.azure_environment.resource_group_name
                                Write-Verbose -Message $("Using resource group name '{0}' from JSON configuration." -f $ResourceGroupName)
                            } `
                        else
                            {
                                Write-Warning -Message $("Resource Group Name parameter is set to '{0}', ignoring resource group name '{1}' in JSON configuration." -f $ResourceGroupName, $ConfigImport.azure_environment.resource_group_name)
                            }

                        if(!$Region)
                            {
                                $Region = $ConfigImport.azure_environment.region
                                Write-Verbose -Message $("Using region '{0}' from JSON configuration." -f $Region)
                            } `
                        else
                            {
                                Write-Warning -Message $("Region parameter is set to '{0}', ignoring region '{1}' in JSON configuration." -f $Region, $ConfigImport.azure_environment.region)
                            }

                        if(!$Zone)
                            {
                                $Zone = $ConfigImport.azure_environment.zone
                                Write-Verbose -Message $("Using zone '{0}' from JSON configuration." -f $Zone)
                            } `
                        else
                            {
                                Write-Warning -Message $("Zone parameter is set to '{0}', ignoring zone '{1}' in JSON configuration." -f $Zone, $ConfigImport.azure_environment.zone)
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
                                # Validate ResourceGroupName is provided when using -CreateResourceGroup
                                if([string]::IsNullOrWhiteSpace($ResourceGroupName))
                                    {
                                        Write-Error -Message $("The '-ResourceGroupName' parameter is required to specify a valid resource group name when using '-CreateResourceGroup' switch.")
                                        $validationError = $true
                                        return
                                    }

                                # Create resource group if it does not exist
                                try
                                    {
                                        $CreatedResourceGroup = $false
                                        if(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)
                                            {
                                                Write-Error -Message $("Resource group '{0}' already exists in subscription '{1}'. Remove the '-CreateResourceGroup' switch to use the existing resource group, or specify a different resource group name." -f $ResourceGroupName, $subscriptionCheck.Name)
                                                $validationError = $true
                                                return
                                            }
                                        Write-Verbose -Message $("Creating resource group '{0}' in region '{1}' within subscription '{2}'." -f $ResourceGroupName, $Region, $subscriptionCheck.Name)
                                        New-AzResourceGroup -Name $ResourceGroupName -Location $Region -ErrorAction Stop -Confirm:$false | Out-Null
                                        $CreatedResourceGroup = $true
                                        Write-Verbose -Message $("✓ Successfully created resource group '{0}'." -f $ResourceGroupName)
                                    } `
                                catch
                                    {
                                        Write-Error -Message $("Failed to create resource group '{0}' in region '{1}' within subscription '{2}': {3}" -f $ResourceGroupName, $Region, $subscriptionCheck.Name, $_.Exception.Message)
                                        $validationError = $true
                                        return
                                    }
                            }

                        try
                            {
                                # Check for resource group
                                $resourceGroupCheck = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
                                Write-Verbose -Message $("Resource group '{0}' was identified in the subscription {1}." -f $resourceGroupCheck.ResourceGroupName, $subscriptionCheck.Name)
                            } `
                        catch
                            {
                                Write-Error -Message $("Resource group '{0}' does not exist in subscription '{1}'. Check the name is correct or use the '-CreateResourceGroup' switch if it should be created for the test.: {2}" -f $ResourceGroupName, $subscriptionCheck.Name, $_.Exception.Message)
                                $validationError = $true
                                return
                            }

                        # Check region and get supported SKUs
                        $locationSupportedSKU = Get-AzComputeResourceSku -Location $Region -ErrorAction Stop

                        # Check zone availability
                        if ($Zone -eq "Zoneless" -and $locationSupportedSKU.LocationInfo.Zones.Count -ne 0)
                            {
                                Write-Error -Message $("The specified region '{0}' has availability zones {1}, but 'Zoneless' was specified." -f ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique), (($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique) -join ", "))
                                $validationError = $true
                                return
                            } `
                        elseif ($locationSupportedSKU.LocationInfo.Zones.Count -eq 0 -and $Zone -ne "Zoneless")
                            {
                                Write-Warning -Message $("The specified region '{0}' has no Availability Zones, but Zone value {1} was specified instead of 'Zoneless'." -f ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique), $Zone)
                                Write-Warning -Message $("Changing deployment Zone selection from '{0}' to 'Zoneless' and deploying in Region {1}." -f $Zone, $Region)
                                $Zone = "Zoneless"
                            } `
                        elseif ($Zone -eq "Zoneless")
                            {
                                Write-Verbose -Message $("Zoneless is a valid zone selection for the specified region '{0}'." -f ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique))
                            } `
                        elseif ($Zone -notin $locationSupportedSKU.LocationInfo.Zones)
                            {
                                Write-Error -Message $("The specified zone '{0}' is not available in the region '{1}'." -f $Zone, $Region)
                                $validationError = $true
                                return
                            } `
                        else
                            {
                                Write-Verbose -Message $("The specified zone '{0}' is available in the region '{1}' with zones {2}." -f $Zone, ($locationSupportedSKU.LocationInfo.Location | Select-Object -Unique), (($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique) -join ", "))
                            }
                    } `
                catch
                    {
                        Write-Error -Message "Failed to validate environment information: $_"
                        $validationError = $true
                        return
                    }

                # Do not run the rest of begin block if cleanup only
                if ($RunCleanupOnly)
                    {
                        return
                    }

                # ===============================================================================
                # Existing Infrastructure Validation
                # ===============================================================================
                # When using existing infrastructure parameter sets, validate that the specified
                # Proximity Placement Group and Availability Set exist and are properly configured
                if($ProximityPlacementGroupName -or $AvailabilitySetName)
                    {
                        $processSection = $("Existing Infrastructure Validation")
                        $messagePrefix = $("[{0}] " -f $processSection)

                        Write-Verbose -Message $("{0}Validating existing infrastructure resources in resource group '{1}'." -f $messagePrefix, $ResourceGroupName)

                        # Both parameters must be provided together
                        if((-not $ProximityPlacementGroupName) -or (-not $AvailabilitySetName))
                            {
                                Write-Error -Message $("{0}Both ProximityPlacementGroupName and AvailabilitySetName parameters must be specified together. Only one parameter was provided." -f $messagePrefix)
                                $validationError = $true
                                return
                            }

                        # Validate Proximity Placement Group exists
                        try
                            {
                                Write-Verbose -Message $("{0}Checking for Proximity Placement Group '{1}' in resource group '{2}'..." -f $messagePrefix, $ProximityPlacementGroupName, $ResourceGroupName)
                                $existingProximityPlacementGroup = Get-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -Name $ProximityPlacementGroupName -ErrorAction Stop

                                Write-Verbose -Message $("{0}✓ Successfully validated Proximity Placement Group '{1}' exists in '{2}' region." -f $messagePrefix, $ProximityPlacementGroupName, $existingProximityPlacementGroup.Location)

                                # Validate PPG region matches target region
                                if($existingProximityPlacementGroup.Location -ne $Region)
                                    {
                                        Write-Error -Message $("{0}Proximity Placement Group '{1}' is located in region '{2}', but deployment is targeting region '{3}'. Regions must match." -f $messagePrefix, $ProximityPlacementGroupName, $existingProximityPlacementGroup.Location, $Region)
                                        $validationError = $true
                                        return
                                    }

                                # Validate PPG zone configuration matches target zone
                                if($Zone -ne "Zoneless")
                                    {
                                        if($existingProximityPlacementGroup.Zones -and $existingProximityPlacementGroup.Zones -notcontains $Zone)
                                            {
                                                Write-Error -Message $("{0}Proximity Placement Group '{1}' is configured for zones '{2}', but deployment is targeting zone '{3}'. Zones must match." -f $messagePrefix, $ProximityPlacementGroupName, ($existingProximityPlacementGroup.Zones -join ", "), $Zone)
                                                $validationError = $true
                                                return
                                            }
                                        Write-Verbose -Message $("{0}✓ Proximity Placement Group zone configuration matches target zone '{1}'." -f $messagePrefix, $Zone)
                                    } `
                                else
                                    {
                                        if($existingProximityPlacementGroup.Zones -and $existingProximityPlacementGroup.Zones.Count -gt 0)
                                            {
                                                Write-Warning -Message $("{0}Proximity Placement Group '{1}' has zone configuration '{2}', but deployment is targeting 'Zoneless'. This may impact deployment." -f $messagePrefix, $ProximityPlacementGroupName, ($existingProximityPlacementGroup.Zones -join ", "))
                                            }
                                    }
                            } `
                        catch
                            {
                                Write-Error -Message $("{0}Failed to retrieve Proximity Placement Group '{1}' in resource group '{2}'. Error: {3}" -f $messagePrefix, $ProximityPlacementGroupName, $ResourceGroupName, $_.Exception.Message)
                                Write-Error -Message $("{0}Ensure the Proximity Placement Group exists and you have appropriate permissions to access it." -f $messagePrefix)
                                $validationError = $true
                                return
                            }

                        # Validate Availability Set exists
                        try
                            {
                                Write-Verbose -Message $("{0}Checking for Availability Set '{1}' in resource group '{2}'..." -f $messagePrefix, $AvailabilitySetName, $ResourceGroupName)
                                $existingAvailabilitySet = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $AvailabilitySetName -ErrorAction Stop

                                Write-Verbose -Message $("{0}✓ Successfully validated Availability Set '{1}' exists with {2} fault domains and {3} update domains." -f $messagePrefix, $AvailabilitySetName, $existingAvailabilitySet.PlatformFaultDomainCount, $existingAvailabilitySet.PlatformUpdateDomainCount)

                                # Validate AvSet region matches target region
                                if($existingAvailabilitySet.Location -ne $Region)
                                    {
                                        Write-Error -Message $("{0}Availability Set '{1}' is located in region '{2}', but deployment is targeting region '{3}'. Regions must match." -f $messagePrefix, $AvailabilitySetName, $existingAvailabilitySet.Location, $Region)
                                        $validationError = $true
                                        return
                                    }

                                # Validate AvSet is associated with the correct PPG
                                if($existingAvailabilitySet.ProximityPlacementGroup.Id -ne $existingProximityPlacementGroup.Id)
                                    {
                                        Write-Error -Message $("{0}Availability Set '{1}' is not associated with Proximity Placement Group '{2}'. These resources must be linked together." -f $messagePrefix, $AvailabilitySetName, $ProximityPlacementGroupName)
                                        Write-Error -Message $("{0}Current AvSet PPG: '{1}', Expected PPG: '{2}'" -f $messagePrefix, $(if($existingAvailabilitySet.ProximityPlacementGroup.Id){$existingAvailabilitySet.ProximityPlacementGroup.Id}else{$("None")}), $existingProximityPlacementGroup.Id)
                                        $validationError = $true
                                        return
                                    }

                                Write-Verbose -Message $("{0}✓ Availability Set '{1}' is correctly associated with Proximity Placement Group '{2}'." -f $messagePrefix, $AvailabilitySetName, $ProximityPlacementGroupName)

                                # Check current VM count in Availability Set
                                $currentVMCount = if($existingAvailabilitySet.VirtualMachinesReferences){$existingAvailabilitySet.VirtualMachinesReferences.Count}else{0}
                                Write-Verbose -Message $("{0}Current VMs in Availability Set '{1}': {2}" -f $messagePrefix, $AvailabilitySetName, $currentVMCount)

                                # Calculate available capacity (max 200 VMs per AvSet in Azure)
                                $availableAvSetCapacity = 200 - $currentVMCount
                                if($CNodeCount -gt $availableAvSetCapacity)
                                    {
                                        Write-Warning -Message $("{0}Requested {1} CNodes exceeds available Availability Set capacity of {2} VMs. Deployment may fail during capacity allocation." -f $messagePrefix, $CNodeCount, $availableAvSetCapacity)
                                    }
                                else
                                    {
                                        Write-Verbose -Message $("{0}✓ Availability Set has capacity for {1} CNodes (current: {2}, requested: {3}, max: 200)." -f $messagePrefix, $CNodeCount, $currentVMCount, $CNodeCount)
                                    }
                            } `
                        catch
                            {
                                Write-Error -Message $("{0}Failed to retrieve Availability Set '{1}' in resource group '{2}'. Error: {3}" -f $messagePrefix, $AvailabilitySetName, $ResourceGroupName, $_.Exception.Message)
                                Write-Error -Message $("{0}Ensure the Availability Set exists and you have appropriate permissions to access it." -f $messagePrefix)
                                $validationError = $true
                                return
                            }

                        Write-Verbose -Message $("{0}✓ All existing infrastructure resources validated successfully. Proceeding with CNode deployment test into existing PPG/AvSet." -f $messagePrefix)
                    }

                # ===============================================================================
                # Environment Information Collection
                # ===============================================================================
                $processSection = $("Environment Information Collection")
                $sectionStep = $("Maximum Fault Domains")
                $messagePrefix = $("{0}{1}" -f $(if($processSection){$("[{0}] " -f $processSection)}else{$("")}), $(if($sectionStep){$("[{0}] " -f $sectionStep)}else{$("")}))

                Write-Verbose -Message $("{0}Querying Azure Resource SKU API to identify maximum availability set fault domains for region '{1}'." -f $messagePrefix, $Region)

                # Query Azure Resource SKU API to determine maximum fault domains supported by the region
                # Fault domains define the number of physical hardware failure boundaries within an availability set
                # Most Azure regions support 3 fault domains, but some regions only support 2
                try
                    {
                        # Define Azure Resource SKU API version for querying compute SKU information
                        $azureSKUApiVersion = $("2025-04-01")

                        # Generate authorization header using current Azure access token for Management API
                        $azureSKUApiRequestHeaders =   @{
                                                            Authorization = $("Bearer {0}" -f $(ConvertFrom-SecureString -SecureString $(Get-AzAccessToken -ResourceUrl $("https://management.azure.com/")).Token -AsPlainText))
                                                        }

                        # Construct API URI to query compute SKUs for the target subscription
                        $azureSKUApiUri = $("https://management.azure.com/subscriptions/{0}/providers/Microsoft.Compute/skus?api-version={1}" -f $SubscriptionId, $azureSKUApiVersion)

                        # Execute REST API call to retrieve SKU information
                        $regionAvailabilitySetSKU = $(Invoke-RestMethod -Method Get -Uri $azureSKUApiUri -Headers $azureSKUApiRequestHeaders).value

                        # Filter SKU response to extract maximum fault domains capability for availability sets in the target region
                        $maximumFaultDomains = $regionAvailabilitySetSKU | Where-Object -FilterScript {$_.resourceType -eq $("availabilitySets") -and $_.locations -eq $Region} | Select-Object -First 1 | Select-Object -ExpandProperty capabilities | Select-Object -ExpandProperty value

                        Write-Verbose -Message $("{0}Successfully identified maximum fault domains for region '{1}': {2}" -f $messagePrefix, $Region, $maximumFaultDomains)
                    } `
                catch
                    {
                        # Default to 3 fault domains if API query fails
                        # Conservative default as majority of Azure regions support 3 fault domains
                        # Only a small subset of regions (e.g., some government or specialized regions) support only 2
                        $maximumFaultDomains = 3
                        Write-Warning -Message $("{0}Failed to query Azure Resource SKU API for fault domain information. Defaulting to {1} fault domains. Error: {2}" -f $messagePrefix, $maximumFaultDomains, $_.Exception.Message)
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
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "s_v5"; QuotaFamily = "Standard Dsv5 Family vCPUs"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "s_v3"; QuotaFamily = "Standard Lsv3 Family vCPUs"; cNodeFriendlyName = "Read_Cache_Enabled"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "s_v5"; QuotaFamily = "Standard Esv5 Family vCPUs"; cNodeFriendlyName = "Increased_Logical_Capacity"}
                                    )

                if ($Development)
                    {
                        Write-Verbose -Message $("Running in Development Mode, using reduced CNode configuration for faster deployment.")
                        $cNodeSizeObject = @(
                                                [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 2; vmSkuSuffix = "s_v5"; QuotaFamily = "Standard Dsv5 Family vCPUs"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                                                [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 8; vmSkuSuffix = "s_v3"; QuotaFamily = "Standard Lsv3 Family vCPUs"; cNodeFriendlyName = "Read_Cache_Enabled"};
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

                if ($Development)
                    {
                        Write-Verbose -Message $("Running in Development Mode, using reduced MNode/DNode configuration for faster deployment.")
                        $mNodeSizeObject = @(
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2;     QuotaFamily = "Standard Lsv3 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01;    QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                                [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35;   QuotaFamily = "Standard Laosv4 Family vCPUs"}
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

                Write-Verbose -Message $("Using IP range: {0} for VNet and subnet configuration." -f $IPRangeCIDR)


                # ===============================================================================
                # SKU Configuration Identification and Validation
                # ===============================================================================
                # Set MNode size from parameter values when not using JSON configuration
                if (!$MNodeSize -and $ConfigImport)
                    {
                        ##################### !
                        #! No PV2 support presently
                        #! zero out the mnode values if PV2 is selected
                        #! delete once PV2 is supported
                        ##################### !
                        if(<# DELETE once PV2 Supported>>>#> $ConfigImport.sdp.m_node_type -and $ConfigImport.sdp.m_node_type -eq "PV2" <# !<<<< DELETE once PV2 Supported#> )
                            {
                                Write-Error -Message $("PV2 MNode type is not currently supported. Please select Lsv3 or Laosv4 MNode types.")
                            }
                        else
                            {
                                # ! Keep this Part VVVV
                                $MNodeSize = $ConfigImport.sdp.m_node_sizes
                            }
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
                        Write-Verbose -Message $("MNode-only deployment mode - CNode configuration skipped.")
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
                        Write-Error $("Configuration is not valid. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters (MnodeSizeLsv3/MnodeSizeLaosv4/MNodeSku), or both.")
                        $validationError = $true
                        return
                    }

                if ($cNodeObject)
                    {
                        $cNodeVMSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix
                        Write-Verbose -Message $("Identified CNode SKU: {0}" -f $cNodeVMSku)
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
                        Write-Verbose -Message $("CNode-only deployment mode - no MNode resources will be created.")
                    } `
                elseif (!$CNodeCount -and !$MnodeSizeLsv3 -and !$MnodeSizeLaosv4 -and !$MNodeSku)
                    {
                        Write-Error $("No valid configuration specified. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters (MnodeSizeLsv3/MnodeSizeLaosv4/MNodeSku), or both.")
                        $validationError = $true
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
                # Cross-Subscription Availability Zone Alignment Validation and Assignment
                # ===============================================================================
                # Ensures Availability Zone Alignment testing a deployments across different Azure subscriptions
                # Process: 1. Verify AvailabilityZonePeering feature registration in deployment subscription
                #          2. Query Azure checkZonePeers REST API for Availabiity Zone mapping between subscriptions
                #          3. Analyze Availability Zone peer relationships and ensure alignment unless disabled with -DisableZoneAlignment switch
                # ===============================================================================
                $processSection = "Availability Zone Alignment"
                $sectionStep = ""
                $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                Write-Verbose -Message $("{0}Starting zone alignment check." -f $messagePrefix)
                if ($ZoneAlignmentSubscriptionId -and $Zone -ne "Zoneless" -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                    {
                        $sectionStep = "Check AvailabilityZonePeering Feature"
                        $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                        # Validate AvailabilityZonePeering feature registration - required for cross-subscription zone querying
                        Write-Verbose -Message $("{0}Validating AvailabilityZonePeering feature registration for zone alignment capabilities..." -f $messagePrefix)
                        try
                            {
                                $featureCheckAvailabilityZonePeering = Get-AzProviderFeature -ProviderNamespace "Microsoft.Compute" -FeatureName "AvailabilityZonePeering" -ErrorAction Stop
                                if ($featureCheckAvailabilityZonePeering.RegistrationState -ne "Registered")
                                    {
                                        Write-Warning -Message $("{0}AvailabilityZonePeering feature status: '{1}' in deployment subscription '{2}' - zone alignment cannot be performed." -f $messagePrefix, $featureCheckAvailabilityZonePeering.RegistrationState, $SubscriptionId)
                                        Write-Warning -Message $("{0}To enable zone alignment, register the feature using: Register-AzProviderFeature -FeatureName AvailabilityZonePeering -ProviderNamespace Microsoft.Compute" -f $messagePrefix)
                                        Write-Verbose -Message $("{0}Proceeding without zone alignment due to missing feature registration." -f $messagePrefix)
                                    } `
                                else
                                    {
                                        Write-Verbose -Message $("{0}AvailabilityZonePeering feature status: '{1}' and available for zone alignment operations." -f $messagePrefix, $featureCheckAvailabilityZonePeering.RegistrationState)
                                    }
                            } `
                        catch
                            {
                                Write-Warning -Message $("{0}Failed to validate AvailabilityZonePeering feature status: {1}" -f $messagePrefix, $_.Exception.Message)
                                Write-Verbose -Message $("{0}Proceeding without Availability Zone alignment due to feature validation error." -f $messagePrefix)
                            }

                        # Query Azure checkZonePeers REST API for cross-subscription zone mapping data
                        $sectionStep = "Request Zone Alignment Info"
                        $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                        Write-Verbose -Message $("{0}Requesting availablity zone peer mappings between deployment subscription '{1}' and alignment subscription '{2}' in region '{3}'..." -f $messagePrefix, $SubscriptionId, $ZoneAlignmentSubscriptionId, $Region)

                        # Generate REST API request URI for checkZonePeers endpoint
                        $zoneAlignmentRequestUri = $("https://management.azure.com/subscriptions/{0}/providers/Microsoft.Resources/checkZonePeers?api-version=2022-12-01" -f $SubscriptionId)

                        # Generate request payload with alignment subscription and target region
                        $zoneAlignmentRequestPayload = @{
                                                            subscriptionIds = @( $("subscriptions/{0}" -f $ZoneAlignmentSubscriptionId) )
                                                            location = $Region
                                                        } | ConvertTo-Json

                        try
                            {
                                # Call Azure REST API to retrieve zone peer relationship data
                                Write-Verbose -Message $("{0}Calling checkZonePeers REST API endpoint..." -f $messagePrefix)
                                $zoneAlignmentResponse = Invoke-AzRestMethod -Method Post -Uri $zoneAlignmentRequestUri -Payload $zoneAlignmentRequestPayload -ErrorAction Stop | Select-Object -ExpandProperty Content | ConvertFrom-Json -Depth 100

                                $sectionStep = "Mapping"
                                $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))

                                # Parse zone peer mappings to identify cross subscription Availability Zone alignment
                                Write-Verbose -Message $("{0}Analyzing Availability Zone peer relationships for production deployment testing accuracy..." -f $messagePrefix)
                                foreach ($peer in $zoneAlignmentResponse.availabilityZonePeers)
                                    {
                                        Write-Verbose -Message $("{0}Deployment Subscription Availability Zone '{1}' corresponds to Alignment Subscription Availability Zone '{2}'" -f $messagePrefix, $peer.availabilityZone, $peer.peers.availabilityZone)
                                        # Find the deployment zone that aligns with the current zone in the alignment subscription
                                        if ($peer.peers.availabilityZone -eq $Zone)
                                            {
                                                $alignedZone = $peer.availabilityZone
                                                $remoteZone = $peer.peers.availabilityZone
                                                Write-Verbose -Message $("{0}Found alignment match: Deployment Subscription Availability Zone '{1}' aligns with Alignment Subscription Availability Zone '{2}'" -f $messagePrefix, $alignedZone, $remoteZone)
                                            }
                                    }

                                # Apply zone alignment decision based on analysis results
                                $sectionStep = "Apply Alignment"
                                $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                                if ($DisableZoneAlignment)
                                    {
                                        Write-Verbose -Message $("{0}Zone alignment disabled by parameter - maintaining original Availability Zone '{1}' (Alignment would be Availability Zone '{2}' with Alignment Subscription '{3}')" -f $messagePrefix, $Zone, $alignedZone, $ZoneAlignmentSubscriptionId)
                                    } `
                                elseif ($alignedZone -and $alignedZone -eq $Zone)
                                    {
                                        Write-Verbose -Message $("{0}Zone Aligned: Current Deployment Availability Zone '{1}' is already aligned with  Alignment Subscription Availability Zone '{2}' in Region '{3}'" -f $messagePrefix, $Zone, $alignedZone, $Region)
                                    } `
                                elseif($alignedZone)
                                    {
                                        $originalZone = $Zone
                                        $Zone = $alignedZone
                                        Write-Verbose -Message $("{0}Zone alignment applied: Changed Deployment Availability Zone from '{1}' to '{2}' for alignment with Subscription '{3}' Availability Zone '{4}' in Region '{5}'" -f $messagePrefix, $originalZone, $Zone, $ZoneAlignmentSubscriptionId, $remoteZone, $Region)
                                    } `
                                else
                                    {
                                        Write-Warning -Message $("{0}Alignment data inconclusive: Unable to determine Availability Zone mapping for Region '{1}'. Proceeding with original Availability Zone '{2}' in Deployment Subscription '{3}'" -f $messagePrefix, $Region, $Zone, $SubscriptionId)
                                    }
                            } `
                        catch
                            {
                                Write-Warning -Message $("{0}Alignment API call failed: {1}. Proceeding with original Availability Zone '{2}' in Deployment Subscription '{3}'" -f $messagePrefix, $_.Exception.Message, $Zone, $SubscriptionId)
                                return
                            }
                    } `
                elseif ($Zone -eq "Zoneless")
                    {
                        Write-Verbose -Message $("{0}Alignment skipped: Deployment configured for 'Zoneless' Region - cross-subscription Zone optimization not applicable" -f $messagePrefix)
                    } `
                elseif ($ZoneAlignmentSubscriptionId -eq $SubscriptionId)
                    {
                        Write-Verbose -Message $("{0}Deployment Subscription : '{1}' is identical to Availability Zone Alignment Subscription ID: '{2}'. Availability Zone alignment not necessary." -f $messagePrefix, $Zone)
                    } `
                else
                    {
                        Write-Verbose -Message $("{0}Alignment skipped: No Alignment Subscription specified - using original Availability Zone '{1}' in Region '{2}'" -f $messagePrefix, $Zone, $Region)
                    }


                # ===============================================================================
                # Compute SKU Location and Zone Support Validation
                # ===============================================================================
                # Verify that selected SKUs are supported in the target region and availability zone
                if ($cNodeObject)
                    {
                        $cNodeSupportedSKU = $locationSupportedSKU | Where-Object Name -eq $cNodeVMSku
                        if (!$cNodeSupportedSKU)
                            {
                                Write-Error $("Unable to identify location for CNode SKU: {0} in region: {1}" -f $cNodeVMSku, $Region)
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
                                        Write-Error $("Unable to identify regional support for MNode SKU: {0}{1}{2} in region: {3}" -f $supportedMNodeSKU.vmSkuPrefix, $supportedMNodeSKU.vCPU, $supportedMNodeSKU.vmSkuSuffix, $Region)
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
                                    } `
                                else
                                    {
                                        Write-Warning $("Unable to determine regional support for MNode SKU: {0} in region: {1}." -f $mNodeSupportedSKU.Name, $mNodeSupportedSKU.LocationInfo.Location)
                                    }
                            }
                    }


                # ===============================================================================
                # quota check
                # ===============================================================================
                try
                    {
                        $computeQuotaUsage = Get-AzVMUsage -Location $Region -ErrorAction SilentlyContinue

                        $totalVMCount = 0
                        $totalvCPUCount = 0

                        $insufficientQuota = $false
                        $originalCNodeCount = $CNodeCount
                        $adjustedCNodeCount = $CNodeCount
                        $cNodeQuotaAdjusted = $false

                        # Check if CNodeSize is within the available quota
                        if($cNodeObject)
                            {
                                # Check if CNodeSize is within the available quota
                                $cNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }
                                $availableVCPUs = $cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue
                                $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount

                                if ($availableVCPUs -lt $cNodevCPUCount)
                                    {
                                        # Calculate how many CNodes we can actually deploy
                                        $maxCNodesFromQuota = [Math]::Floor($availableVCPUs / $cNodeObject.vCPU)

                                        if ($maxCNodesFromQuota -gt 0)
                                            {
                                                $adjustedCNodeCount = $maxCNodesFromQuota
                                                $cNodeQuotaAdjusted = $true
                                                $insufficientQuota = $true
                                                $quotaErrorMessage = "{0} {1}" -f $("Partial CNode quota available for SKU: {0}. Requested: {1} CNodes ({2} vCPU), Available quota: {3} vCPU, Deploying: {4} CNode(s)" -f $cNodeVMSku, $CNodeCount, $cNodevCPUCount, $availableVCPUs, $maxCNodesFromQuota), $quotaErrorMessage
                                                Write-Warning $quotaErrorMessage

                                                # Recalculate with adjusted count
                                                $cNodevCPUCount = $cNodeObject.vCPU * $adjustedCNodeCount
                                            } `
                                        else
                                            {
                                                $adjustedCNodeCount = 0
                                                $cNodeQuotaAdjusted = $true
                                                $insufficientQuota = $true
                                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient vCPU quota for CNode SKU: {0}. Required: {1} vCPU per CNode, Available: {2} vCPU. CNode deployment will be skipped." -f $cNodeVMSku, $cNodeObject.vCPU, $availableVCPUs), $quotaErrorMessage
                                                Write-Warning $quotaErrorMessage
                                                $cNodevCPUCount = 0
                                            }
                                    } `
                                else
                                    {
                                        Write-Verbose -Message $("Sufficient vCPU quota available for CNode SKU: {0}. Required: {1} -> Limit: {2}, Consumed: {3}, Available: {4}" -f $cNodeVMSku, $cNodevCPUCount, $cNodeSKUFamilyQuota.Limit, $cNodeSKUFamilyQuota.CurrentValue, $availableVCPUs)
                                    }

                                # increment for generic quota checks
                                $totalVMCount += $adjustedCNodeCount
                                $totalvCPUCount += $cNodevCPUCount
                            }

                        # check for quota for mnodes
                        if($MNodeSize)
                            {
                                $mNodeFamilyCount = $mNodeObject | Group-Object -Property QuotaFamily
                                $mNodeInstanceCount = $MNodeSize | Group-Object | Select-Object Name, Count
                                $mNodeQuotaAdjustments =   @{}

                                foreach ($mNodeFamily in $mNodeFamilyCount)
                                    {
                                        $mNodeFamilyvCPUCount = 0

                                        # total mnode vcpu count for this family
                                        foreach ($mNodeType in $mNodeObjectUnique)
                                            {
                                                if ($mNodeType.QuotaFamily -eq $mNodeFamily.Name)
                                                    {
                                                        $mNodeFamilyvCPUCount += $mNodeType.vCPU * $mNodeType.dNodeCount * $($mNodeInstanceCount | ? Name -eq $mNodeType.PhysicalSize).Count
                                                    }
                                            }

                                        # Check if MNodeSize is within the available quota
                                        $mNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeFamily.Name }
                                        $availableMNodeVCPUs = $mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue

                                        if ($availableMNodeVCPUs -lt $mNodeFamilyvCPUCount)
                                            {
                                                $insufficientQuota = $true

                                                # For each MNode type in this family, calculate partial deployment
                                                foreach ($mNodeType in $mNodeFamily.Group)
                                                    {
                                                        $requestedDNodes = $mNodeType.dNodeCount
                                                        $vCPUPerDNode = $mNodeType.vCPU
                                                        $maxDNodesFromQuota = [Math]::Floor($availableMNodeVCPUs / $vCPUPerDNode)

                                                        if ($maxDNodesFromQuota -gt 0 -and $maxDNodesFromQuota -lt $requestedDNodes)
                                                            {
                                                                $mNodeQuotaAdjustments[$mNodeType.PhysicalSize] =   @{
                                                                                                                        OriginalCount = $requestedDNodes
                                                                                                                        AdjustedCount = $maxDNodesFromQuota
                                                                                                                        SKU = $("{0}{1}{2}" -f $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix)
                                                                                                                    }
                                                                $quotaErrorMessage = "{0} {1}" -f $("Partial MNode quota available for {2} TiB ({3}). Requested: {4} DNodes, Available quota: {5} vCPU, Deploying: {6} DNode(s)" -f $mNodeType.PhysicalSize, $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix, $requestedDNodes, $availableMNodeVCPUs, $maxDNodesFromQuota), $quotaErrorMessage
                                                                Write-Warning $quotaErrorMessage

                                                                $totalVMCount += $maxDNodesFromQuota
                                                                $totalvCPUCount += ($maxDNodesFromQuota * $vCPUPerDNode)
                                                            } `
                                                        elseif ($maxDNodesFromQuota -eq 0)
                                                            {
                                                                $mNodeQuotaAdjustments[$mNodeType.PhysicalSize] =   @{
                                                                                                                        OriginalCount = $requestedDNodes
                                                                                                                        AdjustedCount = 0
                                                                                                                        SKU = $("{0}{1}{2}" -f $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix)
                                                                                                                    }
                                                                $quotaErrorMessage = "{0} {1}" -f $("Insufficient vCPU quota for MNode {2} TiB ({3}). Required: {4} vCPU per DNode, Available: {5} vCPU. MNode group will be skipped." -f $mNodeType.PhysicalSize, $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix, $vCPUPerDNode, $availableMNodeVCPUs), $quotaErrorMessage
                                                                Write-Warning $quotaErrorMessage
                                                            } `
                                                        else
                                                            {
                                                                # Full quota available for this MNode type
                                                                $totalVMCount += $requestedDNodes
                                                                $totalvCPUCount += ($requestedDNodes * $vCPUPerDNode)
                                                            }
                                                    }
                                            } `
                                        else
                                            {
                                                Write-Verbose -Message $("Sufficient vCPU quota available for MNode SKU {0} of Family: {1}. Required: {2} -> Limit: {3}, Consumed: {4}, Available: {5}" -f $(($mNodeFamily.group | % { "{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix }) -join ', '), $mNodeFamily.Name, $mNodeFamilyvCPUCount, $mNodeSKUFamilyQuota.Limit, $mNodeSKUFamilyQuota.CurrentValue, $availableMNodeVCPUs)

                                                # Add full counts
                                                foreach ($mNodeType in $mNodeFamily.Group)
                                                    {
                                                        $totalVMCount += $mNodeType.dNodeCount
                                                        $totalvCPUCount += ($mNodeType.dNodeCount * $mNodeType.vCPU)
                                                    }
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

                        # Summarize quota adjustments and determine if any deployment is possible
                        $quotaAdjustmentMessages = @()
                        $anyDeploymentPossible = $false

                        if($CNodeCount -gt 0)
                            {
                                if($adjustedCNodeCount -gt 0)
                                    {
                                        $anyDeploymentPossible = $true
                                        if($adjustedCNodeCount -lt $originalCNodeCount)
                                            {
                                                $quotaAdjustmentMessages += "  → CNode: Deploying {0} of {1} requested (quota constrained)" -f $adjustedCNodeCount, $originalCNodeCount
                                            } `
                                        else
                                            {
                                                Write-Verbose $("CNode: All {0} requested VMs can be deployed" -f $adjustedCNodeCount)
                                            }
                                    } `
                                else
                                    {
                                        $quotaAdjustmentMessages += "  → CNode: Cannot deploy any VMs due to insufficient quota"
                                    }
                            }

                        if($mNodeQuotaAdjustments.Count -gt 0)
                            {
                                foreach($physicalSize in $mNodeQuotaAdjustments.Keys)
                                    {
                                        $adjustment = $mNodeQuotaAdjustments[$physicalSize]
                                        if($adjustment.AdjustedCount -gt 0)
                                            {
                                                $anyDeploymentPossible = $true
                                                if($adjustment.AdjustedCount -lt $adjustment.OriginalCount)
                                                    {
                                                        $quotaAdjustmentMessages += "  → MNode ({0}): Deploying {1} of {2} requested DNodes (quota constrained)" -f $physicalSize, $adjustment.AdjustedCount, $adjustment.OriginalCount
                                                    } `
                                                else
                                                    {
                                                        Write-Verbose $("MNode ({0}): All {1} requested DNodes can be deployed" -f $physicalSize, $adjustment.AdjustedCount)
                                                    }
                                            } `
                                        else
                                            {
                                                $quotaAdjustmentMessages += "  → MNode ({0}): Cannot deploy any DNodes due to insufficient quota" -f $physicalSize
                                            }
                                    }
                            }

                        # Display quota adjustment summary if any constraints were detected
                        if($quotaAdjustmentMessages.Count -gt 0)
                            {
                                if(-not $anyDeploymentPossible)
                                    {
                                        Write-Warning $("⚠ CRITICAL QUOTA CONSTRAINTS - No VMs can be deployed, but proceeding with environment analysis:")
                                    } `
                                else
                                    {
                                        Write-Warning $("⚠ QUOTA CONSTRAINTS DETECTED - Proceeding with adjusted deployment:")
                                    }
                                $quotaAdjustmentMessages | ForEach-Object { Write-Warning $_ }
                            } `
                        else
                            {
                                Write-Verbose $("All required quotas are available for the specified CNode and MNode configurations.")
                            }

                        # Track deployment mode for reporting purposes
                        if(-not $anyDeploymentPossible)
                            {
                                Write-Warning $("⚠ Zero VM deployment mode: Function will analyze environment and report quota deficiencies without deploying resources.")
                                # Set adjusted counts to 0 to ensure no deployment attempts
                                $adjustedCNodeCount = 0
                            }

                    } `
                catch
                    {
                        Write-Error $("Error occurred while checking compute quota: {0}" -f $_)
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
                        try
                            {
                                $vMImage = Get-AzVMImage -Location $Region -PublisherName $VMImagePublisher -Offer $VMImageOffer -Skus $VMImageSku -Version $VMImageVersion -ErrorAction Stop
                            } `
                        catch
                            {
                                Write-Warning $("Failed to retrieve VM image '{0}' from publisher '{1}' with SKU '{2}': {3}" -f $VMImageOffer, $VMImagePublisher, $VMImageSku, $_.Exception.Message)
                                $vMImage = $null
                            }
                    }

                # if !$VMImage
                if (-not $vMImage)
                    {
                        Write-Error $("The specified VM image '{0}' from publisher '{1}' with SKU '{2}' and version '{3}' is not available in the region '{4}'." -f $VMImageOffer, $VMImagePublisher, $VMImageSku, $VMImageVersion, $Region)
                        $validationError = $true
                        return
                    }

                # ===============================================================================
                # HTML Report Configuration
                # ===============================================================================
                # Enable HTML report by default unless NoHTMLReport switch is specified
                if (-not $NoHTMLReport)
                    {
                        Write-Verbose -Message $("HTML report generation enabled (default behavior). Use -NoHTMLReport to disable.")
                    } `
                else
                    {
                        Write-Verbose -Message $("HTML report generation disabled by -NoHTMLReport switch.")
                    }

                # Configure HTML report output file path with timestamp
                if (-not $NoHTMLReport)
                    {
                        # Ensure the output path is valid and create directory if needed
                        if (-not (Test-Path $ReportOutputPath))
                            {
                                try
                                    {
                                        New-Item -Path $ReportOutputPath -ItemType Directory -Force | Out-Null
                                        Write-Verbose -Message $("Created report output directory: {0}" -f $ReportOutputPath)
                                    } `
                                catch
                                    {
                                        Write-Warning -Message $("Failed to create report output directory '{0}': {1}. Using current directory." -f $ReportOutputPath, $_.Exception.Message)
                                        $ReportOutputPath = (Get-Location).Path
                                    }
                            }

                        $ReportFullPath = Join-Path -Path $ReportOutputPath -ChildPath $("SilkDeploymentReport_{0}.html" -f $StartTime.ToString("yyyyMMdd_HHmmss"))
                        Write-Verbose -Message $("HTML report will be generated at: {0}" -f $ReportFullPath)
                    }


                # ===============================================================================
                # Deployment Configuration Summary
                # ===============================================================================
                Write-Verbose -Message $("=== Silk Azure Deployment Configuration ===")
                Write-Verbose -Message $("Subscription ID: {0}" -f $SubscriptionId)
                Write-Verbose -Message $("Resource Group: {0}" -f $ResourceGroupName)
                Write-Verbose -Message $("Deployment Region: {0}" -f $Region)
                Write-Verbose -Message $("Availability Zone: {0}" -f $Zone)
                Write-Verbose -Message $("Resource Name Prefix: {0}" -f $ResourceNamePrefix)
                Write-Verbose -Message $("Network CIDR Range: {0}" -f $IPRangeCIDR)
                Write-Verbose -Message $("VM Image: {0}" -f $VMImageOffer)

                if ($CNodeCount -gt 0)
                    {
                        if ($adjustedCNodeCount -lt $originalCNodeCount)
                            {
                                Write-Verbose -Message $("CNode Count: {0} (adjusted to {1} due to quota constraints)" -f $originalCNodeCount, $adjustedCNodeCount)
                            } `
                        else
                            {
                                Write-Verbose -Message $("CNode Count: {0}" -f $adjustedCNodeCount)
                            }
                    } `
                else
                    {
                        Write-Verbose -Message $("CNode Count: 0 (MNode-only deployment)")
                    }

                if ($mNodeObject -and $mNodeObject.Count -gt 0)
                    {
                        $mNodeSizeDisplay = ($mNodeObject | ForEach-Object { $_.PhysicalSize }) -join ", "
                        Write-Verbose -Message $("MNode Configuration: {0} TiB" -f $mNodeSizeDisplay)

                        # Show quota adjustments for MNode groups
                        foreach ($physicalSize in $mNodeQuotaAdjustments.Keys)
                            {
                                $adjustment = $mNodeQuotaAdjustments[$physicalSize]
                                if ($adjustment.AdjustedCount -lt $adjustment.OriginalCount)
                                    {
                                        Write-Verbose -Message $("  → {0} TiB: {1} DNodes (adjusted to {2} due to quota constraints)" -f $physicalSize, $adjustment.OriginalCount, $adjustment.AdjustedCount)
                                    }
                            }
                    }

                # identify total dnodes using adjusted counts
                if($mNodeSize)
                    {
                        $totalDNodes = 0
                        foreach ($mNode in $mNodeObject)
                            {
                                $dNodeCount = $mNode.dNodeCount
                                if ($mNodeQuotaAdjustments.ContainsKey($mNode.PhysicalSize))
                                    {
                                        $dNodeCount = $mNodeQuotaAdjustments[$mNode.PhysicalSize].AdjustedCount
                                    }
                                $totalDNodes += $dNodeCount
                            }
                    } `
                else
                    {
                        $totalDNodes = 0
                    }

                if ($adjustedCNodeCount -gt 0 -and $totalDNodes -gt 0)
                    {
                        $totalVMs = $adjustedCNodeCount + $totalDNodes
                        Write-Verbose -Message $("Total VMs to Deploy: {0} ({1} CNodes + {2} DNodes)" -f $totalVMs, $adjustedCNodeCount, $totalDNodes)
                    } `
                elseif ($adjustedCNodeCount -gt 0 -and $totalDNodes -eq 0)
                    {
                        $totalVMs = $adjustedCNodeCount
                        Write-Verbose -Message $("Total VMs to Deploy: {0} (CNode-only: {1})" -f $totalVMs, $adjustedCNodeCount)
                    } `
                else
                    {
                        $totalVMs = $totalDNodes
                        Write-Verbose -Message $("Total VMs to Deploy: {0} (MNode-only: {1} DNodes)" -f $totalVMs, $totalDNodes)
                    }

                if ($Development)
                    {
                        Write-Verbose -Message $("Development Mode: ENABLED (using smaller VM sizes for faster deployment)")
                    } `
                else
                    {
                        Write-Verbose -Message $("Development Mode: DISABLED (deploying production VM SKUs)")
                    }
                Write-Verbose -Message $("==========================================")
            }

        # This block is used to provide record-by-record processing for the function.
        process
            {
                # if there is a validtion error skip deployment
                if ($validationError)
                    {
                        Write-Error $("Validation failed. Please fix the errors and try again.")
                        return
                    }
                # if run cleanup only, skip the process code
                if($RunCleanupOnly)
                    {
                        # If we're only running cleanup, we can skip the rest of the process code
                        return
                    }

                # Check if any VM deployment is possible - skip infrastructure creation if not
                $totalDeployableVMs = $adjustedCNodeCount
                foreach ($mNode in $mNodeObject)
                    {
                        if ($mNodeQuotaAdjustments.ContainsKey($mNode.PhysicalSize))
                            {
                                $totalDeployableVMs += $mNodeQuotaAdjustments[$mNode.PhysicalSize].AdjustedCount
                            } `
                        else
                            {
                                $totalDeployableVMs += $mNode.dNodeCount
                            }
                    }

                if ($totalDeployableVMs -eq 0)
                    {
                        Write-Warning $("⚠ Zero VM deployment scenario detected - Skipping infrastructure creation")
                        Write-Warning $("   No VMs can be deployed due to insufficient quota for all requested node types")
                        Write-Warning $("   Function will complete with quota analysis report only")
                        return
                    }

                $deploymentStarted = $true
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

                        Write-Verbose -Message $("  - Security Impact: Complete network isolation - NO traffic allowed in any direction")

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
                        Write-Verbose -Message $("✓ Network isolation configured: All VMs will be deployed with NO network access")

                        $mGMTSubnetID = $vNET.Subnets | Where-Object { $_.Name -eq $mGMTSubnet.Name } | Select-Object -ExpandProperty Id
                    } `
                catch
                    {
                        Write-Error $("An error occurred while creating shared resource group infrastructure: {0}" -f $_)
                        return
                    }

                # create vm instances
                try
                    {
                        # Clean up any old jobs before starting deployment to better track jobs related to the active run
                        Write-Verbose -Message $("Cleaning up any existing background jobs...")
                        Get-Job | Remove-Job -Force
                        Write-Verbose -Message $("All existing jobs have been removed.")

                        # Initialize job-to-VM mapping for meaningful error reporting
                        $vmJobMapping = @{}

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

                        if($adjustedCNodeCount -gt 0)
                            {
                                # Update progress for availability set creation
                                Write-Progress `
                                    -Status "Creating CNode Infrastructure" `
                                    -CurrentOperation "Creating CNode availability set..." `
                                    -PercentComplete 2 `
                                    -Activity "VM Deployment" `
                                    -Id 1

                                # Check if using existing infrastructure or creating new infrastructure
                                if($ProximityPlacementGroupName -and $AvailabilitySetName)
                                    {
                                        # Using existing infrastructure for deployment validation
                                        Write-Verbose -Message $("Using existing infrastructure: Proximity Placement Group '{0}' and Availability Set '{1}'" -f $ProximityPlacementGroupName, $AvailabilitySetName)

                                        # Reference already validated resources from begin block
                                        $cNodeProximityPlacementGroup = $existingProximityPlacementGroup
                                        $cNodeAvailabilitySet = $existingAvailabilitySet

                                        Write-Verbose -Message $("✓ CNode deployment will target existing Proximity Placement Group '{0}' in region '{1}'" -f $cNodeProximityPlacementGroup.Name, $cNodeProximityPlacementGroup.Location)
                                        Write-Verbose -Message $("✓ CNode deployment will target existing Availability Set '{0}' with {1} fault domains" -f $cNodeAvailabilitySet.Name, $cNodeAvailabilitySet.PlatformFaultDomainCount)
                                    } `
                                else
                                    {
                                        # Creating new infrastructure for deployment
                                        # create cnode proximity placement group including VM SKUs if Zoneless
                                        if($Zone -ne "Zoneless")
                                            {
                                                Write-Verbose -Message $("Creating CNode Proximity Placement Group in region '{0}' with zone '{1}' and VM SKU: {2}" -f $Region, $Zone, $cNodeVMSku)
                                                $cNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -Location $Region `
                                                                            -Zone $Zone `
                                                                            -Name $("{0}-cnode-ppg" -f $ResourceNamePrefix) `
                                                                            -ProximityPlacementGroupType "Standard" `
                                                                            -IntentVMSize $cNodeVMSku
                                            } `
                                        else
                                            {
                                                Write-Verbose -Message $("Creating CNode Proximity Placement Group in region '{0}' without zones" -f $Region)
                                                $cNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -Location $Region `
                                                                            -Name $("{0}-cnode-ppg" -f $ResourceNamePrefix) `
                                                                            -ProximityPlacementGroupType "Standard"
                                            }

                                        Write-Verbose -Message $("✓ CNode Proximity Placement Group '{0}' created" -f $cNodeProximityPlacementGroup.Name)

                                        # create an availability set for the c-node group
                                        $cNodeAvailabilitySet = New-AzAvailabilitySet `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Name $("{0}-cnode-avset" -f $ResourceNamePrefix) `
                                                            -Location $Region `
                                                            -ProximityPlacementGroupId $cNodeProximityPlacementGroup.Id `
                                                            -Sku "Aligned" `
                                                            -PlatformFaultDomainCount $maximumFaultDomains `
                                                            -PlatformUpdateDomainCount 20

                                        Write-Verbose -Message $("✓ CNode availability set '{0}' created." -f $cNodeAvailabilitySet.Name)
                                    }

                                # CNode creation phase with updated progress
                                Write-Progress `
                                    -Status "Creating CNodes" `
                                    -CurrentOperation $("Preparing to create {0} CNode VMs..." -f $adjustedCNodeCount) `
                                    -PercentComplete 5 `
                                    -Activity "VM Deployment" `
                                    -Id 1

                                for ($cNode = 1; $cNode -le $adjustedCNodeCount; $cNode++)
                                    {
                                # Calculate CNode SKU for display
                                $currentCNodeSku = "{0}" -f $CNodeSku

                                # Update sub-progress for CNode creation
                                Write-Progress `
                                    -Status $("Creating CNode {0} of {1} ({2})" -f $cNode, $adjustedCNodeCount, $currentCNodeSku) `
                                    -CurrentOperation $("Configuring CNode {0} with SKU {1}..." -f $cNode, $currentCNodeSku) `
                                    -PercentComplete $(($cNode / $adjustedCNodeCount) * 100) `
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
                                # Use availability sets
                                $cNodeConfig = New-AzVMConfig `
                                                -VMName $("{0}-cnode-{1:D2}" -f $ResourceNamePrefix, $cNode) `
                                                -VMSize $cNodeVMSku `
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
                                        # Suppress warnings specifically for VM creation
                                        $cNodeJob = New-AzVM `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -VM $cNodeConfig `
                                                        -AsJob `
                                                        -WarningAction SilentlyContinue

                                        # Track job-to-VM mapping for meaningful error reporting
                                        $vmJobMapping[$cNodeJob.Id] = @{
                                            VMName = $("{0}-cnode-{1:D2}" -f $ResourceNamePrefix, $cNode)
                                            VMSku = $cNodeVMSku
                                            NodeType = "CNode"
                                            NodeNumber = $cNode
                                        }

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
                                        Write-Verbose -Message $("✓ CNode availability set '{0}' is assigned to proximity placement group '{1}'." -f $cNodeAvailabilitySetComplete.Name, $cNodeProximityPlacementGroup.Name)
                                    }

                                # Clean up CNode creation sub-progress bar as this phase is complete
                                Write-Progress -Activity "CNode Creation" -Id 2 -Completed
                            }

                        # Skip MNode deployment if quota is insufficient
                        if ($mNodeObject)
                            {
                                $dNodeStartCount = 0
                                $currentMNode = 0
                                foreach ($mNode in $mNodeObject)
                                    {
                                $currentMNode++

                                # Calculate MNode SKU and physical size for display
                                $currentMNodeSku = "{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix
                                $currentMNodePhysicalSize = $mNode.PhysicalSize

                                # Check if this MNode group has quota adjustments
                                $currentDNodeCount = $mNode.dNodeCount
                                if ($mNodeQuotaAdjustments.ContainsKey($currentMNodePhysicalSize))
                                    {
                                        $currentDNodeCount = $mNodeQuotaAdjustments[$currentMNodePhysicalSize].AdjustedCount
                                        if ($currentDNodeCount -eq 0)
                                            {
                                                Write-Warning $("⚠ Skipping MNode group {0} ({1} TiB) - No quota available for deployment" -f $currentMNode, $currentMNodePhysicalSize)
                                                continue
                                            }
                                    }

                                # create mnode proximity placement group including VM SKUs if Zoneless
                                if($Zone -ne "Zoneless")
                                    {
                                        Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' with zone '{1}' and VM SKUs: {2}" -f $Region, $Zone, $currentMNodeSku)
                                        $mNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                        -ResourceGroupName $ResourceGroupName `
                                                                        -Location $Region `
                                                                        -Zone $Zone `
                                                                        -Name $("{0}-mNode-{1}-ppg" -f $ResourceNamePrefix, $currentMNode) `
                                                                        -ProximityPlacementGroupType "Standard" `
                                                                        -IntentVMSize $currentMNodeSku
                                    } `
                                else
                                    {
                                        Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' without zones" -f $Region)
                                        $mNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                        -ResourceGroupName $ResourceGroupName `
                                                                        -Location $Region `
                                                                        -Name $("{0}-mNode-{1}-ppg" -f $ResourceNamePrefix, $currentMNode) `
                                                                        -ProximityPlacementGroupType "Standard"
                                    }

                                Write-Verbose -Message $("✓ Proximity Placement Group '{0}' created" -f $mNodeProximityPlacementGroup.Name)

                                # create availability set for current mNode
                                $mNodeAvailabilitySet = New-AzAvailabilitySet `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Location $Region `
                                                            -Name $("{0}-mNode-{1}-avset" -f $ResourceNamePrefix, $currentMNode) `
                                                            -ProximityPlacementGroupId $mNodeProximityPlacementGroup.Id `
                                                            -Sku "Aligned" `
                                                            -PlatformFaultDomainCount $maximumFaultDomains `
                                                            -PlatformUpdateDomainCount 20

                                Write-Verbose -Message $("✓ Availability Set '{0}' created" -f $mNodeAvailabilitySet.Name)

                                # Update main progress for MNode group
                                $processedCNodes = $adjustedCNodeCount
                                $processedDNodes = $dNodeStartCount
                                $totalProcessed = $processedCNodes + $processedDNodes
                                $mainPercentComplete = [Math]::Min([Math]::Round(($totalProcessed / $totalVMs) * 100), 90)

                                Write-Progress `
                                    -Status $("Processing MNode Group {0} of {1} - {2} TiB ({3})" -f $currentMNode, $mNodeObject.Count, $currentMNodePhysicalSize, $currentMNodeSku) `
                                    -CurrentOperation $("Creating {0} DNodes for {1} TiB MNode..." -f $currentDNodeCount, $currentMNodePhysicalSize) `
                                    -PercentComplete $mainPercentComplete `
                                    -Activity "VM Deployment" `
                                    -Id 1

                                for ($dNode = 1; $dNode -le $currentDNodeCount; $dNode++)
                                    {
                                        # Update sub-progress for DNode creation
                                        Write-Progress `
                                            -Status $("Creating DNode {0} of {1} - {2} TiB ({3})" -f $dNode, $currentDNodeCount, $currentMNodePhysicalSize, $currentMNodeSku) `
                                            -CurrentOperation $("Configuring DNode {0} with SKU {1}..." -f ($dNode + $dNodeStartCount), $currentMNodeSku) `
                                            -PercentComplete $(($dNode / $currentDNodeCount) * 100) `
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
                                                # Suppress warnings specifically for VM creation
                                                $dNodeJob = New-AzVM `
                                                                -ResourceGroupName $ResourceGroupName `
                                                                -Location $Region `
                                                                -VM $dNodeConfig `
                                                                -AsJob `
                                                                -WarningAction SilentlyContinue

                                                # Track job-to-VM mapping for meaningful error reporting
                                                $vmJobMapping[$dNodeJob.Id] =  @{
                                                                                    VMName = $("{0}-dnode-{1:D2}" -f $ResourceNamePrefix, $dNodeNumber)
                                                                                    VMSku = $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix)
                                                                                    NodeType = "DNode"
                                                                                    NodeNumber = $dNodeNumber
                                                                                    MNodeGroup = $currentMNode
                                                                                    MNodePhysicalSize = $currentMNodePhysicalSize
                                                                                }

                                                Write-Verbose -Message $("✓ DNode {0} VM creation job started successfully" -f $dNodeNumber)
                                            } `
                                        catch
                                            {
                                                Write-Error $("✗ Failed to start DNode {0} VM creation: {1}" -f $dNodeNumber, $_.Exception.Message)
                                            }
                                    }

                                if ($mNodeAvailabilitySet)
                                    {
                                        # get the mnode availability set to assess its state
                                        $mNodeAvailabilitySetComplete = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $mNodeAvailabilitySet.Name
                                        Write-Verbose -Message $("✓ MNode availability set '{0}' created with {1} MNodes." -f $mNodeAvailabilitySetComplete.Name, $mNodeAvailabilitySetComplete)
                                        Write-Verbose -Message $("✓ MNode availability set '{0}' is assigned to proximity placement group '{1}'." -f $mNodeAvailabilitySetComplete.Name, $mNodeProximityPlacementGroup.Name)
                                    }

                                $mNodeProximityPlacementGroup = $null
                                $dNodeStartCount += $currentDNodeCount

                                # Clean up this MNode group's sub-progress bar as it's complete
                                Write-Progress -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) -Id 3 -Completed
                            }
                            }

                        # ========================================================================================================
                        # begin vm creation job monitoring
                        # ========================================================================================================
                        # Initialize deployment validation tracking for reporting
                        $deploymentValidationResults = @()

                        # Validate all network interfaces were created successfully
                        Write-Verbose -Message $("✓ All network interfaces created successfully: {0} total NICs" -f (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }).Count)

                        # Wait for all VMs to be created - Final phase of VM deployment
                        $allVMJobs = Get-Job

                        # Update main progress to show completion phase and immediately show monitoring sub-progress
                        Write-Progress `
                            -Status "Monitoring VM Creation Jobs" `
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
                        $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                        $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
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
                                $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                                $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                                $completionPercent = [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100)

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
                                $runningJobs.Count -gt 0
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

                        # Analyze failed jobs AFTER monitoring is complete
                        $finalVMJobs = Get-Job
                        $failedJobs = $finalVMJobs | Where-Object { $_.State -eq 'Failed' }

                        if ($failedJobs.Count -gt 0)
                            {
                                foreach ($failedJob in $failedJobs)
                                    {
                                        # Get the job error details and categorize the failure
                                        $jobErrorRaw = Receive-Job -Job $failedJob 2>&1
                                        $jobErrorString = $jobErrorRaw | Out-String

                                        # Extract VM details from job mapping
                                        $vmDetails = $vmJobMapping[$failedJob.Id]
                                        $vmName = if ($vmDetails) { $vmDetails.VMName } else { "Unknown VM" }
                                        $vmSku = if ($vmDetails) { $vmDetails.VMSku } else { "Unknown SKU" }

                                        # Extract meaningful deployment validation information
                                        $errorCode = ""
                                        $errorMessage = ""
                                        $failureCategory = "Unknown"
                                        $alternativeZones = @()

                                        if ($jobErrorString)
                                            {
                                                # Look for specific Azure error patterns
                                                if ($jobErrorString -match "ErrorCode[:\s]*([^\s,\r\n]+)")
                                                    {
                                                        $errorCode = $matches[1]
                                                    }
                                                if ($jobErrorString -match "ErrorMessage[:\s]*([^\r\n]+)")
                                                    {
                                                        $errorMessage = $matches[1].Trim()
                                                        # Clean up common Azure error suffixes
                                                        $errorMessage = $errorMessage -replace "\s*Read more about.*$", ""
                                                        $errorMessage = $errorMessage -replace "\s*For more information.*$", ""
                                                    }

                                                # Also look for allocation failure patterns
                                                if ($jobErrorString -match "AllocationFailed" -or $jobErrorString -match "allocation.*failed")
                                                    {
                                                        $errorCode = "AllocationFailed"
                                                        if ([string]::IsNullOrWhiteSpace($errorMessage))
                                                            {
                                                                $errorMessage = "VM allocation failed due to insufficient capacity"
                                                            }
                                                    }

                                                # Categorize the failure type for better reporting
                                                if ($errorCode -eq "AllocationFailed" -or $errorMessage -match "sufficient capacity|allocation failed")
                                                    {
                                                        $failureCategory = "No SKU Capacity Available"
                                                        if ([string]::IsNullOrWhiteSpace($errorMessage))
                                                            {
                                                                $errorMessage = "No capacity available for this SKU in the zone/region"
                                                            }
                                                    } `
                                                elseif ($errorCode -match "Quota|quota" -or $errorMessage -match "quota|limit")
                                                    {
                                                        $failureCategory = "Quota Exceeded"
                                                    } `
                                                elseif ($errorCode -match "SKU|sku" -or $errorMessage -match "sku|size")
                                                    {
                                                        $failureCategory = "SKU Support"

                                                        # For SKU support issues, check if SKU is supported in other zones within the region
                                                        if ($vmSku)
                                                            {
                                                                $skuInfo = Get-AzComputeResourceSku | Where-Object { $_.Name -eq $vmSku -and $_.LocationInfo.Location -eq $Region }
                                                                if ($skuInfo -and $skuInfo.LocationInfo.Zones -and $skuInfo.LocationInfo.Zones.Count -gt 0)
                                                                    {
                                                                        $alternativeZones = $skuInfo.LocationInfo.Zones | Where-Object { $_ -ne $Zone }
                                                                    }
                                                            }
                                                    } `
                                                else
                                                    {
                                                        $failureCategory = "Other"
                                                    }

                                                # Fallback to extract any error message if specific patterns not found
                                                if ([string]::IsNullOrWhiteSpace($errorMessage))
                                                    {
                                                        # Try to find any meaningful error text
                                                        $errorLines = $jobErrorString -split "`n" | Where-Object { $_ -match "error|failed|exception" -and $_ -notmatch "^VERBOSE:|^DEBUG:" } | Select-Object -First 3
                                                        if ($errorLines)
                                                            {
                                                                $errorMessage = ($errorLines -join "; ").Trim()
                                                                # Limit error message length for readability
                                                                if ($errorMessage.Length -gt 300)
                                                                    {
                                                                        $errorMessage = $errorMessage.Substring(0, 300) + "..."
                                                                    }
                                                            } `
                                                        else
                                                            {
                                                                $errorMessage = "Deployment failed - check Azure portal for detailed error information"
                                                            }
                                                    }
                                            } `
                                        else
                                            {
                                                $errorMessage = "Deployment failed without detailed information"
                                                $failureCategory = "Unknown"
                                            }

                                        # Store deployment validation result for reporting
                                        $deploymentValidationResults += [PSCustomObject]@{
                                            VMName = $vmName
                                            VMSku = $vmSku
                                            JobName = $failedJob.Name
                                            ErrorCode = $errorCode
                                            ErrorMessage = $errorMessage
                                            FailureCategory = $failureCategory
                                            AlternativeZones = $alternativeZones
                                            TestedZone = $Zone
                                            TestedRegion = $Region
                                            Timestamp = $StartTime
                                        }

                                        # Log deployment validation findings appropriately based on failure type
                                        if ($failureCategory -eq "No SKU Capacity Available")
                                            {
                                                Write-Verbose -Message $("⚠ No SKU Capacity available for deployment - VM {0} ({1}): {2}" -f $vmName, $vmSku, $errorMessage)
                                            } `
                                        elseif ($failureCategory -eq "Quota Exceeded")
                                            {
                                                Write-Warning -Message $("Quota limitation detected for VM {0} ({1}): {2}" -f $vmName, $vmSku, $errorMessage)
                                            } `
                                        elseif ($failureCategory -eq "SKU Support")
                                            {
                                                Write-Warning -Message $("SKU support issue detected for VM {0} ({1}): {2}" -f $vmName, $vmSku, $errorMessage)
                                            } `
                                        else
                                            {
                                                Write-Warning -Message $("Deployment validation finding for VM {0} ({1}): {2}" -f $vmName, $vmSku, $errorMessage)
                                            }
                                    }
                            }

                    } `
                catch
                    {
                        Write-Warning -Message $("Error occurred while creating VMs: {0}" -f $_)

                        # Clear all active Write-Progress bars on error
                        Write-Progress -Id 1 -Activity $("VM Deployment") -Completed
                        Write-Progress -Id 2 -Activity $("CNode Creation") -Completed
                        Write-Progress -Id 3 -Activity $("DNode Creation") -Completed
                        Write-Progress -Id 4 -Activity $("Sub-task") -Completed
                    }

                # clean up jobs
                Get-Job | Remove-Job -Force | Out-Null

                # ===============================================================================
                # Console Output Stabilization
                # ===============================================================================
                # Ensure all progress updates are complete before displaying reports
                Start-Sleep -Milliseconds 250
                [System.Console]::Out.Flush()

                # get timespan to report on deployment duration
                $DeploymentTimespan = New-TimeSpan -Start $StartTime -End (Get-Date)

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
                for ($cNode = 1; $cNode -le $adjustedCNodeCount; $cNode++)
                    {
                        $expectedVMName = "$ResourceNamePrefix-cnode-{0:D2}" -f $cNode
                        $expectedNICName = "$ResourceNamePrefix-cnode-mgmt-nic-{0:D2}" -f $cNode

                        $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                        $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                        # Determine availability set status
                        $avSetStatus = if ($vm -and $vm.AvailabilitySetReference) { "CNode AvSet" } else { "Not Assigned" }

                        # Determine VM provisioning status and check for validation findings
                        $vmValidationFinding = $deploymentValidationResults | Where-Object { $_.VMName -eq $expectedVMName -or $_.VMName -like "*$expectedVMName*" }
                        $vmStatus = if (-not $vm)
                                        {
                                            if ($vmValidationFinding)
                                                {
                                                    "✗ Not Found ($($vmValidationFinding.FailureCategory))"
                                                }
                                            else
                                                {
                                                    "✗ Not Found"
                                                }
                                        } `
                                    elseif ($vm.ProvisioningState -eq "Succeeded")
                                        {
                                            "✓ Deployed"
                                        } `
                                    elseif ($vm.ProvisioningState -eq "Failed")
                                        {
                                            if ($vmValidationFinding)
                                                {
                                                    "✗ Failed ($($vmValidationFinding.FailureCategory))"
                                                }
                                            else
                                                {
                                                    "✗ Failed"
                                                }
                                        } `
                                    elseif ($vm.ProvisioningState -eq "Creating" -or $vm.ProvisioningState -eq "Running")
                                        {
                                            "⚠ In Progress"
                                        } `
                                    else
                                        {
                                            "⚠ $($vm.ProvisioningState)"
                                        }

                        $deploymentReport +=  [PSCustomObject]@{
                                                                    ResourceType = "CNode"
                                                                    GroupNumber = "CNode Group"
                                                                    NodeNumber = $cNode
                                                                    VMName = $expectedVMName
                                                                    ExpectedSKU = $cNodeVMSku
                                                                    DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                                                                    VMStatus = $vmStatus
                                                                    ProvisioningState = if ($vm) { $vm.ProvisioningState } else { "Not Found" }
                                                                    NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                    AvailabilitySet = $avSetStatus
                                                                    ValidationFinding = if ($vmValidationFinding) { $vmValidationFinding.ErrorMessage } else { "" }
                                                                    FailureCategory = if ($vmValidationFinding) { $vmValidationFinding.FailureCategory } else { "" }
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

                        # Check if this MNode group has quota adjustments
                        $reportDNodeCount = $mNode.dNodeCount
                        if ($mNodeQuotaAdjustments.ContainsKey($currentMNodePhysicalSize))
                            {
                                $reportDNodeCount = $mNodeQuotaAdjustments[$currentMNodePhysicalSize].AdjustedCount
                            }

                        for ($dNode = 1; $dNode -le $reportDNodeCount; $dNode++)
                            {
                                $dNodeNumber = $dNode + $dNodeStartCount
                                $expectedVMName = "$ResourceNamePrefix-dnode-{0:D2}" -f $dNodeNumber
                                $expectedNICName = "$ResourceNamePrefix-dnode-{0:D2}-mgmt-nic" -f $dNodeNumber

                                $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                                $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                                # Determine availability set status for DNode
                                $avSetStatus = if ($vm -and $vm.AvailabilitySetReference) { "MNode $currentMNode AvSet" } else { "Not Assigned" }

                                # Determine VM provisioning status and check for validation findings
                                $vmValidationFinding = $deploymentValidationResults | Where-Object { $_.VMName -eq $expectedVMName -or $_.VMName -like "*$expectedVMName*" }
                                $vmStatus = if (-not $vm)
                                                {
                                                    if ($vmValidationFinding)
                                                        {
                                                            "✗ Not Found ($($vmValidationFinding.FailureCategory))"
                                                        } `
                                                    else
                                                        {
                                                            "✗ Not Found"
                                                        }
                                                } `
                                            elseif ($vm.ProvisioningState -eq "Succeeded")
                                                {
                                                    "✓ Deployed"
                                                } `
                                            elseif ($vm.ProvisioningState -eq "Failed")
                                                {
                                                    if ($vmValidationFinding)
                                                        {
                                                            "✗ Failed ($($vmValidationFinding.FailureCategory))"
                                                        }
                                                    else
                                                        {
                                                            "✗ Failed"
                                                        }
                                                } `
                                            elseif ($vm.ProvisioningState -eq "Creating" -or $vm.ProvisioningState -eq "Running")
                                                {
                                                    "⚠ In Progress"
                                                } `
                                            else
                                                {
                                                    "⚠ $($vm.ProvisioningState)"
                                                }

                                $deploymentReport +=   [PSCustomObject]@{
                                                                            ResourceType = "DNode"
                                                                            GroupNumber = $("MNode {0} ({1} TiB)" -f $currentMNode, $currentMNodePhysicalSize)
                                                                            NodeNumber = $dNodeNumber
                                                                            VMName = $expectedVMName
                                                                            ExpectedSKU = $reportMNodeSku
                                                                            DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                                                                            VMStatus = $vmStatus
                                                                            ProvisioningState = if ($vm) { $vm.ProvisioningState } else { "Not Found" }
                                                                            NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                            AvailabilitySet = $avSetStatus
                                                                            ValidationFinding = if ($vmValidationFinding) { $vmValidationFinding.ErrorMessage } else { "" }
                                                                            FailureCategory = if ($vmValidationFinding) { $vmValidationFinding.FailureCategory } else { "" }
                                                                        }
                            }

                        $dNodeStartCount += $reportDNodeCount
                    }

                # ===============================================================================
                # Report Data Processing and Analysis
                # ===============================================================================
                # Centralized data processing for both console and HTML reports
                # This section calculates all report data once to ensure consistency

                # Infrastructure Summary Data
                $totalExpectedVMs = $CNodeCount + ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum
                $successfulVMs = ($deploymentReport | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                $failedVMs = ($deploymentReport | Where-Object { $_.VMStatus -like "*Failed*" }).Count
                $nonSuccessfulVMs = $deploymentReport | Where-Object { $_.ProvisioningState -ne "Succeeded" -and $_.ProvisioningState -ne "Not Found" }

                # Zone Alignment Reporting Information
                # Capture zone alignment details for console and HTML reporting
                $zoneAlignmentInfo = @{
                    AlignmentPerformed = $false
                    AlignmentDisabled = $DisableZoneAlignment
                    AlignmentSubscription = $ZoneAlignmentSubscriptionId
                    OriginalZone = ""
                    FinalZone = $Zone
                    ZoneMappings = @()
                    AlignmentReason = "Not applicable"
                }

                # Determine alignment status and populate reporting information
                if ($ZoneAlignmentSubscriptionId -and $Zone -ne "Zoneless" -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                    {
                        $zoneAlignmentInfo.AlignmentSubscription = $ZoneAlignmentSubscriptionId

                        if ($originalZone)
                            {
                                $zoneAlignmentInfo.AlignmentPerformed = $true
                                $zoneAlignmentInfo.OriginalZone = $originalZone
                                $zoneAlignmentInfo.AlignmentReason = "Zone alignment applied"
                            } `
                        elseif ($DisableZoneAlignment -and $alignedZone)
                            {
                                $zoneAlignmentInfo.AlignmentReason = "Zone alignment available but disabled by parameter"
                                $zoneAlignmentInfo.OriginalZone = $Zone
                            } `
                        elseif ($alignedZone -eq $Zone)
                            {
                                $zoneAlignmentInfo.AlignmentReason = "Zone already aligned - no adjustment needed"
                            } `
                        else
                            {
                                $zoneAlignmentInfo.AlignmentReason = "Zone alignment data unavailable or inconclusive"
                            }

                        # Capture zone mappings for reporting if available
                        if ($zoneAlignmentResponse -and $zoneAlignmentResponse.availabilityZonePeers)
                            {
                                foreach ($peer in $zoneAlignmentResponse.availabilityZonePeers)
                                    {
                                        $zoneAlignmentInfo.ZoneMappings += [PSCustomObject]@{
                                            DeploymentZone = $peer.availabilityZone
                                            AlignmentZone = $peer.peers.availabilityZone
                                        }
                                    }
                            }
                    } `
                elseif ($Zone -eq "Zoneless")
                    {
                        $zoneAlignmentInfo.AlignmentReason = "Zoneless deployment - alignment not applicable"
                    } `
                elseif ($ZoneAlignmentSubscriptionId -eq $SubscriptionId)
                    {
                        $zoneAlignmentInfo.AlignmentReason = "Same subscription deployment - alignment not necessary"
                    } `
                else
                    {
                        $zoneAlignmentInfo.AlignmentReason = "No alignment subscription specified"
                    }

                # SKU Support Analysis Data
                $skuSupportData = @()

                # CNode SKU Support Analysis
                if($cNodeObject)
                    {
                        $cNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $cNodeVMSku }
                        $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount
                        $cNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }

                        # Determine zone support status
                        if ($cNodeSupportedSKU)
                            {
                                if ($Zone -eq "Zoneless")
                                    {
                                        $cNodeZoneSupport = "✓ Supported (Zoneless deployment)"
                                        $cNodeZoneSupportStatus = "Success"
                                    } `
                                elseif ($cNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                    {
                                        $cNodeZoneSupport = "✓ Supported in target zone $Zone"
                                        $cNodeZoneSupportStatus = "Success"
                                    } `
                                else
                                    {
                                        $cNodeZoneSupport = "⚠ Not supported in target zone $Zone"
                                        $cNodeZoneSupportStatus = "Warning"
                                    }
                            } `
                        else
                            {
                                $cNodeZoneSupport = "✗ Not supported in region"
                                $cNodeZoneSupportStatus = "Error"
                            }

                        $skuSupportData += [PSCustomObject]@{
                            ComponentType = "CNode"
                            SKUName = $cNodeVMSku
                            SupportedSKU = $cNodeSupportedSKU
                            ZoneSupport = $cNodeZoneSupport
                            ZoneSupportStatus = $cNodeZoneSupportStatus
                            vCPUCount = $cNodevCPUCount
                            SKUFamilyQuota = $cNodeSKUFamilyQuota
                            AvailableZones = if ($cNodeSupportedSKU.LocationInfo.Zones) { $cNodeSupportedSKU.LocationInfo.Zones } else { @() }
                        }
                    }

                # MNode SKU Support Analysis
                if($MNodeSize -and $mNodeObjectUnique)
                    {
                        foreach ($mNodeType in $mNodeObjectUnique)
                            {
                                $mNodeSkuName = "{0}{1}{2}" -f $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix
                                $mNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $mNodeSkuName }
                                $mNodeInstanceCount = $MNodeSize | Group-Object | Select-Object Name, Count
                                $mNodevCPUCount = $mNodeType.vCPU * $mNodeType.dNodeCount * ($mNodeInstanceCount | Where-Object { $_.Name -eq $mNodeType.PhysicalSize }).Count
                                $mNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeType.QuotaFamily }

                                # Determine zone support status
                                if ($mNodeSupportedSKU)
                                    {
                                        if ($Zone -eq "Zoneless")
                                            {
                                                $mNodeZoneSupport = "✓ Supported (Zoneless deployment)"
                                                $mNodeZoneSupportStatus = "Success"
                                            } `
                                        elseif ($mNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                            {
                                                $mNodeZoneSupport = "✓ Supported in target zone $Zone"
                                                $mNodeZoneSupportStatus = "Success"
                                            } `
                                        else
                                            {
                                                $mNodeZoneSupport = "⚠ Not supported in target zone $Zone"
                                                $mNodeZoneSupportStatus = "Warning"
                                            }
                                    } `
                                else
                                    {
                                        $mNodeZoneSupport = "✗ Not supported in region"
                                        $mNodeZoneSupportStatus = "Error"
                                    }

                                $instanceCount = ($mNodeInstanceCount | Where-Object { $_.Name -eq $mNodeType.PhysicalSize }).Count
                                $skuSupportData += [PSCustomObject]@{
                                    ComponentType = "MNode"
                                    SKUName = $mNodeSkuName
                                    SupportedSKU = $mNodeSupportedSKU
                                    ZoneSupport = $mNodeZoneSupport
                                    ZoneSupportStatus = $mNodeZoneSupportStatus
                                    vCPUCount = $mNodevCPUCount
                                    SKUFamilyQuota = $mNodeSKUFamilyQuota
                                    InstanceCount = $instanceCount
                                    PhysicalSize = $mNodeType.PhysicalSize
                                    AvailableZones = if ($mNodeSupportedSKU.LocationInfo.Zones) { $mNodeSupportedSKU.LocationInfo.Zones } else { @() }
                                }
                            }
                    }

                # Quota Analysis Data
                $quotaAnalysisData = @()

                # Virtual Machine Quota
                $totalVMQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Virtual Machines" }
                if ($totalVMQuota)
                    {
                        $availableVMQuota = $totalVMQuota.Limit - $totalVMQuota.CurrentValue
                        $vmQuotaStatus = if ($availableVMQuota -ge $totalExpectedVMs) { "✓ Sufficient" } else { "✗ Insufficient" }
                        $vmQuotaStatusLevel = if ($availableVMQuota -ge $totalExpectedVMs) { "Success" } else { "Error" }

                        $quotaAnalysisData += [PSCustomObject]@{
                            QuotaType = "Virtual Machines"
                            Required = $totalExpectedVMs
                            Available = $availableVMQuota
                            Limit = $totalVMQuota.Limit
                            Status = $vmQuotaStatus
                            StatusLevel = $vmQuotaStatusLevel
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
                        $vcpuQuotaStatus = if ($availableVCPUQuota -ge $totalvCPUCount) { "✓ Sufficient" } else { "✗ Insufficient" }
                        $vcpuQuotaStatusLevel = if ($availableVCPUQuota -ge $totalvCPUCount) { "Success" } else { "Error" }

                        $quotaAnalysisData += [PSCustomObject]@{
                            QuotaType = "Regional vCPUs"
                            Required = $totalvCPUCount
                            Available = $availableVCPUQuota
                            Limit = $totalVCPUQuota.Limit
                            Status = $vcpuQuotaStatus
                            StatusLevel = $vcpuQuotaStatusLevel
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
                        $avsetQuotaStatus = if ($availableAvSetQuota -ge $totalAvailabilitySetCount) { "✓ Sufficient" } else { "✗ Insufficient" }
                        $avsetQuotaStatusLevel = if ($availableAvSetQuota -ge $totalAvailabilitySetCount) { "Success" } else { "Error" }

                        $quotaAnalysisData += [PSCustomObject]@{
                            QuotaType = "Availability Sets"
                            Required = $totalAvailabilitySetCount
                            Available = $availableAvSetQuota
                            Limit = $totalAvailabilitySetQuota.Limit
                            Status = $avsetQuotaStatus
                            StatusLevel = $avsetQuotaStatusLevel
                        }
                    }

                # Infrastructure Resources Data
                $deployedPPG = Get-AzProximityPlacementGroup -ResourceGroupName $ResourceGroupName -Name $("{0}*-ppg" -f $ResourceNamePrefix) -ErrorAction SilentlyContinue
                $deployedAvailabilitySets = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                $totalResourcesCreated = $deployedVMs.Count + $deployedNICs.Count + $(if($deployedPPG){1}else{0}) + $deployedAvailabilitySets.Count + $(if($deployedVNet){1}else{0}) + $(if($deployedNSG){1}else{0})

                # Deployment Validation Findings Analysis
                $validationFindings = @{
                    NoCapacityIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "No SKU Capacity Available" }
                    QuotaIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Quota Exceeded" }
                    SKUSupportIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "SKU Support" }
                    OtherIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Other" }
                }

                # ===============================================================================
                # SKU Support and Quota Availability Report
                # ===============================================================================
                Write-Host "`n=== SKU Support and Quota Availability Report ===" -ForegroundColor Cyan

                # CNode SKU Support Report
                if($cNodeObject)
                    {
                        $cNodeData = $skuSupportData | Where-Object { $_.ComponentType -eq "CNode" }

                        Write-Host "`nCNode SKU Support:" -ForegroundColor Yellow
                        Write-Host $("  SKU: {0}" -f $cNodeData.SKUName)
                        Write-Host $("  Region: {0}" -f $Region)

                        switch ($cNodeData.ZoneSupportStatus)
                            {
                                "Success" { Write-Host "  Zone Support: $($cNodeData.ZoneSupport)" -ForegroundColor Green }
                                "Warning" { Write-Host "  Zone Support: $($cNodeData.ZoneSupport)" -ForegroundColor Yellow }
                                "Error" { Write-Host "  Region Support: $($cNodeData.ZoneSupport)" -ForegroundColor Red }
                            }

                        if ($cNodeData.AvailableZones.Count -gt 0 -and $cNodeData.ZoneSupportStatus -ne "Error")
                            {
                                Write-Host $("  All Available Zones: {0}" -f ($cNodeData.AvailableZones -join ", "))
                            }
                    }

                # MNode SKU Support Report
                if($MNodeSize -and $mNodeObjectUnique)
                    {
                        $mNodeData = $skuSupportData | Where-Object { $_.ComponentType -eq "MNode" }
                        foreach ($mNodeTypeData in $mNodeData)
                            {
                                Write-Host $("`n{0} x MNode SKU Support ({1} TiB):" -f $mNodeTypeData.InstanceCount, $mNodeTypeData.PhysicalSize) -ForegroundColor Yellow
                                Write-Host $("  SKU: {0}" -f $mNodeTypeData.SKUName)
                                Write-Host $("  Region: {0}" -f $Region)

                                switch ($mNodeTypeData.ZoneSupportStatus)
                                    {
                                        "Success" { Write-Host "  Zone Support: $($mNodeTypeData.ZoneSupport)" -ForegroundColor Green }
                                        "Warning" { Write-Host "  Zone Support: $($mNodeTypeData.ZoneSupport)" -ForegroundColor Yellow }
                                        "Error" { Write-Host "  Region Support: $($mNodeTypeData.ZoneSupport)" -ForegroundColor Red }
                                    }

                                if ($mNodeTypeData.AvailableZones.Count -gt 0 -and $mNodeTypeData.ZoneSupportStatus -ne "Error")
                                    {
                                        Write-Host $("  All Available Zones: {0}" -f ($mNodeTypeData.AvailableZones -join ", "))
                                    }
                            }
                    }

                # Quota Family Summary
                if ($computeQuotaUsage)
                    {
                        Write-Host "`nQuota Family Summary:" -ForegroundColor Yellow

                        # Display quota family summary using preprocessed data
                        $quotaFamilies = ($skuSupportData | ForEach-Object {
                            if ($_.ComponentType -eq "CNode") { $cNodeObject.QuotaFamily }
                            else { ($mNodeObjectUnique | Where-Object { $_.PhysicalSize -eq $_.PhysicalSize }).QuotaFamily }
                        }) | Sort-Object -Unique

                        foreach ($quotaFamily in $quotaFamilies)
                            {
                                $requiredvCPU = 0

                                # Calculate total vCPU for this quota family
                                $skuSupportData | ForEach-Object {
                                    if ($_.ComponentType -eq "CNode" -and $cNodeObject.QuotaFamily -eq $quotaFamily)
                                        {
                                            $requiredvCPU += $_.vCPUCount
                                        } `
                                    elseif ($_.ComponentType -eq "MNode")
                                        {
                                            $mNodeType = $mNodeObjectUnique | Where-Object { $_.PhysicalSize -eq $_.PhysicalSize }
                                            if ($mNodeType.QuotaFamily -eq $quotaFamily)
                                                {
                                                    $requiredvCPU += $_.vCPUCount
                                                }
                                        }
                                }

                                $quotaFamilyInfo = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $quotaFamily }

                                Write-Host $("`n  {0}:" -f $quotaFamily) -ForegroundColor Cyan
                                if ($quotaFamilyInfo)
                                    {
                                        $availableQuota = $quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue
                                        if ($availableQuota -ge $requiredvCPU)
                                            {
                                                Write-Host $("    vCPU Required: {0}" -f $requiredvCPU)
                                                Write-Host $("    vCPU Available: {0}/{1}" -f $availableQuota, $quotaFamilyInfo.Limit)
                                                Write-Host $("    Status: ✓ Sufficient") -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                Write-Host $("    vCPU Required: {0}" -f $requiredvCPU)
                                                Write-Host $("    vCPU Available: {0}/{1}" -f $availableQuota, $quotaFamilyInfo.Limit)
                                                Write-Host $("    Status: ✗ Insufficient (Shortfall: {0} vCPU)" -f ($requiredvCPU - $availableQuota)) -ForegroundColor Red
                                            }
                                    } `
                                else
                                    {
                                        Write-Host $("    vCPU Required: {0}" -f $requiredvCPU)
                                        Write-Host $("    Status: ⚠ Unable to determine quota") -ForegroundColor Yellow
                                    }
                            }
                    }

                # Quota Summary
                if ($computeQuotaUsage)
                    {
                        Write-Host "`nQuota Summary:" -ForegroundColor Yellow

                        # Display quota summary using preprocessed data
                        foreach ($quotaData in $quotaAnalysisData)
                            {
                                switch ($quotaData.StatusLevel)
                                    {
                                        "Success" { Write-Host $("  {0}: {1} (Required: {2}, Available: {3}/{4})" -f $quotaData.QuotaType, $quotaData.Status, $quotaData.Required, $quotaData.Available, $quotaData.Limit) -ForegroundColor Green }
                                        "Error" { Write-Host $("  {0}: {1} (Required: {2}, Available: {3}/{4})" -f $quotaData.QuotaType, $quotaData.Status, $quotaData.Required, $quotaData.Available, $quotaData.Limit) -ForegroundColor Red }
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
                                                                    @{Label="VM Status"; Expression={$_.VMStatus}; Width=15},
                                                                    @{Label="Provisioned State"; Expression={$_.ProvisioningState}; Width=15},
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
                                                                    @{Label="VM Status"; Expression={$_.VMStatus}; Width=15},
                                                                    @{Label="Provisioned State"; Expression={$_.ProvisioningState}; Width=15},
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
                                        } `
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
                if ($CNodeCount)
                    {
                        $silkSummary +=    [PSCustomObject]@{
                                                                Component = "CNode"
                                                                DeployedCount = $successfulCNodes
                                                                ExpectedCount = $CNodeCount
                                                                SKU = $cNodeSummaryLabel
                                                                Status = if ($successfulCNodes -eq $CNodeCount) { "✓ Complete" } elseif ($successfulCNodes -eq 0) { "✗ Failed" } else { "⚠ Partial" }
                                                            }
                    }

                # Add MNode/DNode summary for each group
                if ($mNodeGroups.Count -gt 0)
                    {
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
                                                                        Status = if ($groupSuccessful -eq $groupExpected) { "✓ Complete" } elseif ($groupSuccessful -eq 0) { "✗ Failed" } else { "⚠ Partial" }
                                                                    }
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
                if ($nonSuccessfulVMs.Count -gt 0)
                    {
                        Write-Host "`nVMs with Non-Successful Provisioning States:" -ForegroundColor Yellow
                        $nonSuccessfulVMs | ForEach-Object { Write-Host "  $($_.VMName): $($_.ProvisioningState)" -ForegroundColor Yellow }
                    }

                # Display deployment validation findings if available
                if ($deploymentValidationResults -and $deploymentValidationResults.Count -gt 0)
                    {
                        Write-Host "`nDeployment Validation Findings:" -ForegroundColor Yellow

                        # Display deployment validation findings using preprocessed data
                        if ($validationFindings.NoCapacityIssues.Count -gt 0)
                            {
                                $affectedSkus = $validationFindings.NoCapacityIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                Write-Host $("  ⚠️ No SKU Capacity Available: {0} VM(s) affected ({1})" -f $validationFindings.NoCapacityIssues.Count, ($affectedSkus -join ", ")) -ForegroundColor Gray
                                Write-Host "      → Azure has no available capacity for these VM SKUs in the target zone/region" -ForegroundColor DarkGray
                                Write-Host "      → Try: Different availability zone, different region, or wait and retry" -ForegroundColor DarkGray
                            }

                        if ($validationFindings.QuotaIssues.Count -gt 0)
                            {
                                $affectedSkus = $validationFindings.QuotaIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                Write-Host $("  📊 Quota Exceeded: {0} VM(s) affected ({1})" -f $validationFindings.QuotaIssues.Count, ($affectedSkus -join ", ")) -ForegroundColor Gray
                                Write-Host "      → Subscription has reached limits for these VM families or total vCPUs" -ForegroundColor DarkGray
                                Write-Host "      → Try: Request quota increase via Azure portal Support tickets" -ForegroundColor DarkGray
                            }

                        if ($validationFindings.SKUSupportIssues.Count -gt 0)
                            {
                                $affectedSkus = $validationFindings.SKUSupportIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                Write-Host $("  🔧 SKU Support: {0} VM(s) affected ({1})" -f $validationFindings.SKUSupportIssues.Count, ($affectedSkus -join ", ")) -ForegroundColor Gray
                                Write-Host "      → These VM SKUs are not supported in the target region/zone" -ForegroundColor DarkGray
                                Write-Host "      → Try: Different region that supports these SKUs, or use alternative VM SKUs" -ForegroundColor DarkGray

                                # Show zone-specific information for SKU support issues
                                $skuIssuesWithAlternatives = $validationFindings.SKUSupportIssues | Where-Object { $_.AlternativeZones -and $_.AlternativeZones.Count -gt 0 }
                                if ($skuIssuesWithAlternatives.Count -gt 0)
                                    {
                                        Write-Host $("      → Alternative zones available within {0} for affected SKUs" -f $Region) -ForegroundColor DarkGray
                                    }
                            }

                        if ($validationFindings.OtherIssues.Count -gt 0)
                            {
                                $affectedSkus = $validationFindings.OtherIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                Write-Host $("  ⚙️ Other Constraints: {0} VM(s) affected ({1})" -f $validationFindings.OtherIssues.Count, ($affectedSkus -join ", ")) -ForegroundColor Gray
                                Write-Host "      → Deployment failed due to other Azure constraints or configuration issues" -ForegroundColor DarkGray
                                Write-Host "      → Try: Review error details in HTML report for specific troubleshooting steps" -ForegroundColor DarkGray
                            }
                    }

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
                Write-Host "Proximity Placement Groups: " -NoNewline
                if ($deployedPPG)
                    {
                        Write-Host $("✓ {0} groups ({1})" -f $deployedPPG.Count, ($deployedPPG.Name -join ", ")) -ForegroundColor Green
                    } `
                else
                    {
                        Write-Host "✗ Not Found" -ForegroundColor Red
                    }

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
                Write-Host $("Total Resources Created: {0}" -f $totalResourcesCreated)

                # Zone Alignment Information
                Write-Host "`n=== Zone Alignment Information ===" -ForegroundColor Cyan
                Write-Host "Deployment Zone: " -NoNewline
                Write-Host $("{0}" -f $zoneAlignmentInfo.FinalZone) -ForegroundColor Green

                if ($zoneAlignmentInfo.AlignmentSubscription)
                    {
                        Write-Host "Alignment Subscription: " -NoNewline
                        Write-Host $("{0}" -f $zoneAlignmentInfo.AlignmentSubscription) -ForegroundColor Yellow

                        if ($zoneAlignmentInfo.AlignmentPerformed)
                            {
                                Write-Host "Zone Alignment: " -NoNewline
                                Write-Host $("✓ Applied") -ForegroundColor Green
                                Write-Host $("  Original Zone: {0} → Final Zone: {1}" -f $zoneAlignmentInfo.OriginalZone, $zoneAlignmentInfo.FinalZone) -ForegroundColor Gray
                            } `
                        elseif ($zoneAlignmentInfo.AlignmentDisabled)
                            {
                                Write-Host "Zone Alignment: " -NoNewline
                                Write-Host $("⚠ Disabled by parameter") -ForegroundColor Yellow
                            } `
                        else
                            {
                                Write-Host "Zone Alignment: " -NoNewline
                                Write-Host $("- No adjustment needed") -ForegroundColor Gray
                            }

                        Write-Host $("Reason: {0}" -f $zoneAlignmentInfo.AlignmentReason) -ForegroundColor Gray

                        # Display zone mappings if available
                        if ($zoneAlignmentInfo.ZoneMappings.Count -gt 0)
                            {
                                Write-Host "Zone Mappings:" -ForegroundColor Gray
                                foreach ($mapping in $zoneAlignmentInfo.ZoneMappings)
                                    {
                                        Write-Host $("  Deployment Zone {0} ↔ Alignment Zone {1}" -f $mapping.DeploymentZone, $mapping.AlignmentZone) -ForegroundColor DarkGray
                                    }
                            }
                    } `
                else
                    {
                        Write-Host "Zone Alignment: " -NoNewline
                        Write-Host $("- Not Applicable") -ForegroundColor Gray
                        Write-Host $("Reason: {0}" -f $zoneAlignmentInfo.AlignmentReason) -ForegroundColor Gray
                    }

                # Deployment Results Status
                Write-Host "`n=== Deployment Results Status ===" -ForegroundColor Cyan

                # Get unique SKUs that failed for more accurate reporting using preprocessed data
                $uniqueFailedSkus = @()
                if ($deploymentValidationResults -and $deploymentValidationResults.Count -gt 0)
                    {
                        $uniqueFailedSkus = $deploymentValidationResults | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                    }

                if ($successfulVMs -eq $totalExpectedVMs -and $deployedVNet -and $deployedNSG)
                    {
                        Write-Host $("✓ DEPLOYMENT VALIDATION COMPLETE - All SKUs successfully deployed in target region: {0} zone: {1}" -f $Region, $Zone) -ForegroundColor Green
                        Write-Host $("📊 Deployment Readiness: Excellent - No SKU Capacity or availability constraints detected") -ForegroundColor Green
                    } `
                elseif ($totalExpectedVMs -eq 0)
                    {
                        Write-Host $("⚠ ENVIRONMENT ANALYSIS COMPLETE - No VMs could be deployed due to quota constraints") -ForegroundColor Red
                        Write-Host $("📊 Quota Status: Insufficient - All requested VM deployments exceed available quota") -ForegroundColor Red
                        Write-Host $("💡 Recommendation: Review quota report above and request quota increases for required VM families") -ForegroundColor Yellow
                    } `
                elseif ($successfulVMs -gt 0)
                    {
                        if ($uniqueFailedSkus.Count -gt 0)
                            {
                                Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Specific SKU constraints detected") -ForegroundColor Yellow
                                Write-Host $("📊 Deployment Readiness: Partial - {0} SKU(s) affected: {1}" -f $uniqueFailedSkus.Count, ($uniqueFailedSkus -join ", ")) -ForegroundColor Yellow
                            } `
                        else
                            {
                                Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Mixed results detected") -ForegroundColor Yellow
                                Write-Host $("📊 Deployment Readiness: Partial - {0}/{1} VMs successfully validated" -f $successfulVMs, $totalExpectedVMs) -ForegroundColor Yellow
                            }
                    } `
                else
                    {
                        Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Significant constraints detected") -ForegroundColor Red
                        Write-Host $("📊 Deployment Readiness: Limited - Review validation findings in summary") -ForegroundColor Red
                    }

                Write-Host $("⏱️ Total Deployment Time: {0}" -f $DeploymentTimespan.ToString("hh\:mm\:ss")) -ForegroundColor Cyan
                Write-Progress -Id 1 -Completed

                # ===============================================================================
                # Console Output Buffer Management
                # ===============================================================================
                # Add buffer space to prevent console output overlap in Azure Cloud Shell
                Write-Host ""
                Write-Host ""
                Start-Sleep -Milliseconds 500

                # Clear any remaining progress artifacts
                [System.Console]::Out.Flush()

                # ===============================================================================
                # HTML Report Generation
                # ===============================================================================
                if (-not $NoHTMLReport)
                    {
                        # ===============================================================================
                        # Pre-HTML Generation Buffer
                        # ===============================================================================
                        # Ensure clean console state before HTML generation messages
                        Start-Sleep -Milliseconds 300
                        [System.Console]::Out.Flush()

                        Write-Host "`n=== Generating HTML Report ===" -ForegroundColor Cyan
                        Write-Verbose -Message $("Generating HTML report at: {0}" -f $ReportFullPath)

                        try
                            {
                                # Check if ReportFullPath was properly initialized
                                if (-not $ReportFullPath)
                                    {
                                        Write-Warning $("HTML report generation skipped: Report path not initialized (likely due to early validation failure).")
                                        return
                                    }

                                # HTML report template with embedded CSS for professional styling
                                $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Silk Azure Deployment Report - $($StartTime.ToString("yyyy-MM-dd HH:mm:ss"))</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; line-height: 1.6; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #FF00FF; padding-bottom: 10px; margin-bottom: 30px; }
        h2 { color: #34495e; border-left: 4px solid #FF00FF; padding-left: 15px; margin-top: 30px; }
        h3 { color: #7f8c8d; margin-top: 25px; }
        .status-success { color: #27ae60; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .status-error { color: #e74c3c; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; }
        th, td { padding: 12px; text-align: left; border: 1px solid #ddd; }
        th { background-color: #FF00FF; color: white; font-weight: 600; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e8f4f8; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin: 20px 0; }
        .info-card { background: #f8f9fa; padding: 20px; border-radius: 6px; border-left: 4px solid #FF00FF; }
        .info-card h4 { margin-top: 0; color: #2c3e50; }
        .quota-item { margin: 8px 0; padding: 8px; background: #ecf0f1; border-radius: 4px; }
        .timestamp { color: #7f8c8d; font-size: 0.9em; text-align: right; margin-top: 30px; }
        .checkmark { color: #27ae60; }
        .warning-mark { color: #f39c12; }
        .error-mark { color: #e74c3c; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏗️ Silk Azure Deployment Report</h1>

        <div class="info-grid">
            <div class="info-card">
                <h4>📋 Deployment Configuration</h4>
                <strong>Subscription ID:</strong> $SubscriptionId<br>
                <strong>Resource Group:</strong> $ResourceGroupName<br>
                <strong>Region:</strong> $Region<br>
                <strong>Availability Zone:</strong> $Zone<br>
"@

                                # Add CNode configuration if present
                                if ($cNodeObject -and $CNodeCount -gt 0)
                                    {
                                        $htmlContent += @"
                <strong>CNode Count:</strong> $CNodeCount<br>
                <strong>CNode SKU:</strong> $($cNodeObject.vmSkuPrefix)$($cNodeObject.vCPU)$($cNodeObject.vmSkuSuffix)<br>
"@
                                    }

                                # Add MNode configuration if present
                                if ($mNodeObject -and $mNodeObject.Count -gt 0)
                                    {
                                        $mNodeSizeDisplay = ($mNodeObject | ForEach-Object { $_.PhysicalSize }) -join ", "
                                        $htmlContent += @"
                <strong>MNode Sizes:</strong> $mNodeSizeDisplay TiB<br>
                <strong>Total DNodes:</strong> $totalDNodes<br>
"@
                                    }

                                $htmlContent += @"
            </div>
            <div class="info-card">
                <h4>📊 Deployment Summary</h4>
                <strong>Total Expected VMs:</strong> $totalExpectedVMs<br>
                <strong>Successfully Deployed:</strong> <span class="$(if($successfulVMs -eq $totalExpectedVMs){'status-success'}else{'status-warning'})">$successfulVMs</span><br>
                $(if($failedVMs -gt 0){"<strong>Failed Deployments:</strong> <span class='status-error'>$failedVMs</span><br>"})
                <strong>Network Interfaces:</strong> $($deployedNICs.Count)<br>
                <strong>Overall Status:</strong> <span class="$(if($successfulVMs -eq $totalExpectedVMs -and $deployedVNet -and $deployedNSG){'status-success'}else{'status-warning'})">$(if($successfulVMs -eq $totalExpectedVMs -and $deployedVNet -and $deployedNSG){'✓ SUCCESSFUL'}else{'⚠ ISSUES DETECTED'})</span>
            </div>
        </div>

        <h2>🏗️ Silk Component Summary</h2>
        <table>
            <thead>
                <tr>
                    <th>Silk Component</th>
                    <th>Deployed</th>
                    <th>Expected</th>
                    <th>VM SKU</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
"@

                                # Add CNode summary row to HTML
                                foreach ($component in $silkSummary)
                                    {
                                        $statusClass = if ($component.Status -like "*Complete*") { "status-success" } elseif ($component.Status -like "*Failed*") { "status-error" } else { "status-warning" }
                                        $htmlContent += @"
                <tr>
                    <td>$($component.Component)</td>
                    <td>$($component.DeployedCount)</td>
                    <td>$($component.ExpectedCount)</td>
                    <td>$($component.SKU)</td>
                    <td><span class="$statusClass">$($component.Status)</span></td>
                </tr>
"@
                                    }

                                $htmlContent += @"
            </tbody>
        </table>
"@

                                # Add CNode deployment table if present
                                if ($cNodeReport)
                                    {
                                        $htmlContent += @"
        <h2>🖥️ CNode Deployment Status</h2>
        <p><strong>Expected SKU:</strong> $($cNodeReport[0].ExpectedSKU)</p>
        <table>
            <thead>
                <tr>
                    <th>Node</th>
                    <th>VM Name</th>
                    <th>Deployed SKU</th>
                    <th>VM Status</th>
                    <th>Provisioned State</th>
                    <th>NIC Status</th>
                    <th>Availability Set</th>
                </tr>
            </thead>
            <tbody>
"@
                                        foreach ($cNode in $cNodeReport)
                                            {
                                                $vmStatusClass = if ($cNode.VMStatus -like "*Deployed*") { "checkmark" } else { "error-mark" }
                                                $nicStatusClass = if ($cNode.NICStatus -like "*Created*") { "checkmark" } else { "error-mark" }
                                                $provisioningClass = if ($cNode.ProvisioningState -eq "Succeeded") { "checkmark" } elseif ($cNode.ProvisioningState -eq "Failed") { "error-mark" } else { "warning" }

                                                $htmlContent += @"
                <tr>
                    <td>CNode $($cNode.NodeNumber)</td>
                    <td>$($cNode.VMName)</td>
                    <td>$($cNode.DeployedSKU)</td>
                    <td><span class="$vmStatusClass">$($cNode.VMStatus)</span></td>
                    <td><span class="$provisioningClass">$($cNode.ProvisioningState)</span></td>
                    <td><span class="$nicStatusClass">$($cNode.NICStatus)</span></td>
                    <td>$($cNode.AvailabilitySet)</td>
                </tr>
"@
                                            }
                                        $htmlContent += @"
            </tbody>
        </table>
"@
                                    }

                                # Add MNode/DNode deployment tables if present
                                $mNodeGroups = $deploymentReport | Where-Object { $_.ResourceType -eq "DNode" } | Group-Object GroupNumber
                                if ($mNodeGroups)
                                    {
                                        foreach ($group in $mNodeGroups)
                                            {
                                                $mNodeExpectedSku = $group.Group[0].ExpectedSKU
                                                $groupNumber = $group.Name

                                                $htmlContent += @"
        <h2>💾 MNode Group $groupNumber DNode Status</h2>
        <p><strong>Expected SKU:</strong> $mNodeExpectedSku</p>
        <table>
            <thead>
                <tr>
                    <th>Node</th>
                    <th>VM Name</th>
                    <th>Deployed SKU</th>
                    <th>VM Status</th>
                    <th>Provisioned State</th>
                    <th>NIC Status</th>
                    <th>Availability Set</th>
                </tr>
            </thead>
            <tbody>
"@
                                                foreach ($dNode in $group.Group)
                                                    {
                                                        $vmStatusClass = if ($dNode.VMStatus -like "*Deployed*") { "checkmark" } else { "error-mark" }
                                                        $nicStatusClass = if ($dNode.NICStatus -like "*Created*") { "checkmark" } else { "error-mark" }
                                                        $provisioningClass = if ($dNode.ProvisioningState -eq "Succeeded") { "checkmark" } elseif ($dNode.ProvisioningState -eq "Failed") { "error-mark" } else { "warning" }

                                                        $htmlContent += @"
                <tr>
                    <td>DNode $($dNode.NodeNumber)</td>
                    <td>$($dNode.VMName)</td>
                    <td>$($dNode.DeployedSKU)</td>
                    <td><span class="$vmStatusClass">$($dNode.VMStatus)</span></td>
                    <td><span class="$provisioningClass">$($dNode.ProvisioningState)</span></td>
                    <td><span class="$nicStatusClass">$($dNode.NICStatus)</span></td>
                    <td>$($dNode.AvailabilitySet)</td>
                </tr>
"@
                                                    }
                                                $htmlContent += @"
            </tbody>
        </table>
"@
                                            }
                                    }

                                # Add SKU Support and Quota Summary sections
                                $htmlContent += @"
        <h2>🔧 SKU Support Analysis</h2>
        <div class="info-grid">
"@

                                # Add CNode SKU Support if present
                                if($cNodeObject)
                                    {
                                        $cNodeData = $skuSupportData | Where-Object { $_.ComponentType -eq "CNode" }

                                        $zoneSupport = $cNodeData.ZoneSupport
                                        $zoneSupportClass = switch ($cNodeData.ZoneSupportStatus)
                                            {
                                                "Success" { "status-success" }
                                                "Warning" { "status-warning" }
                                                "Error" { "status-error" }
                                                default { "status-warning" }
                                            }

                                        $htmlContent += @"
            <div class="info-card">
                <h4>🖥️ CNode SKU Support</h4>
                <strong>SKU:</strong> $($cNodeData.SKUName)<br>
                <strong>Region:</strong> $Region<br>
                <strong>Zone Support:</strong> <span class="$zoneSupportClass">$zoneSupport</span><br>
                $(if($cNodeData.AvailableZones.Count -gt 0){"<strong>Available Zones:</strong> $($cNodeData.AvailableZones -join ', ')"})
            </div>
"@
                                    }

                                # Add MNode SKU Support if present
                                if($MNodeSize -and $mNodeObjectUnique)
                                    {
                                        $mNodeData = $skuSupportData | Where-Object { $_.ComponentType -eq "MNode" }
                                        foreach ($mNodeTypeData in $mNodeData)
                                            {
                                                $zoneSupport = $mNodeTypeData.ZoneSupport
                                                $zoneSupportClass = switch ($mNodeTypeData.ZoneSupportStatus)
                                                    {
                                                        "Success" { "status-success" }
                                                        "Warning" { "status-warning" }
                                                        "Error" { "status-error" }
                                                        default { "status-warning" }
                                                    }

                                                $htmlContent += @"
            <div class="info-card">
                <h4>💾 MNode SKU Support ($($mNodeTypeData.InstanceCount)x $($mNodeTypeData.PhysicalSize) TiB)</h4>
                <strong>SKU:</strong> $($mNodeTypeData.SKUName)<br>
                <strong>Region:</strong> $Region<br>
                <strong>Zone Support:</strong> <span class="$zoneSupportClass">$zoneSupport</span><br>
                $(if($mNodeTypeData.AvailableZones.Count -gt 0){"<strong>Available Zones:</strong> $($mNodeTypeData.AvailableZones -join ', ')"})
            </div>
"@
                                            }
                                    }

                                $htmlContent += @"
        </div>

        <h2>� Quota Family Summary</h2>
        <div class="info-grid">
"@

                                # Add quota family summary if available
                                if ($computeQuotaUsage)
                                    {
                                        # Display quota family summary using preprocessed data
                                        $quotaFamilies = ($skuSupportData | ForEach-Object {
                                            if ($_.ComponentType -eq "CNode") { $cNodeObject.QuotaFamily }
                                            else { ($mNodeObjectUnique | Where-Object { $_.PhysicalSize -eq $_.PhysicalSize }).QuotaFamily }
                                        }) | Sort-Object -Unique

                                        foreach ($quotaFamily in $quotaFamilies)
                                            {
                                                $requiredvCPU = 0

                                                # Calculate total vCPU for this quota family
                                                $skuSupportData | ForEach-Object {
                                                    if ($_.ComponentType -eq "CNode" -and $cNodeObject.QuotaFamily -eq $quotaFamily)
                                                        {
                                                            $requiredvCPU += $_.vCPUCount
                                                        }
                                                    elseif ($_.ComponentType -eq "MNode")
                                                        {
                                                            $mNodeType = $mNodeObjectUnique | Where-Object { $_.PhysicalSize -eq $_.PhysicalSize }
                                                            if ($mNodeType.QuotaFamily -eq $quotaFamily)
                                                                {
                                                                    $requiredvCPU += $_.vCPUCount
                                                                }
                                                        }
                                                }

                                                $quotaFamilyInfo = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $quotaFamily }

                                                $quotaStatus = ""
                                                $quotaStatusClass = ""
                                                if ($quotaFamilyInfo)
                                                    {
                                                        $availableQuota = $quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue
                                                        if ($availableQuota -ge $requiredvCPU)
                                                            {
                                                                $quotaStatus = "✓ Sufficient"
                                                                $quotaStatusClass = "status-success"
                                                            }
                                                        else
                                                            {
                                                                $shortfall = $requiredvCPU - $availableQuota
                                                                $quotaStatus = "✗ Insufficient (Shortfall: $shortfall vCPU)"
                                                                $quotaStatusClass = "status-error"
                                                            }
                                                    }
                                                else
                                                    {
                                                        $quotaStatus = "⚠ Unable to determine quota"
                                                        $quotaStatusClass = "status-warning"
                                                    }

                                                $htmlContent += @"
            <div class="info-card">
                <h4>🔧 $quotaFamily</h4>
                <strong>vCPU Required:</strong> $requiredvCPU<br>
                $(if($quotaFamilyInfo){"<strong>vCPU Available:</strong> $($quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue)/$($quotaFamilyInfo.Limit)<br>"})
                <strong>Status:</strong> <span class="$quotaStatusClass">$quotaStatus</span>
            </div>
"@
                                            }
                                    }

                                $htmlContent += @"
        </div>

        <h2>�📊 Quota Summary</h2>
        <div class="info-grid">
"@

                                # Add quota summary if available
                                if ($computeQuotaUsage)
                                    {
                                        # Virtual Machine Quota using preprocessed data
                                        $vmQuotaData = $quotaAnalysisData | Where-Object { $_.QuotaType -eq "Virtual Machines" }
                                        if ($vmQuotaData)
                                            {
                                                $vmQuotaClass = if ($vmQuotaData.StatusLevel -eq "Success") { "status-success" } else { "status-error" }

                                                $htmlContent += @"
            <div class="info-card">
                <h4>🖥️ Virtual Machine Quota</h4>
                <strong>Status:</strong> <span class="$vmQuotaClass">$($vmQuotaData.Status)</span><br>
                <strong>Required:</strong> $($vmQuotaData.Required) VMs<br>
                <strong>Available:</strong> $($vmQuotaData.Available)/$($vmQuotaData.Limit)<br>
            </div>
"@
                                            }

                                        # Regional vCPU Quota using preprocessed data
                                        $vcpuQuotaData = $quotaAnalysisData | Where-Object { $_.QuotaType -eq "Regional vCPUs" }
                                        if ($vcpuQuotaData)
                                            {
                                                $vcpuQuotaClass = if ($vcpuQuotaData.StatusLevel -eq "Success") { "status-success" } else { "status-error" }

                                                $htmlContent += @"
            <div class="info-card">
                <h4>⚡ Regional vCPU Quota</h4>
                <strong>Status:</strong> <span class="$vcpuQuotaClass">$($vcpuQuotaData.Status)</span><br>
                <strong>Required:</strong> $($vcpuQuotaData.Required) vCPUs<br>
                <strong>Available:</strong> $($vcpuQuotaData.Available)/$($vcpuQuotaData.Limit)<br>
            </div>
"@
                                            }

                                        # Availability Sets Quota using preprocessed data
                                        $avsetQuotaData = $quotaAnalysisData | Where-Object { $_.QuotaType -eq "Availability Sets" }
                                        if ($avsetQuotaData)
                                            {
                                                $avsetQuotaClass = if ($avsetQuotaData.StatusLevel -eq "Success") { "status-success" } else { "status-error" }

                                                $htmlContent += @"
            <div class="info-card">
                <h4>🎯 Availability Sets Quota</h4>
                <strong>Status:</strong> <span class="$avsetQuotaClass">$($avsetQuotaData.Status)</span><br>
                <strong>Required:</strong> $($avsetQuotaData.Required) sets<br>
                <strong>Available:</strong> $($avsetQuotaData.Available)/$($avsetQuotaData.Limit)<br>
            </div>
"@
                                            }
                                    }

                                $htmlContent += @"
        </div>

        <h2>🏗️ Infrastructure Resources</h2>
        <div class="info-grid">
            <div class="info-card">
                <h4>🌐 Network Infrastructure</h4>
                <strong>Virtual Network:</strong> <span class="$(if($deployedVNet){'checkmark'}else{'error-mark'})">$(if($deployedVNet){'✓ Created'}else{'✗ Not Created'})</span><br>
                $(if($deployedVNet){"<strong>VNet Name:</strong> $($deployedVNet.Name)<br><strong>Address Space:</strong> $($deployedVNet.AddressSpace.AddressPrefixes -join ', ')<br>"})
                <strong>Network Security Group:</strong> <span class="$(if($deployedNSG){'checkmark'}else{'error-mark'})">$(if($deployedNSG){'✓ Created'}else{'✗ Not Created'})</span><br>
                $(if($deployedNSG){"<strong>NSG Name:</strong> $($deployedNSG.Name)<br>"})
                <strong>Subnet Configuration:</strong> $(if($deployedVNet){'✓ Management subnet configured'}else{'✗ Not configured'})
            </div>
            <div class="info-card">
                <h4>📍 Placement and Availability</h4>
"@

                                # Add Proximity Placement Groups details using preprocessed data
                                if ($deployedPPG)
                                    {
                                        $htmlContent += @"
                <strong>Proximity Placement Groups:</strong> <span class="checkmark">✓ $($deployedPPG.Count) Created</span><br>
                <strong>PPG Names:</strong> $($deployedPPG.Name -join ', ')<br>
                <strong>PPG Type:</strong> Standard<br>
                <strong>Location:</strong> $(($deployedPPG | Select-Object -ExpandProperty Location -Unique -ErrorAction SilentlyContinue) -join ', ')<br>
"@
                                    }
                                else
                                    {
                                        $htmlContent += @"
                <strong>Proximity Placement Groups:</strong> <span class="error-mark">✗ Not Found</span><br>
"@
                                    }

                                # Add Availability Sets details using preprocessed data
                                if ($deployedAvailabilitySets)
                                    {
                                        $avSetNames = ($deployedAvailabilitySets.Name | Sort-Object) -join ", "
                                        $htmlContent += @"
                <strong>Availability Sets:</strong> <span class="checkmark">✓ $($deployedAvailabilitySets.Count) Created</span><br>
                <strong>AvSet Names:</strong> $avSetNames<br>
                <strong>Fault Domains:</strong> $($deployedAvailabilitySets[0].PlatformFaultDomainCount)<br>
                <strong>Update Domains:</strong> $($deployedAvailabilitySets[0].PlatformUpdateDomainCount)
"@
                                    }
                                else
                                    {
                                        $htmlContent += @"
                <strong>Availability Sets:</strong> <span class="error-mark">✗ Not Found</span>
"@
                                    }

                                $htmlContent += @"
            </div>
            <div class="info-card">
                <h4>📈 Resource Summary</h4>
                <strong>Resource Group:</strong> $ResourceGroupName<br>
                <strong>Resource Name Prefix:</strong> $ResourceNamePrefix<br>
                <strong>Total Resources Created:</strong> $totalResourcesCreated<br>
                <strong>Virtual Machines:</strong> $($deployedVMs.Count)<br>
                <strong>Network Interfaces:</strong> $($deployedNICs.Count)<br>
                <strong>Network Resources:</strong> $($(if($deployedVNet){1}else{0}) + $(if($deployedNSG){1}else{0}))<br>
                <strong>Placement Resources:</strong> $($(if($deployedPPG){1}else{0}) + $deployedAvailabilitySets.Count)
            </div>
            <div class="info-card">
                <h4>🔄 Zone Alignment Information</h4>
                <strong>Deployment Zone:</strong> <span class="status-success">$($zoneAlignmentInfo.FinalZone)</span><br>
"@

                                # Add alignment subscription information if available
                                if ($zoneAlignmentInfo.AlignmentSubscription)
                                    {
                                        $htmlContent += @"
                <strong>Alignment Subscription:</strong> $($zoneAlignmentInfo.AlignmentSubscription)<br>
"@

                                        if ($zoneAlignmentInfo.AlignmentPerformed)
                                            {
                                                $htmlContent += @"
                <strong>Zone Alignment:</strong> <span class="status-success">✓ Applied</span><br>
                <strong>Zone Change:</strong> $($zoneAlignmentInfo.OriginalZone) → $($zoneAlignmentInfo.FinalZone)<br>
"@
                                            } `
                                        elseif ($zoneAlignmentInfo.AlignmentDisabled)
                                            {
                                                $htmlContent += @"
                <strong>Zone Alignment:</strong> <span class="status-warning">⚠ Disabled by parameter</span><br>
"@
                                            } `
                                        else
                                            {
                                                $htmlContent += @"
                <strong>Zone Alignment:</strong> <span class="status-success">- No adjustment needed</span><br>
"@
                                            }
                                    } `
                                else
                                    {
                                        $htmlContent += @"
                <strong>Zone Alignment:</strong> <span class="status-success">- Not Applicable</span><br>
"@
                                    }

                                $htmlContent += @"
                <strong>Reason:</strong> $($zoneAlignmentInfo.AlignmentReason)<br>
"@

                                # Add zone mappings table if available
                                if ($zoneAlignmentInfo.ZoneMappings.Count -gt 0)
                                    {
                                        $htmlContent += @"
                <br><strong>Zone Mappings:</strong><br>
                <table style="margin: 5px 0; width: 100%;">
                    <thead>
                        <tr>
                            <th style="padding: 5px; font-size: 0.9em;">Deployment Zone</th>
                            <th style="padding: 5px; font-size: 0.9em;">Alignment Zone</th>
                        </tr>
                    </thead>
                    <tbody>
"@
                                        foreach ($mapping in $zoneAlignmentInfo.ZoneMappings)
                                            {
                                                $htmlContent += @"
                        <tr>
                            <td style="padding: 5px; font-size: 0.9em;">$($mapping.DeploymentZone)</td>
                            <td style="padding: 5px; font-size: 0.9em;">$($mapping.AlignmentZone)</td>
                        </tr>
"@
                                            }
                                        $htmlContent += @"
                    </tbody>
                </table>
"@
                                    }

                                $htmlContent += @"
            </div>
"@

                                # Add deployment validation findings if available
                                if ($deploymentValidationResults -and $deploymentValidationResults.Count -gt 0)
                                    {
                                        $htmlContent += @"
            <div class="info-card">
                <h4>⚠️ Deployment Validation Findings</h4>
"@

                                        # Group validation results by failure category for HTML summary
                                        $noCapacityIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "No SKU Capacity Available" }
                                        $quotaIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Quota Exceeded" }
                                        $skuSupportIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "SKU Support" }
                                        $otherIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Other" }

                                        if ($noCapacityIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $noCapacityIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                                $htmlContent += @"
                <strong>⚠️ No SKU Capacity Available:</strong> <span class="status-warning">$($noCapacityIssues.Count) VM(s) affected</span><br>
                <strong>Affected SKUs:</strong> $($affectedSkus -join ", ")<br>
                <strong>Issue:</strong> Azure has no available capacity for these VM SKUs in the target zone/region<br>
                <strong>Solutions:</strong> Try different availability zone, different region, or wait and retry<br><br>
"@
                                            }

                                        if ($quotaIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $quotaIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                                $htmlContent += @"
                <strong>📊 Quota Exceeded:</strong> <span class="status-warning">$($quotaIssues.Count) VM(s) affected</span><br>
                <strong>Affected SKUs:</strong> $($affectedSkus -join ", ")<br>
                <strong>Issue:</strong> Subscription has reached limits for these VM families or total vCPUs<br>
                <strong>Solutions:</strong> Request quota increase via Azure portal Support tickets<br><br>
"@
                                            }

                                        if ($skuSupportIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $skuSupportIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                                $htmlContent += @"
                <strong>🔧 SKU Support:</strong> <span class="status-warning">$($skuSupportIssues.Count) VM(s) affected</span><br>
                <strong>Affected SKUs:</strong> $($affectedSkus -join ", ")<br>
                <strong>Issue:</strong> These VM SKUs are not supported in the target region/zone<br>
                <strong>Solutions:</strong> Use different region that supports these SKUs, or use alternative VM SKUs<br>
"@

                                                # Show zone-specific information for SKU support issues
                                                $skuIssuesWithAlternatives = $skuSupportIssues | Where-Object { $_.AlternativeZones -and $_.AlternativeZones.Count -gt 0 }
                                                if ($skuIssuesWithAlternatives.Count -gt 0)
                                                    {
                                                        $htmlContent += @"
                <strong>Alternative Zones:</strong> Available within $Region for affected SKUs<br>
"@
                                                    }
                                                $htmlContent += "<br>"
                                            }

                                        if ($otherIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $otherIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne "" }
                                                $htmlContent += @"
                <strong>⚙️ Other Constraints:</strong> <span class="status-warning">$($otherIssues.Count) VM(s) affected</span><br>
                <strong>Affected SKUs:</strong> $($affectedSkus -join ", ")<br>
                <strong>Issue:</strong> Deployment failed due to other Azure constraints or configuration issues<br>
                <strong>Solutions:</strong> Review detailed error messages below for specific troubleshooting steps<br><br>
"@
                                            }

                                        $htmlContent += @"
            </div>
"@
                                    }

                                $htmlContent += @"
        </div>

        <div class="timestamp">
            ⏱️ Total Deployment Time: $($DeploymentTimespan.ToString("hh\:mm\:ss")) | Report generated on $($StartTime.ToString("yyyy-MM-dd HH:mm:ss")) by Silk Test-SilkResourceDeployment PowerShell module
        </div>
    </div>
</body>
</html>
"@

                                # Write HTML content to file
                                $htmlContent | Out-File -FilePath $ReportFullPath -Encoding UTF8
                                Write-Host -Message $("✓ HTML report generated successfully!") -ForegroundColor Green
                                Write-Host -Message $("📄 Report saved to: `"{0}`"" -f $ReportFullPath) -ForegroundColor Cyan

                                # Attempt to open the report automatically (with error handling for headless systems)
                                try
                                    {
                                        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5)
                                            {
                                                Start-Process $ReportFullPath
                                                Write-Verbose -Message $("HTML report opened in default browser.")
                                            }
                                        elseif ($IsLinux)
                                            {
                                                if (Get-Command xdg-open -ErrorAction SilentlyContinue)
                                                    {
                                                        & xdg-open $ReportFullPath
                                                        Write-Verbose -Message $("HTML report opened with xdg-open.")
                                                    }
                                                else
                                                    {
                                                        Write-Verbose -Message $("xdg-open not available. Report saved but not opened automatically.")
                                                    }
                                            }
                                        elseif ($IsMacOS)
                                            {
                                                & open $ReportFullPath
                                                Write-Verbose -Message $("HTML report opened with macOS open command.")
                                            }
                                    }
                                catch
                                    {
                                        Write-Verbose -Message $("Unable to automatically open HTML report (likely headless system): {0}" -f $_.Exception.Message)
                                        Write-Host -Message $("ℹ️  Report available at: `"{0}`"" -f $ReportFullPath) -ForegroundColor Yellow
                                    }
                            }
                        catch
                            {
                                Write-Warning -Message $("Failed to generate HTML report: {0}" -f $_.Exception.Message)
                            }

                        # ===============================================================================
                        # Post-HTML Generation Buffer
                        # ===============================================================================
                        # Final console stabilization for clean output
                        Write-Host ""
                        Start-Sleep -Milliseconds 200
                        [System.Console]::Out.Flush()
                    }

                Start-Sleep -Seconds 2

                Write-Verbose -Message $("Deployment completed. Resources have been created in the resource group: {0}." -f $ResourceGroupName)

                if (!$DisableCleanup)
                    {
                        Read-Host -Prompt "Press Enter to continue with cleanup or Ctrl+C to exit without cleanup."
                    }
            }
        end
            {
                # Restore original warning preference if it was changed and not already restored
                # Note: Warning preference is typically restored after Azure module initialization
                # This serves as a safety net in case script execution was interrupted
                try
                    {
                        if (Get-Variable -Name originalWarningPreference -ErrorAction SilentlyContinue)
                            {
                                if ($WarningPreference -eq 'SilentlyContinue')
                                    {
                                        $WarningPreference = $originalWarningPreference
                                        Write-Verbose -Message $("✓ Original PowerShell warning preference restored in cleanup.")
                                    }
                            }
                    }
                catch
                    {
                        Write-Verbose -Message $("Note: Could not restore original warning preference.")
                    }

                # ===============================================================================
                # Cleanup Phase
                # ===============================================================================
                $cleanupStartTime = Get-Date

                Write-Host -Message $("Cleanup Started at: {0}" -f $cleanupStartTime.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor Yellow

                if ( $RunCleanupOnly -or (!$DisableCleanup -and $deploymentStarted))
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
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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
                                Write-Verbose -Message $("Waiting for all virtual machines to be removed...")

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
                                Write-Verbose -Message $("All virtual machines have been removed.")

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
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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

                                Write-Verbose -Message $("Waiting for all network interfaces to be removed...")
                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message $("All network interfaces have been removed.")

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
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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

                                Write-Verbose -Message $("Virtual Network resource cleanup completed.")

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

                        # Protect existing infrastructure - exclude user-provided AvailabilitySet from cleanup
                        if($AvailabilitySetName)
                            {
                                Write-Verbose -Message $("Protecting existing infrastructure: Excluding Availability Set '{0}' from cleanup" -f $AvailabilitySetName)
                                $availabilitySets = $availabilitySets | Where-Object { $_.Name -ne $AvailabilitySetName }
                            }

                        if ($availabilitySets)
                            {
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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

                                Write-Verbose -Message $("Availability Sets resource cleanup completed.")

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

                        # Protect existing infrastructure - exclude user-provided ProximityPlacementGroup from cleanup
                        if($ProximityPlacementGroupName)
                            {
                                Write-Verbose -Message $("Protecting existing infrastructure: Excluding Proximity Placement Group '{0}' from cleanup" -f $ProximityPlacementGroupName)
                                $proximityPlacementGroups = $proximityPlacementGroups | Where-Object { $_.Name -ne $ProximityPlacementGroupName }
                            }

                        if ($proximityPlacementGroups)
                            {
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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

                                Write-Verbose -Message $("Proximity Placement Groups resource cleanup completed.")

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
                                # identify cleanup removed resources
                                $cleanupDidRun = $true

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

                                Write-Verbose -Message $("Network Security Group resource cleanup completed.")

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

                        Write-Verbose -Message $("Resource group removal completed.")

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

                        # identify cleanup removed resources
                        $cleanupDidRun = $true
                    }

                # notify cleanup complete if it actually cleaned anything up
                if($cleanupDidRun)
                    {
                        Write-Host -Message $("Cleanup process completed ran for {0}" -f  (New-TimeSpan -Start $cleanupStartTime -End (Get-Date)).ToString("hh\:mm\:ss")) -ForegroundColor Green
                    }

                # notify total runtime
                Write-Host -message $("⏱️ Total Script Runtime: {0}" -f (New-TimeSpan -Start $StartTime -End (Get-Date)).ToString("hh\:mm\:ss")) -ForegroundColor Cyan
            }
    }



Export-ModuleMember -Function Test-SilkResourceDeployment

