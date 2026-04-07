

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

                Function Version: 1.0.3
                Supporting Silk SDP configurations from Flex: v2.10.86 VisionOS: v8.6.10

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
                - "Increased_Logical_Capacity_AMD" (Standard_E64as_v6) - AMD-based high memory SKU with increased capacity capabilities
                - "Increased_Logical_Capacity" (Standard_E64s_v5) - High memory SKU, most commonly used due to increased capacity capabilities and cost effectiveness
                - "Read_Cache_Enabled" (Standard_L64s_v3) - High-speed local SSD storage for read-intensive workloads
                - "No_Increased_Logical_Capacity_AMD" (Standard_D64as_v6) - AMD-based basic compute SKU
                - "No_Increased_Logical_Capacity" (Standard_D64s_v5) - Basic compute SKU, uncommonly used in favor of the increased logical capacity configuration
                - "Entry_Level" (Standard_E32as_v5) - Production entry level SKU for smaller deployments

            .PARAMETER CNodeSku
                Explicit Azure VM SKU for CNode VMs when using direct SKU specification.
                Alternative to CNodeFriendlyName for advanced scenarios requiring specific SKU control.
                Valid values: "Standard_E64as_v6", "Standard_E64s_v5", "Standard_L64s_v3", "Standard_D64as_v6", "Standard_D64s_v5", "Standard_E32as_v5"

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
                Array of MNode storage capacities for Lsv3 series SKUs.
                Valid values correspond to physical storage capacity in TiB:
                - "19.5" TiB (Standard_L8s_v3)  - 8 vCPU, 64 GB RAM, local NVMe storage
                - "39.1" TiB (Standard_L16s_v3) - 16 vCPU, 128 GB RAM, local NVMe storage
                - "78.2" TiB (Standard_L32s_v3) - 32 vCPU, 256 GB RAM, local NVMe storage
                Example: @("19.5", "39.1") for mixed capacity deployment

            .PARAMETER MnodeSizeLsv4
                Array of MNode storage capacities for Lsv4 series SKUs.
                Valid values correspond to physical storage capacity in TiB:
                - "19.5" TiB (Standard_L8s_v4)  - 8 vCPU, 64 GB RAM, local NVMe storage
                - "39.1" TiB (Standard_L16s_v4) - 16 vCPU, 128 GB RAM, local NVMe storage
                - "78.2" TiB (Standard_L32s_v4) - 32 vCPU, 256 GB RAM, local NVMe storage
                Example: @("19.5", "39.1") for mixed capacity deployment

            .PARAMETER MnodeSizeLasv3
                Array of MNode storage capacities for Lsv3 series SKUs.
                Valid values correspond to physical storage capacity in TiB:
                - "19.5" TiB (Standard_L8as_v3)  - 8 vCPU, 64 GB RAM, local NVMe storage
                - "39.1" TiB (Standard_L16as_v3) - 16 vCPU, 128 GB RAM, local NVMe storage
                - "78.2" TiB (Standard_L32as_v3) - 32 vCPU, 256 GB RAM, local NVMe storage
                Example: @("19.5", "39.1") for mixed capacity deployment

            .PARAMETER MnodeSizeLasv4
                Array of MNode storage capacities for Lasv4 series SKUs.
                Valid values correspond to physical storage capacity in TiB:
                - "19.5" TiB (Standard_L8as_v4)  - 8 vCPU, 64 GB RAM, local NVMe storage
                - "39.1" TiB (Standard_L16as_v4) - 16 vCPU, 128 GB RAM, local NVMe storage
                - "78.2" TiB (Standard_L32as_v4) - 32 vCPU, 256 GB RAM, local NVMe storage
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
                Default: Current working directory.
                HTML reports are generated by default unless -NoHTMLReport is specified.
                The filename is automatically generated using the -ReportLabel prefix, region, zone, and a timestamp.
                Example: -ReportOutputPath "C:\Reports" saves the report to 'C:\Reports\Silk-eastus-1-DeploymentReport_yyyyMMdd_HHmmss.html'

            .PARAMETER ReportLabel
                Label prefix used as the first part of the HTML report filename, page title, and report heading.
                If not provided, the value is automatically sourced from the 'customer_name' field in the JSON configuration file (if used).
                If neither is specified, defaults to 'Silk' - producing filenames in the format 'Silk-[Region]-[Zone]-DeploymentReport_[timestamp].html'.
                Customize this to brand reports for a specific customer or deployment environment.
                The label is also embedded in the browser tab title and the main heading inside the report.
                Region and Zone are automatically appended to the filename, title, and heading when available.
                Example: -ReportLabel 'Contoso' with Region 'eastus' and Zone '1' produces:
                    Filename : Contoso-eastus-1-DeploymentReport_20260310_143052.html
                    Title    : Contoso eastus 1 Azure SKU Availability Report - 2026-03-10 14:30:52
                    Heading  : 🏗️ Contoso eastus 1 Azure SKU Availability Report

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

            .PARAMETER GenerateReportOnly
                Switch parameter to generate an SKU availability and quota analysis report without deploying any resources.
                Performs comprehensive SKU support checking across all Silk-supported VM families, quota analysis,
                and zone availability validation. Produces both console output and an HTML report.
                Useful for pre-deployment capacity planning and environment validation.
                Can be combined with -TestAllZones for multi-zone analysis.

            .PARAMETER TestAllSKUFamilies
                Switch parameter to test all Silk-supported VM SKU families in the specified region and zone.
                Deploys a single reduced-size test VM for each unique SKU family to validate actual deployment
                capacity beyond what quota and zone availability data alone can confirm.
                Automatically enables Development Mode to minimize quota consumption and deployment time.
                Results include per-SKU deployment pass/fail status with failure categorization.
                Can be combined with -TestAllZones to test all SKU families across all availability zones.

            .PARAMETER TestAllZones
                Switch parameter to expand testing across all availability zones in the specified region.
                When combined with -TestAllSKUFamilies, deploys test VMs for each SKU in every supported zone.
                When combined with -GenerateReportOnly, produces a multi-zone SKU support matrix.
                The -Zone parameter is still used for zone alignment reporting purposes.
                Results include a per-zone availability matrix in both console and HTML report output.
                Not compatible with -ProximityPlacementGroupName or -AvailabilitySetName: existing infrastructure
                is zone-locked to the PPG zone and multi-zone deployment against it is not a valid operation.

            .PARAMETER Development
                Switch parameter to enable Development Mode with reduced VM sizes and instance counts.
                When enabled, CNode VMs use 2 vCPU SKUs instead of production 64 vCPU, and MNode groups
                deploy 1 DNode instead of 16. Significantly reduces deployment time, cost, and quota
                consumption for faster testing iterations.
                Automatically enabled by -TestAllSKUFamilies. The SKU reference table in the HTML report
                always displays full production SKU sizes regardless of this setting.

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
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -RunCleanupOnly

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

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -GenerateReportOnly

                Generates an SKU availability and quota analysis report without deploying any resources.
                Analyzes all Silk-supported VM families for zone support, quota availability, and region presence.
                Produces console output and an HTML report with a comprehensive SKU reference table.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -TestAllSKUFamilies

                Tests all Silk-supported VM SKU families by deploying a reduced-size test VM for each unique SKU.
                Validates actual deployment capacity and produces a deployment test results report showing
                pass/fail status per SKU family with failure categorization (capacity, quota, SKU restriction).

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -TestAllSKUFamilies -TestAllZones

                Tests all Silk-supported VM SKU families across all availability zones in the region.
                Deploys test VMs for each SKU in every supported zone and produces a multi-zone deployment
                results matrix showing per-zone pass/fail status for each SKU family.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCount 2 -MnodeSizeLsv3 @("19.5","39.1") -TestAllZones

                Tests a specific deployment configuration across all availability zones simultaneously.
                Deploys the full CNode and MNode configuration into every zone where all requested SKUs are
                supported, producing a multi-zone deployment comparison showing pass/fail per zone.
                The -Zone parameter is still used for zone alignment reporting.

            .EXAMPLE
                Test-SilkResourceDeployment -ChecklistJSON "C:\configs\silk-deployment.json" -ReportLabel "Contoso" -ReportOutputPath "C:\Reports"

                Runs the deployment check with a custom report label and output directory.
                The HTML report will be saved as 'C:\Reports\Contoso-eastus-1-DeploymentReport_yyyyMMdd_HHmmss.html' (region and zone sourced from JSON).
                The browser tab title and report heading will read 'Contoso eastus 1 Azure SKU Availability Report'.
                Useful when running checks on behalf of a customer or to distinguish reports across multiple environments.

            .EXAMPLE
                Test-SilkResourceDeployment -SubscriptionId "12345678-1234-1234-1234-123456789012" -ResourceGroupName "silk-test-rg" -Region "eastus" -Zone "1" -CNodeFriendlyName "Increased_Logical_Capacity" -CNodeCount 2 -ReportLabel "Contoso" -ReportOutputPath "C:\Reports\Contoso"

                Runs a standard CNode deployment check and saves a fully branded report.
                Report saved as 'C:\Reports\Contoso\Contoso-eastus-1-DeploymentReport_yyyyMMdd_HHmmss.html'.
                Heading and title will read 'Contoso eastus 1 Azure SKU Availability Report'.

            .INPUTS
                Command line parameters or JSON configuration file containing deployment specifications.
                Supports both individual parameter specification and bulk configuration via JSON import.

            .OUTPUTS
                Console output with comprehensive deployment status information, resource validation results,
                SKU availability reports, quota validation summaries (including adjusted deployment counts when
                quota is insufficient), and deployment progress tracking.
                Additionally, an HTML report is generated (unless -NoHTMLReport is specified) summarizing deployment status,
                quota usage, SKU support, and resource validation results. The HTML report includes a light/dark theme
                toggle switch and persists the user's theme preference. The report is saved to the path specified by
                -ReportOutputPath or defaults to the current working directory in the format '[ReportLabel]-[Region]-[Zone]-DeploymentReport_[timestamp].html' (default label: 'Silk'; region and zone segments are omitted if not available).
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
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $true,  HelpMessage = $("Enter your Azure Subscription ID (GUID format). Example: 12345678-1234-1234-1234-123456789012"))]
                [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $SubscriptionId,

                # Azure Resource Group name where test resources will be deployed
                # Resource group must already exist in the specified subscription
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $true,  HelpMessage = $("Enter the name of an existing Azure Resource Group where test resources will be deployed. Example: my-test-rg"))]
                [ValidatePattern('^[a-z][a-z0-9\-]{1,61}[a-z0-9]$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceGroupName,

                # Azure region for resource deployment - must be a valid Azure region name
                # Common examples: eastus, westus2, northeurope, eastasia
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $false, HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $true,  HelpMessage = $("Choose an Azure region for deployment. Popular options: eastus, westus2, centralus, northeurope, eastasia"))]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [ValidateNotNullOrEmpty()]
                [string]
                $Region,

                # Azure Availability Zone for resource placement (1, 2, 3, or Zoneless for regions without zones)
                # Use "Zoneless" for regions that do not support availability zones
                # Overrides JSON configuration values when specified via command line
                # if -ZoneAlignmentSubscriptionId specified, zone alignment will occur unless -DisableZoneAlignment is also specified
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON",     Mandatory = $false, HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cleanup Only",                   Mandatory = $false, HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $true,  HelpMessage = $("Select an Availability Zone: 1, 2, 3 (for high availability) or Zoneless (for regions without zone support)."))]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [ValidateNotNullOrEmpty()]
                [string]
                $Zone,

                # Path to JSON configuration file containing all deployment parameters
                # When specified, all parameters are loaded from file unless overridden by command line
                # Enables simplified deployment management and repeatability
                [Parameter(ParameterSetName = 'ChecklistJSON',              Mandatory = $true, HelpMessage = $("Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\configs\silk-deployment.json"))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON", Mandatory = $true, HelpMessage = $("Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\configs\silk-deployment.json"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",  Mandatory = $true, HelpMessage = $("Enter the full path to a JSON configuration file containing deployment parameters. Example: C:\configs\silk-deployment.json"))]
                [string]
                $ChecklistJSON,

                # Friendly name for CNode SKU selection using descriptive categories
                # Increased_Logical_Capacity (Standard_E64s_v5) - Most common, high memory
                # Read_Cache_Enabled (Standard_L64s_v3) - High-speed local SSD storage
                # No_Increased_Logical_Capacity (Standard_D64s_v5) - Basic compute, rarely used
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = $("Choose CNode type: Increased_Logical_Capacity_Easv6 (Standard_E64as_v6), Increased_Logical_Capacity_Easv5 (Standard_E64as_v5), Increased_Logical_Capacity_Esv5 (Standard_E64s_v5), Read_Cache_Enabled_Lasv4 (Standard_L64as_v4), Read_Cache_Enabled_Lasv3 (Standard_L64as_v3), Read_Cache_Enabled_Lsv3 (Standard_L64s_v3), No_Increased_Logical_Capacity_Dasv6 (Standard_D64as_v6), No_Increased_Logical_Capacity_Dasv5 (Standard_D64as_v5), No_Increased_Logical_Capacity_Dsv5 (Standard_D64s_v5), or Entry_Level (Standard_E32as_v5)."))]
                [ValidateSet("Increased_Logical_Capacity_Eav6","Increased_Logical_Capacity_Easv5","Increased_Logical_Capacity_Esv5","Read_Cache_Enabled_Lasv4","Read_Cache_Enabled_Lasv3","Read_Cache_Enabled_Lsv3","No_Increased_Logical_Capacity_Dav6","No_Increased_Logical_Capacity_Dasv5","No_Increased_Logical_Capacity_Dsv5","Entry_Level_Easv3")]
                [string]
                $CNodeFriendlyName,

                # Explicit Azure VM SKU for CNode VMs when using direct SKU specification
                # Standard_E64s_v5 (default) - High memory, Standard_L64s_v3 - SSD storage, Standard_D64s_v5 - Basic compute
                # Alternative to CNodeFriendlyName for advanced scenarios requiring specific SKU control
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = $("Choose CNode VM SKU: Standard_E64as_v6, Standard_E64as_v5 or Standard_E64s_v5 (supports increased logical capacity), Standard_L64as_v4, Standard_L64as_v3 or Standard_L64s_v3 (supports read cache), Standard_D64as_v6, Standard_D64as_v5 or Standard_D64s_v5 (Basic Production CNode), or Standard_E32as_v5 (Production Entry Level)."))]
                [ValidateSet("Standard_D64as_v6", "Standard_D64s_v5", "Standard_D64as_v5", "Standard_L64as_v4", "Standard_L64as_v3", "Standard_L64s_v3", "Standard_E64as_v6", "Standard_E64s_v5", "Standard_E64as_v5", "Standard_E32as_v5")]
                [string]
                $CNodeSku,

                # Number of CNode VMs to deploy (range: 2-8)
                # Silk Infrastructure requires minimum 2 CNodes for pod resilience, supporting up to 8 for maximum performance
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = $("Enter number of CNode VMs to deploy (2-8). Minimum 2 required Maximum of 8. 3 CNodes required at deployment to enable up to 1 PB of logical capacity."))]
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

                # Array of MNode storage capacities for Lsv3 series SKUs
                # Valid values: "19.5" (L8s_v3), "39.1" (L16s_v3), "78.2" (L32s_v3) TiB capacity
                # Example: @("19.5", "39.1") for mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",  Mandatory = $true, HelpMessage = $("Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",    Mandatory = $true, HelpMessage = $("Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                 Mandatory = $true, HelpMessage = $("Specify Lsv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [ValidateSet("19.5", "39.1", "78.2")]
                [ValidateCount(1, 4)]
                [string[]]
                $MnodeSizeLsv3,

                # Array of MNode storage capacities for Lsv4 series SKUs
                # Valid values: "19.5" (L8s_v4), "39.1" (L16s_v4), "78.2" (L32s_v4) TiB capacity
                # Example: @("19.5", "39.1") for mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",  Mandatory = $true, HelpMessage = $("Specify Lsv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",    Mandatory = $true, HelpMessage = $("Specify Lsv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                 Mandatory = $true, HelpMessage = $("Specify Lsv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [ValidateSet("19.5", "39.1", "78.2")]
                [ValidateCount(1, 4)]
                [string[]]
                $MnodeSizeLsv4,

                # Array of MNode storage capacities for Lasv3 series SKUs
                # Valid values: "19.5" (L8as_v3), "39.1" (L16as_v3), "78.2" (L32as_v3) TiB capacity
                # Example: @("19.5", "39.1") for mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",  Mandatory = $true, HelpMessage = $("Specify Lasv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",    Mandatory = $true, HelpMessage = $("Specify Lasv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                 Mandatory = $true, HelpMessage = $("Specify Lasv3 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [ValidateSet("19.5", "39.1", "78.2")]
                [ValidateCount(1, 4)]
                [string[]]
                $MnodeSizeLasv3,

                # Array of MNode storage capacities for Lasv4 series SKUs
                # Valid values: "19.5" (L8as_v4), "39.1" (L16as_v4), "78.2" (L32as_v4) TiB capacity
                # Example: @("19.5", "39.1") for mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",  Mandatory = $true, HelpMessage = $("Specify Lasv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",    Mandatory = $true, HelpMessage = $("Specify Lasv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                 Mandatory = $true, HelpMessage = $("Specify Lasv4 MNodes sizes. Valid sizes are: 19.5, 39.1, 78.2 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [ValidateSet("19.5", "39.1", "78.2")]
                [ValidateCount(1, 4)]
                [string[]]
                $MnodeSizeLasv4,

                # Array of MNode storage capacities for Laosv4 series SKUs (newer generation, higher density)
                # Valid values: "14.67" (L2aos_v4), "29.34" (L4aos_v4), "58.67" (L8aos_v4), "88.01" (L12aos_v4), "117.35" (L16aos_v4) TiB capacity
                # Example: @("14.67", "29.34") for cost-optimized mixed capacity deployment
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $true, HelpMessage = $("Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $true, HelpMessage = $("Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $true, HelpMessage = $("Specify Laosv4 MNodes sizes. Valid sizes are: 14.67, 29.34, 58.67, 88.01, 117.35 (comma-separated, up to 4 values). Each value represents an MNode in TiB of storage capacity."))]
                [ValidateCount(1, 4)]
                [ValidateSet("14.67", "29.34", "58.67", "88.01", "117.35")]
                [string[]]
                $MnodeSizeLaosv4,

                # Array of explicit Azure VM SKUs for MNode/DNode VMs when using direct SKU specification
                # Lsv3 SKUs: Standard_L8s_v3, Standard_L16s_v3, Standard_L32s_v3
                # Laosv4 SKUs: Standard_L2aos_v4, Standard_L4aos_v4, Standard_L8aos_v4, Standard_L12aos_v4, Standard_L16aos_v4
                # Alternative to size-based selection for advanced scenarios requiring specific SKU control
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = $("Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Lasv3 options: Standard_L8as_v3 (19.5 TiB), Standard_L16as_v3 (39.1 TiB), Standard_L32as_v3 (78.2 TiB). LSv4 options: Standard_L8s_v4 (19.5 TiB), Standard_L16s_v4 (39.1 TiB), Standard_L32s_v4 (78.2 TiB). Lasv4 options: Standard_L8as_v4 (19.5 TiB), Standard_L16as_v4 (39.1 TiB), Standard_L32as_v4 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB)."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = $("Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Lasv3 options: Standard_L8as_v3 (19.5 TiB), Standard_L16as_v3 (39.1 TiB), Standard_L32as_v3 (78.2 TiB). LSv4 options: Standard_L8s_v4 (19.5 TiB), Standard_L16s_v4 (39.1 TiB), Standard_L32s_v4 (78.2 TiB). Lasv4 options: Standard_L8as_v4 (19.5 TiB), Standard_L16as_v4 (39.1 TiB), Standard_L32as_v4 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB)."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true, HelpMessage = $("Select MNode VM SKU. LSv3 options: Standard_L8s_v3 (19.5 TiB), Standard_L16s_v3 (39.1 TiB), Standard_L32s_v3 (78.2 TiB). Lasv3 options: Standard_L8as_v3 (19.5 TiB), Standard_L16as_v3 (39.1 TiB), Standard_L32as_v3 (78.2 TiB). LSv4 options: Standard_L8s_v4 (19.5 TiB), Standard_L16s_v4 (39.1 TiB), Standard_L32s_v4 (78.2 TiB). Lasv4 options: Standard_L8as_v4 (19.5 TiB), Standard_L16as_v4 (39.1 TiB), Standard_L32as_v4 (78.2 TiB). Laosv4 options: Standard_L2aos_v4 (14.67 TiB) to Standard_L16aos_v4 (117.35 TiB)."))]
                [ValidateSet("Standard_L2aos_v4", "Standard_L4aos_v4", "Standard_L8aos_v4", "Standard_L12aos_v4", "Standard_L16aos_v4", "Standard_L8as_v3", "Standard_L16as_v3", "Standard_L32as_v3", "Standard_L8as_v4", "Standard_L16as_v4", "Standard_L32as_v4", "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3", "Standard_L8s_v4", "Standard_L16s_v4", "Standard_L32s_v4")]
                [string[]]
                $MNodeSku,

                # Number of MNode instances when using explicit SKU specification (range: 1-4)
                # Determines how many DNode VMs are deployed per MNode configuration
                # Production typically uses 1 MNode per capacity requirement
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $true, HelpMessage = $("Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $true, HelpMessage = $("Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $true, HelpMessage = $("Enter number (1-4) of MNode instances (x16 DNode VMs) to deploy."))]
                [ValidateRange(1, 4)]
                [ValidateNotNullOrEmpty()]
                [int]
                $MNodeCount,

                # Subscription ID to compare zone alignment against the deployment subscription *Requires AvailablityZonePeering feature to be registered*
                # When specified, the script ouputs the deployment region and zone alignment with this given subscription
                # Useful for validating zone support and alignment across multiple subscriptions
                # if using the json configuration file, this parameter is assumed to be the subscription in the configuration file
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Enter an additional Azure Subscription ID to check the regions zone alignment. Example: 12345678-1234-1234-1234-123456789012"))]
                [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $ZoneAlignmentSubscriptionId,

                # Switch to disable zone alignment, by default  the script  will align the deployment zone with the either the -ZoneAlignmentSubscriptionId or the subscription in the json configuration file
                # Must provide -ZoneAlignmentSubscriptionId OR
                # Must provide the -ChecklistJSON configuration and specify a different -SubscriptionId
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Disable zone alignment check. Zone alignment is enabled by default when an additional subscription ID is provided."))]
                [Switch]
                $DisableZoneAlignment,

                # Switch to disable HTML report generation
                # By default, a comprehensive HTML report is generated summarizing deployment status,
                # quota usage, SKU support, and resource validation results
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Disable HTML report generation. Reports are generated by default."))]
                [Switch]
                $NoHTMLReport,

                # Path where the HTML report should be saved
                # Default: Current working directory with filename '[ReportLabel]-[Region]-[Zone]-DeploymentReport_[timestamp].html'
                # HTML reports are generated by default unless -NoHTMLReport is specified
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Path where the HTML report should be saved. Defaults to current working directory."))]
                [ValidateNotNullOrEmpty()]
                [string]
                $ReportOutputPath = (Get-Location).Path,

                # Label prefix for the HTML report filename
                # Default: 'Silk' - results in filename format 'Silk-[Region]-[Zone]-DeploymentReport_[timestamp].html'
                # Customize to distinguish reports from different deployments or environments
                # Example: 'Contoso' with Region 'eastus' and Zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Label prefix for the HTML report filename. Default: 'Silk'. Example: 'Contoso' with region 'eastus' zone '1' produces 'Contoso-eastus-1-DeploymentReport_[timestamp].html'"))]
                [string]
                $ReportLabel,

                # Switch to disable automatic cleanup of test resources after deployment validation
                # When specified, resources remain in Azure for manual inspection or extended testing
                # Resources must be manually removed or cleaned up using -RunCleanupOnly parameter
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Skip automatic cleanup to keep test resources for inspection. Use -RunCleanupOnly later to clean up."))]
                [Switch]
                $DisableCleanup,

                # Switch to only perform cleanup operations, removing all previously created test resources
                # Identifies and removes resources based on resource name prefix (default: "sdp-test")
                # Use this to clean up resources from failed deployments or when cleanup was disabled
                [Parameter(ParameterSetName = "Cleanup Only",               Mandatory = $true, HelpMessage = $("Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group"))]
                [Parameter(ParameterSetName = "Cleanup Only ChecklistJSON", Mandatory = $true, HelpMessage = $("Run cleanup only mode to remove all test resources (prefixed by -ResourceNamePrefix default is 'sdp-test') from the resource group"))]
                [Switch]
                $RunCleanupOnly,

                # CIDR notation for VNet and subnet IP address range, will not be peered or exposed otherwise.
                # Default: "10.0.0.0/24" (provides 254 usable IP addresses)
                # Overrides JSON configuration values when specified via command line
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Specify VNet CIDR range for VNET and subnet IP space. Example: 10.0.0.0/24"))]
                [ValidatePattern('^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/(3[0-2]|[1-2][0-9]|[0-9]))$')]
                [ValidateNotNullOrEmpty()]
                [string]
                $IPRangeCIDR,

                # Switch to enabled Creation of a resource group by the given resource group name
                # The resource group must NOT already exist
                # When specified, a resource group is created for the test deployment and deleted
                # the -RunCleanupOnly parameter can not be used to clean up resource groups you will have to manually delete them
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Advanced Option to create a resource group by the given name, requires elevated Role assignment."))]
                [Switch]
                $CreateResourceGroup,

                # Azure Marketplace image offer for VM operating system
                # Default: "0001-com-ubuntu-server-jammy" (Ubuntu 22.04 LTS)
                # Advanced parameter - modify only if specific OS requirements exist
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Azure Marketplace VM image offer. Default: 0001-com-ubuntu-server-jammy (Ubuntu 22.04 LTS). Advanced use only"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageOffer = "0001-com-ubuntu-server-jammy",

                # Azure Marketplace image publisher for VM operating system
                # Default: "Canonical" (official Ubuntu publisher)
                # Advanced parameter - modify only if using non-Ubuntu images
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Azure Marketplace VM image publisher. Default: Canonical (Ubuntu). Advanced use only"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImagePublisher = "Canonical",

                # Azure Marketplace image SKU for VM operating system
                # If not specified, automatically selects latest available SKU with Gen2 preference
                # Advanced parameter - function auto-detects best available SKU for most scenarios
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Azure Marketplace VM image SKU. Leave blank for auto-detection of latest Gen2 SKU. Advanced use only"))]
                [string]
                $VMImageSku,

                # Azure Marketplace image version for VM operating system
                # Default: "latest" (automatically uses most recent image version)
                # Advanced parameter - specify only if specific image version required for compliance
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Azure Marketplace VM image version. Default: latest (most recent). Specify version only for compliance requirements"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageVersion = "latest",

                # Prefix used for all created Azure resource names to enable easy identification and cleanup
                # Default: "sdp-test" (creates names like "sdp-test-cnode-01", "sdp-test-vnet")
                # Modify for multiple parallel test deployments or organizational naming standards
                [Parameter(HelpMessage = $("Resource name prefix for easy identification and cleanup. Default: sdp-test. Example: my-test (creates my-test-cnode-01, my-test-vnet)"))]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceNamePrefix = "sdp-test",

                # Switch to generate a report without deploying any resources
                # Performs SKU availability checks and quota analysis only
                # Useful for pre-deployment validation and capacity planning
                # Mandatory on Report Only sets; optional modifier on deployment sets
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $true,  HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $true,  HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "ChecklistJSON",                  Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Generate a report without deploying resources."))]
                [Switch]
                $GenerateReportOnly,

                # Switch to test all SKU families in the specified region and zone
                # Expands testing beyond the requested CNode/MNode to all Silk-supported VM families
                # Results appear in an expanded report section (Phase 2+ implementation)
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $true,  HelpMessage = $("Test all SKU families in the specified region and zone."))]
                [Switch]
                $TestAllSKUFamilies,

                # Switch to test all availability zones in the specified region
                # Can be used with any deployment or report parameter set as a modifier
                # When specified, deployment testing occurs across all supported zones in the region
                # Zone parameter is still used for zone alignment reporting purposes
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Report Only",                    Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "Report Only ChecklistJSON",      Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Test all availability zones in the specified region."))]
                [Switch]
                $TestAllZones,

                # Switch to enable Development Mode with reduced VM sizes and instance counts
                # When enabled: Uses 2 vCPU SKUs instead of production 64 vCPU, 1 DNode per MNode instead of 16
                # Significantly reduces deployment time and costs for faster testing iterations
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("Enable Development Mode with reduced VM sizes and instance counts."))]
                [Switch]
                $Development,

                # PowerShell credential object for VM local administrator account
                # Default: Username "azureuser" with secure password for testing purposes
                # Used for VM deployment - SSH key authentication not implemented in test scenarios
                [Parameter(ParameterSetName = 'ChecklistJSON',                  Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode",                 Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Existing Infra",  Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3",      Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv4",      Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv3",     Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lasv4",     Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4",    Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU",    Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU",                   Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Existing Infra",    Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3",        Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv4",        Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv3",       Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lasv4",       Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4",      Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU",      Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode Lsv3",                     Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode Lsv4",                     Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode Lasv3",                    Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode Lasv4",                    Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode Laosv4",                   Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "Mnode by SKU",                   Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [Parameter(ParameterSetName = "SKU Family Test",                Mandatory = $false, HelpMessage = $("PowerShell credential object to assign to VM local administrator account."))]
                [ValidateNotNullOrEmpty()]
                [pscredential]
                $VMInstanceCredential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "azureuser", (ConvertTo-SecureString 'sdpD3ploym3ntT3$t' -AsPlainText -Force))
            )

        begin
            {
                $StartTime = Get-Date
                Write-Verbose -Message $("=== Starting Silk Resource Deployment Test Script ===")
                Write-Verbose -Message $("Script started at: {0}" -f $StartTime.ToString("yyyy-MM-dd HH:mm:ss"))


                # ===============================================================================
                # CNode SKU Configuration Object
                # ===============================================================================
                # Maps friendly CNode names to their corresponding Azure VM SKUs
                # CNode Types:
                # - Standard_D*_v*: Basic compute, minimal memory (No_Increased_Logical_Capacity)
                # - Standard_L*_v*: High-speed local SSD storage (Read_Cache_Enabled)
                # - Standard_E*_v*: High memory, most commonly used (Increased_Logical_Capacity)

                # Production CNode SKU Configuration
                # Actual production deployments use 64 vCPU SKUs for high performance
                $cNodeSizeObject = @(
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "as_v6"; QuotaFamily = "Standard Dav6 Family vCPUs";     cNodeFriendlyName = "No_Increased_Logical_Capacity_Dav6"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "as_v5"; QuotaFamily = "Standard Dasv5 Family vCPUs";    cNodeFriendlyName = "No_Increased_Logical_Capacity_Dasv5"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "s_v5";  QuotaFamily = "Standard Dsv5 Family vCPUs";     cNodeFriendlyName = "No_Increased_Logical_Capacity_Dsv5"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "as_v4"; QuotaFamily = "Standard Lasv 4 Family vCPUs";   cNodeFriendlyName = "Read_Cache_Enabled_Lasv4"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "as_v3"; QuotaFamily = "Standard Lasv3 Family vCPUs";    cNodeFriendlyName = "Read_Cache_Enabled_Lasv3"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "s_v3";  QuotaFamily = "Standard Lsv3 Family vCPUs";     cNodeFriendlyName = "Read_Cache_Enabled_Lsv3"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "as_v6"; QuotaFamily = "Standard Eav6 Family vCPUs";     cNodeFriendlyName = "Increased_Logical_Capacity_Eav6"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "as_v5"; QuotaFamily = "Standard Easv5 Family vCPUs";    cNodeFriendlyName = "Increased_Logical_Capacity_Easv5"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "s_v5";  QuotaFamily = "Standard Esv5 Family vCPUs";     cNodeFriendlyName = "Increased_Logical_Capacity_Esv5"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 32; vmSkuSuffix = "as_v5"; QuotaFamily = "Standard Easv5 Family vCPUs";    cNodeFriendlyName = "Entry_Level_Easv5"};
                                    )

                # Preserve full-size (production) CNode SKU objects for the SKU Support & Quota Reference
                # table so it always reports production-grade VM SKUs regardless of Development mode
                $cNodeSizeObjectFullSize = $cNodeSizeObject

                # SKU Family Test mode implicitly uses development-sized configurations
                # to minimize quota consumption and deployment time when testing all families
                if ($TestAllSKUFamilies -and (-not $Development))
                    {
                        Write-Verbose -Message $("SKU Family Test mode - automatically enabling Development Mode for reduced VM sizes.")
                        $Development = $true
                    }

                if ($Development)
                    {
                        Write-Verbose -Message $("Running in Development Mode, dynamically generating reduced CNode configuration for faster deployment.")

                        # Generate development configuration by transforming production configuration
                        # Lsv3 series has minimum of 8 vCPU, others can use 2 vCPU
                        $cNodeSizeObject = $cNodeSizeObject | ForEach-Object    {
                                                                                    # Determine development vCPU based on SKU series minimum vcpu count requirements
                                                                                    $devVcpu = if ($_.vmSkuPrefix -eq 'Standard_L' -and $_.vmSkuSuffix -match 's_v3') { 8 } else { 2 }

                                                                                    [pscustomobject]@{
                                                                                                        vmSkuPrefix = $_.vmSkuPrefix
                                                                                                        vCPU = $devVcpu
                                                                                                        vmSkuSuffix = $_.vmSkuSuffix
                                                                                                        QuotaFamily = $_.QuotaFamily
                                                                                                        cNodeFriendlyName = $_.cNodeFriendlyName
                                                                                                    }
                                                                                }
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
                # Lsv3 Series (NVMe SSD storage - older generation, proven stability):
                # - 19 TiB: Standard_L8as_v3  (8 vCPU, 64 GB RAM, local NVMe storage)
                # - 39 TiB: Standard_L16as_v3 (16 vCPU, 128 GB RAM, local NVMe storage)
                # - 78 TiB: Standard_L32as_v3 (32 vCPU, 256 GB RAM, local NVMe storage)
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
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v4";   PhysicalSize = 19.5;    QuotaFamily = "Standard Lsv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v4";   PhysicalSize = 39.1;    QuotaFamily = "Standard Lsv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v4";   PhysicalSize = 78.2;    QuotaFamily = "Standard Lsv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "as_v3";  PhysicalSize = 19.5;    QuotaFamily = "Standard Lasv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "as_v3";  PhysicalSize = 39.1;    QuotaFamily = "Standard Lasv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "as_v3";  PhysicalSize = 78.2;    QuotaFamily = "Standard Lasv3 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "as_v4";  PhysicalSize = 19.5;    QuotaFamily = "Standard Lasv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "as_v4";  PhysicalSize = 39.1;    QuotaFamily = "Standard Lasv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "as_v4";  PhysicalSize = 78.2;    QuotaFamily = "Standard Lasv 4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01;   QuotaFamily = "Standard Laosv4 Family vCPUs"};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35;  QuotaFamily = "Standard Laosv4 Family vCPUs"}
                                    )

                # Preserve full-size (production) MNode SKU objects for the SKU Support & Quota Reference
                # table so it always reports production-grade VM SKUs regardless of Development mode
                $mNodeSizeObjectFullSize = $mNodeSizeObject

                if ($Development)
                    {
                        Write-Verbose -Message $("Running in Development Mode, dynamically generating reduced MNode/DNode configuration for faster deployment.")

                        # Generate development configuration by transforming production configuration
                        # Dynamically determines minimum vCPU per SKU family suffix from $mNodeSizeObject data
                        # Reduce dNodeCount from 16 to 1 for faster testing
                        # Build a lookup of minimum vCPU per suffix from the production size objects
                        # This ensures new SKU families automatically get correct dev mode sizing
                        $minVcpuBySuffix = @{}
                        $mNodeSizeObject | ForEach-Object  {
                                                                if (-not $minVcpuBySuffix.ContainsKey($_.vmSkuSuffix) -or $_.vCPU -lt $minVcpuBySuffix[$_.vmSkuSuffix])
                                                                    {
                                                                        $minVcpuBySuffix[$_.vmSkuSuffix] = $_.vCPU
                                                                    }
                                                            }
                        Write-Verbose -Message $("Development mode - minimum vCPU per family: {0}" -f (($minVcpuBySuffix.GetEnumerator() | ForEach-Object { $("{0}={1}" -f $_.Key, $_.Value) }) -join $(", ")))

                        $mNodeSizeObject = $mNodeSizeObject | ForEach-Object    {
                                                                                    # Determine development vCPU from dynamically computed per-suffix minimums
                                                                                    $devVcpu = $minVcpuBySuffix[$_.vmSkuSuffix]

                                                                                    [pscustomobject]@{
                                                                                                        dNodeCount = 1
                                                                                                        vmSkuPrefix = $_.vmSkuPrefix
                                                                                                        vCPU = $devVcpu
                                                                                                        vmSkuSuffix = $_.vmSkuSuffix
                                                                                                        PhysicalSize = $_.PhysicalSize
                                                                                                        QuotaFamily = $_.QuotaFamily
                                                                                                     }
                                                                                }
                    }


                # ========================================================================================================
                # Known Preview/New SKU Families Configuration
                # ========================================================================================================
                # Centralized list of SKU families that may not yet be registered in Azure's quota system
                # These families are typically in preview or newly released and may not appear in Get-AzVMUsage results
                # Update this list as new SKU families are released or when preview families become GA
                $knownPreviewSkuFamilies = @(
                                                $("Standard Easv6 Family vCPUs"),  # AMD-based E-series v6 with increased logical capacity
                                                $("Standard Dasv6 Family vCPUs")   # AMD-based D-series v6 general purpose
                                            )
                Write-Verbose -Message $("Tracking {0} known preview/new SKU families that may not be in quota system" -f $knownPreviewSkuFamilies.Count)

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
                # Deployment Progress Tracking Framework
                # ===============================================================================
                # Define weighted progress sections for end-to-end deployment tracking
                # Weights represent relative time/effort, not strictly binding percentages
                $progressSections = @{
                    'ModuleValidation'      = @{ Weight = 10;  StartPercent = 0;   EndPercent = 10  }
                    'Configuration'         = @{ Weight = 5;   StartPercent = 10;  EndPercent = 15  }
                    'EnvironmentValidation' = @{ Weight = 10;  StartPercent = 15;  EndPercent = 25  }
                    'QuotaAnalysis'         = @{ Weight = 25;  StartPercent = 25;  EndPercent = 50  }
                    'NetworkCreation'       = @{ Weight = 5;   StartPercent = 50;  EndPercent = 55  }
                    'VMDeployment'          = @{ Weight = 35;  StartPercent = 55;  EndPercent = 90  }
                    'Reporting'             = @{ Weight = 10;  StartPercent = 90;  EndPercent = 100 }
                }

                # Helper function to update staged progress
                function Update-StagedProgress
                    {

                        param
                            (
                                [Parameter(Mandatory = $true)]
                                [string]
                                $SectionName,

                                [Parameter(Mandatory = $false)]
                                [int]
                                $SectionCurrentStep = 0,

                                [Parameter(Mandatory = $false)]
                                [int]
                                $SectionTotalSteps = 1,

                                [Parameter(Mandatory = $false)]
                                [string]
                                $DetailMessage = $("")
                            )

                        if (-not $progressSections.ContainsKey($SectionName))
                            {
                                return
                            }

                        $section = $progressSections[$SectionName]
                        $sectionStart = $section.StartPercent
                        $sectionWeight = $section.Weight

                        # Calculate section-level progress (0-100 within section)
                        $sectionPercent = if ($SectionTotalSteps -gt 0)
                            {
                                [Math]::Floor(($SectionCurrentStep / $SectionTotalSteps) * 100)
                            } `
                        else
                            {
                                100
                            }

                        # Calculate overall progress (0-100 across all sections)
                        $overallPercent = $sectionStart + (($sectionPercent / 100) * $sectionWeight)

                        # Main progress bar (top-level: overall deployment progress)
                        Write-Progress `
                            -Id 1 `
                            -Activity $("Deployment Progress") `
                            -Status $("{0} ({1}%)" -f $SectionName, [Math]::Floor($overallPercent)) `
                            -PercentComplete ([Math]::Floor($overallPercent))

                        # Child progress bar (detailed operation within section)
                        if ($DetailMessage)
                            {
                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity $SectionName `
                                    -Status $DetailMessage `
                                    -PercentComplete $sectionPercent
                            } `
                        else
                            {
                                Write-Progress `
                                    -Id 2 `
                                    -ParentId 1 `
                                    -Activity $SectionName `
                                    -Status $(" ") `
                                    -PercentComplete $sectionPercent
                                Write-Progress -Id 2 -Completed
                            }
                    }

                # ===============================================================================
                # Centralized Report Data Object Factory
                # ===============================================================================
                # Creates a single PSCustomObject that serves as the canonical data source
                # for both console and HTML report rendering. Populated throughout execution
                # and consumed by Write-SilkConsoleReport / Write-SilkHTMLReport.
                function New-SilkReportData
                    {

                        return [PSCustomObject]@{

                            # ===== Metadata =====
                            Metadata =     [PSCustomObject]@{
                                                FunctionVersion     = $("1.98.10-2.0.0")
                                                StartTime           = $null
                                                EndTime             = $null
                                                Duration            = $null
                                                ReportMode          = $("Standard")
                                                TestAllZones        = $false
                                                ParameterSetName    = $("")
                                                ReportLabel         = $("Silk")
                                            }

                            # ===== Configuration =====
                            Configuration = [PSCustomObject]@{
                                                SubscriptionId      = $("")
                                                ResourceGroupName   = $("")
                                                Region              = $("")
                                                Zone                = $("")
                                                CNodeSKU            = $("")
                                                CNodeFriendlyName   = $("")
                                                CNodeCount          = 0
                                                CNodeCountAdjusted  = 0
                                                MNodeSizes          = @()
                                                MNodeSKUs           = @()
                                                IPRange             = $("")
                                                ResourceNamePrefix  = $("")
                                                UseExistingInfra    = $false
                                                PPGName             = $("")
                                                AvSetName           = $("")
                                                ZoneAlignmentSubId  = $("")
                                                DisableZoneAlignment = $false
                                                DisableCleanup      = $false
                                                DevelopmentMode     = $false
                                                NoHTMLReport        = $false
                                            }

                            # ===== Environment Validation =====
                            EnvironmentValidation = [PSCustomObject]@{
                                                        SubscriptionValid       = $false
                                                        SubscriptionName        = $("")
                                                        RegionValid             = $false
                                                        RegionDisplayName       = $("")
                                                        RegionGeography         = $("")
                                                        RegionPhysicalLocation  = $("")
                                                        ZoneValid               = $false
                                                        AvailableZones          = @()
                                                        ResourceGroupValid      = $false
                                                        ResourceGroupCreated    = $false
                                                        ExistingInfraValid      = $null
                                                        ModulesValid            = $false
                                                        ImageResolved           = $false
                                                        ImageDetails            = $null
                                                        ZoneAlignment =    [PSCustomObject]@{
                                                                                AlignmentPerformed  = $false
                                                                                AlignmentDisabled   = $false
                                                                                AlignmentSubId      = $("")
                                                                                OriginalZone        = $("")
                                                                                FinalZone           = $("")
                                                                                ZoneMappings        = @()
                                                                                Reason              = $("")
                                                                            }
                                                    }

                            # ===== SKU Support =====
                            SKUSupport =   [PSCustomObject]@{
                                                RawRegionSKUs           = $null
                                                RequestedCNodeSKU       = $null
                                                RequestedMNodeSKUs      = @()
                                                ComprehensiveReport     = @()
                                            }

                            # ===== Quota Analysis =====
                            QuotaAnalysis = [PSCustomObject]@{
                                                RawQuotaData            = $null
                                                CNodeQuota              = $null
                                                MNodeQuota              = @()
                                                ComprehensiveReport     = @()
                                                InfrastructureQuota     = @()
                                            }

                            # ===== Deployment =====
                            Deployment =   [PSCustomObject]@{
                                                Attempted               = $false
                                                SkippedReason           = $("")
                                                TotalExpectedVMs        = 0
                                                TotalDeployedVMs        = 0
                                                TotalFailedVMs          = 0
                                                VMReport                = @()
                                                ValidationFindings      = @()
                                                SkippedZones            = @()
                                                FindingsAnalysis =     [PSCustomObject]@{
                                                                            NoCapacityIssues    = @()
                                                                            QuotaIssues         = @()
                                                                            SKUSupportIssues    = @()
                                                                            OtherIssues         = @()
                                                                        }
                                                Infrastructure =       [PSCustomObject]@{
                                                                            VNetCreated         = $false
                                                                            VNetName            = $("")
                                                                            VNetAddressSpace    = $("")
                                                                            NSGCreated          = $false
                                                                            NSGName             = $("")
                                                                            PPGsCreated         = @()
                                                                            AvSetsCreated       = @()
                                                                            PPGsReferenced      = @()
                                                                            AvSetsReferenced    = @()
                                                                            NICsCreated         = 0
                                                                            TotalResources      = 0
                                                                        }
                                            }

                            # ===== Silk Component Summary =====
                            SilkSummary                 = @()

                            # ===== SKU Support Analysis (per-request) =====
                            SKUSupportData              = @()

                            # ===== Quota Analysis Data (infrastructure quotas) =====
                            QuotaAnalysisData           = @()

                            # ===== Multi-Zone Results =====
                            ZoneResults                 = @()

                            # ===== SKU Family Testing =====
                            SKUFamilyTesting =     [PSCustomObject]@{
                                                        Plan                    = @()
                                                        Results                 = @()
                                                        DeploymentResults       = @()
                                                    }

                            # ===== Cleanup =====
                            Cleanup =      [PSCustomObject]@{
                                                Performed               = $false
                                                StartTime               = $null
                                                Duration                = $null
                                                ResourcesRemoved        = 0
                                            }
                        }
                    }

                # ===============================================================================
                # Console Report Rendering Function
                # ===============================================================================
                # Reads exclusively from the centralized $ReportData object to produce
                # formatted console output. All data must be populated before calling.
                function Write-SilkConsoleReport
                    {

                        param
                            (
                                [Parameter(Mandatory = $true)]
                                [PSCustomObject]
                                $ReportData
                            )

                        # ---------------------------------------------------------------
                        # SKU Support and Quota Availability Report
                        # ---------------------------------------------------------------
                        Write-Verbose -Message $("Generating SKU support and quota availability analysis report")
                        Write-Host $("`n=== SKU Support and Quota Availability Report ===") -ForegroundColor Cyan
                        Write-Verbose -Message $("Analyzing SKU support for region '{0}' and zone '{1}' against deployment requirements" -f $ReportData.Configuration.Region, $ReportData.Configuration.Zone)

                        # CNode SKU Support Report
                        $cNodeData = $ReportData.SKUSupportData | Where-Object { $_.ComponentType -eq $("CNode") }
                        if ($cNodeData)
                            {
                                Write-Host $("`nCNode SKU Support:") -ForegroundColor Yellow
                                Write-Host $("  SKU: {0}" -f $cNodeData.SKUName)
                                Write-Host $("  Region: {0}" -f $ReportData.Configuration.Region)

                                switch ($cNodeData.ZoneSupportStatus)
                                    {
                                        "Success" { Write-Host $("  Zone Support: {0}" -f $cNodeData.ZoneSupport) -ForegroundColor Green }
                                        "Warning" { Write-Host $("  Zone Support: {0}" -f $cNodeData.ZoneSupport) -ForegroundColor Yellow }
                                        "Error"   { Write-Host $("  Region Support: {0}" -f $cNodeData.ZoneSupport) -ForegroundColor Red }
                                    }

                                if ($cNodeData.AvailableZones.Count -gt 0 -and $cNodeData.ZoneSupportStatus -ne $("Error"))
                                    {
                                        Write-Host $("  All Available Zones: {0}" -f ($cNodeData.AvailableZones -join $( ", ")))
                                    }
                            }

                        # MNode SKU Support Report
                        $mNodeData = $ReportData.SKUSupportData | Where-Object { $_.ComponentType -eq $("MNode") }
                        if ($mNodeData)
                            {
                                foreach ($mNodeTypeData in $mNodeData)
                                    {
                                        Write-Host $("`n{0} x MNode SKU Support ({1} TiB):" -f $mNodeTypeData.InstanceCount, $mNodeTypeData.PhysicalSize) -ForegroundColor Yellow
                                        Write-Host $("  SKU: {0}" -f $mNodeTypeData.SKUName)
                                        Write-Host $("  Region: {0}" -f $ReportData.Configuration.Region)

                                        switch ($mNodeTypeData.ZoneSupportStatus)
                                            {
                                                "Success" { Write-Host $("  Zone Support: {0}" -f $mNodeTypeData.ZoneSupport) -ForegroundColor Green }
                                                "Warning" { Write-Host $("  Zone Support: {0}" -f $mNodeTypeData.ZoneSupport) -ForegroundColor Yellow }
                                                "Error"   { Write-Host $("  Region Support: {0}" -f $mNodeTypeData.ZoneSupport) -ForegroundColor Red }
                                            }

                                        if ($mNodeTypeData.AvailableZones.Count -gt 0 -and $mNodeTypeData.ZoneSupportStatus -ne $("Error"))
                                            {
                                                Write-Host $("  All Available Zones: {0}" -f ($mNodeTypeData.AvailableZones -join $(", ")))
                                            }
                                    }
                            }

                        # Quota Family Summary
                        if ($ReportData.QuotaAnalysis.RawQuotaData)
                            {
                                Write-Verbose -Message $("Processing quota family requirements and availability analysis")
                                Write-Host $("`nQuota Family Summary:") -ForegroundColor Yellow

                                # Build unique quota families from SKU support data
                                $quotaFamilies = @()
                                foreach ($skuEntry in $ReportData.SKUSupportData)
                                    {
                                        if ($skuEntry.SKUFamilyQuota)
                                            {
                                                $familyName = $skuEntry.SKUFamilyQuota.Name.LocalizedValue
                                            } `
                                        else
                                            {
                                                # Derive family name from the SKU object data stored in report
                                                $familyName = $null
                                            }

                                        if ($familyName -and $quotaFamilies -notcontains $familyName)
                                            {
                                                $quotaFamilies += $familyName
                                            }
                                    }

                                # Also include families from raw data that match known preview families
                                foreach ($skuEntry in $ReportData.SKUSupportData)
                                    {
                                        if (-not $skuEntry.SKUFamilyQuota -and $skuEntry.QuotaFamilyName)
                                            {
                                                if ($quotaFamilies -notcontains $skuEntry.QuotaFamilyName)
                                                    {
                                                        $quotaFamilies += $skuEntry.QuotaFamilyName
                                                    }
                                            }
                                    }

                                $quotaFamilies = $quotaFamilies | Sort-Object -Unique

                                foreach ($quotaFamily in $quotaFamilies)
                                    {
                                        $requiredvCPU = 0

                                        # Calculate total vCPU for this quota family from SKU support data
                                        foreach ($skuEntry in $ReportData.SKUSupportData)
                                            {
                                                $entryFamily = if ($skuEntry.SKUFamilyQuota)
                                                    {
                                                        $skuEntry.SKUFamilyQuota.Name.LocalizedValue
                                                    } `
                                                elseif ($skuEntry.QuotaFamilyName)
                                                    {
                                                        $skuEntry.QuotaFamilyName
                                                    } `
                                                else
                                                    {
                                                        $null
                                                    }

                                                if ($entryFamily -eq $quotaFamily)
                                                    {
                                                        $requiredvCPU += $skuEntry.vCPUCount
                                                    }
                                            }

                                        $quotaFamilyInfo = $ReportData.QuotaAnalysis.RawQuotaData | Where-Object { $_.Name.LocalizedValue -eq $quotaFamily }

                                        Write-Host $("`n  {0}:" -f $quotaFamily) -ForegroundColor Cyan

                                        if (-not $quotaFamilyInfo)
                                            {
                                                Write-Host $("    ⚠️  Quota information unavailable - SKU family not yet registered in Azure quota system") -ForegroundColor Yellow
                                                Write-Host $("    Status: This is expected for preview or newly released SKU families") -ForegroundColor Yellow
                                                Write-Host $("    Impact: Quota validation skipped - deployment will proceed but may fail if insufficient quota") -ForegroundColor Yellow
                                                Write-Host $("    vCPU Required: {0}" -f $requiredvCPU) -ForegroundColor Yellow
                                            } `
                                        else
                                            {
                                                $availableQuota = $quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue
                                                if ($availableQuota -ge $requiredvCPU)
                                                    {
                                                        Write-Host $("    vCPU Required: {0}" -f $requiredvCPU)
                                                        Write-Host $("    vCPU Available: {0}/{1}" -f $availableQuota, $quotaFamilyInfo.Limit)
                                                        Write-Host $("    Quota Status: ✓ Sufficient") -ForegroundColor Green
                                                    } `
                                                else
                                                    {
                                                        Write-Host $("    vCPU Required: {0}" -f $requiredvCPU)
                                                        Write-Host $("    vCPU Available: {0}/{1}" -f $availableQuota, $quotaFamilyInfo.Limit)
                                                        Write-Host $("    Quota Status: ✗ Insufficient Quota (Shortfall: {0} vCPU)" -f ($requiredvCPU - $availableQuota)) -ForegroundColor Red
                                                    }
                                            }
                                    }
                            }

                        # Quota Summary
                        if ($ReportData.QuotaAnalysisData.Count -gt 0)
                            {
                                Write-Host $("`nQuota Summary:") -ForegroundColor Yellow

                                foreach ($quotaData in $ReportData.QuotaAnalysisData)
                                    {
                                        switch ($quotaData.StatusLevel)
                                            {
                                                "Success" { Write-Host $("  {0}: {1} (Required: {2}, Available: {3}/{4})" -f $quotaData.QuotaType, $quotaData.Status, $quotaData.Required, $quotaData.Available, $quotaData.Limit) -ForegroundColor Green }
                                                "Error"   { Write-Host $("  {0}: {1} (Required: {2}, Available: {3}/{4})" -f $quotaData.QuotaType, $quotaData.Status, $quotaData.Required, $quotaData.Available, $quotaData.Limit) -ForegroundColor Red }
                                            }
                                    }
                            }

                        # ---------------------------------------------------------------
                        # Multi-Zone Analysis Results (Zone Support Matrix)
                        # ---------------------------------------------------------------
                        if ($ReportData.ZoneResults -and $ReportData.ZoneResults.Zones.Count -gt 0)
                            {
                                $zones = $ReportData.ZoneResults.Zones
                                Write-Host $("`n=== Multi-Zone SKU Support Matrix ===") -ForegroundColor Cyan
                                Write-Host $("Region: {0} | Zones: {1}" -f $ReportData.Configuration.Region, ($zones -join $(", "))) -ForegroundColor Yellow

                                # CNode zone matrix
                                if ($ReportData.ZoneResults.CNodeMatrix.Count -gt 0)
                                    {
                                        Write-Host $("`nCNode VM Families:") -ForegroundColor Yellow

                                        # Header
                                        $headerZones = ($zones | ForEach-Object { $("Z{0}" -f $_) }) -join $("  ")
                                        Write-Host $("  {0,-45} {1,-22} {2}  {3}" -f $("Configuration"), $("VM SKU"), $headerZones, $("Quota")) -ForegroundColor Gray
                                        Write-Host $("  {0}" -f $("-" * 100)) -ForegroundColor DarkGray

                                        foreach ($entry in $ReportData.ZoneResults.CNodeMatrix)
                                            {
                                                # Build zone indicator string
                                                $zoneIndicators = $("")
                                                foreach ($z in $zones)
                                                    {
                                                        if ($entry.ZoneSupport[$z])
                                                            {
                                                                $zoneIndicators += $(" ✓ ")
                                                            } `
                                                        else
                                                            {
                                                                $zoneIndicators += $(" ✗ ")
                                                            }
                                                    }

                                                $lineColor = if ($entry.SupportedZoneCount -eq $zones.Count) { "Green" } `
                                                    elseif ($entry.SupportedZoneCount -gt 0) { "Yellow" } `
                                                    elseif (-not $entry.InRegion) { "Red" } `
                                                    else { "Red" }
                                                Write-Host $("  {0,-45} {1,-22} {2}  {3}" -f $entry.FriendlyName, $entry.SKUName, $zoneIndicators, $entry.QuotaDisplay) -ForegroundColor $lineColor
                                            }
                                    }

                                # MNode zone matrix
                                if ($ReportData.ZoneResults.MNodeMatrix.Count -gt 0)
                                    {
                                        Write-Host $("`nMNode VM Families:") -ForegroundColor Yellow

                                        # Header
                                        $headerZones = ($zones | ForEach-Object { $("Z{0}" -f $_) }) -join $("  ")
                                        Write-Host $("  {0,-45} {1,-22} {2}  {3}" -f $("Configuration"), $("VM SKU"), $headerZones, $("Quota")) -ForegroundColor Gray
                                        Write-Host $("  {0}" -f $("-" * 100)) -ForegroundColor DarkGray

                                        foreach ($entry in $ReportData.ZoneResults.MNodeMatrix)
                                            {
                                                # Build zone indicator string
                                                $zoneIndicators = $("")
                                                foreach ($z in $zones)
                                                    {
                                                        if ($entry.ZoneSupport[$z])
                                                            {
                                                                $zoneIndicators += $(" ✓ ")
                                                            } `
                                                        else
                                                            {
                                                                $zoneIndicators += $(" ✗ ")
                                                            }
                                                    }

                                                $displayName = $("{0} ({1})" -f $entry.FriendlyName, $entry.SKUName)
                                                $lineColor = if ($entry.SupportedZoneCount -eq $zones.Count) { "Green" } `
                                                    elseif ($entry.SupportedZoneCount -gt 0) { "Yellow" } `
                                                    elseif (-not $entry.InRegion) { "Red" } `
                                                    else { "Red" }
                                                Write-Host $("  {0,-45} {1,-22} {2}  {3}" -f $entry.FriendlyName, $entry.SKUName, $zoneIndicators, $entry.QuotaDisplay) -ForegroundColor $lineColor
                                            }
                                    }
                            }

                        # ---------------------------------------------------------------
                        # SKU Family Deployment Test Results (Actual VM Allocation Tests)
                        # ---------------------------------------------------------------
                        if ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0)
                            {
                                $deployResults = $ReportData.SKUFamilyTesting.DeploymentResults
                                $uniqueSKUs = $deployResults | Select-Object -ExpandProperty SKUName -Unique
                                $uniqueSKUCount = $uniqueSKUs.Count
                                $uniqueSuccessCount = ($uniqueSKUs | Where-Object { $sku = $_; ($deployResults | Where-Object { $_.SKUName -eq $sku } | Select-Object -First 1).DeploymentResult -eq $("Success") }).Count
                                $uniqueFailedCount = $uniqueSKUCount - $uniqueSuccessCount

                                Write-Host $("{0}=== SKU Family Deployment Test Results ===" -f "`n") -ForegroundColor Cyan
                                Write-Host $("Region: {0} | Zone: {1} | Unique SKUs: {2} | Succeeded: {3} | Failed: {4}" -f $ReportData.Configuration.Region, $ReportData.Configuration.Zone, $uniqueSKUCount, $uniqueSuccessCount, $uniqueFailedCount) -ForegroundColor Yellow

                                # Group results by unique SKU — show what each SKU covers
                                foreach ($skuName in $uniqueSKUs)
                                    {
                                        $skuEntries = $deployResults | Where-Object { $_.SKUName -eq $skuName }
                                        $skuResult = ($skuEntries | Select-Object -First 1).DeploymentResult
                                        $quotaFamily = ($skuEntries | Select-Object -First 1).QuotaFamily
                                        $vCPU = ($skuEntries | Select-Object -First 1).vCPU

                                        # Build covers list
                                        $coversList = @()
                                        $cNodeCovers = $skuEntries | Where-Object { $_.NodeType -eq $("CNode") }
                                        $mNodeCovers = $skuEntries | Where-Object { $_.NodeType -eq $("MNode") }
                                        if ($cNodeCovers.Count -gt 0)
                                            {
                                                $coversList += $cNodeCovers | ForEach-Object { $("CNode: {0}" -f $_.FriendlyName) } | Select-Object -Unique
                                            }
                                        if ($mNodeCovers.Count -gt 0)
                                            {
                                                $coversList += $mNodeCovers | ForEach-Object { $("MNode: {0}" -f $_.FriendlyName) } | Select-Object -Unique
                                            }

                                        if ($skuResult -eq $("Success"))
                                            {
                                                Write-Host $("  ✓ {0,-28} vCPU: {1,-4} {2}" -f $skuName, $vCPU, $quotaFamily) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                $failureCategory = ($skuEntries | Select-Object -First 1).FailureCategory
                                                Write-Host $("  ✗ {0,-28} vCPU: {1,-4} {2} — {3}" -f $skuName, $vCPU, $quotaFamily, $failureCategory) -ForegroundColor Red
                                                $errorMessage = ($skuEntries | Select-Object -First 1).ErrorMessage
                                                if ($errorMessage)
                                                    {
                                                        Write-Host $("    Error: {0}" -f $errorMessage) -ForegroundColor DarkRed
                                                    }
                                            }

                                        # Show covers indented
                                        foreach ($cover in $coversList)
                                            {
                                                Write-Host $("      └─ {0}" -f $cover) -ForegroundColor DarkGray
                                            }
                                    }
                            }

                        # ---------------------------------------------------------------
                        # VM Deployment Report
                        # ---------------------------------------------------------------
                        if ($ReportData.Deployment.VMReport.Count -gt 0)
                            {
                                Write-Verbose -Message $("Generating comprehensive VM deployment status report")
                                Write-Host $("`n=== VM Deployment Report ===") -ForegroundColor Cyan
                                Write-Verbose -Message $("Report includes deployment status for {0} total VMs across CNode and DNode groups" -f $ReportData.Deployment.VMReport.Count)

                                # Detect multi-zone deployment for conditional Zone column display
                                $reportUniqueZones = @($ReportData.Deployment.VMReport | Select-Object -ExpandProperty Zone -Unique -ErrorAction SilentlyContinue)
                                $isMultiZoneReport = $reportUniqueZones.Count -gt 1

                                # CNode Report
                                $cNodeReport = $ReportData.Deployment.VMReport | Where-Object { $_.ResourceType -eq $("CNode") }

                                if ($cNodeReport)
                                    {
                                        $cNodeExpectedSku = $cNodeReport[0].ExpectedSKU
                                        Write-Host $("`nCNode Deployment Status (Expected SKU: {0}):" -f $cNodeExpectedSku) -ForegroundColor Yellow

                                        $cNodeColumns = @(
                                            @{Label=$("Node"); Expression={$("CNode {0}" -f $_.NodeNumber)}; Width=12}
                                        )
                                        if ($isMultiZoneReport)
                                            {
                                                $cNodeColumns += @{Label=$("Zone"); Expression={$_.Zone}; Width=6}
                                            }
                                        $cNodeColumns += @(
                                            @{Label=$("VM Name"); Expression={$_.VMName}; Width=30},
                                            @{Label=$("Deployed SKU"); Expression={$_.DeployedSKU}; Width=18},
                                            @{Label=$("VM Status"); Expression={$_.VMStatus}; Width=15},
                                            @{Label=$("Provisioned State"); Expression={$_.ProvisioningState}; Width=15},
                                            @{Label=$("NIC Status"); Expression={$_.NICStatus}; Width=12},
                                            @{Label=$("Availability Set"); Expression={$_.AvailabilitySet}; Width=18}
                                        )

                                        $cNodeReport | Format-Table -Property $cNodeColumns -AutoSize | Out-String | Write-Host -NoNewline
                                    }

                                # DNode Report by MNode Group
                                $mNodeGroups = $ReportData.Deployment.VMReport | Where-Object { $_.ResourceType -eq $("DNode") } | Group-Object GroupNumber

                                foreach ($group in $mNodeGroups)
                                    {
                                        $mNodeExpectedSku = $group.Group[0].ExpectedSKU
                                        Write-Host $("`n{0} DNode Deployment Status (Expected SKU: {1}):" -f $group.Name, $mNodeExpectedSku) -ForegroundColor Yellow

                                        $dNodeColumns = @(
                                            @{Label=$("Node"); Expression={$("DNode {0}" -f $_.NodeNumber)}; Width=12}
                                        )
                                        if ($isMultiZoneReport)
                                            {
                                                $dNodeColumns += @{Label=$("Zone"); Expression={$_.Zone}; Width=6}
                                            }
                                        $dNodeColumns += @(
                                            @{Label=$("VM Name"); Expression={$_.VMName}; Width=30},
                                            @{Label=$("Deployed SKU"); Expression={$_.DeployedSKU}; Width=18},
                                            @{Label=$("VM Status"); Expression={$_.VMStatus}; Width=15},
                                            @{Label=$("Provisioned State"); Expression={$_.ProvisioningState}; Width=15},
                                            @{Label=$("NIC Status"); Expression={$_.NICStatus}; Width=12},
                                            @{Label=$("Availability Set"); Expression={$_.AvailabilitySet}; Width=18}
                                        )

                                        $group.Group | Format-Table -Property $dNodeColumns -AutoSize | Out-String | Write-Host -NoNewline
                                    }
                            }

                        # ---------------------------------------------------------------
                        # Silk Component Summary
                        # ---------------------------------------------------------------
                        if ($ReportData.SilkSummary.Count -gt 0)
                            {
                                Write-Verbose -Message $("Generating Silk component deployment summary with CNode and MNode statistics")
                                Write-Host $("`n=== Silk Component Summary ===") -ForegroundColor Cyan

                                $ReportData.SilkSummary |
                                    Format-Table -Property @(
                                                                @{Label=$("Silk Component"); Expression={$_.Component}; Width=20},
                                                                @{Label=$("Deployed"); Expression={$_.DeployedCount}; Width=10},
                                                                @{Label=$("Expected"); Expression={$_.ExpectedCount}; Width=10},
                                                                @{Label=$("VM SKU"); Expression={$_.SKU}; Width=20},
                                                                @{Label=$("Status"); Expression={$_.Status}; Width=15}
                                                            ) -AutoSize | Out-String | Write-Host -NoNewline
                            }

                        # ---------------------------------------------------------------
                        # Infrastructure Summary (only when deployment was attempted)
                        # ---------------------------------------------------------------
                        if ($ReportData.Deployment.Attempted)
                            {
                                Write-Verbose -Message $("Compiling infrastructure deployment summary for all Azure resources")
                                Write-Host $("`n=== Infrastructure Summary ===") -ForegroundColor Cyan
                                Write-Verbose -Message $("Infrastructure summary includes VNet, NSG, PPG, AvSet, and VM deployment status")

                                # Non-successful VMs
                                if ($ReportData.Deployment.VMReport.Count -gt 0)
                            {
                                $nonSuccessfulVMs = $ReportData.Deployment.VMReport | Where-Object { $_.ProvisioningState -ne $("Succeeded") -and $_.ProvisioningState -ne $("Not Found") -and $_.ProvisioningState -ne $("Allocation Failed") }
                                if ($nonSuccessfulVMs.Count -gt 0)
                                    {
                                        Write-Host $("`nVMs with Non-Successful Provisioning States:") -ForegroundColor Yellow
                                        $nonSuccessfulVMs | ForEach-Object { Write-Host $("  {0}: {1}" -f $_.VMName, $_.ProvisioningState) -ForegroundColor Yellow }
                                    }
                            }

                        # Deployment validation findings
                        if ($ReportData.Deployment.ValidationFindings -and $ReportData.Deployment.ValidationFindings.Count -gt 0)
                            {
                                Write-Host $("`nDeployment Validation Findings:") -ForegroundColor Yellow

                                $findings = $ReportData.Deployment.FindingsAnalysis

                                if ($findings.NoCapacityIssues.Count -gt 0)
                                    {
                                        $affectedSkus = $findings.NoCapacityIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                        $zoneGrouping = $findings.NoCapacityIssues | Group-Object -Property TestedZone | Sort-Object Name
                                        $zoneDetails = ($zoneGrouping | ForEach-Object { $("Zone {0}: {1}" -f $_.Name, $_.Count) }) -join ", "
                                        Write-Host $("  ⚠️ No SKU Capacity Available: {0} VM(s) affected ({1})" -f $findings.NoCapacityIssues.Count, ($affectedSkus -join $(", "))) -ForegroundColor Yellow
                                        Write-Host $("      Affected Zones: {0}" -f $zoneDetails) -ForegroundColor Gray
                                        Write-Host $("      → SKU quota is available and SKU is listed as supported, but Azure could not allocate capacity") -ForegroundColor DarkGray
                                        Write-Host $("      → Try: Different availability zone, different region, or retry later") -ForegroundColor DarkGray
                                    }

                                if ($findings.QuotaIssues.Count -gt 0)
                                    {
                                        $affectedSkus = $findings.QuotaIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                        Write-Host $("  📊 Quota Exceeded: {0} VM(s) affected ({1})" -f $findings.QuotaIssues.Count, ($affectedSkus -join $(", "))) -ForegroundColor Gray
                                        Write-Host $("      → Subscription has reached limits for these VM families or total vCPUs") -ForegroundColor DarkGray
                                        Write-Host $("      → Try: Request quota increase via Azure portal Support tickets") -ForegroundColor DarkGray
                                    }

                                if ($findings.SKUSupportIssues.Count -gt 0)
                                    {
                                        $affectedSkus = $findings.SKUSupportIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                        Write-Host $("  🔧 SKU Support: {0} VM(s) affected ({1})" -f $findings.SKUSupportIssues.Count, ($affectedSkus -join $(", "))) -ForegroundColor Gray
                                        Write-Host $("      → These VM SKUs are not supported in the target region/zone") -ForegroundColor DarkGray
                                        Write-Host $("      → Try: Different region that supports these SKUs, or use alternative VM SKUs") -ForegroundColor DarkGray

                                        $skuIssuesWithAlternatives = $findings.SKUSupportIssues | Where-Object { $_.AlternativeZones -and $_.AlternativeZones.Count -gt 0 }
                                        if ($skuIssuesWithAlternatives.Count -gt 0)
                                            {
                                                Write-Host $("      → Alternative zones available within {0} for affected SKUs" -f $ReportData.Configuration.Region) -ForegroundColor DarkGray
                                            }
                                    }

                                if ($findings.OtherIssues.Count -gt 0)
                                    {
                                        $affectedSkus = $findings.OtherIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                        Write-Host $("  ⚙️ Other Constraints: {0} VM(s) affected ({1})" -f $findings.OtherIssues.Count, ($affectedSkus -join $(", "))) -ForegroundColor Gray
                                        Write-Host $("      → Deployment failed due to other Azure constraints or configuration issues") -ForegroundColor DarkGray
                                        Write-Host $("      → Try: Review error details in HTML report for specific troubleshooting steps") -ForegroundColor DarkGray
                                    }

                                # Show per-VM error details only for failures that could not be automatically classified
                                $unresolvedConsoleFindings = @($ReportData.Deployment.ValidationFindings | Where-Object { $_.FailureCategory -in @("Other", "Unknown") })
                                if ($unresolvedConsoleFindings.Count -gt 0)
                                    {
                                        Write-Host $("`n  Unresolved Failure Details:") -ForegroundColor Yellow
                                        foreach ($finding in $unresolvedConsoleFindings)
                                            {
                                                $findingColor = if ($finding.FailureCategory -eq "Unknown") { "Red" } else { "Gray" }
                                                Write-Host $("    {0} ({1}, Zone {2}): [{3}] {4}" -f $finding.VMName, $finding.VMSku, $finding.TestedZone, $finding.FailureCategory, $finding.ErrorMessage) -ForegroundColor $findingColor
                                            }
                                    }

                                # Hint about -DisableCleanup for deeper investigation
                                if (-not $ReportData.Configuration.DisableCleanup)
                                    {
                                        Write-Host $("`n  💡 Tip: Re-run with -DisableCleanup to keep failed resources for investigation in the Azure portal.") -ForegroundColor Cyan
                                        Write-Host $("     Check Azure Activity Log for the resource group to see detailed allocation failure reasons.") -ForegroundColor DarkCyan
                                    }
                            }

                        # Skipped zones (zones excluded because one or more SKUs are not available there)
                        if ($ReportData.Deployment.SkippedZones -and $ReportData.Deployment.SkippedZones.Count -gt 0)
                            {
                                Write-Host $("`n=== Skipped Zones — Invalid Configuration Zones ===") -ForegroundColor Yellow
                                Write-Host $("  {0} zone(s) exist in the region but were not tested:" -f $ReportData.Deployment.SkippedZones.Count) -ForegroundColor DarkYellow
                                foreach ($skipped in $ReportData.Deployment.SkippedZones)
                                    {
                                        Write-Host $("  Zone {0}: No deployment attempted" -f $skipped.Zone) -ForegroundColor DarkYellow
                                        Write-Host $("    Unsupported SKU(s): {0}" -f ($skipped.UnsupportedSKUs -join ", ")) -ForegroundColor Gray
                                        Write-Host $("    Reason: {0}" -f $skipped.Reason) -ForegroundColor Gray
                                        Write-Host $("    → This zone cannot host the requested Silk configuration. Select a different SKU set or choose") -ForegroundColor DarkGray
                                        Write-Host $("      a zone where all required SKUs are available.") -ForegroundColor DarkGray
                                    }
                            }

                        # Infrastructure resource status
                        $infra = $ReportData.Deployment.Infrastructure

                        Write-Host $("Virtual Network: ") -NoNewline
                        if ($infra.VNetCreated)
                            {
                                Write-Host $("✓ {0}" -f $infra.VNetName) -ForegroundColor Green
                            } `
                        else
                            {
                                Write-Host $("✗ Not Found") -ForegroundColor Red
                            }

                        Write-Host $("Network Security Group: ") -NoNewline
                        if ($infra.NSGCreated)
                            {
                                Write-Host $("✓ {0}" -f $infra.NSGName) -ForegroundColor Green
                            } `
                        else
                            {
                                Write-Host $("✗ Not Found") -ForegroundColor Red
                            }

                        Write-Host $("Proximity Placement Groups: ") -NoNewline
                        if ($infra.PPGsCreated.Count -gt 0)
                            {
                                Write-Host $("✓ {0} groups ({1})" -f $infra.PPGsCreated.Count, ($infra.PPGsCreated.Name -join $(", "))) -ForegroundColor Green
                            } `
                        elseif ($infra.PPGsReferenced.Count -gt 0)
                            {
                                Write-Host $("✓ {0} groups ({1}) [Existing Infrastructure]" -f $infra.PPGsReferenced.Count, ($infra.PPGsReferenced.Name -join $(", "))) -ForegroundColor Cyan
                            } `
                        else
                            {
                                Write-Host $("✗ Not Found") -ForegroundColor Red
                            }

                        Write-Host $("Availability Sets: ") -NoNewline
                        if ($infra.AvSetsCreated.Count -gt 0)
                            {
                                $avSetNames = ($infra.AvSetsCreated.Name | Sort-Object) -join $(", ")
                                Write-Host $("✓ {0} sets ({1})" -f $infra.AvSetsCreated.Count, $avSetNames) -ForegroundColor Green
                            } `
                        elseif ($infra.AvSetsReferenced.Count -gt 0)
                            {
                                $avSetRefNames = ($infra.AvSetsReferenced.Name | Sort-Object) -join $(", ")
                                Write-Host $("✓ {0} sets ({1}) [Existing Infrastructure]" -f $infra.AvSetsReferenced.Count, $avSetRefNames) -ForegroundColor Cyan
                            } `
                        else
                            {
                                Write-Host $("✗ Not Found") -ForegroundColor Red
                            }

                        Write-Host $("Expected VMs: {0}" -f $ReportData.Deployment.TotalExpectedVMs)
                        Write-Host $("Successfully Deployed VMs: ") -NoNewline
                        if ($ReportData.Deployment.TotalDeployedVMs -eq $ReportData.Deployment.TotalExpectedVMs)
                            {
                                Write-Host $("{0}" -f $ReportData.Deployment.TotalDeployedVMs) -ForegroundColor Green
                            } `
                        else
                            {
                                Write-Host $("{0}" -f $ReportData.Deployment.TotalDeployedVMs) -ForegroundColor Yellow
                            }

                        if ($ReportData.Deployment.TotalFailedVMs -gt 0)
                            {
                                Write-Host $("Failed VM Deployments: ") -NoNewline
                                Write-Host $("{0}" -f $ReportData.Deployment.TotalFailedVMs) -ForegroundColor Red
                            }

                                Write-Host $("Total Network Interfaces: {0}" -f $infra.NICsCreated)
                                Write-Host $("Total Resources Created: {0}" -f $infra.TotalResources)
                                $existingReferencedList = @($("Resource Group: {0}" -f $ReportData.Configuration.ResourceGroupName))
                                if ($infra.PPGsReferenced.Count -gt 0)
                                    { $infra.PPGsReferenced.Name | ForEach-Object { $existingReferencedList += $("Proximity Placement Group: {0}" -f $_) } }
                                if ($infra.AvSetsReferenced.Count -gt 0)
                                    { $infra.AvSetsReferenced.Name | ForEach-Object { $existingReferencedList += $("Availability Set: {0}" -f $_) } }
                                Write-Host $("Existing Resources Referenced: {0}" -f $existingReferencedList.Count)
                                $existingReferencedList | ForEach-Object { Write-Host $("  · {0}" -f $_) -ForegroundColor Cyan }
                            }

                        # ---------------------------------------------------------------
                        # Zone Alignment Information
                        # ---------------------------------------------------------------
                        Write-Verbose -Message $("Displaying zone alignment configuration and cross-subscription mapping details")
                        Write-Host $("`n=== Zone Alignment Information ===") -ForegroundColor Cyan
                        Write-Host $("Deployment Zone: ") -NoNewline
                        Write-Host $("{0}" -f $ReportData.EnvironmentValidation.ZoneAlignment.FinalZone) -ForegroundColor Green
                        Write-Host $("Subscription: ") -NoNewline
                        Write-Host $("{0}" -f $ReportData.Configuration.SubscriptionId) -ForegroundColor Gray

                        $alignment = $ReportData.EnvironmentValidation.ZoneAlignment

                        # Always show zone mapping table when mappings are available
                        if ($alignment.ZoneMappings.Count -gt 0)
                            {
                                $hasPeerAlignment = [bool]$alignment.AlignmentSubId
                                if ($hasPeerAlignment)
                                    {
                                        Write-Host $("Azure Zone  Deployment Zone  Peer Zone ({0})" -f $alignment.AlignmentSubId.Substring(0, 8)) -ForegroundColor Gray
                                        Write-Host $("─────────── ──────────────── ─────────────────────" ) -ForegroundColor DarkGray
                                    } `
                                else
                                    {
                                        Write-Host $("Azure Zone  Deployment Zone") -ForegroundColor Gray
                                        Write-Host $("─────────── ────────────────") -ForegroundColor DarkGray
                                    }

                                foreach ($mapping in $alignment.ZoneMappings)
                                    {
                                        $isDeployZone = ($mapping.DeploymentZone -eq $alignment.FinalZone)
                                        $zoneColor = if ($isDeployZone) { $("Green") } else { $("DarkGray") }
                                        $marker = if ($isDeployZone) { $("  ◄") } else { $("   ") }

                                        if ($hasPeerAlignment)
                                            {
                                                Write-Host $("  Zone {0}     Zone {1}          Zone {2}{3}" -f $mapping.DeploymentZone, $mapping.DeploymentZone, $mapping.AlignmentZone, $marker) -ForegroundColor $zoneColor
                                            } `
                                        else
                                            {
                                                Write-Host $("  Zone {0}     Zone {1}{2}" -f $mapping.DeploymentZone, $mapping.DeploymentZone, $marker) -ForegroundColor $zoneColor
                                            }
                                    }
                            }

                        # Cross-subscription alignment details (only when peer sub provided)
                        if ($alignment.AlignmentSubId)
                            {
                                Write-Host $("Alignment Subscription: ") -NoNewline
                                Write-Host $("{0}" -f $alignment.AlignmentSubId) -ForegroundColor Yellow

                                if ($alignment.AlignmentPerformed)
                                    {
                                        Write-Host $("Zone Alignment: ") -NoNewline
                                        Write-Host $("✓ Applied") -ForegroundColor Green
                                        Write-Host $("  Original Zone: {0} → Final Zone: {1}" -f $alignment.OriginalZone, $alignment.FinalZone) -ForegroundColor Gray
                                    } `
                                elseif ($alignment.AlignmentDisabled)
                                    {
                                        Write-Host $("Zone Alignment: ") -NoNewline
                                        Write-Host $("⚠ Disabled by parameter") -ForegroundColor Yellow
                                    } `
                                else
                                    {
                                        Write-Host $("Zone Alignment: ") -NoNewline
                                        Write-Host $("- No adjustment needed") -ForegroundColor Gray
                                    }

                                Write-Host $("Reason: {0}" -f $alignment.Reason) -ForegroundColor Gray
                            } `
                        else
                            {
                                Write-Host $("Reason: {0}" -f $alignment.Reason) -ForegroundColor Gray
                            }

                        # ---------------------------------------------------------------
                        # Results Status
                        # ---------------------------------------------------------------
                        if ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0)
                            {
                                # SKU Family Deployment Test mode — results already printed in dedicated section above
                                $deployResults = $ReportData.SKUFamilyTesting.DeploymentResults
                                $uniqueSKUs = $deployResults | Select-Object -ExpandProperty SKUName -Unique
                                $uniqueSKUCount = $uniqueSKUs.Count
                                $uniqueSuccessCount = ($uniqueSKUs | Where-Object { $sku = $_; ($deployResults | Where-Object { $_.SKUName -eq $sku } | Select-Object -First 1).DeploymentResult -eq $("Success") }).Count
                                $uniqueFailedCount = $uniqueSKUCount - $uniqueSuccessCount

                                Write-Host $("`n=== SKU Family Deployment Test Summary ===") -ForegroundColor Cyan
                                if ($uniqueFailedCount -eq 0)
                                    {
                                        Write-Host $("✓ ALL {0} UNIQUE SKUs DEPLOYED SUCCESSFULLY in region: {1} zone: {2}" -f $uniqueSKUCount, $ReportData.Configuration.Region, $ReportData.Configuration.Zone) -ForegroundColor Green
                                        Write-Host $("📊 No allocation or capacity constraints detected") -ForegroundColor Green
                                    } `
                                elseif ($uniqueSuccessCount -gt 0)
                                    {
                                        Write-Host $("⚠ {0}/{1} unique SKUs deployed, {2} failed in region: {3} zone: {4}" -f $uniqueSuccessCount, $uniqueSKUCount, $uniqueFailedCount, $ReportData.Configuration.Region, $ReportData.Configuration.Zone) -ForegroundColor Yellow
                                        Write-Host $("📊 Review failed SKUs above for allocation or capacity constraints") -ForegroundColor Yellow
                                    } `
                                else
                                    {
                                        Write-Host $("✗ ALL {0} UNIQUE SKUs FAILED in region: {1} zone: {2}" -f $uniqueSKUCount, $ReportData.Configuration.Region, $ReportData.Configuration.Zone) -ForegroundColor Red
                                        Write-Host $("📊 No SKU families could be allocated - check capacity and quota") -ForegroundColor Red
                                    }
                            } `
                        elseif ($ReportData.Deployment.Attempted)
                            {
                                Write-Verbose -Message $("Analyzing final deployment results and generating readiness assessment")
                                Write-Host $("`n=== Deployment Results Status ===") -ForegroundColor Cyan

                                $uniqueFailedSkus = @()
                                if ($ReportData.Deployment.ValidationFindings -and $ReportData.Deployment.ValidationFindings.Count -gt 0)
                                    {
                                        $uniqueFailedSkus = $ReportData.Deployment.ValidationFindings | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                    }

                                $totalExpected = $ReportData.Deployment.TotalExpectedVMs
                                $totalDeployed = $ReportData.Deployment.TotalDeployedVMs

                                if ($totalDeployed -eq $totalExpected -and $infra.VNetCreated -and $infra.NSGCreated)
                                    {
                                        Write-Host $("✓ DEPLOYMENT VALIDATION COMPLETE - All SKUs successfully deployed in target region: {0} zone: {1}" -f $ReportData.Configuration.Region, $ReportData.Configuration.Zone) -ForegroundColor Green
                                        Write-Host $("📊 Deployment Readiness: Excellent - No SKU Capacity or availability constraints detected") -ForegroundColor Green
                                    } `
                                elseif ($totalExpected -eq 0)
                                    {
                                        Write-Host $("⚠ ENVIRONMENT ANALYSIS COMPLETE - No VMs could be deployed due to quota constraints") -ForegroundColor Red
                                        Write-Host $("📊 Quota Status: Insufficient - All requested VM deployments exceed available quota") -ForegroundColor Red
                                        Write-Host $("💡 Recommendation: Review quota report above and request quota increases for required VM families") -ForegroundColor Yellow
                                    } `
                                elseif ($totalDeployed -gt 0)
                                    {
                                        if ($uniqueFailedSkus.Count -gt 0)
                                            {
                                                Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Specific SKU constraints detected") -ForegroundColor Yellow
                                                Write-Host $("📊 Deployment Readiness: Partial - {0} SKU(s) affected: {1}" -f $uniqueFailedSkus.Count, ($uniqueFailedSkus -join $(", "))) -ForegroundColor Yellow
                                            } `
                                        else
                                            {
                                                Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Mixed results detected") -ForegroundColor Yellow
                                                Write-Host $("📊 Deployment Readiness: Partial - {0}/{1} VMs successfully validated" -f $totalDeployed, $totalExpected) -ForegroundColor Yellow
                                            }
                                    } `
                                else
                                    {
                                        Write-Host $("⚠ DEPLOYMENT VALIDATION COMPLETE - Significant constraints detected") -ForegroundColor Red
                                        Write-Host $("📊 Deployment Readiness: Limited - Review validation findings in summary") -ForegroundColor Red
                                    }
                            } `
                        else
                            {
                                Write-Host $("`n=== Report Only Analysis ===") -ForegroundColor Cyan
                                Write-Host $("✓ REPORT ONLY MODE - SKU and quota analysis complete for region: {0} zone: {1}" -f $ReportData.Configuration.Region, $ReportData.Configuration.Zone) -ForegroundColor Green
                                Write-Host $("📊 No deployment was attempted. Review SKU support and quota data above.") -ForegroundColor Cyan
                            }

                        # ---------------------------------------------------------------
                        # SKU Support & Quota Reference (All Silk-Supported Families)
                        # ---------------------------------------------------------------
                        # Always rendered at the bottom of every report as a reference
                        # section grouped by quota family. Quota is per-family; zone
                        # support is per-individual-SKU within a family.
                        if ($ReportData.SKUFamilyTesting.Results.Count -gt 0)
                            {
                                Write-Host $("`n=== SKU Support & Quota Reference ===") -ForegroundColor Cyan
                                Write-Verbose -Message $("Rendering SKU support reference for {0} entries" -f $ReportData.SKUFamilyTesting.Results.Count)

                                # Group by quota family first, then by unique SKU within each family
                                $familyGroups = $ReportData.SKUFamilyTesting.Results | Group-Object -Property QuotaFamily
                                $uniqueSKUCount = ($ReportData.SKUFamilyTesting.Results | Select-Object -Property SKUName -Unique).Count

                                Write-Host $("Region: {0} | Zone: {1} | Quota Families: {2} | Unique SKUs: {3}" -f $ReportData.Configuration.Region, $ReportData.Configuration.Zone, $familyGroups.Count, $uniqueSKUCount) -ForegroundColor Yellow

                                $allSKUStatuses = @()

                                foreach ($familyGroup in $familyGroups)
                                    {
                                        # Family header - show quota once
                                        $familyRepresentative = $familyGroup.Group[0]
                                        $quotaColor = switch ($familyRepresentative.QuotaStatusLevel)
                                            {
                                                "Success" { "Green" }
                                                "Warning" { "Yellow" }
                                                "Error"   { "Red" }
                                            }

                                        Write-Host $("")
                                        Write-Host $("  {0}: " -f $familyGroup.Name) -ForegroundColor White -NoNewline
                                        Write-Host $familyRepresentative.QuotaStatus -ForegroundColor $quotaColor

                                        # Group SKUs within this family
                                        $skuGroups = $familyGroup.Group | Group-Object -Property SKUName

                                        foreach ($skuGroup in $skuGroups)
                                            {
                                                $skuEntry = $skuGroup.Group[0]
                                                $skuMinDeploy = ($skuGroup.Group | Measure-Object -Property MinDeploymentVcpu -Minimum).Minimum
                                                $allSKUStatuses += $skuEntry.ZoneSupportStatus
                                                $statusIcon = switch ($skuEntry.ZoneSupportStatus)
                                                    {
                                                        "Success" { "✓" }
                                                        "Warning" { "⚠" }
                                                        "Error"   { "✗" }
                                                    }
                                                $skuColor = switch ($skuEntry.ZoneSupportStatus)
                                                    {
                                                        "Success" { "Green" }
                                                        "Warning" { "Yellow" }
                                                        "Error"   { "Red" }
                                                    }

                                                Write-Host $("    {0} " -f $statusIcon) -NoNewline -ForegroundColor $skuColor
                                                Write-Host $("{0}" -f $skuGroup.Name) -ForegroundColor White -NoNewline
                                                Write-Host $("  vCPU: {0}" -f $skuEntry.vCPU) -NoNewline
                                                Write-Host $("  Min Deploy: {0} vCPU" -f $skuMinDeploy) -NoNewline
                                                if ($skuEntry.AvailableZones.Count -gt 0)
                                                    {
                                                        Write-Host $("  Zones: {0}" -f ($skuEntry.AvailableZones -join $(", "))) -NoNewline
                                                    }
                                                Write-Host $("")

                                                # Covers list for this SKU
                                                foreach ($entry in $skuGroup.Group)
                                                    {
                                                        if ($entry.ComponentType -eq $("CNode"))
                                                            {
                                                                Write-Host $("        └─ CNode: {0}" -f $entry.FriendlyName) -ForegroundColor DarkGray
                                                            } `
                                                        else
                                                            {
                                                                Write-Host $("        └─ MNode: {0} ({1} DNode{2})" -f $entry.FriendlyName, $entry.DNodeCount, $(if([int]$entry.DNodeCount -ne 1){"s"}else{""})) -ForegroundColor DarkGray
                                                            }
                                                    }
                                            }
                                    }

                                # Summary counts (by unique SKU across all families)
                                $totalSKUSupported = ($allSKUStatuses | Where-Object { $_ -eq $("Success") }).Count
                                $totalSKUWarning = ($allSKUStatuses | Where-Object { $_ -eq $("Warning") }).Count
                                $totalSKUUnsupported = ($allSKUStatuses | Where-Object { $_ -eq $("Error") }).Count
                                Write-Host $("`nSKU Reference: {0} available in zone, {1} available elsewhere, {2} not in region" -f $totalSKUSupported, $totalSKUWarning, $totalSKUUnsupported) -ForegroundColor Cyan
                            }

                        # Duration (null-safe)
                        if ($ReportData.Metadata.Duration)
                            {
                                Write-Host $("⏱️ Total Time: {0}" -f $ReportData.Metadata.Duration.ToString("hh\:mm\:ss")) -ForegroundColor Cyan
                            }
                    }

                # ===============================================================================
                # HTML Report Rendering Function
                # ===============================================================================
                # Reads exclusively from the centralized $ReportData object to produce
                # the HTML deployment report. All data must be populated before calling.
                function Write-SilkHTMLReport
                    {

                        param
                            (
                                [Parameter(Mandatory = $true)]
                                [PSCustomObject]
                                $ReportData,

                                [Parameter(Mandatory = $true)]
                                [string]
                                $OutputPath
                            )

                        Write-Host $("`n=== Generating HTML Report ===") -ForegroundColor Cyan
                        Write-Verbose -Message $("Generating HTML report at: {0}" -f $OutputPath)
                        $silkLogoBase64 = "iVBORw0KGgoAAAANSUhEUgAAAZAAAAGQCAYAAACAvzbMAAAACXBIWXMAAAsTAAALEwEAmpwYAAAHd2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDYwLCAyMDIwLzA1LzEyLTE2OjA0OjE3ICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpzdFJlZj0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlUmVmIyIgeG1sbnM6ZGM9Imh0dHA6Ly9wdXJsLm9yZy9kYy9lbGVtZW50cy8xLjEvIiB4bWxuczpwaG90b3Nob3A9Imh0dHA6Ly9ucy5hZG9iZS5jb20vcGhvdG9zaG9wLzEuMC8iIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDIxLjIgKE1hY2ludG9zaCkiIHhtcDpDcmVhdGVEYXRlPSIyMDIwLTA2LTI5VDEyOjMxOjU2LTA0OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDIwLTA2LTI5VDEyOjMxOjU2LTA0OjAwIiB4bXA6TW9kaWZ5RGF0ZT0iMjAyMC0wNi0yOVQxMjozMTo1Ni0wNDowMCIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpkN2JkMDM0Ny01NTUwLTRjY2QtYjhmZi1jMTZjZjM2ZmQzMDciIHhtcE1NOkRvY3VtZW50SUQ9ImFkb2JlOmRvY2lkOnBob3Rvc2hvcDpjZDRiZGM4MS03MGEyLTlmNDktYWFkMS0zN2RmNjZhZjAyMmYiIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDoyMjdkNjM3ZS0yODA0LTQxNGQtYTRjMS00ZTQ2NDVjNjM2OTciIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiBwaG90b3Nob3A6SUNDUHJvZmlsZT0ic1JHQiBJRUM2MTk2Ni0yLjEiPiA8eG1wTU06SGlzdG9yeT4gPHJkZjpTZXE+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJjcmVhdGVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjIyN2Q2MzdlLTI4MDQtNDE0ZC1hNGMxLTRlNDY0NWM2MzY5NyIgc3RFdnQ6d2hlbj0iMjAyMC0wNi0yOVQxMjozMTo1Ni0wNDowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDIxLjIgKE1hY2ludG9zaCkiLz4gPHJkZjpsaSBzdEV2dDphY3Rpb249InNhdmVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOmQ3YmQwMzQ3LTU1NTAtNGNjZC1iOGZmLWMxNmNmMzZmZDMwNyIgc3RFdnQ6d2hlbj0iMjAyMC0wNi0yOVQxMjozMTo1Ni0wNDowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDIxLjIgKE1hY2ludG9zaCkiIHN0RXZ0OmNoYW5nZWQ9Ii8iLz4gPC9yZGY6U2VxPiA8L3htcE1NOkhpc3Rvcnk+IDx4bXBNTTpJbmdyZWRpZW50cz4gPHJkZjpCYWc+IDxyZGY6bGkgc3RSZWY6bGlua0Zvcm09IlJlZmVyZW5jZVN0cmVhbSIgc3RSZWY6ZmlsZVBhdGg9ImNsb3VkLWFzc2V0Oi8vY2MtYXBpLXN0b3JhZ2UuYWRvYmUuaW8vYXNzZXRzL2Fkb2JlLWxpYnJhcmllcy9jN2QwYmRmMC1lZGU0LTExZTQtOGI4Yi05ZDFhNmExZjg4Mjc7bm9kZT0zZjc5MmE4Ni1lMzRiLTQ4YmYtOTMzNi0xMzI5NTE5ZWI2NzIiIHN0UmVmOkRvY3VtZW50SUQ9InV1aWQ6ZTRkNjEzNWYtZWY0ZC1jMzRlLTlmZmQtODhlYzI5ZTY5MjQwIi8+IDwvcmRmOkJhZz4gPC94bXBNTTpJbmdyZWRpZW50cz4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz7QtEyyAAAqR0lEQVR4nO3dd3xW5f3/8XcSkrBBQASZylQUsYhbcRbtV1DEOuseFFo7nDirVYtV21InWHBbt4J7K7hncSGKIFuQvTJJ7t8fl/mJGEJy5ZzPGffr+XjcD9p8vz2foyR5n3ONz5WT6f2HNyX1kFQsKSMAADYtR1IjSTMaSOonqUmktwMASJomuZJKo74LAEDilObKDV0BAFAXxbmSyqO+CwBA4pTnRn0HAIBkIkAAAF4IEACAFwIEAOCFAAEAeCFAAABeCBAAgBcCBADghQABAHghQAAAXggQAIAXAgQA4IUAAQB4IUAAAF4IEACAFwIEAOCFAAEAeCFAAABeCBAAgBcCBADghQABAHghQAAAXggQAIAXAgQA4IUAAQB4IUAAAF4IEACAFwIEAOCFAAEAeCFAAABeCBAAgBcCBADghQABAHghQAAAXggQAIAXAgQA4IUAAQB4IUAAAF4IEACAFwIEAOCFAAEAeCFAAABeGkR9A0CqXHCEdPzeUmF+eDVKyqSbn5cmvBJeDaAWeAMBgtKjvXTq/uGGhyQ1LJDOHSy1aR5uHWAzCBAgKJ3b2NXKyZHaNLOrB1SDAAEAeCFAAABeCBAAgBcCBADghQABAHghQAAAXggQAIAXAgQA4IUAAQB4IUAAAF4IEACAFwIEAOCFAAEAeCFAAABeCBAAgBcCBADghQABAHghQAAAXggQAIAXAgQA4IUAAQB4IUAAAF4IEACAFwIEAOCFAAGCUlxmWy+Tsa0HbIQAAYLy6Rxp6WqbWquKpLlLbWoBm9Ag6hsAUmNtiTTsBunQnaVmjX78ekEDqTC/+v9Ns4ZSTs7Pv17T/6a4TLp3sv0bD7ARAgQI0verpLtfj/ouABMMYQEAvBAgAAAvBAgAwAsBAgDwQoAAALwQIAAALwQIAMALAQIA8EKAAAC8ECAAAC8ECADACwECAPBCgAAAvBAgAAAvBAgAwAsBAgDwQoAAALxwIiEQpIIG0rF7Sb06SLnVHFUbhKWrpYfeluYvC+f6QC0RIECQzhsinTgw/DqH7SINukoqWx9+LWATGMICgrRLN5s67VpKXba0qQVsAgECBCknpGGr6uTx44to8R0IAPBCgAAAvBAgAAAvBAiQVKXlUd8BshwBAiQVS3gRMQIEAOCFAAEAeCFAgCCtr4j6DgAzBAgQpOKyqO8AMEOAAAC8ECAAAC8ECADACwECAPBCgABJVc6KL0SLAAGSihVfiBgBAgDwQoAAALwQIECQMlHfAGCHAAGCtKY46jsAzBAgAAAvBAgAwAsBAgDwQoAAALwQIEBSVVZGfQfIcgQIkFTrSqO+A2Q5AgQA4IUAAQB4IUAAAF4IECBI60qivgPADAECBKmSZljIHgQIAMALAQIA8EKAAAC8ECAAAC8ECJBEa1nthegRIEASZVjthegRIAAALwQIAMALAQIEqbgs6jsAzBAgQJDKK6K+A8AMAQIA8EKAAAC8ECAAAC8ECADACwECJFERq70QPQIESKIKVnshegQIAMALAQIA8EKAAEEqXx/1HQBmCBAgSCXlUd8BYIYAAQB4IUAAAF4IEACAFwIEAOCFAAGSiMl6xAABAiRRGcuFET0CBADghQABAHghQIAgVVRGfQeAGQIECNK60qjvADBDgAAAvBAgAAAvBAgAwAsBAgDwQoAASVTOkbaIHgECJFFJWdR3ABAgAAA/BAgAwAsBAgDwQoAAQVpTHPUdAGYIEACAFwIEAOCFAAEAeCFAAABeCBAgiSozUd8BQIAAibS2JOo7AAgQAIAfAgQA4IUAAQB4IUCAIBVxJjqyBwECBGk953QgexAgAAAvBAgAwAsBAgDwQoAAALwQIEASsRMdMUCAAEmUoRcWokeAAAC8ECAAAC8ECBCk0vKo7wAwQ4AAQSpbH/UdAGYIEACAFwIEAOClQdQ3EFutm0ktG0vNG0stGkuNCqSGBVJujtSkofv/aVIo5eVKFZXSuh+6sK4tljKSSsrc11YXSauKpOVr3Z8AkBLZGyBNG0rd2knd20kdW0udWkud2khtW0htmkkN8oKvWbZe+n6VtHiVNH+ZNG+pNHepNOM76dvvmYAFkCjZESBNG0r9ukp9u0o7dJK26yi1a2l/HwUNXFh1bC313/an/7fKjAuUL+ZJn82VPp3j/jOhguqEce5I7w7Svtu779MwrK+Q3vjSfV8jFdIZIIX50i7dpH22k3btLvXq4Iae4iw3R+qypfv86hfua2XrXZi8+7X05pfuP1dURnufYTusv7Rbj3DeACUX1F8tkB58K9krptYH/H3Qu4P06HluSDZMZ/9KOn6M9MnscOvERW6OtH0nqdtWUq7BlHMmI03+QlqxLvxaSlOAtGgs7ddHGtRP2rOXC5GkK2jg3lT6byv97hBpTbH02hfSS5+4QClJ2dvJkAHS339jU6tTG+max2xqJcE+24UfHpL7hbr/DtkRIEfu5gLTerRj3EvSmKdNSiU7QBrkSQO3l4bu5v4M66k1Lpo1kobs4j7FZdILU6VJH0jvz3BP1km3a3e7WhsPIWY7y5+dbDi18YIjpFP3t6+7Yp305Adm5ZIZIFu1kI7e033aNI/6bqLRqEA6Ylf3mb/MDck89q600ubVNRQWT8BVckIa0gx6aMnKOs5yD8xpB0QTHutKpd+Ok2YtNiuZrADZpq10+oHS4QPS/7ZRFx1bS+cNkc4+1IXIHa9KC5ZHfVfZKYzJbSTHEbtK5x9uX7dsvfT78W7xjaFkBEiHVm4sccgu4T05pkFhvnT8PtIxe7mhrZufk75bEfVdAdlh3+2lq4+zr1uZkf58p1tsYyzeAdKkUBp5iHTSQN446iIv103gDd5Fum+KdOvzHECEmq0z/P5I49L0fl2lf59mOwxb5eL7pVc/t6+rOLcyGdRPevYSN55IePjJz3Njsc9f6lY4xd3q4qjvIHtZLsIoTfDy6ep020oaO1xqGMHKz7897kYbIhK/AGnZRLrhJGnMqW5XOOqvdTO3PHbCSKn9FlHfTTxYPnEjvdq1lMaPdNsIrN38nHTvZPu6G4hXgPTfVpp4ofR//aO+k3Tas5f01EU/blTMZklf9lwW8DBQkjdVRqVFY2n8iGi6WtwzWbrlefu6G4lPgJw0ULr7bLdEF+FpUij942Q32ZeGzZbZKuhhoJKyYK9Xo4SHt+Qaq44d7vrpWZv4vnTtE/Z1qxF9gOTlSlccLV10ZDQTUNlq2O7SPWdLW2bpPhpEZ03Chw/zcqUxp7iJc2uvfCZd+oBrWRID0f7Gzs+TbjzdLTuFvb5dpIfPdR2JAWxeTo501bHSwD72td+b4ZbrxqgfXnQBkp/nXgEP2CGyW4Dc+O19f3RhErU0tLiIyZNhna1hBVytnDvYtU6y9ukcaeR/pPJ4/YxEEyB5udKY09ykLqLXorFboRV1iBQbjsOH9RTHfpv0Onk/1wnD2ozvpOHjYtnlIJoA+cvRvHnETdOGLkS27xj1ndig91N0TCfsA3JYf2nUUPu685ZJZ42NbY87+53oJ+0n/XoP87J1sqbYnRQ4d6k75GnxKvcXWPUpLf+xlXpxmWtsKLmjbvPzpC2auP0srZpJbZv/eM5H5zbxXvnUtKE0brh09D9pgZJtLI8GSNqS4b17S6NPsK+7ZLV0xq3SopX2tWvJNkB23ka6IIJGYzXJZKQvF0jvfCV9PtedljZvWTi1cnKkrltKO3V1w0W/2FbqtXU4tXy1aS7d/lvpmH/G8pUZIUnaL3UrfbtIN51u3w1jdZF0xm3uITbG7AKkWSO3wzwOS3UrKt3Rms9+LL01XVq+1qZuJuPOPv/2e7eWW3KT2Pv1cZ+9jQ712Zzu7dw+kXPuivpOgOh0bftDi5IC27ol5dKZY6WvF9rW9WAXIBccLm3dyqxctRatlO56TXrqQ7vQ2JxFK91ZHg++5Z7+j9jVDfF1bhPtfR26s/TBN9IDb0Z7H6he0CvWkr4zP2hbtZAmjHDD0ZbWV7jVVsZt2X3ZBMiA7tJREc57zFvmOtI+/VG8l4ouXS2Nf1m64xXpkJ1dJ+JuW0V3PxccIb39lTRniU29tB3RG6aigCeiLXuDxX3JcLNG0n9G2D/wVmakc+52w+kJEf54SW6OdMmw0MtUq7Rcuuk5afBoN2QU5/DYUGXGDa8NGS2df090k2gN86Vrjrc7g8VyHD6NLcVRfw0LpNvOknq0t6992QPSS5/Y162H8ANk8C7RTBRPmy8dcZ1780jqL4vKjHtrOvQa1zwtik1q/beVhu5qXzdsTBpjY3m5bp62/7b2ta99Qnr8Pfu69RRugOTlumEYa09+IB0/Rpr9vX3tMJSUSaMfdxNrUczdnDPYvdYjvbJ9xV1OjnTlMdKBO9rXvu0F6e7X7esGINwAGdTPfjL4jlelUfcn962jJm9Nl466QZq+wLZu62ZuFy42L6k70dcb9leK41zX2Ye6BqPW/vuGdOOz9nUDEm6AnDgw1Mv/zH/fkK6flNx+RLXx3QrppJukD2fa1j1lf/sVKUnEaqbNi9vw4YkDpRGD7Os+9aF09WP2dQMUXoD03Nq23fGb093xjtlgTbEbzpo6265mk0LphH3t6sFWzJr0mTl052halLz2uXTR/Yl/2A0vQA43PIN72Rrpwntj1eY4dCVlrsGa5TzPsXtJBSGu/OaY2egksT9Vfe3RS7ruRLdS1NL737jluin4fRVegBy8U2iX/pm/PR6fjYGWVhe5TUdWE6Ctm4V7HK7l8E9S5yoQjD6domlR8vlc6ffjUxPY4QRI7w5Sp9ahXPpn/vet2zORrb79XrryYbt6UZyFEIakz1Ukeegj6o2Endu4jYJNCm3rzlzsRg2i/ucPUDgBYnnOx4RX7GrF1ZMfSlOm2dQa0E3qEHFLGoTzBpUNb2VtmkvjR9ovCPluheusm7KRknACZPeeoVz2ZxYsd5NRkK55zGZ1S06O7fAk7CT5raY2mjWS/vNbu9GRKsvXSqfcHOu27L7CCZCdjE62e/y95A9FBGXuUteQ0UIUm62A+ihoIN1yhhtet7S2RDrtlti3ZfcVfIB0ai01bxz4ZatlNWyTFONftun39Yttw9mZXpn8VSmJZrX51nojYV6udP1JrqmrpZJyd5rgV/Fvy+4r+ADpadT3avlaado8m1pJsWS1650VttyccPoFWY7BhxVWlue6B81qg5/1RsJLj5J+aTzsur5COnu8W+STYsEHiFXrkmnzGb6qzqQPbOrs2sOmTljCOhM9KR2fs8XvD3X7lyxVZqQL7nWbm1MuhCEsowCZucimTtK8P8O9iYTNsssAbKTtgey4vaXfRdDM9YqHpOf+Z183AsEHSNsWgV+yWmnptBu0yoz0vME3b6+t7XfwIlxWQ4gWq71+uZMburJ2w5PSI+/Y141I8AHSqmngl6zWinU2dZLoLYMTzRoXSh2Nl0MiHcIOql27SzecbP+Ac/tLWbcvLfgAaWG0Aivbzy+oyf++tXnK2ybC43aB6vTuIN1yppRv3KLkobekMc/Y1oyB4AOkYX7gl6xWGs/7CMrqIukbgzmioDdkZWtHWB9htMNI8goyyX0/jh8hNW1oW/fZj6WrHk3/RsxqBB8gVudnW9VJqmnzw68R9BCWZYO5pD+AhPHLKskryFo1dS1KWjezrTtlmjTqvlR01vURfIBYdbe0mmtJqnkGO1+3bB5+jbCUxuxQo2wRxibCpg1dc0Tr008/min98c6sfnMOPkDKjX4wt6ahX40sAqQlJxSmisUbSNC/H/LzXFv27TsGe93Nmb5AGvGf1LRl9xV8gFidrWz9DZM0s5eEX6N5CO1M0iCpT6RFCftlmJsjXXeSXfPWKnOWSKffmqq27L6CD5DVRYFfsloDurMPoSZffxf+UudP54R7/aTK8qdSMxcdKR3Sz7bm4lWus27K2rL7Cv58Uqv9GVs2d039PpxpUy9pSsrcN/qJ+0pbBDxflMm4Sfo7Xw32uki/oCb/RwySfrNvMNeqrRXrUtuW3VfwAWKZzMfvQ4DU5OuF0mUPRn0XtZf0ZaRJZ3EmfRCbCI/aQ/rDr+p/nbpYW+IOhKIDxk8EP4S1YFngl9ykQf2kHu3t6iFclnMHFr8skyYJvbAO3FG68hjbmiXl0ojbbZbGJ0zwATLH8OCU3BzpL0e7fv9AXSThlyV+qn83+xYl6yukP93JSMcmBP+bd9biwC9Zo/7bSiMH2dYEamK1Fyqb9NxaGnuWXacLyT1kjLpfmvyFXc2ECT5Avl5ov4xx5CHS0N1sawKb0qgg6jtIl61bubPMrVuUXP2o9IzBAW0JFnyAlK13m2ysXX2c/cExAMLVqqk0YYTdMRFVxjwtPfCmbc0ECmfy4L2vQ7lsjarmQy49SioIfnEZECvZ8D3eqEAaO1zq2ta27h2vSuNesq2ZUOEEiMV5FJtywj7SQ+ewUz2JLHf2hnUmupWGKR8mq2pRsmNn27qPvuMOhUKthBMgH86025Fend4dpEfOk644OtkN/xAeq9P3UHc5OdLfTpD26m1b94Wp0hUPZ2Vbdl/hBMj6CumFT0K5dK3l5kjH7CW9dLl0yTCpA80XgRpZH8K0KaOOkA7rb1937ItZ25bdV3gbKCa9H9ql66Qw37U8ePFyadxw6dCds2P8GNFI8jk1cRgWO+Mg6aT9oqk9amg0dRMsvN+kH81yq7F6dwitRJ3k5kj7bu8+q4uk56dKr37uJvzDOKMA2cl6qWmaHLmbdO7g6Orv1kP61S/cCYOolXC3cN/1WqiX99a8sXT0nm5j0juj3RnKx+3t2qIk+QkSSKqBfaS/Hhv1XUgXHiE1KYz6LhIj3LGcpz6UzjxY6rZVqGXqpWG+dMAO7iO5jpsffCP971vXrvzL+TT5s8L4c+2lqX3PzttIY06Nxz9T2xZuY/L1k6K+k0QIN0AqM25Dzk2nh1omUFs0kX65k/tI7pfazEXSZ3PdLvvpC6TpC6NdZZZW60rtapUl/Ejbxil5Su7ezr5FyeacvJ/0+Hvu5x41Cn82+eVPpTenS3sbL8kLSl6u68PTc+uffn3RSumbRe6bbOYiaeZi9+cqgiURSpn3ily7ltL4kW5IOU7ycqXLjnJnf6BGNsuRrnxYmnRhep6aJPfN367lz4Nx2Zofw6QqWL5ZJC1dHcVdArVnuYy3ZRMXHlsZtyipLSbUa8UmQOYvk/72uOtXlXatm7nPrt1/+vU1xS5IZi3e4M1lsfTdCjYuIR6smkA2LHDDVnGeG5XchPrkL2yHVhPGbkPEY++6ybJhu5uVjJVmjdw//87b/PTrxWUuTL5ayBxLGrCMt2YN8qR/nyrt1DXqO9k8JtQ3y3ZH3V8fkbq1k/p1NS0ba40KpB06u8+GFq2UPp/rVoJ9Mc9N4lv2ioIfy8OOkqhtC/vOuvXBhHqNbAOkbL3023HSfX90qy+waVVzLAf1/fFr334vfTzLLTP+aJYbGkyTpK+MskRO2WBCvUb2PT1WFUmn3yqNH8F55nW1TVv3qRoGXLzK7aSf8qX09nS3hyXJLFdGJX1cu1mjqO8ge+zWQzqkn+tegZ+IpinU96tcov9nBG3X62OrFtKQAe6Tybhhrje/dI0sv14Y9d3FG5sWURcXDpUmT2NT8Uai2/q5fK10wr+lVz6L7BZSJSdH6tvFTfpNulB69hLpD7/6+f4VYFM4y33T2rWURg6K+i5iJ9reASVl0tkTpH8/43atIzjbtJVGDHJh8tj5rvdXmvbhIHic5V6zU/aXto350mNj0TefyWRcH/6TbpIWLI/6btJp+47SlcdIU66SLv81c09h4pdwejXIky4dFvVdxEr0AVLlo5nSkGvdQfZsrAtHk0LXdfjJUW4jVxLW4icNw0DptkcvN6EOSXEKEEkqKnV7RY75p/TJ7KjvJt0G9pEe/LN0+2/jc2aLxOQ24u/Cobxp/iBeAVLls7nScWOkP9/p2n0gPPtsJz1+vnTVsa4FS9Ti0NI7CTizwi37nhXB7wcm1P+/+P60ZjJu3fWQ0dKo+1z/KIQjJ0c6ag/p2YvdHhMO1Yq/3Pj+6JqozEjn3yudc1c0b61MqEuKc4BUqcxIkz5w8yPDx0lTprFiKyzNG7uGl+OGS22aR303sJak+ZurHpFe+sT1kLtnsn19JtQlJSFAqmQyLjyGj5MOvEK6+TnXyRbB22c7N9G+e8+o7wSWGidkXP+W56UH3/rxv9/8nOsdZ40J9QQFyIYWrXTfRAddKZ16i/TQW25jIoKzRRNpwkjXTC6NwhqmK4zRyXpp9Mg7LjA2VFQqXf1oNPeT5RPqyQyQKpUZ6d2vpSselva9TDrxRum+KdK8lDUZjEpujjRqqHTJsPRNbjcLqe16YTTdgbLCy5+6w+mq88pn0muf296P5CbUf/tL+7oxkZ7v9opK6cOZ7nPNY1LnNtLe27kTA3ftwaqV+vjNvu4EuVH3hTthWZCeb0cE7KNZ0vn31Pz9d/Vj0h493YFVlk49wLV8n7PEtm4MpPcndu5S6b9vuE9ertvr0L+b1H9b94nDktUkOay/VFkpjbo/vI2eDP/UXjYNm8z4Thpxu1SymW7NC5dLNz8vnTfE5r6q5OdJlx4lnXmbbd0YSG+AbKii0h3K9MU86Z7X3dc6tZZ27OIOcurbWdq+U3b9UPoYMsC1kP/nU1HfCSzPL4/SopXSWWNrf5jaXa9Jhw+wb9ezd2/p4J3cyrAskh0BUp15y9zn2Y/df8/Llbps6d5Uqj7bdWA568bOPMht3pr4ftR3gqDFbW/JqiLpjFvrtsKqotLNid7/x9Bua5MuGiq98aVrEpslsjdANlZR6X4xzlr8Y6hIUovGUq+tpe7t3SmKPdu7p5vmjaO716j95Whp2nzOHEmbOM0TlpS700t9OlF8PEt69B23OdZS+y3chPqYp23rRogA2ZxVRdL737jPhtq2cIHSvb0LmB7tpR7t7CfwotAwX/rHydKw6zmGdmNJ2owXV5UZ6U93SlNn+1/jhielA/u65eiWTjtAeiJ7JtQJEF/fr3Kft7/68Wu5OVLH1i5MenX48W2ly5bpWwbbvZ07b+Tfz0R9J37COhKWebT6u+wBafIX9bvGqiLpuonS6BMCuaVay7IJdQIkSJUZt/pr7tKfnrRYmC9120rq0+nHT68OyZ8IPf1A97Q1d2kw10v6vw/U35in3ZLYIEz6QDpyN2lA92CuV1tZNKFOgFgoLXdzBtPmu520khvq2L6j1G8baedt3NLiLRM2YZ+fJ51/uDtVMgg8vddeGsP2vinSuJeCu14m4zYeTrzQfmgxSybUCZCorK+QPp3jPlVLizu3kfbq7T679ZCahrRbOkgH9ZW26yh9OT/qO8kuaZtre36qNPrx4K87c7E04VVp+MHBX7smWTKhnrKB+YSbu9SdyPj78dLuF7nWLPe/IS1ZHfWd1WxE9rZySJWo5unemyFdcE94XbbHviDNj6C90WkHuPnPFCNA4qqqNcvVj0r7XS795kY3Nry53bhROGBH1xMIydY4gmW80xe4IdDyivBqlJRLV0XQbDE/z/WRSzECJAkqM+7M+Ev+Kw28XBr9RLyWCeblSr82XnMfV3HbjBdn85dJZ9Zhl3l9TJkmvTA1/Dob22c76YAd7Osa4bs9aVYXuTmTX10jnXt3fIJk8ICo76Buwto0l4R5qzhYsU464zZpqeHw7N8el9aV2tWrcvEwt3cqhQiQpKrMuB3zh412byRFEfxgbKhTa7c8uT5yDY/SzUvhKqakKC5z/a2sH36+XyXdGMG+pQ6tpLOMJ/GNECBJt77CvZEcNvrnu+Wt7V/PV/UmPL3XWpI3po5+XPp8bjS173/DLae3dvqBbpVlyiT4uxA/8d0K6bRbpNsDXEdfVxyBaydOfavqKsrTQysqpSseCu9Igk0paJDKCXUCJE0qKqV/PS1d/N/wlkTWZKcuqR3rTT3L4cOofTbXLZe3tu/2qZtQJ0DS6In3pEsfsK/bIM+1aEHyZNvw4ZhnbCfwq6RsQj2YnejbdZTOHRzeKX/zlkrXTnQnjqF2nnjP9d86/UDbun06SZ/Mtq0J1NWaYrf45B8n29atmlC/8VnbuiEJJkDGnBruBFHvDq4h4fBx4dVIo3897c6D37GzXc3u7exq1UdYT4FhdflF8J79WBq2u7RnL9u6px/oDmQLqglphIIZwrJYXcDQSN1FMWHYKSErTfJpAwe5ZovWZ9qkaEI9mACpqAzkMjVqkcUnANbHtPmuUZ2Vjq38/7fNeXqHsblLpbEv2tdNyYR6MAFisYmtYX6qJp9MVXX7tcAZ8jaSPFQWt7b9E16RZn9vXzcFE+oBBYhRz/uWxsdTpsXU2dI8o26kTRum86yKtMsxXMYbt+HDsvXSlY/Y1+3QSjrNeJFLwIIJkBVGG4MIEH+vf25XqwV/T4nTLMuW8W7s3a+lpz60r3vWQe4Y7IQKJkCWrgnkMpuV4H/Rkfvft3a1CmP2hAnUxt8n2nQG3lBhvnTxkbY1AxRMgCw3CpCkLBGNo1mL7WpZDof4Kggp5JLcYiTbLVsj/eMp+7r77yAN7GNfNwDBBIjVaV/btLWpk0YLV9jVKkzAxGBYk5dJbnII6ZG3o9kIe8mwZPzcbCSY73arCdpuvIF4s3w1L/FcVMFZGohaZUa64mGbrQkb6tTavmtEAIIJEKsdlT3ahzf0gOD4HrubhKGvuIji+NlsMX2BdM9k+7oJnFAPJkBmfBfIZTaroEH9Dy3KVpbrzdeW2NXKVg0YKgvVzc9Ji1ba1kzghHow34Vriu3mQfYw7luTFlbdVlcXSaWebyCITpI3JoahqFS6+lH7ugmbUA/uMWb6gsAuVaN9t7OpkzZWe2iWRNAiGwjDK59Jr39hXzdBE+rBBYjVPoO+XaStWtjUSpOe7W3qzElIh9EGIe2WT3hrCmzkqkf95/R8JWhCPbgAsTqPOydH+r/+NrXSpIdRgMxaZFOnvsLqxxS3Nh2on4XL3XyItYRMqAcXIF/Ot5s8PWoPVuzUldXigxn1CBA24SGO7n5d+sb4wagwXxo11Lamh+ACpKJSenN6YJer0TZtpd172tRKg4IG7mApC1PrMZSZRxPGWkvIGHkqrK+Q/vKQfd0Dd5T2ifecb7BrAV/7LNDL1ejMZIwRxsLAPjZj88vXpuKUtURI8n6oJHZr/niW9Ni79nUvPSrWf9fBBsjkaS6tLezRS9rN6Kk66Y7czabOu1/b1EHwLA/zahiz80Bq64YnpRXrbGt2biOddoBtzToINkBWFbkQsXLBEVIucyE16txGGri9Ta3JESx5BKysXCddP8m+7vBfSlvX46TPEAW/nXXi+4FfcpO27ygdv49dvST63SE2Cw4qKm0fHuorrAePGA83IAAT35c+nGlbs2G+dFE8J9SDD5DJX0hLDTeTnTNY6rKlXb0k2amrNGSATa3J09wbaFKE1biRfSDplvmh2aLVUH2Vg/rGckI9+AApr5AefCvwy25SowLpHyezKmVjBQ2kq4+zqzcpgDdPfvkiCWYuku541b5uDCfUw+nI9uBbtv2Q+nSSrjqWvSEbGjXU7gCuRStd24f6YhNe7SVxJVOa3PaCXf+/KjGcUA8nQJatkR56O5RLb9LgXaTzhtjWjKtj95KO29uu3v1v2J+fkO2SupIpLUrKXZsTazGbUA+vJ/T4l+27sp52gHTuYNuacTN4F+myX9vVW1UkPWQ4ZIlw0I237qZMk16YalszZhPq4QXIktXSvREcynLGQdKVx2Tn0aJH7iZd+xvbpc0TXrE97RCIk79PtH9QjtGEeri/Zce+GE1776P3lCaMlNo0t68dhbxc6c+HSdccbxsei1ZK902xq5cE2fjgks2+WyE98KZ93UuGxWIeLNzv9nWl0g0RbLyR3C71iRe4A1rSrF1L6Y7fSWcdbF/7709IxZ7nn0ctrCEbjprNPre/ZP8W3mVL6ZT9bWtWI/zHpSc/dGOFUWjdTLr1TOmfp6TvDJG8XOnU/aVnLpZ27W5ff8o06fmpwV4zZksUgVpZsU668zX7uiMHuQfICNm8b1/6QLSbzA7dWXr+UrfpMOmThTk5rkvnxAtdK5connhXFbm/06CxD6RuaOMTH3e/bruBWnIr8SJu+W4TIEtWSxfdb1JqkxoWSGceJE3+q1vF0Cn+h7X8RIM8d5DWpAulm8+w2+NRncse5OjaOLA65x6bV1Qq3faifd1B/aQ9e9nX/YHdjN9rn0eze3NjjQqkk/aTXrhMuvN30rDd3VBXXPXaWrroSGnKVdINJ9mdLLgpE16RXvok2ntA8MJq7VKdtL44PfJ2NMcZXHpUZBPqtoPO/3zKPTnva9QdtiY5Oe5Qqt17SpUZ1+//5U/dn9PmR7cxrjBfGtDN/Tsa2MftPo2LN6dL/3o66rtAGHINV48lfRh5U8orpJuela4/ybbuNm3dhPp/XratK+sAqaiUzrlLuu+PUu8OpqVrlJsj7dLNfSS3y/TTOdIns13fm2+/d5+gV1o0byx1aSN1by/t2Nl9tusYz6WgX86X/nQHO843h3Y62e3Zj6XTD7T//TZykPTUh25pvSH7ZS/rSqURt0t3nx2vp+sNNcx3K5s2Xt20Yp20cLn7c/laN2m2Yp1Utt5156xa0lpcKjX6YXK7aUOpQa60RVNpiyZSq2ZS66ZS17ZSi8a2/1y+Zi2WzrjN/d2lRVjnrzdjXiKrVWbcW/q44bZ1qybU/3Snadlo1k0uWimdfJN07x+kjgmazN6iiftkk7lLpdNvdYEZtgaG47hxfMtDOkyZJn3wjTTAeHl91YT621+ZlYzup2jRSunEG93TLeJp2nzp+DF2r8WNaBCIlPjHU9HUNZ5Qj/YxrCpEPp0T6W2gGm9/JZ10o+usjHiyXDmFuvlkdjBHHNRV1YS6kejf45evdcNZz3wU9Z2gyl2vSWeNTdecRxoFuZGQMArev552cyLWDHeoRx8gklv1dN490g1PssonSutKpXPvdh1G+XvILqweC97MRcGc1FlXDQtclwoD8QiQKhNekU74t/1JX3DDiEP/7pYhAgjGTc+5VZrWDt3Z7XELWbwCRHJjh0Ovkx55J+o7yQ4l5e7N7/gx0rwsCu6wTvRjKAgbiqrdu+Qm1ENe2Ri/AJGktSXS5Q9Kp9wszVkS9d2k15Rp0uHXuje/OAxZWS6tDWulCkNB2Ni4F93vNGvdtpJO3i/UEvEMkCrvzZAGj5aumxjNX0BazVwsDR/nPlH07tmUsDb3AVFasS66PoAjB4V6lEW8A0Ry/WXufE365V/dn9bHR6bJwuXSxf91bx1RndGC4LBvJjnufj2aJfGNC6ULw2v5Hv8AqbJinXsTOfiHIGGJae3NXCSNuk8adLX0xHvxGK5C/QU5vs3bX7iKSqXbXoimdogT6skJkCpLVrsg2e9y6fpJrNjalEzGtdA/a6w0+Fpp0geuXxdQHVq7hO/ht6NbqBLShHpyzxBdW+LGFe98zZ1/fvSe0gE7uHbo2WzuUhcWE993Q1aoHmEanWw9N76q3ft1J9rXrppQn/BKoJdNboBUyWSkd792nyaF0oF93Svbnr2y54zt71ZIL0x1Z5R/Osf9O0kiy7fJlz8N57qLVtq08i6vcH/vQbHsSfdtFve/e+YjafAu0j7b2dceOYgAqdG6UunJD9ynUYELkYF9pD16Jqvr7+ZUVEpTv5WmfOkmw6cviPqOgnHXa66XT3mF9GWI/0xzlkiTvwjn2qMfd8cBhHlUQXGZNPZFdzZ9UF6YKv1iW+ngvuFNzpeUS69/IT0Rwe7suKjMSGdPkH5/iHTwTlKrpjZ1M5lQenPlZHr/4VtJXQO/ctx0aCXt2kPq11Xq28UdDZuUcd+1JdLnc6Wps6X3v5H+961UUhb1XQHIbrOzJ0A21qjAnTfeo73Uc2t31G6XLV0Tsqg2g62vkBaukGZ8J32zSPp6oXu7mP19NE3ZAGDTZqdrCKsuisvcE/3U2T/9ekED97aydSupbQu3CadtC3d6YIvGUssmrl1FYb6bc2lcWPObzNoS97ZQUi6tLpZWrnNDDyvWSotXSYtXuj/nL3Nj2iyxBZAQ2Rsgm1K2/scz0AEAm5SQSQAAQNwQIAAALwQIAMALAQIA8EKAAAC8ECAAAC8ECADACwECAPBCgAAAvBAgAAAvBAgAwAsBAgDwQoAAALwQIAAALwQIAMALAQIA8EKAAAC8ECAAAC8ECADACwECAPBCgAAAvBAgAAAvBAgAwAsBAgDwQoAAALwQIAAALwQIAMALAQIA8EKAAAC8ECAAAC8ECADACwECAPBCgAAAvBAgAAAvBAgAwAsBAgDwQoAAALwQIAAALwQIAMALAQIA8EKAAAC8ECAAAC8ECADACwECAPCSKyk/6psAACROfq6kRlHfBQAgcRrlSiqM+i4AAIlT2EDSVEk9JBVLykR6OwCAuMuRG7ma8f8ANweKgJ3fkDEAAAAASUVORK5CYII="
                        try
                            {
                                if (-not $OutputPath)
                                    {
                                        Write-Warning $("HTML report generation skipped: Report path not initialized (likely due to early validation failure).")
                                        return
                                    }

                                # Build configuration card content
                                $configCardContent = @"
                <strong>$("Subscription:")</strong> $(if ($ReportData.EnvironmentValidation.SubscriptionName) { $("{0} ({1})" -f $ReportData.EnvironmentValidation.SubscriptionName, $ReportData.Configuration.SubscriptionId) } else { $ReportData.Configuration.SubscriptionId })<br>
                <strong>$("Resource Group:")</strong> $($ReportData.Configuration.ResourceGroupName)<br>
                <strong>$("Region:")</strong> $(if ($ReportData.EnvironmentValidation.RegionDisplayName) { $("{0} ({1}){2}{3}" -f $ReportData.EnvironmentValidation.RegionDisplayName, $ReportData.Configuration.Region, $(if ($ReportData.EnvironmentValidation.RegionGeography) { " | {0}" -f $ReportData.EnvironmentValidation.RegionGeography } else { "" }), $(if ($ReportData.EnvironmentValidation.RegionPhysicalLocation) { " | {0}" -f $ReportData.EnvironmentValidation.RegionPhysicalLocation } else { "" })) } else { $ReportData.Configuration.Region })<br>
                <strong>$("Availability Zone:")</strong> $($ReportData.Configuration.Zone)<br>
"@

                                if ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0)
                                    {
                                        $configCardContent += @"
                <strong>$("Mode:")</strong> SKU Family Deployment Test<br>
"@
                                    } `
                                elseif ($ReportData.Configuration.CNodeSKU -and $ReportData.Configuration.CNodeCount -gt 0)
                                    {
                                        $configCardContent += @"
                <strong>$("CNode Count:")</strong> $($ReportData.Configuration.CNodeCount)<br>
                <strong>$("CNode SKU:")</strong> $($ReportData.Configuration.CNodeSKU)<br>
"@
                                    }

                                if (-not ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0))
                                    {
                                        if ($ReportData.Configuration.MNodeSizes.Count -gt 0)
                                            {
                                                $mNodeSizeDisplay = ($ReportData.Configuration.MNodeSizes | ForEach-Object { $_ }) -join $(", ")
                                                $totalDNodes = 0
                                                foreach ($mNodeSku in $ReportData.Configuration.MNodeSKUs)
                                                    {
                                                        $totalDNodes += $mNodeSku.dNodeCount
                                                    }
                                                $configCardContent += @"
                <strong>$("MNode Sizes:")</strong> $($mNodeSizeDisplay) TiB<br>
                <strong>$("Total DNodes:")</strong> $($totalDNodes)<br>
"@
                                            }
                                    }

                                # Build summary card content
                                $totalExpected = $ReportData.Deployment.TotalExpectedVMs
                                $totalDeployed = $ReportData.Deployment.TotalDeployedVMs
                                $totalFailed = $ReportData.Deployment.TotalFailedVMs
                                $infra = $ReportData.Deployment.Infrastructure

                                if ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0)
                                    {
                                        $deploySkuResults = $ReportData.SKUFamilyTesting.DeploymentResults
                                        $skuUniqueNames = $deploySkuResults | Select-Object -ExpandProperty SKUName -Unique
                                        $skuUniqueCount = $skuUniqueNames.Count
                                        $skuUniqueSuccessCount = ($skuUniqueNames | Where-Object { $sku = $_; ($deploySkuResults | Where-Object { $_.SKUName -eq $sku } | Select-Object -First 1).DeploymentResult -eq $("Success") }).Count
                                        $skuUniqueFailedCount = $skuUniqueCount - $skuUniqueSuccessCount
                                        $summaryStatusClass = if ($skuUniqueFailedCount -eq 0) { $("status-success") } else { $("status-warning") }
                                        $summaryStatusText = if ($skuUniqueFailedCount -eq 0) { $("✓ ALL {0} SKUs DEPLOYED" -f $skuUniqueCount) } else { $("⚠ {0} SKU(s) FAILED" -f $skuUniqueFailedCount) }
                                        $deployedCountClass = if ($skuUniqueFailedCount -eq 0) { $("status-success") } else { $("status-warning") }
                                        $isSKUTestMode = $true
                                    } `
                                elseif ($ReportData.Deployment.Attempted)
                                    {
                                        $summaryStatusClass = if ($totalDeployed -eq $totalExpected -and $infra.VNetCreated -and $infra.NSGCreated) { $("status-success") } else { $("status-warning") }
                                        $summaryStatusText = if ($totalDeployed -eq $totalExpected -and $infra.VNetCreated -and $infra.NSGCreated) { $("✓ SUCCESSFUL") } else { $("⚠ ISSUES DETECTED") }
                                        $deployedCountClass = if ($totalDeployed -eq $totalExpected) { $("status-success") } else { $("status-warning") }
                                    } `
                                else
                                    {
                                        $summaryStatusClass = $("status-success")
                                        $summaryStatusText = $("📊 REPORT ONLY")
                                        $deployedCountClass = $("status-warning")
                                    }

                                # Build Silk Component Summary table rows
                                $silkSummaryRows = $("")
                                foreach ($component in $ReportData.SilkSummary)
                                    {
                                        $statusClass = if ($component.Status -like $("*Complete*")) { $("status-success") } elseif ($component.Status -like $("*Failed*")) { $("status-error") } else { $("status-warning") }
                                        $silkSummaryRows += @"
                <tr>
                    <td>$($component.Component)</td>
                    <td>$($component.DeployedCount)</td>
                    <td>$($component.ExpectedCount)</td>
                    <td>$($component.SKU)</td>
                    <td><span class="$statusClass">$($component.Status)</span></td>
                </tr>
"@
                                    }

                                # Build CNode deployment table
                                $cNodeTableHtml = $("")
                                $cNodeReport = $ReportData.Deployment.VMReport | Where-Object { $_.ResourceType -eq $("CNode") }

                                # Detect multi-zone deployment for conditional Zone column
                                $htmlUniqueZones = @($ReportData.Deployment.VMReport | Select-Object -ExpandProperty Zone -Unique -ErrorAction SilentlyContinue)
                                $htmlIsMultiZone = $htmlUniqueZones.Count -gt 1
                                $zoneThHtml = if ($htmlIsMultiZone) { $("{0}                    <th>{1}</th>" -f $("`n"), $("Zone")) } else { $("") }

                                if ($cNodeReport)
                                    {
                                        $cNodeTableHtml = @"
        <h2>$("🖥️ CNode Deployment Status")</h2>
        <p><strong>$("Expected SKU:")</strong> $($cNodeReport[0].ExpectedSKU)</p>
        <table>
            <thead>
                <tr>
                    <th>$("Node")</th>$zoneThHtml
                    <th>$("VM Name")</th>
                    <th>$("Deployed SKU")</th>
                    <th>$("VM Status")</th>
                    <th>$("Provisioned State")</th>
                    <th>$("NIC Status")</th>
                    <th>$("Availability Set")</th>
                </tr>
            </thead>
            <tbody>
"@
                                        foreach ($cNode in $cNodeReport)
                                            {
                                                $vmStatusClass = if ($cNode.VMStatus -like $("*Deployed*")) { $("checkmark") } else { $("error-mark") }
                                                $nicStatusClass = if ($cNode.NICStatus -like $("*Created*")) { $("checkmark") } else { $("error-mark") }
                                                $provisioningClass = if ($cNode.ProvisioningState -eq $("Succeeded")) { $("checkmark") } elseif ($cNode.ProvisioningState -eq $("Failed")) { $("error-mark") } else { $("warning") }
                                                $zoneTdHtml = if ($htmlIsMultiZone) { $("{0}                    <td>{1}</td>" -f $("`n"), $cNode.Zone) } else { $("") }

                                                $cNodeTableHtml += @"
                <tr>
                    <td>$("CNode {0}" -f $cNode.NodeNumber)</td>$zoneTdHtml
                    <td>$($cNode.VMName)</td>
                    <td>$($cNode.DeployedSKU)</td>
                    <td><span class="$vmStatusClass">$($cNode.VMStatus)</span></td>
                    <td><span class="$provisioningClass">$($cNode.ProvisioningState)</span></td>
                    <td><span class="$nicStatusClass">$($cNode.NICStatus)</span></td>
                    <td>$($cNode.AvailabilitySet)</td>
                </tr>
"@
                                            }
                                        $cNodeTableHtml += @"
            </tbody>
        </table>
"@
                                    }

                                # Build MNode/DNode deployment tables
                                $mNodeTablesHtml = $("")
                                $mNodeGroups = $ReportData.Deployment.VMReport | Where-Object { $_.ResourceType -eq $("DNode") } | Group-Object GroupNumber
                                if ($mNodeGroups)
                                    {
                                        foreach ($group in $mNodeGroups)
                                            {
                                                $mNodeExpectedSku = $group.Group[0].ExpectedSKU
                                                $groupNumber = $group.Name

                                                $mNodeTablesHtml += @"
        <h2>$("💾 MNode Group {0} DNode Status" -f $groupNumber)</h2>
        <p><strong>$("Expected SKU:")</strong> $($mNodeExpectedSku)</p>
        <table>
            <thead>
                <tr>
                    <th>$("Node")</th>$zoneThHtml
                    <th>$("VM Name")</th>
                    <th>$("Deployed SKU")</th>
                    <th>$("VM Status")</th>
                    <th>$("Provisioned State")</th>
                    <th>$("NIC Status")</th>
                    <th>$("Availability Set")</th>
                </tr>
            </thead>
            <tbody>
"@
                                                foreach ($dNode in $group.Group)
                                                    {
                                                        $vmStatusClass = if ($dNode.VMStatus -like $("*✓ Deployed*")) { $("checkmark") } elseif ($dNode.VMStatus -like $("*⚠*")) { $("warning-mark") } else { $("error-mark") }
                                                        $nicStatusClass = if ($dNode.NICStatus -like $("*Created*")) { $("checkmark") } elseif ($dNode.NICStatus -eq $("—")) { $("warning-mark") } else { $("error-mark") }
                                                        $provisioningClass = if ($dNode.ProvisioningState -eq $("Succeeded")) { $("checkmark") } elseif ($dNode.ProvisioningState -eq $("Not Attempted")) { $("warning-mark") } elseif ($dNode.ProvisioningState -eq $("Failed")) { $("error-mark") } else { $("warning-mark") }
                                                        $zoneTdHtml = if ($htmlIsMultiZone) { $("{0}                    <td>{1}</td>" -f $("`n"), $dNode.Zone) } else { $("") }

                                                        $mNodeTablesHtml += @"
                <tr>
                    <td>$("DNode {0}" -f $dNode.NodeNumber)</td>$zoneTdHtml
                    <td>$($dNode.VMName)</td>
                    <td>$($dNode.DeployedSKU)</td>
                    <td><span class="$vmStatusClass">$($dNode.VMStatus)</span></td>
                    <td><span class="$provisioningClass">$($dNode.ProvisioningState)</span></td>
                    <td><span class="$nicStatusClass">$($dNode.NICStatus)</span></td>
                    <td>$($dNode.AvailabilitySet)</td>
                </tr>
"@
                                                    }
                                                $mNodeTablesHtml += @"
            </tbody>
        </table>
"@
                                            }
                                    }

                                # Build SKU Support cards
                                $skuSupportCardsHtml = $("")
                                $cNodeSkuData = $ReportData.SKUSupportData | Where-Object { $_.ComponentType -eq $("CNode") }
                                if ($cNodeSkuData)
                                    {
                                        $zoneSupportClass = switch ($cNodeSkuData.ZoneSupportStatus)
                                            {
                                                "Success" { $("status-success") }
                                                "Warning" { $("status-warning") }
                                                "Error"   { $("status-error") }
                                                default   { $("status-warning") }
                                            }

                                        $availableZonesHtml = if ($cNodeSkuData.AvailableZones.Count -gt 0) { $("<strong>$("Available Zones:")</strong> {0}" -f ($cNodeSkuData.AvailableZones -join $(', '))) } else { $("") }

                                        $skuSupportCardsHtml += @"
            <div class="info-card">
                <h4>$("🖥️ CNode SKU Support")</h4>
                <strong>$("SKU:")</strong> $($cNodeSkuData.SKUName)<br>
                <strong>$("Region:")</strong> $($ReportData.Configuration.Region)<br>
                <strong>$("Zone Support:")</strong> <span class="$zoneSupportClass">$($cNodeSkuData.ZoneSupport)</span><br>
                $availableZonesHtml
            </div>
"@
                                    }

                                $mNodeSkuData = $ReportData.SKUSupportData | Where-Object { $_.ComponentType -eq $("MNode") }
                                if ($mNodeSkuData)
                                    {
                                        foreach ($mNodeTypeData in $mNodeSkuData)
                                            {
                                                $zoneSupportClass = switch ($mNodeTypeData.ZoneSupportStatus)
                                                    {
                                                        "Success" { $("status-success") }
                                                        "Warning" { $("status-warning") }
                                                        "Error"   { $("status-error") }
                                                        default   { $("status-warning") }
                                                    }

                                                $availableZonesHtml = if ($mNodeTypeData.AvailableZones.Count -gt 0) { $("<strong>$("Available Zones:")</strong> {0}" -f ($mNodeTypeData.AvailableZones -join $(', '))) } else { $("") }

                                                $skuSupportCardsHtml += @"
            <div class="info-card">
                <h4>$("💾 MNode SKU Support ({0}x {1} TiB)" -f $mNodeTypeData.InstanceCount, $mNodeTypeData.PhysicalSize)</h4>
                <strong>$("SKU:")</strong> $($mNodeTypeData.SKUName)<br>
                <strong>$("Region:")</strong> $($ReportData.Configuration.Region)<br>
                <strong>$("Zone Support:")</strong> <span class="$zoneSupportClass">$($mNodeTypeData.ZoneSupport)</span><br>
                $availableZonesHtml
            </div>
"@
                                            }
                                    }

                                # Build Quota Family cards
                                $quotaFamilyCardsHtml = $("")
                                if ($ReportData.QuotaAnalysis.RawQuotaData)
                                    {
                                        # Build unique quota families from SKU support data
                                        $quotaFamilies = @()
                                        foreach ($skuEntry in $ReportData.SKUSupportData)
                                            {
                                                if ($skuEntry.SKUFamilyQuota)
                                                    {
                                                        $familyName = $skuEntry.SKUFamilyQuota.Name.LocalizedValue
                                                    } `
                                                else
                                                    {
                                                        $familyName = $null
                                                    }

                                                if ($skuEntry.QuotaFamilyName -and $quotaFamilies -notcontains $skuEntry.QuotaFamilyName)
                                                    {
                                                        $quotaFamilies += $skuEntry.QuotaFamilyName
                                                    } `
                                                elseif ($familyName -and $quotaFamilies -notcontains $familyName)
                                                    {
                                                        $quotaFamilies += $familyName
                                                    }
                                            }

                                        $quotaFamilies = $quotaFamilies | Sort-Object -Unique

                                        foreach ($quotaFamily in $quotaFamilies)
                                            {
                                                $requiredvCPU = 0
                                                foreach ($skuEntry in $ReportData.SKUSupportData)
                                                    {
                                                        $entryFamily = if ($skuEntry.SKUFamilyQuota) { $skuEntry.SKUFamilyQuota.Name.LocalizedValue } elseif ($skuEntry.QuotaFamilyName) { $skuEntry.QuotaFamilyName } else { $null }
                                                        if ($entryFamily -eq $quotaFamily) { $requiredvCPU += $skuEntry.vCPUCount }
                                                    }

                                                $quotaFamilyInfo = $ReportData.QuotaAnalysis.RawQuotaData | Where-Object { $_.Name.LocalizedValue -eq $quotaFamily }

                                                $quotaStatus = $("")
                                                $quotaStatusClass = $("")
                                                $quotaWarning = $("")

                                                if (-not $quotaFamilyInfo)
                                                    {
                                                        $quotaStatus = $("⚠ Quota Information Unavailable")
                                                        $quotaStatusClass = $("status-warning")
                                                        $quotaWarning = $("<br><em style='color: var(--warning);'>$("This SKU family is not yet registered in Azure quota system (expected for preview/new families). Quota validation was skipped.")</em>")
                                                    } `
                                                else
                                                    {
                                                        $availableQuota = $quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue
                                                        if ($availableQuota -ge $requiredvCPU)
                                                            {
                                                                $quotaStatus = $("✓ Sufficient Quota")
                                                                $quotaStatusClass = $("status-success")
                                                            } `
                                                        else
                                                            {
                                                                $shortfall = $requiredvCPU - $availableQuota
                                                                $quotaStatus = $("✗ Insufficient Quota (Shortfall: {0} vCPU)" -f $shortfall)
                                                                $quotaStatusClass = $("status-error")
                                                            }
                                                    }

                                                $availableHtml = if ($quotaFamilyInfo) { $("<strong>$("vCPU Available:")</strong> {0}/{1}<br>" -f ($quotaFamilyInfo.Limit - $quotaFamilyInfo.CurrentValue), $quotaFamilyInfo.Limit) } else { $("") }

                                                $quotaFamilyCardsHtml += @"
            <div class="info-card">
                <h4>$("🔧 {0}" -f $quotaFamily)</h4>
                <strong>$("vCPU Required:")</strong> $($requiredvCPU)<br>
                $availableHtml
                <strong>$("Quota Status:")</strong> <span class="$quotaStatusClass">$($quotaStatus)</span>$($quotaWarning)
            </div>
"@
                                            }
                                    }

                                # Build Quota Summary cards
                                $quotaSummaryCardsHtml = $("")
                                if ($ReportData.QuotaAnalysisData.Count -gt 0)
                                    {
                                        $vmQuotaData = $ReportData.QuotaAnalysisData | Where-Object { $_.QuotaType -eq $("Virtual Machines") }
                                        if ($vmQuotaData)
                                            {
                                                $vmQuotaClass = if ($vmQuotaData.StatusLevel -eq $("Success")) { $("status-success") } else { $("status-error") }
                                                $quotaSummaryCardsHtml += @"
            <div class="info-card">
                <h4>$("🖥️ Virtual Machine Quota")</h4>
                <strong>$("Status:")</strong> <span class="$vmQuotaClass">$($vmQuotaData.Status)</span><br>
                <strong>$("Required:")</strong> $($vmQuotaData.Required) $("VMs")<br>
                <strong>$("Available:")</strong> $($vmQuotaData.Available)/$($vmQuotaData.Limit)<br>
            </div>
"@
                                            }

                                        $vcpuQuotaData = $ReportData.QuotaAnalysisData | Where-Object { $_.QuotaType -eq $("Regional vCPUs") }
                                        if ($vcpuQuotaData)
                                            {
                                                $vcpuQuotaClass = if ($vcpuQuotaData.StatusLevel -eq $("Success")) { $("status-success") } else { $("status-error") }
                                                $quotaSummaryCardsHtml += @"
            <div class="info-card">
                <h4>$("⚡ Regional vCPU Quota")</h4>
                <strong>$("Status:")</strong> <span class="$vcpuQuotaClass">$($vcpuQuotaData.Status)</span><br>
                <strong>$("Required:")</strong> $($vcpuQuotaData.Required) $("vCPUs")<br>
                <strong>$("Available:")</strong> $($vcpuQuotaData.Available)/$($vcpuQuotaData.Limit)<br>
            </div>
"@
                                            }

                                        $avsetQuotaData = $ReportData.QuotaAnalysisData | Where-Object { $_.QuotaType -eq $("Availability Sets") }
                                        if ($avsetQuotaData)
                                            {
                                                $avsetQuotaClass = if ($avsetQuotaData.StatusLevel -eq $("Success")) { $("status-success") } else { $("status-error") }
                                                $quotaSummaryCardsHtml += @"
            <div class="info-card">
                <h4>$("🎯 Availability Sets Quota")</h4>
                <strong>$("Status:")</strong> <span class="$avsetQuotaClass">$($avsetQuotaData.Status)</span><br>
                <strong>$("Required:")</strong> $($avsetQuotaData.Required) $("sets")<br>
                <strong>$("Available:")</strong> $($avsetQuotaData.Available)/$($avsetQuotaData.Limit)<br>
            </div>
"@
                                            }
                                    }

                                # Build Infrastructure cards
                                $ppgHtml = if ($infra.PPGsCreated.Count -gt 0)
                                    {
                                        @"
                <strong>$("Proximity Placement Groups:")</strong> <span class="checkmark">$("✓ {0} Created" -f $infra.PPGsCreated.Count)</span><br>
                <strong>$("PPG Names:")</strong> $($infra.PPGsCreated.Name -join ', ')<br>
                <strong>$("PPG Type:")</strong> $("Standard")<br>
                <strong>$("Location:")</strong> $(($infra.PPGsCreated | Select-Object -ExpandProperty Location -Unique -ErrorAction SilentlyContinue) -join ', ')<br>
"@
                                    } `
                                elseif ($infra.PPGsReferenced.Count -gt 0)
                                    {
                                        @"
                <strong>$("Proximity Placement Groups:")</strong> <span class="status-info">$("✓ {0} Existing" -f $infra.PPGsReferenced.Count)</span><br>
                <strong>$("PPG Names:")</strong> $($infra.PPGsReferenced.Name -join ', ')<br>
                <strong>$("PPG Type:")</strong> $("Standard")<br>
                <strong>$("Location:")</strong> $(($infra.PPGsReferenced | Select-Object -ExpandProperty Location -Unique -ErrorAction SilentlyContinue) -join ', ')<br>
"@
                                    } `
                                else
                                    {
                                        @"
                <strong>$("Proximity Placement Groups:")</strong> <span class="error-mark">$("✗ Not Found")</span><br>
"@
                                    }

                                $avSetHtml = if ($infra.AvSetsCreated.Count -gt 0)
                                    {
                                        $avSetNames = ($infra.AvSetsCreated.Name | Sort-Object) -join $(", ")
                                        @"
                <strong>$("Availability Sets:")</strong> <span class="checkmark">$("✓ {0} Created" -f $infra.AvSetsCreated.Count)</span><br>
                <strong>$("AvSet Names:")</strong> $($avSetNames)<br>
                <strong>$("Fault Domains:")</strong> $($infra.AvSetsCreated[0].PlatformFaultDomainCount)<br>
                <strong>$("Update Domains:")</strong> $($infra.AvSetsCreated[0].PlatformUpdateDomainCount)
"@
                                    } `
                                elseif ($infra.AvSetsReferenced.Count -gt 0)
                                    {
                                        $avSetRefNames = ($infra.AvSetsReferenced.Name | Sort-Object) -join $(", ")
                                        @"
                <strong>$("Availability Sets:")</strong> <span class="status-info">$("✓ {0} Existing" -f $infra.AvSetsReferenced.Count)</span><br>
                <strong>$("AvSet Names:")</strong> $($avSetRefNames)<br>
                <strong>$("Fault Domains:")</strong> $($infra.AvSetsReferenced[0].PlatformFaultDomainCount)<br>
                <strong>$("Update Domains:")</strong> $($infra.AvSetsReferenced[0].PlatformUpdateDomainCount)
"@
                                    } `
                                else
                                    {
                                        @"
                <strong>$("Availability Sets:")</strong> <span class="error-mark">$("✗ Not Found")</span>
"@
                                    }

                                # Build Zone Alignment card content
                                $alignment = $ReportData.EnvironmentValidation.ZoneAlignment
                                $hasPeerAlignment = [bool]$alignment.AlignmentSubId
                                $zoneAlignmentHtml = @"
                <strong>$("Deployment Zone:")</strong> <span class="status-success">$($alignment.FinalZone)</span><br>
                <strong>$("Subscription:")</strong> $($ReportData.Configuration.SubscriptionId)<br>
"@

                                # Always show zone mapping table when mappings are available
                                if ($alignment.ZoneMappings.Count -gt 0)
                                    {
                                        $peerColumnHeader = if ($hasPeerAlignment) { @"
                            <th style="padding: 5px; font-size: 0.9em;">$("Peer Zone ({0}...)" -f $alignment.AlignmentSubId.Substring(0, 8))</th>
"@ } else { $("") }

                                        $zoneAlignmentHtml += @"
                <br><strong>$("Zone Mappings:")</strong><br>
                <table style="margin: 5px 0; width: 100%;">
                    <thead>
                        <tr>
                            <th style="padding: 5px; font-size: 0.9em;">$("Azure Zone")</th>
                            <th style="padding: 5px; font-size: 0.9em;">$("Deployment Zone")</th>
                            $peerColumnHeader
                        </tr>
                    </thead>
                    <tbody>
"@
                                        foreach ($mapping in $alignment.ZoneMappings)
                                            {
                                                $isDeployZone = ($mapping.DeploymentZone -eq $alignment.FinalZone)
                                                $rowStyle = if ($isDeployZone) { $("background-color: var(--bg-deploy-zone); font-weight: bold;") } else { $("") }
                                                $deployMarker = if ($isDeployZone) { $(" ◄") } else { $("") }
                                                $peerColumn = if ($hasPeerAlignment) { @"
                            <td style="padding: 5px; font-size: 0.9em; $rowStyle">$($mapping.AlignmentZone)</td>
"@ } else { $("") }

                                                $zoneAlignmentHtml += @"
                        <tr>
                            <td style="padding: 5px; font-size: 0.9em; $rowStyle">$("Zone {0}" -f $mapping.DeploymentZone)</td>
                            <td style="padding: 5px; font-size: 0.9em; $rowStyle">$("Zone {0}{1}" -f $mapping.DeploymentZone, $deployMarker)</td>
                            $peerColumn
                        </tr>
"@
                                            }
                                        $zoneAlignmentHtml += @"
                    </tbody>
                </table>
"@
                                    }

                                # Cross-subscription alignment details (only when peer sub provided)
                                if ($hasPeerAlignment)
                                    {
                                        $zoneAlignmentHtml += @"
                <br><strong>$("Alignment Subscription:")</strong> $($alignment.AlignmentSubId)<br>
"@

                                        if ($alignment.AlignmentPerformed)
                                            {
                                                $zoneAlignmentHtml += @"
                <strong>$("Zone Alignment:")</strong> <span class="status-success">$("✓ Applied")</span><br>
                <strong>$("Zone Change:")</strong> $($alignment.OriginalZone) → $($alignment.FinalZone)<br>
"@
                                            } `
                                        elseif ($alignment.AlignmentDisabled)
                                            {
                                                $zoneAlignmentHtml += @"
                <strong>$("Zone Alignment:")</strong> <span class="status-warning">$("⚠ Disabled by parameter")</span><br>
"@
                                            } `
                                        else
                                            {
                                                $zoneAlignmentHtml += @"
                <strong>$("Zone Alignment:")</strong> <span class="status-success">$("- No adjustment needed")</span><br>
"@
                                            }
                                    }

                                $zoneAlignmentHtml += @"
                <strong>$("Reason:")</strong> $($alignment.Reason)<br>
"@

                                # Build Validation Findings card
                                $validationFindingsHtml = $("")
                                if ($ReportData.Deployment.ValidationFindings -and $ReportData.Deployment.ValidationFindings.Count -gt 0)
                                    {
                                        $findings = $ReportData.Deployment.FindingsAnalysis

                                        $validationFindingsHtml = @"
            <div class="info-card">
                <h4>$("⚠️ Deployment Validation Findings")</h4>
"@

                                        if ($findings.NoCapacityIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $findings.NoCapacityIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                                $zoneGrouping = $findings.NoCapacityIssues | Group-Object -Property TestedZone | Sort-Object Name
                                                $zoneDetails = ($zoneGrouping | ForEach-Object { $("Zone {0}: {1} VM(s)" -f $_.Name, $_.Count) }) -join ", "
                                                $validationFindingsHtml += @"
                <strong>$("⚠️ No SKU Capacity Available:")</strong> <span class="status-warning">$($findings.NoCapacityIssues.Count) $("VM(s) affected")</span><br>
                <strong>$("Affected SKUs:")</strong> $($affectedSkus -join ", ")<br>
                <strong>$("Affected Zones:")</strong> $($zoneDetails)<br>
                <strong>$("Assessment:")</strong> $("SKU quota is available and the SKU is listed as supported, but Azure could not allocate capacity for deployment.")<br>
                <strong>$("Solutions:")</strong> $("Try a different availability zone, different region, or retry later when capacity becomes available.")<br><br>
"@
                                            }

                                        if ($findings.QuotaIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $findings.QuotaIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                                $validationFindingsHtml += @"
                <strong>$("📊 Quota Exceeded:")</strong> <span class="status-warning">$($findings.QuotaIssues.Count) $("VM(s) affected")</span><br>
                <strong>$("Affected SKUs:")</strong> $($affectedSkus -join ", ")<br>
                <strong>$("Issue:")</strong> $("Subscription has reached limits for these VM families or total vCPUs")<br>
                <strong>$("Solutions:")</strong> $("Request quota increase via Azure portal Support tickets")<br><br>
"@
                                            }

                                        if ($findings.SKUSupportIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $findings.SKUSupportIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                                $validationFindingsHtml += @"
                <strong>$("🔧 SKU Support:")</strong> <span class="status-warning">$($findings.SKUSupportIssues.Count) $("VM(s) affected")</span><br>
                <strong>$("Affected SKUs:")</strong> $($affectedSkus -join ", ")<br>
                <strong>$("Issue:")</strong> $("These VM SKUs are not supported in the target region/zone")<br>
                <strong>$("Solutions:")</strong> $("Use different region that supports these SKUs, or use alternative VM SKUs")<br>
"@

                                                $skuIssuesWithAlternatives = $findings.SKUSupportIssues | Where-Object { $_.AlternativeZones -and $_.AlternativeZones.Count -gt 0 }
                                                if ($skuIssuesWithAlternatives.Count -gt 0)
                                                    {
                                                        $validationFindingsHtml += @"
                <strong>$("Alternative Zones:")</strong> $("Available within {0} for affected SKUs" -f $ReportData.Configuration.Region)<br>
"@
                                                    }
                                                $validationFindingsHtml += $("<br>")
                                            }

                                        if ($findings.OtherIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $findings.OtherIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                                $validationFindingsHtml += @"
                <strong>$("⚙️ Other Constraints:")</strong> <span class="status-warning">$($findings.OtherIssues.Count) $("VM(s) affected")</span><br>
                <strong>$("Affected SKUs:")</strong> $($affectedSkus -join ", ")<br>
                <strong>$("Issue:")</strong> $("Deployment failed due to other Azure constraints or configuration issues")<br>
                <strong>$("Solutions:")</strong> $("Review detailed error messages below for specific troubleshooting steps")<br><br>
"@
                                            }

                                        if ($findings.UnknownIssues.Count -gt 0)
                                            {
                                                $affectedSkus = $findings.UnknownIssues | Select-Object -ExpandProperty VMSku -Unique | Where-Object { $_ -ne $("") }
                                                $validationFindingsHtml += @"
                <strong>$("❓ Unclassified Failures:")</strong> <span class="status-error">$($findings.UnknownIssues.Count) $("VM(s) affected")</span><br>
                <strong>$("Affected SKUs:")</strong> $($affectedSkus -join ", ")<br>
                <strong>$("Issue:")</strong> $("Azure did not return a classifiable error and failure could not be deduced from quota/SKU context.")<br>
                <strong>$("Solutions:")</strong> $("Re-run with -DisableCleanup and check Azure Activity Log for detailed error information.")<br><br>
"@
                                            }

                                        # Per-VM detail table: only show if there are Other/Unknown issues that
                                        # could not be reclassified, so the user has granular detail to investigate
                                        $unresolvedFindings = @($ReportData.Deployment.ValidationFindings | Where-Object { $_.FailureCategory -in @("Other", "Unknown") })
                                        if ($unresolvedFindings.Count -gt 0)
                                            {
                                                $validationFindingsHtml += @"
                <br><strong>$("Unresolved Failure Details:")</strong><br>
                <table style="margin-top: 5px; font-size: 0.9em;">
                    <thead>
                        <tr>
                            <th>$("VM Name")</th>
                            <th>$("SKU")</th>
                            <th>$("Zone")</th>
                            <th>$("Category")</th>
                            <th>$("Error Details")</th>
                        </tr>
                    </thead>
                    <tbody>
"@
                                                foreach ($finding in $unresolvedFindings)
                                                    {
                                                        $errorDisplay = if ($finding.ErrorMessage) { $finding.ErrorMessage } else { $("No error details available") }
                                                        $errorCodeDisplay = if ($finding.ErrorCode) { $(" [{0}]" -f $finding.ErrorCode) } else { $("") }
                                                        $zoneDisplay = if ($finding.TestedZone) { $finding.TestedZone } else { $("N/A") }

                                                        $validationFindingsHtml += @"
                        <tr>
                            <td>$($finding.VMName)</td>
                            <td>$($finding.VMSku)</td>
                            <td>$($zoneDisplay)</td>
                            <td><span class="status-error">$($finding.FailureCategory)</span></td>
                            <td>$($errorDisplay)$($errorCodeDisplay)</td>
                        </tr>
"@
                                                    }

                                                $validationFindingsHtml += @"
                    </tbody>
                </table>
"@
                                            }

                                        # DisableCleanup tip
                                        if (-not $ReportData.Configuration.DisableCleanup)
                                            {
                                                $validationFindingsHtml += @"
                <br><span class="text-muted" style="font-size: 0.9em;">$("💡 Tip: Re-run with -DisableCleanup to keep failed resources for investigation. Check the Azure Activity Log for detailed error reasons.")</span><br>
"@
                                            }

                                        $validationFindingsHtml += @"
            </div>
"@
                                    }

                                # Build Skipped Zones card — zones that exist in the region but cannot host
                                # this configuration because one or more required SKUs are unavailable there
                                $skippedZonesHtml = $("")
                                if ($ReportData.Deployment.SkippedZones -and $ReportData.Deployment.SkippedZones.Count -gt 0)
                                    {
                                        $skippedZonesHtml = @"
            <div class="info-card">
                <h4>$("⚠️ Skipped Zones — Invalid Configuration Zones")</h4>
                <strong>$("Note:")</strong> $("The following zone(s) exist in this region but were not tested because one or more required SKUs are not available there. Deployment into these zones would not be possible with the current SKU selection regardless of capacity. To use these zones, select a different VM SKU that is supported across all desired zones.")<br><br>
"@
                                        foreach ($skipped in $ReportData.Deployment.SkippedZones)
                                            {
                                                $skippedSkuList = $skipped.UnsupportedSKUs -join ", "
                                                $skippedZonesHtml += @"
                <strong>$("Zone {0}:" -f $skipped.Zone)</strong> <span class="status-warning">$("⚠ No deployment attempted")</span><br>
                <strong>$("Unsupported SKU(s):")</strong> $($skippedSkuList)<br>
                <strong>$("Reason:")</strong> $($skipped.Reason)<br><br>
"@
                                            }
                                        $skippedZonesHtml += @"
            </div>
"@
                                    }

                                # Build SKU Support & Quota Reference HTML (always present when results exist)
                                # Uses rowspan on Quota Family and Quota Status columns to show shared
                                # family quota once, spanning all SKU rows that belong to that family.
                                $skuFamilyTestingHtml = $("")
                                if ($ReportData.SKUFamilyTesting.Results.Count -gt 0)
                                    {
                                        # Group by quota family, then by unique SKU within each family
                                        $familyGroups = $ReportData.SKUFamilyTesting.Results | Group-Object -Property QuotaFamily
                                        $uniqueSKUCount = ($ReportData.SKUFamilyTesting.Results | Select-Object -Property SKUName -Unique).Count

                                        $allSKUStatuses = @()
                                        foreach ($fg in $familyGroups)
                                            {
                                                foreach ($sg in ($fg.Group | Group-Object -Property SKUName))
                                                    {
                                                        $allSKUStatuses += $sg.Group[0].ZoneSupportStatus
                                                    }
                                            }
                                        $totalSKUSupported = ($allSKUStatuses | Where-Object { $_ -eq $("Success") }).Count
                                        $totalSKUWarning = ($allSKUStatuses | Where-Object { $_ -eq $("Warning") }).Count
                                        $totalSKUUnsupported = ($allSKUStatuses | Where-Object { $_ -eq $("Error") }).Count

                                        # Build table rows with rowspan on Quota Family and Quota Status
                                        $skuReferenceRows = $("")
                                        foreach ($familyGroup in $familyGroups)
                                            {
                                                $familyRepresentative = $familyGroup.Group[0]
                                                $quotaClass = switch ($familyRepresentative.QuotaStatusLevel)
                                                    {
                                                        "Success" { $("status-success") }
                                                        "Warning" { $("status-warning") }
                                                        "Error"   { $("status-error") }
                                                    }

                                                # Get unique SKUs in this family for rowspan count
                                                $skuGroups = @($familyGroup.Group | Group-Object -Property SKUName)
                                                $familyRowSpan = $skuGroups.Count
                                                $isFirstInFamily = $true

                                                foreach ($skuGroup in $skuGroups)
                                                    {
                                                        $skuEntry = $skuGroup.Group[0]
                                                        $skuMinDeploy = ($skuGroup.Group | Measure-Object -Property MinDeploymentVcpu -Minimum).Minimum
                                                        $zoneClass = switch ($skuEntry.ZoneSupportStatus)
                                                            {
                                                                "Success" { $("status-success") }
                                                                "Warning" { $("status-warning") }
                                                                "Error"   { $("status-error") }
                                                            }
                                                        $zonesDisplay = if ($skuEntry.AvailableZones.Count -gt 0) { $skuEntry.AvailableZones -join $(", ") } else { $("-") }

                                                        # Build covers list (deduplicated for multi-zone)
                                                        $coversList = @()
                                                        foreach ($entry in $skuGroup.Group | Select-Object -Property ComponentType, FriendlyName -Unique)
                                                            {
                                                                if ($entry.ComponentType -eq $("CNode"))
                                                                    {
                                                                        $coversList += $("CNode: {0}" -f $entry.FriendlyName)
                                                                    } `
                                                                else
                                                                    {
                                                                        $coversList += $("MNode: {0}" -f $entry.FriendlyName)
                                                                    }
                                                            }
                                                        $coversDisplay = $coversList -join $("<br>")

                                                        # First SKU in family gets the rowspan cells
                                                        if ($isFirstInFamily)
                                                            {
                                                                $skuReferenceRows += @"
                <tr>
                    <td rowspan="$familyRowSpan" style="vertical-align: middle; border-bottom: 2px solid var(--border);">$($familyGroup.Name)</td>
                    <td rowspan="$familyRowSpan" style="vertical-align: middle; border-bottom: 2px solid var(--border);"><span class="$quotaClass">$($familyRepresentative.QuotaStatus)</span></td>
                    <td>$($skuGroup.Name)</td>
                    <td>$($skuEntry.vCPU)</td>
                    <td>$($skuMinDeploy) vCPU</td>
                    <td><span class="$zoneClass">$($skuEntry.ZoneSupport)</span></td>
                    <td>$($zonesDisplay)</td>
                    <td>$($coversDisplay)</td>
                </tr>
"@
                                                                $isFirstInFamily = $false
                                                            } `
                                                        else
                                                            {
                                                                $skuReferenceRows += @"
                <tr>
                    <td>$($skuGroup.Name)</td>
                    <td>$($skuEntry.vCPU)</td>
                    <td>$($skuMinDeploy) vCPU</td>
                    <td><span class="$zoneClass">$($skuEntry.ZoneSupport)</span></td>
                    <td>$($zonesDisplay)</td>
                    <td>$($coversDisplay)</td>
                </tr>
"@
                                                            }
                                                    }
                                            }

                                        $skuFamilyTestingHtml = @"
        <h2>$("📋 SKU Support & Quota Reference")</h2>
        <div class="info-grid">
            <div class="info-card">
                <h4>$("📊 SKU Reference Summary")</h4>
                <strong>$("Quota Families:")</strong> $($familyGroups.Count)<br>
                <strong>$("Unique SKUs:")</strong> $($uniqueSKUCount)<br>
                <strong>$("Available in Zone:")</strong> <span class="status-success">$($totalSKUSupported)</span><br>
                <strong>$("Available Elsewhere:")</strong> <span class="status-warning">$($totalSKUWarning)</span><br>
                <strong>$("Not in Region:")</strong> <span class="status-error">$($totalSKUUnsupported)</span>
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th>$("Quota Family")</th>
                    <th>$("Quota Status")</th>
                    <th>$("VM SKU")</th>
                    <th>$("vCPU")</th>
                    <th>$("Min Deploy")</th>
                    <th>$("Zone Support")</th>
                    <th>$("Available Zones")</th>
                    <th>$("Covers")</th>
                </tr>
            </thead>
            <tbody>
                $skuReferenceRows
            </tbody>
        </table>
"@
                                    }

                                # Build Multi-Zone Analysis HTML (conditional on ZoneResults)
                                $zoneTestingHtml = $("")
                                if ($ReportData.ZoneResults -and $ReportData.ZoneResults.Zones.Count -gt 0)
                                    {
                                        $zones = $ReportData.ZoneResults.Zones

                                        # Build dynamic zone column headers
                                        $zoneHeaderCells = $("")
                                        foreach ($z in $zones)
                                            {
                                                $zoneHeaderCells += $("<th>Zone {0}</th>" -f $z)
                                            }

                                        # CNode matrix rows
                                        $cNodeMatrixRows = $("")
                                        foreach ($entry in $ReportData.ZoneResults.CNodeMatrix)
                                            {
                                                $zoneCells = $("")
                                                foreach ($z in $zones)
                                                    {
                                                        if ($entry.ZoneSupport[$z])
                                                            {
                                                                $zoneCells += $("<td><span class='status-success'>✓</span></td>")
                                                            } `
                                                        else
                                                            {
                                                                $zoneCells += $("<td><span class='status-error'>✗</span></td>")
                                                            }
                                                    }
                                                $cNodeMatrixRows += @"
                <tr>
                    <td>$($entry.FriendlyName)</td>
                    <td>$($entry.SKUName)</td>
                    <td>$($entry.vCPU)</td>
                    $zoneCells
                    <td>$($entry.QuotaFamily)</td>
                    <td>$($entry.QuotaDisplay)</td>
                </tr>
"@
                                            }

                                        # MNode matrix rows
                                        $mNodeMatrixRows = $("")
                                        foreach ($entry in $ReportData.ZoneResults.MNodeMatrix)
                                            {
                                                $zoneCells = $("")
                                                foreach ($z in $zones)
                                                    {
                                                        if ($entry.ZoneSupport[$z])
                                                            {
                                                                $zoneCells += $("<td><span class='status-success'>✓</span></td>")
                                                            } `
                                                        else
                                                            {
                                                                $zoneCells += $("<td><span class='status-error'>✗</span></td>")
                                                            }
                                                    }
                                                $mNodeMatrixRows += @"
                <tr>
                    <td>$($entry.FriendlyName)</td>
                    <td>$($entry.SKUName)</td>
                    <td>$($entry.vCPU)</td>
                    <td>$($entry.DNodeCount)</td>
                    $zoneCells
                    <td>$($entry.QuotaFamily)</td>
                    <td>$($entry.QuotaDisplay)</td>
                </tr>
"@
                                            }

                                        $zoneTestingHtml = @"
        <h2>$("🌍 Multi-Zone SKU Support Matrix")</h2>

        <h3>$("CNode VM Families")</h3>
        <table>
            <thead>
                <tr>
                    <th>$("Configuration")</th>
                    <th>$("VM SKU")</th>
                    <th>$("vCPU")</th>
                    $zoneHeaderCells
                    <th>$("Quota Family")</th>
                    <th>$("Quota (Region)")</th>
                </tr>
            </thead>
            <tbody>
                $cNodeMatrixRows
            </tbody>
        </table>

        <h3>$("MNode VM Families")</h3>
        <table>
            <thead>
                <tr>
                    <th>$("Configuration")</th>
                    <th>$("VM SKU")</th>
                    <th>$("vCPU")</th>
                    <th>$("DNodes")</th>
                    $zoneHeaderCells
                    <th>$("Quota Family")</th>
                    <th>$("Quota (Region)")</th>
                </tr>
            </thead>
            <tbody>
                $mNodeMatrixRows
            </tbody>
        </table>
"@
                                    }

                                # Build SKU Family Deployment Test Results HTML (conditional on DeploymentResults)
                                $skuDeploymentTestHtml = $("")
                                if ($ReportData.SKUFamilyTesting.DeploymentResults -and $ReportData.SKUFamilyTesting.DeploymentResults.Count -gt 0)
                                    {
                                        $deployResults = $ReportData.SKUFamilyTesting.DeploymentResults
                                        $deploySuccessCount = ($deployResults | Where-Object { $_.DeploymentResult -eq $("Success") }).Count
                                        $deployFailedCount = ($deployResults | Where-Object { $_.DeploymentResult -eq $("Failed") }).Count

                                        # Group deployment results by Quota Family, then unique SKU within each
                                        $deployFamilyGroups = $deployResults | Group-Object -Property QuotaFamily
                                        $uniqueSKUNames = $deployResults | Select-Object -ExpandProperty SKUName -Unique
                                        $skuDeployRows = $("")
                                        foreach ($deployFamilyGroup in $deployFamilyGroups)
                                            {
                                                $deploySkuGroups = @($deployFamilyGroup.Group | Group-Object -Property SKUName)
                                                $deployFamilyRowSpan = $deploySkuGroups.Count
                                                $isFirstDeployInFamily = $true

                                                foreach ($deploySkuGroup in $deploySkuGroups)
                                                    {
                                                        $skuEntries = $deploySkuGroup.Group
                                                        $firstEntry = $skuEntries | Select-Object -First 1
                                                        $statusClass = if ($firstEntry.DeploymentResult -eq $("Success")) { $("status-success") } else { $("status-error") }
                                                        $statusText = if ($firstEntry.DeploymentResult -eq $("Success")) { $("✓ Deployed") } else { $("✗ {0}" -f $firstEntry.FailureCategory) }
                                                        $errorDetail = if ($firstEntry.DeploymentResult -eq $("Failed") -and $firstEntry.ErrorMessage) { $firstEntry.ErrorMessage } else { $("-") }
                                                        $coversList = ($skuEntries | ForEach-Object { $("{0}: {1}" -f $_.NodeType, $_.FriendlyName) } | Select-Object -Unique) -join $("<br>")

                                                        if ($isFirstDeployInFamily)
                                                            {
                                                                $skuDeployRows += @"
                <tr>
                    <td rowspan="$deployFamilyRowSpan" style="vertical-align: middle; border-bottom: 2px solid var(--border);">$($deployFamilyGroup.Name)</td>
                    <td>$($deploySkuGroup.Name)</td>
                    <td>$($firstEntry.vCPU)</td>
                    <td><span class="$statusClass">$statusText</span></td>
                    <td>$coversList</td>
                    <td>$errorDetail</td>
                </tr>
"@
                                                                $isFirstDeployInFamily = $false
                                                            } `
                                                        else
                                                            {
                                                                $skuDeployRows += @"
                <tr>
                    <td>$($deploySkuGroup.Name)</td>
                    <td>$($firstEntry.vCPU)</td>
                    <td><span class="$statusClass">$statusText</span></td>
                    <td>$coversList</td>
                    <td>$errorDetail</td>
                </tr>
"@
                                                            }
                                                    }
                                            }

                                        $htmlUniqueSKUCount = $uniqueSKUNames.Count
                                        $htmlUniqueSuccessCount = ($uniqueSKUNames | Where-Object { $sku = $_; ($deployResults | Where-Object { $_.SKUName -eq $sku } | Select-Object -First 1).DeploymentResult -eq $("Success") }).Count
                                        $htmlUniqueFailedCount = $htmlUniqueSKUCount - $htmlUniqueSuccessCount

                                        $skuDeploymentTestHtml = @"
        <h2>$("🚀 SKU Family Deployment Test Results")</h2>
        <div class="info-grid">
            <div class="info-card">
                <h4>$("📋 Deployment Test Summary")</h4>
                <strong>$("Region:")</strong> $($ReportData.Configuration.Region)<br>
                <strong>$("Zone:")</strong> $($ReportData.Configuration.Zone)<br>
                <strong>$("Unique SKUs Tested:")</strong> $($htmlUniqueSKUCount)<br>
                <strong>$("Succeeded:")</strong> <span class="status-success">$htmlUniqueSuccessCount</span><br>
                <strong>$("Failed:")</strong> $(if ($htmlUniqueFailedCount -gt 0) { $("<span class='status-error'>{0}</span>" -f $htmlUniqueFailedCount) } else { $("<span class='status-success'>0</span>") })
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th>$("Quota Family")</th>
                    <th>$("VM SKU")</th>
                    <th>$("vCPU")</th>
                    <th>$("Deployment Result")</th>
                    <th>$("Covers")</th>
                    <th>$("Details")</th>
                </tr>
            </thead>
            <tbody>
                $skuDeployRows
            </tbody>
        </table>
"@
                                    }

                                # Build VNet/NSG status strings and infrastructure HTML (conditional on deployment)
                                $infrastructureHtml = $("")
                                if ($ReportData.Deployment.Attempted)
                                    {
                                        $vnetStatusClass = if ($infra.VNetCreated) { $("checkmark") } else { $("error-mark") }
                                        $vnetStatusText = if ($infra.VNetCreated) { $("✓ Created") } else { $("✗ Not Created") }
                                        $nsgStatusClass = if ($infra.NSGCreated) { $("checkmark") } else { $("error-mark") }
                                        $nsgStatusText = if ($infra.NSGCreated) { $("✓ Created") } else { $("✗ Not Created") }

                                        $vnetDetailsHtml = if ($infra.VNetCreated) { $("<strong>$("VNet Name:")</strong> {0}<br><strong>$("Address Space:")</strong> {1}<br>" -f $infra.VNetName, $infra.VNetAddressSpace) } else { $("") }
                                        $nsgDetailsHtml = if ($infra.NSGCreated) { $("<strong>$("NSG Name:")</strong> {0}<br>" -f $infra.NSGName) } else { $("") }
                                        $subnetHtml = if ($infra.VNetCreated) { $("✓ Management subnet configured") } else { $("✗ Not configured") }

                                        $networkPPGCount = if ($infra.PPGsCreated.Count -gt 0) { 1 } else { 0 }

                                        $existingRefItemsHtml = @($("<li>Resource Group: {0}</li>" -f $ReportData.Configuration.ResourceGroupName))
                                        if ($infra.PPGsReferenced.Count -gt 0)
                                            { $infra.PPGsReferenced.Name | ForEach-Object { $existingRefItemsHtml += $("<li>Proximity Placement Group: {0}</li>" -f $_) } }
                                        if ($infra.AvSetsReferenced.Count -gt 0)
                                            { $infra.AvSetsReferenced.Name | ForEach-Object { $existingRefItemsHtml += $("<li>Availability Set: {0}</li>" -f $_) } }
                                        $existingRefCount    = $existingRefItemsHtml.Count
                                        $existingRefListHtml = $existingRefItemsHtml -join $("`n                ")

                                        $infrastructureHtml = @"
        <h2>$("🏗️ Infrastructure Resources")</h2>
        <div class="info-grid">
            <div class="info-card">
                <h4>$("🌐 Network Infrastructure")</h4>
                <strong>$("Virtual Network:")</strong> <span class="$vnetStatusClass">$($vnetStatusText)</span><br>
                $vnetDetailsHtml
                <strong>$("Network Security Group:")</strong> <span class="$nsgStatusClass">$($nsgStatusText)</span><br>
                $nsgDetailsHtml
                <strong>$("Subnet Configuration:")</strong> $($subnetHtml)
            </div>
            <div class="info-card">
                <h4>$("📍 Placement and Availability")</h4>
                $ppgHtml
                $avSetHtml
            </div>
            <div class="info-card">
                <h4>$("📈 Resource Summary")</h4>
                <strong>$("Resource Group:")</strong> $($ReportData.Configuration.ResourceGroupName)<br>
                <strong>$("Resource Name Prefix:")</strong> $($ReportData.Configuration.ResourceNamePrefix)<br>
                <strong>$("Total Resources Created:")</strong> $($infra.TotalResources)<br>
                <strong>$("Virtual Machines:")</strong> $($totalDeployed + $totalFailed)<br>
                <strong>$("Network Interfaces:")</strong> $($infra.NICsCreated)<br>
                <strong>$("Network Resources:")</strong> $($(if($infra.VNetCreated){1}else{0}) + $(if($infra.NSGCreated){1}else{0}))<br>
                <strong>$("Placement Resources:")</strong> $($networkPPGCount + $infra.AvSetsCreated.Count)<br>
                <strong>$("Existing Resources Referenced:")</strong> $($existingRefCount)<br>
                <ul style="margin: 3px 0 0 15px; padding: 0; font-size: 0.9em; color: var(--info);">
                $($existingRefListHtml)
                </ul>
            </div>
            $validationFindingsHtml
            $skippedZonesHtml
        </div>
"@
                                    }

                                # Zone Alignment section - always rendered regardless of deployment mode
                                $zoneAlignmentSectionHtml = @"
        <h2>$("🔄 Zone Alignment Information")</h2>
        <div class="info-grid">
            <div class="info-card">
                <h4>$("🗺️ Zone Mapping")</h4>
                $zoneAlignmentHtml
            </div>
        </div>
"@

                                # Failed VMs line
                                $isSKUTestMode = if (-not $isSKUTestMode) { $false } else { $isSKUTestMode }
                                $failedVMsHtml = if ($isSKUTestMode) { if ($skuUniqueFailedCount -gt 0) { $("<strong>$("Failed:")</strong> <span class='status-error'>{0}</span><br>" -f $skuUniqueFailedCount) } else { $("") } } elseif ($totalFailed -gt 0) { $("<strong>$("Failed Deployments:")</strong> <span class='status-error'>{0}</span><br>" -f $totalFailed) } else { $("") }

                                # Build the location segment used in title, heading, and filename
                                $titleLocationPart = $($(if ($ReportData.Configuration.Region) { $(" {0}" -f $ReportData.Configuration.Region) } else { $("") }) + $(if ($ReportData.Configuration.Zone) { $(" {0}" -f $ReportData.Configuration.Zone) } else { $("") }))

                                # Assemble the full HTML document
                                $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$( if ($ReportData.Metadata.StartTime) { $("{0}{1} Azure SKU Availability Report - {2}" -f $ReportData.Metadata.ReportLabel, $titleLocationPart, $ReportData.Metadata.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) } else { $("{0}{1} Azure SKU Availability Report - {2}" -f $ReportData.Metadata.ReportLabel, $titleLocationPart, $ReportData.Metadata.ReportMode) } )</title>
    <style>
        :root { --bg-body: #0f1923; --bg-container: #1c2733; --bg-card: #232f3e; --bg-quota: #2d3748; --bg-row-even: #232f3e; --bg-row-hover: #2a3a4e; --bg-deploy-zone: #1a3a2a; --text-primary: #e2e8f0; --text-heading: #f7fafc; --text-muted: #a0aec0; --accent: #e91e78; --success: #48bb78; --warning: #ed8936; --error: #fc5c65; --info: #63b3ed; --border: #2d3748; --shadow: 0 2px 10px rgba(0,0,0,0.4); --toggle-bg: #2d3748; --toggle-knob: #e2e8f0; }
        body.light-theme { --bg-body: #f5f5f5; --bg-container: #ffffff; --bg-card: #f8f9fa; --bg-quota: #f0f0f0; --bg-row-even: #f9f9f9; --bg-row-hover: #eef2f7; --bg-deploy-zone: #e8f5e9; --text-primary: #333333; --text-heading: #2d3748; --text-muted: #666666; --accent: #e91e78; --success: #28a745; --warning: #e67e00; --error: #dc3545; --info: #0066cc; --border: #dee2e6; --shadow: 0 2px 10px rgba(0,0,0,0.1); --toggle-bg: #dee2e6; --toggle-knob: #ffffff; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; font-size: 12pt; margin: 0; padding: 15px; background-color: var(--bg-body); color: var(--text-primary); line-height: 1.4; transition: background-color 0.3s, color 0.3s; }
        .container { max-width: 1600px; margin: 0 auto; background: var(--bg-container); padding: 20px; border-radius: 8px; box-shadow: var(--shadow); transition: background 0.3s, box-shadow 0.3s; }
        .report-header { display: flex; justify-content: space-between; align-items: center; border-bottom: 3px solid var(--accent); padding-bottom: 8px; margin-bottom: 15px; }
        .report-header h1 { border: none; padding: 0; margin: 0; font-size: 1.8em; }
        h1 { color: var(--text-heading); border-bottom: 3px solid var(--accent); padding-bottom: 8px; margin-bottom: 15px; }
        h2 { color: var(--text-primary); border-left: 4px solid var(--accent); padding-left: 15px; margin-top: 20px; }
        h3 { color: var(--text-muted); margin-top: 15px; }
        .status-success { color: var(--success); font-weight: bold; }
        .status-warning { color: var(--warning); font-weight: bold; }
        .status-error { color: var(--error); font-weight: bold; }
        .status-info { color: var(--info); font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; background: var(--bg-container); }
        th, td { padding: 8px 10px; text-align: left; border: 1px solid var(--border); color: var(--text-primary); transition: background-color 0.3s, color 0.3s, border-color 0.3s; }
        th { background-color: var(--accent); color: white; font-weight: 600; }
        tr:nth-child(even) { background-color: var(--bg-row-even); }
        tr:hover { background-color: var(--bg-row-hover); }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 12px; margin: 12px 0; }
        .info-card { background: var(--bg-card); padding: 14px; border-radius: 6px; border-left: 4px solid var(--accent); transition: background 0.3s; }
        .info-card h4 { margin-top: 0; color: var(--text-heading); }
        .quota-item { margin: 4px 0; padding: 6px; background: var(--bg-quota); border-radius: 4px; transition: background 0.3s; }
        .timestamp { color: var(--text-muted); font-size: 0.9em; text-align: right; margin-top: 15px; }
        .checkmark { color: var(--success); }
        .warning-mark { color: var(--warning); }
        .error-mark { color: var(--error); }
        .theme-switch { display: flex; align-items: center; gap: 8px; cursor: default; }
        .theme-switch span { font-size: 1.1em; line-height: 1; }
        .theme-switch label { position: relative; display: inline-block; width: 44px; height: 24px; cursor: pointer; margin: 0; }
        .theme-switch input { opacity: 0; width: 0; height: 0; }
        .theme-switch .slider { position: absolute; inset: 0; background: var(--toggle-bg); border-radius: 24px; transition: background 0.3s; }
        .theme-switch .slider::before { content: ''; position: absolute; height: 18px; width: 18px; left: 3px; bottom: 3px; background: var(--toggle-knob); border-radius: 50%; transition: transform 0.3s, background 0.3s; }
        .theme-switch input:checked + .slider { background: var(--accent); }
        .theme-switch input:checked + .slider::before { transform: translateX(20px); }
    </style>
</head>
<body>
    <div class="container">
        <div class="report-header">
            <div style="display:flex; align-items:center; gap:12px;">
                <a href="https://github.com/silk-us/scripts-and-configs/tree/main/Azure/Resource%20Availability%20Check" target="_blank" rel="noopener">
                    <img src="data:image/png;base64,$silkLogoBase64" style="height:42px; border-radius:6px;" alt="Silk" />
                </a>
                <h1>$("{0}{1} Azure SKU Availability Report" -f $ReportData.Metadata.ReportLabel, $titleLocationPart)</h1>
            </div>
            <div class="theme-switch">
                <span>$("☀️")</span>
                <label><input type="checkbox" id="themeToggle" checked><span class="slider"></span></label>
                <span>$("🌙")</span>
            </div>
        </div>

        <div class="info-grid">
            <div class="info-card">
                <h4>$("📋 Deployment Configuration")</h4>
                $configCardContent
            </div>
            <div class="info-card">
                <h4>$("📊 Deployment Summary")</h4>
                $(if ($isSKUTestMode) { @"
                <strong>$("Unique SKUs Tested:")</strong> $($skuUniqueCount)<br>
                <strong>$("Succeeded:")</strong> <span class="$deployedCountClass">$($skuUniqueSuccessCount)</span><br>
                $failedVMsHtml
                <strong>$("Overall Status:")</strong> <span class="$summaryStatusClass">$($summaryStatusText)</span>
"@ } else { @"
                <strong>$("Total Expected VMs:")</strong> $($totalExpected)<br>
                <strong>$("Successfully Deployed:")</strong> <span class="$deployedCountClass">$($totalDeployed)</span><br>
                $failedVMsHtml
                <strong>$("Network Interfaces:")</strong> $($infra.NICsCreated)<br>
                <strong>$("Overall Status:")</strong> <span class="$summaryStatusClass">$($summaryStatusText)</span>
"@ })
            </div>
        </div>

        $(if ($silkSummaryRows) { @"
        <h2>$("🏗️ Silk Component Summary")</h2>
        <table>
            <thead>
                <tr>
                    <th>$("Silk Component")</th>
                    <th>$("Deployed")</th>
                    <th>$("Expected")</th>
                    <th>$("VM SKU")</th>
                    <th>$("Status")</th>
                </tr>
            </thead>
            <tbody>
                $silkSummaryRows
            </tbody>
        </table>
"@ })

        $cNodeTableHtml
        $mNodeTablesHtml

        $(if ($skuSupportCardsHtml) { @"
        <h2>$("🔧 SKU Support Analysis")</h2>
        <div class="info-grid">
            $skuSupportCardsHtml
        </div>
"@ })

        $(if ($quotaFamilyCardsHtml) { @"
        <h2>$("📊 Quota Family Summary")</h2>
        <div class="info-grid">
            $quotaFamilyCardsHtml
        </div>
"@ })

        <h2>$("📊 Quota Summary")</h2>
        <div class="info-grid">
            $quotaSummaryCardsHtml
        </div>

        $zoneTestingHtml

        $skuDeploymentTestHtml

        $infrastructureHtml

        $zoneAlignmentSectionHtml

        $skuFamilyTestingHtml

        <div class="timestamp">
            $( if ($ReportData.Metadata.Duration -and $ReportData.Metadata.StartTime) { $("⏱️ Total Time: {0} | Report generated on {1} by Silk Test-SilkResourceDeployment PowerShell module" -f $ReportData.Metadata.Duration.ToString("hh\:mm\:ss"), $ReportData.Metadata.StartTime.ToString("yyyy-MM-dd HH:mm:ss")) } else { $("Report generated by Silk Test-SilkResourceDeployment PowerShell module ({0})" -f $ReportData.Metadata.ReportMode) } )
        </div>
        <a href="https://github.com/silk-us/scripts-and-configs/tree/main/Azure/Resource%20Availability%20Check" target="_blank" rel="noopener">
            <img src="data:image/png;base64,$silkLogoBase64" style="height:24px; border-radius:3px;" alt="Silk" />
        </a>
    </div>
    <script>
        (function() {
            var toggle = document.getElementById('themeToggle');
            var stored = null;
            try { stored = localStorage.getItem('silk-report-theme'); } catch(e) {}
            if (stored === 'light') {
                document.body.classList.add('light-theme');
                toggle.checked = false;
            }
            toggle.addEventListener('change', function() {
                if (this.checked) {
                    document.body.classList.remove('light-theme');
                    try { localStorage.setItem('silk-report-theme', 'dark'); } catch(e) {}
                } else {
                    document.body.classList.add('light-theme');
                    try { localStorage.setItem('silk-report-theme', 'light'); } catch(e) {}
                }
            });
        })();
    </script>
</body>
</html>
"@

                                # Write HTML content to file
                                $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
                                Write-Host -Message $("✓ HTML report generated successfully!") -ForegroundColor Green
                                Write-Host -Message $("📄 Report saved to: `"{0}`"" -f $OutputPath) -ForegroundColor Cyan

                                # Attempt to open the report automatically
                                try
                                    {
                                        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5)
                                            {
                                                Start-Process $OutputPath
                                                Write-Verbose -Message $("HTML report opened in default browser.")
                                            } `
                                        elseif ($IsLinux)
                                            {
                                                if (Get-Command xdg-open -ErrorAction SilentlyContinue)
                                                    {
                                                        & xdg-open $OutputPath
                                                        Write-Verbose -Message $("HTML report opened with xdg-open.")
                                                    } `
                                                else
                                                    {
                                                        Write-Verbose -Message $("xdg-open not available. Report saved but not opened automatically.")
                                                    }
                                            } `
                                        elseif ($IsMacOS)
                                            {
                                                & open $OutputPath
                                                Write-Verbose -Message $("HTML report opened with macOS open command.")
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose -Message $("Unable to automatically open HTML report (likely headless system): {0}" -f $_.Exception.Message)
                                        Write-Host -Message $("ℹ️  Report available at: `"{0}`"" -f $OutputPath) -ForegroundColor Yellow
                                    }
                            } `
                        catch
                            {
                                Write-Warning -Message $("Failed to generate HTML report: {0}" -f $_.Exception.Message)
                            }
                    }

                # ===============================================================================
                # Report Data Object Initialization
                # ===============================================================================
                $reportData = New-SilkReportData
                $reportData.Metadata.StartTime = $StartTime
                $reportData.Metadata.ParameterSetName = $PSCmdlet.ParameterSetName

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
                                        Write-Verbose -Message $("Initiating interactive Azure authentication process...")
                                        Write-Host $("Opening Azure authentication dialog. Please complete the sign-in process...") -ForegroundColor Yellow
                                        $connectResult = Connect-AzAccount -ErrorAction Stop
                                        Write-Verbose -Message $("Azure authentication command completed, validating connection result...")

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
                                        Get-AzSubscription -SubscriptionId $currentAzContext.Subscription.Id -ErrorAction Stop | Out-Null
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

                        # Update progress: Module validation complete
                        Update-StagedProgress -SectionName 'ModuleValidation' -SectionCurrentStep 1 -SectionTotalSteps 1 `
                            -DetailMessage $("Modules validated and Azure authenticated")

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

                        # Import customer name as report label if not explicitly provided
                        if (!$ReportLabel -and $ConfigImport.customer_name)
                            {
                                $ReportLabel = $ConfigImport.customer_name
                                Write-Verbose -Message $("Using customer name '{0}' from JSON configuration as report label." -f $ReportLabel)
                            }
                    }

                # Resolve ReportLabel: fall back to 'Silk' if not set by parameter or JSON
                if (-not $ReportLabel)
                    {
                        $ReportLabel = 'Silk'
                    }
                $reportData.Metadata.ReportLabel = $ReportLabel


                # ===============================================================================
                # Validate provided environment information is accurate
                # ===============================================================================
                try
                    {
                        # Update progress: Starting environment validation
                        Update-StagedProgress -SectionName 'EnvironmentValidation' -SectionCurrentStep 0 -SectionTotalSteps 4 `
                            -DetailMessage $("Checking subscription...")

                        # Check subscription ID
                        $subscriptionCheck = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
                        Write-Verbose -Message $("Subscription '{0}' was identified with the ID '{1}'." -f $subscriptionCheck.Name, $subscriptionCheck.Id)
                        $reportData.EnvironmentValidation.SubscriptionValid = $true
                        $reportData.EnvironmentValidation.SubscriptionName  = $subscriptionCheck.Name

                        Update-StagedProgress -SectionName 'EnvironmentValidation' -SectionCurrentStep 1 -SectionTotalSteps 4 `
                            -DetailMessage $("Validating resource group...")

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

                        # Resource group validation (conditional - not required for Report Only mode)
                        if ($ResourceGroupName)
                            {
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
                            } `
                        else
                            {
                                Write-Verbose -Message $("Resource group name not specified - skipping resource group validation (Report Only mode)")
                            }

                        Update-StagedProgress -SectionName 'EnvironmentValidation' -SectionCurrentStep 2 -SectionTotalSteps 4 `
                            -DetailMessage $("Checking region and zones...")

                        # Cleanup only mode does not require region or zone validation
                        if ($RunCleanupOnly)
                            {
                                Update-StagedProgress -SectionName 'EnvironmentValidation' -SectionCurrentStep 4 -SectionTotalSteps 4 `
                                    -DetailMessage $("Cleanup only mode - skipping region and zone validation...")
                                return
                            }

                        # Verify the subscription has access to the specified region before attempting any resource operations.
                        # Get-AzLocation returns only locations accessible to the current subscription context.
                        # An inaccessible or non-existent region is not returned, which would cause all subsequent
                        # resource creation calls to fail with cryptic errors rather than a clear access message.
                        $accessibleRegion = Get-AzLocation -ErrorAction Stop | Where-Object { $_.Location -eq $Region } | Select-Object -First 1

                        if (-not $accessibleRegion)
                            {
                                Write-Error -Message $("Region '{0}' is not accessible to subscription '{1}' ({2}). The region name may be incorrect, or the subscription may not be registered for this region. Verify the region name at https://aka.ms/azureregions and ensure the subscription has been enabled for this region in the Azure portal under Subscription > Resource Providers or by contacting your Azure administrator." -f $Region, $subscriptionCheck.Name, $SubscriptionId)
                                $validationError = $true
                                return
                            }

                        # Region is accessible - populate metadata fields for reporting
                        $reportData.EnvironmentValidation.RegionValid            = $true
                        $reportData.EnvironmentValidation.RegionDisplayName      = $accessibleRegion.DisplayName
                        $reportData.EnvironmentValidation.RegionGeography        = $accessibleRegion.GeographyGroup
                        $reportData.EnvironmentValidation.RegionPhysicalLocation = if ($accessibleRegion.PhysicalLocation) { $accessibleRegion.PhysicalLocation } else { $("") }

                        Write-Verbose -Message $("✓ Region '{0}' ({1}) is accessible to subscription '{2}'. Geography: {3}{4}." -f $Region, $accessibleRegion.DisplayName, $subscriptionCheck.Name, $accessibleRegion.GeographyGroup, $(if ($accessibleRegion.PhysicalLocation) { " | Physical location: {0}" -f $accessibleRegion.PhysicalLocation } else { $("") }))

                        # Check region and get supported SKUs
                        $locationSupportedSKU = Get-AzComputeResourceSku -Location $Region -ErrorAction Stop

                        # Guard against an empty SKU response. This is a distinct failure from region access —
                        # the region is registered but compute resources cannot be enumerated (e.g., permissions issue).
                        if (-not $locationSupportedSKU -or $locationSupportedSKU.Count -eq 0)
                            {
                                Write-Error -Message $("Region '{0}' ({1}) is accessible but returned no compute SKU data. The subscription may lack permissions to enumerate compute resources in this region (requires Microsoft.Compute/skus/read), or the region may not support compute workloads." -f $Region, $accessibleRegion.DisplayName)
                                $validationError = $true
                                return
                            }

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

                # Update progress: Environment validation complete
                Update-StagedProgress -SectionName 'EnvironmentValidation' -SectionCurrentStep 4 -SectionTotalSteps 4 `
                    -DetailMessage $("Subscription, region, and zones verified...")

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

                # Query Azure Resource SKU API to determine maximum fault domains supported by the region.
                # Fault domains define the number of physical hardware failure boundaries within an availability set.
                # Most Azure regions support 3 fault domains, but some (e.g. uksouth) only support 2.
                try
                    {
                        # Define Azure Resource SKU API version for querying compute SKU information
                        $azureSKUApiVersion = $("2025-04-01")

                        # Generate authorization header using current Azure access token for Management API
                        $azureSKUApiRequestHeaders =   @{
                                                            Authorization = $("Bearer {0}" -f $(ConvertFrom-SecureString -SecureString $(Get-AzAccessToken -ResourceUrl $("https://management.azure.com/")).Token -AsPlainText))
                                                        }

                        # Construct API URI to query compute SKUs for the target subscription, filtered to the target region.
                        $azureSKUApiUri = $("https://management.azure.com/subscriptions/{0}/providers/Microsoft.Compute/skus?api-version={1}&`$filter=location eq '{2}'" -f $SubscriptionId, $azureSKUApiVersion, $Region)

                        # Execute REST API call to retrieve SKU information for the target region.
                        $regionAvailabilitySetSKU = $(Invoke-RestMethod -Method Get -Uri $azureSKUApiUri -Headers $azureSKUApiRequestHeaders).value

                        # Filter SKU response to extract maximum fault domains capability for availability sets in the target region.
                        $maximumFaultDomains = [int]($regionAvailabilitySetSKU | Where-Object -FilterScript {$_.resourceType -eq $("availabilitySets") -and $_.locations -eq $Region} | Select-Object -First 1 | Select-Object -ExpandProperty capabilities | Where-Object {$_.name -eq $("MaximumPlatformFaultDomainCount")} | Select-Object -ExpandProperty value)

                        # Validate that the query returned a usable value. A null/zero result means the API responded
                        # but returned no availabilitySets entry for this region — treat this as a hard failure rather
                        # than proceeding on an assumption that could produce an invalid AvSet configuration.
                        if (-not $maximumFaultDomains -or $maximumFaultDomains -lt 1)
                            {
                                throw $("Azure Resource SKU API returned no availabilitySets fault domain data for region '{0}'. The region name may be invalid or the subscription may not have access to this region." -f $Region)
                            }

                        Write-Verbose -Message $("{0}Successfully identified maximum fault domains for region '{1}': {2}" -f $messagePrefix, $Region, $maximumFaultDomains)
                    } `
                catch
                    {
                        throw $("{0}Unable to determine maximum fault domains for region '{1}'. Cannot safely create Availability Sets without this value. Error: {2}" -f $messagePrefix, $Region, $_.Exception.Message)
                    }


                # Output current CNode size object configuration
                foreach ($cNodeSize in $cNodeSizeObject)
                    {
                        Write-Verbose -Message $("CNode SKU: {0}{1}{2} with friendly name '{3}'" -f $cNodeSize.vmSkuPrefix, $cNodeSize.vCPU, $cNodeSize.vmSkuSuffix, $cNodeSize.cNodeFriendlyName)
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
                                Write-Error -Message $("PV2 MNode type is not currently supported. Please select Lsv3, Lasv3, or Laosv4 MNode types.")
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
                        $selectedMNodeSuffix = "s_v3"
                    } `
                elseif ($MnodeSizeLsv4)
                    {
                        $MNodeSize = $MnodeSizeLsv4
                        $selectedMNodeSuffix = "s_v4"
                    } `
                elseif ($MnodeSizeLasv3)
                    {
                        $MNodeSize = $MnodeSizeLasv3
                        $selectedMNodeSuffix = "as_v3"
                    } `
                elseif ($MnodeSizeLasv4)
                    {
                        $MNodeSize = $MnodeSizeLasv4
                        $selectedMNodeSuffix = "as_v4"
                    } `
                elseif ($MnodeSizeLaosv4)
                    {
                        $MNodeSize = $MnodeSizeLaosv4
                        $selectedMNodeSuffix = "aos_v4"
                    }

                if ($MNodeSize)
                    {
                        Write-Verbose -Message ("MNode size(s) identified: {0}" -f ($MNodeSize -join ", "))
                    }

                # Dynamically determine if any MNode size/SKU parameter was provided
                # This single boolean replaces repeated per-family checks throughout the validation logic
                # When new MNode size parameters are added, only this line needs to be updated
                $mNodeSizeParamProvided = [bool]($MnodeSizeLsv3 -or $MnodeSizeLsv4 -or $MnodeSizeLasv3 -or $MnodeSizeLasv4 -or $MnodeSizeLaosv4 -or $MNodeSku)

                # Build dynamic MNode parameter name list from available size objects for use in error messages
                # Derives family names from $mNodeSizeObject suffixes so new families are automatically included
                $mNodeUniqueSuffixes = $mNodeSizeObject | ForEach-Object { $_.vmSkuSuffix } | Select-Object -Unique
                $mNodeFamilyParamNames =    @(
                                                $mNodeUniqueSuffixes | ForEach-Object   {
                                                                                            $suffix = $_
                                                                                            # Convert suffix (e.g., "s_v3", "s_v4", "as_v3", "as_v4", "aos_v4") to parameter-style names (e.g., "MnodeSizeLsv3", "MnodeSizeLsv4", "MnodeSizeLasv3", "MnodeSizeLasv4", "MnodeSizeLaosv4")
                                                                                            $familyName = $suffix -replace $('_'), $('')
                                                                                            $("MnodeSize{0}" -f $("L{0}" -f $familyName))
                                                                                        }
                                            )
                $mNodeParamNameList = ($mNodeFamilyParamNames + @($("MNodeSku"))) -join $("/")

                # Identify and validate CNode SKU configuration based on provided parameters
                if (!$CNodeCount -and !$CNodeFriendlyName -and !$CNodeSku -and $mNodeSizeParamProvided)
                    {
                        # MNode-only deployment scenario - no CNode configuration required
                        Write-Verbose -Message $("MNode-only deployment mode - CNode configuration skipped.")
                        $cNodeObject = $null
                    } `
                elseif ($CNodeCount -and $CNodeFriendlyName)
                    {
                        # Dynamic friendly name lookup - automatically supports any friendly name in $cNodeSizeObject
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq $CNodeFriendlyName }

                        if (-not $cNodeObject)
                            {
                                $availableFriendlyNames = ($cNodeSizeObject.cNodeFriendlyName | Sort-Object) -join ", "
                                Write-Error $("Invalid CNode friendly name '{0}'. Available options: {1}" -f $CNodeFriendlyName, $availableFriendlyNames)
                                $validationError = $true
                                return
                            }
                    } `
                elseif ($CNodeCount -and $CNodeSku)
                    {
                        # Dynamic SKU lookup - automatically supports any SKU in $cNodeSizeObject
                        $cNodeObject = $cNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $CNodeSku }

                        if (-not $cNodeObject)
                            {
                                $availableSkus = ($cNodeSizeObject | ForEach-Object { "{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix } | Sort-Object) -join ", "
                                Write-Error $("Invalid CNode SKU '{0}'. Available options: {1}" -f $CNodeSku, $availableSkus)
                                $validationError = $true
                                return
                            }
                    } `
                elseif ($CNodeCount -and $ConfigImport.sdp.read_cache_enabled)
                    {
                        # JSON config fallback: read_cache_enabled maps to Read_Cache_Enabled
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq $("Read_Cache_Enabled{0}" -f $ConfigImport.sdp.c_node_sku_variant) }
                    } `
                elseif ($CNodeCount -and $ConfigImport.sdp.increased_logical_capacity)
                    {
                        # JSON config fallback: increased_logical_capacity maps to Increased_Logical_Capacity
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq $("Increased_Logical_Capacity{0}" -f $ConfigImport.sdp.c_node_sku_variant) }
                    } `
                elseif ($CNodeCount -and (!$ConfigImport.sdp.increased_logical_capacity -and !$ConfigImport.sdp.read_cache_enabled))
                    {
                        # JSON config fallback: no flags maps to No_Increased_Logical_Capacity
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq $("No_Increased_Logical_Capacity{0}" -f $ConfigImport.sdp.c_node_sku_variant) }
                    } `
                else
                    {
                        if ($GenerateReportOnly -or $TestAllSKUFamilies)
                            {
                                # Report Only / SKU Family Test mode - no specific CNode/MNode configuration required
                                Write-Verbose -Message $("Report/SKU test mode - CNode/MNode configuration skipped. All families will be tested from the full size object arrays.")
                                $cNodeObject = $null
                            } `
                        else
                            {
                                Write-Error $("Configuration is not valid. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters ({0}), or both." -f $mNodeParamNameList)
                                $validationError = $true
                                return
                            }
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
                        $MNodeSize | ForEach-Object { $nodeSize = $_; $mNodeObject.Add($($mNodeSizeObject | Where-Object { $_.PhysicalSize -eq $nodeSize -and (!$selectedMNodeSuffix -or $_.vmSkuSuffix -eq $selectedMNodeSuffix) } | Select-Object -First 1)) }
                    } `
                elseif ($MNodeCount -and $MNodeSku)
                    {
                        foreach ($sku in $MNodeSku)
                            {
                                for ($node = 1; $node -le $MNodeCount; $node++)
                                    {
                                        $mNodeObject.Add($($mNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $sku } | Select-Object -First 1))
                                    }
                            }
                    } `
                elseif ($CNodeCount -and !$mNodeSizeParamProvided)
                    {
                        # CNode-only deployment scenario - no MNode configuration required
                        Write-Verbose -Message $("CNode-only deployment mode - no MNode resources will be created.")
                    } `
                elseif ($GenerateReportOnly -and !$CNodeCount -and !$mNodeSizeParamProvided)
                    {
                        # Report Only mode - no CNode/MNode configuration required
                        Write-Verbose -Message $("Report Only mode - no CNode/MNode configuration specified. SKU/Quota analysis will use raw region data only.")
                    } `
                elseif ($TestAllSKUFamilies -and !$CNodeCount -and !$mNodeSizeParamProvided)
                    {
                        # SKU Family Test mode - no specific MNode configuration required, all families tested from size objects
                        Write-Verbose -Message $("SKU Family Test mode - all MNode families will be tested from the full size object array.")
                    } `
                elseif (!$CNodeCount -and !$mNodeSizeParamProvided)
                    {
                        Write-Error $("No valid configuration specified. Please specify either CNode parameters (CNodeFriendlyName/CNodeSku with CNodeCount) or MNode parameters ({0}), or both." -f $mNodeParamNameList)
                        $validationError = $true
                        return
                    }

                # Create unique MNode object list to avoid duplicates and detail MNode configurations
                if ($mNodeObject.Count -gt 0)
                    {
                        # Create unique MNode object list to avoid duplicates
                        $mNodeObjectUnique = New-Object System.Collections.Generic.List[PSCustomObject]
                        $mNodeObject | ForEach-Object { if(-not $mNodeObjectUnique.Contains($_)) { $mNodeObjectUnique.Add($_) } }

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
                if ($Zone -ne "Zoneless")
                    {
                        # Determine peer subscription for zone mapping query
                        $isCrossSubscription = ($ZoneAlignmentSubscriptionId -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                        $peerSubscriptionId = if ($isCrossSubscription) { $ZoneAlignmentSubscriptionId } else { $SubscriptionId }

                        # Feature check only needed for cross-subscription alignment
                        if ($isCrossSubscription)
                            {
                                $sectionStep = "Check AvailabilityZonePeering Feature"
                                $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
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
                            }

                        # Query Azure checkZonePeers REST API for zone mapping data
                        $sectionStep = "Request Zone Alignment Info"
                        $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                        if ($isCrossSubscription)
                            {
                                Write-Verbose -Message $("{0}Requesting availability zone peer mappings between deployment subscription '{1}' and alignment subscription '{2}' in region '{3}'..." -f $messagePrefix, $SubscriptionId, $peerSubscriptionId, $Region)
                            } `
                        else
                            {
                                Write-Verbose -Message $("{0}Requesting availability zone mapping for subscription '{1}' in region '{2}'..." -f $messagePrefix, $SubscriptionId, $Region)
                            }

                        # Generate REST API request URI for checkZonePeers endpoint
                        $zoneAlignmentRequestUri = $("https://management.azure.com/subscriptions/{0}/providers/Microsoft.Resources/checkZonePeers?api-version=2022-12-01" -f $SubscriptionId)

                        # Generate request payload with peer subscription and target region
                        $zoneAlignmentRequestPayload = @{
                                                            subscriptionIds = @( $("subscriptions/{0}" -f $peerSubscriptionId) )
                                                            location = $Region
                                                        } | ConvertTo-Json

                        try
                            {
                                # Call Azure REST API to retrieve zone peer relationship data
                                Write-Verbose -Message $("{0}Calling checkZonePeers REST API endpoint..." -f $messagePrefix)
                                $zoneAlignmentResponse = Invoke-AzRestMethod -Method Post -Uri $zoneAlignmentRequestUri -Payload $zoneAlignmentRequestPayload -ErrorAction Stop | Select-Object -ExpandProperty Content | ConvertFrom-Json -Depth 100

                                $sectionStep = "Mapping"
                                $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))

                                # Parse zone peer mappings
                                Write-Verbose -Message $("{0}Analyzing Availability Zone peer relationships..." -f $messagePrefix)
                                foreach ($peer in $zoneAlignmentResponse.availabilityZonePeers)
                                    {
                                        Write-Verbose -Message $("{0}Deployment Subscription Availability Zone '{1}' corresponds to Peer Subscription Availability Zone '{2}'" -f $messagePrefix, $peer.availabilityZone, $peer.peers.availabilityZone)
                                        # Find the deployment zone that aligns with the current zone in the peer subscription
                                        if ($peer.peers.availabilityZone -eq $Zone)
                                            {
                                                $alignedZone = $peer.availabilityZone
                                                $remoteZone = $peer.peers.availabilityZone
                                                Write-Verbose -Message $("{0}Found alignment match: Deployment Subscription Availability Zone '{1}' aligns with Peer Subscription Availability Zone '{2}'" -f $messagePrefix, $alignedZone, $remoteZone)
                                            }
                                    }

                                # Apply zone alignment decision only for cross-subscription scenarios
                                if ($isCrossSubscription)
                                    {
                                        $sectionStep = "Apply Alignment"
                                        $messagePrefix = $("{0}{1}" -f $(if($processSection){"[{0}] " -f $processSection}else{""}), $(if($sectionStep){"[{0}] " -f $sectionStep}else{""}))
                                        if ($DisableZoneAlignment)
                                            {
                                                Write-Verbose -Message $("{0}Zone alignment disabled by parameter - maintaining original Availability Zone '{1}' (Alignment would be Availability Zone '{2}' with Alignment Subscription '{3}')" -f $messagePrefix, $Zone, $alignedZone, $ZoneAlignmentSubscriptionId)
                                            } `
                                        elseif ($alignedZone -and $alignedZone -eq $Zone)
                                            {
                                                Write-Verbose -Message $("{0}Zone Aligned: Current Deployment Availability Zone '{1}' is already aligned with Alignment Subscription Availability Zone '{2}' in Region '{3}'" -f $messagePrefix, $Zone, $alignedZone, $Region)
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
                                else
                                    {
                                        Write-Verbose -Message $("{0}Zone mapping retrieved for subscription '{1}' (self-reference)" -f $messagePrefix, $SubscriptionId)
                                    }
                            } `
                        catch
                            {
                                Write-Warning -Message $("{0}Zone mapping API call failed: {1}. Proceeding with original Availability Zone '{2}' in Deployment Subscription '{3}'" -f $messagePrefix, $_.Exception.Message, $Zone, $SubscriptionId)
                            }
                    } `
                else
                    {
                        Write-Verbose -Message $("{0}Alignment skipped: Deployment configured for 'Zoneless' Region - zone mapping not applicable" -f $messagePrefix)
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

                if ($mNodeObject.Count -gt 0)
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
                        # Update progress: Starting quota analysis
                        Update-StagedProgress -SectionName 'QuotaAnalysis' -SectionCurrentStep 0 -SectionTotalSteps 3 `
                            -DetailMessage $("Querying quota for region...")

                        $computeQuotaUsage = Get-AzVMUsage -Location $Region -ErrorAction SilentlyContinue

                        $totalVMCount = 0
                        $totalvCPUCount = 0

                        $originalCNodeCount = $CNodeCount
                        $adjustedCNodeCount = $CNodeCount

                        # Update progress: CNode quota check
                        Update-StagedProgress -SectionName 'QuotaAnalysis' -SectionCurrentStep 1 -SectionTotalSteps 3 `
                            -DetailMessage $("Checking CNode quota...")

                        # Check if CNodeSize is within the available quota
                        if($cNodeObject)
                            {
                                # Check if CNodeSize is within the available quota
                                $cNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }

                                # Check if quota family exists in Azure
                                if (-not $cNodeSKUFamilyQuota)
                                    {
                                        $quotaWarningMessage = $("WARNING: Quota family '{0}' for CNode SKU '{1}' is not available in Azure quota system for region '{2}'. This is expected for preview/new SKU families ({3}). Quota validation will be skipped - deployment may fail if insufficient quota exists." -f $cNodeObject.QuotaFamily, $cNodeVMSku, $Region, ($knownPreviewSkuFamilies -join ", "))
                                        Write-Warning $quotaWarningMessage
                                        Write-Verbose -Message $quotaWarningMessage

                                        # Set to "unlimited" scenario since we can't check quota
                                        $availableVCPUs = [int]::MaxValue
                                    }
                                else
                                    {
                                        $availableVCPUs = $cNodeSKUFamilyQuota.Limit - $cNodeSKUFamilyQuota.CurrentValue
                                    }

                                $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount

                                if ($availableVCPUs -lt $cNodevCPUCount)
                                    {
                                        # Calculate how many CNodes we can actually deploy
                                        $maxCNodesFromQuota = [Math]::Floor($availableVCPUs / $cNodeObject.vCPU)

                                        if ($maxCNodesFromQuota -gt 0)
                                            {
                                                $adjustedCNodeCount = $maxCNodesFromQuota
                                                $quotaErrorMessage = $("Partial CNode quota available for SKU: {0}. Requested: {1} CNodes ({2} vCPU), Available quota: {3} vCPU, Deploying: {4} CNode(s)" -f $cNodeVMSku, $CNodeCount, $cNodevCPUCount, $availableVCPUs, $maxCNodesFromQuota)
                                                Write-Warning $quotaErrorMessage

                                                # Recalculate with adjusted count
                                                $cNodevCPUCount = $cNodeObject.vCPU * $adjustedCNodeCount
                                            } `
                                        else
                                            {
                                                $adjustedCNodeCount = 0
                                                $quotaErrorMessage = $("Insufficient vCPU quota for CNode SKU: {0}. Required: {1} vCPU per CNode, Available: {2} vCPU. CNode deployment will be skipped." -f $cNodeVMSku, $cNodeObject.vCPU, $availableVCPUs)
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

                        # Initialize quota adjustment tracking before MNode quota checks
                        # Must be defined outside the if($MNodeSize) gate so downstream .ContainsKey()
                        # calls work for both size-based and SKU-based MNode paths
                        $mNodeQuotaAdjustments = @{}

                        # check for quota for mnodes
                        if($mNodeObject.Count -gt 0)
                            {
                                $mNodeFamilyCount = $mNodeObject | Group-Object -Property QuotaFamily
                                $mNodeInstanceCount = $mNodeObject | Group-Object -Property PhysicalSize | Select-Object Name, Count

                                foreach ($mNodeFamily in $mNodeFamilyCount)
                                    {
                                        $mNodeFamilyvCPUCount = 0

                                        # total mnode vcpu count for this family
                                        foreach ($mNodeType in $mNodeObjectUnique)
                                            {
                                                if ($mNodeType.QuotaFamily -eq $mNodeFamily.Name)
                                                    {
                                                        $mNodeFamilyvCPUCount += $mNodeType.vCPU * $mNodeType.dNodeCount * $($mNodeInstanceCount | Where-Object Name -eq $mNodeType.PhysicalSize).Count
                                                    }
                                            }

                                        # Check if MNodeSize is within the available quota
                                        $mNodeSKUFamilyQuota = $ComputeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeFamily.Name }

                                        # Check if quota family exists in Azure
                                        if (-not $mNodeSKUFamilyQuota)
                                            {
                                                $quotaWarningMessage = $("WARNING: Quota family '{0}' for MNode SKU family is not available in Azure quota system for region '{1}'. This is expected for preview/new SKU families ({2}). Quota validation will be skipped - deployment may fail if insufficient quota exists." -f $mNodeFamily.Name, $Region, ($knownPreviewSkuFamilies -join ", "))
                                                Write-Warning $quotaWarningMessage
                                                Write-Verbose -Message $quotaWarningMessage

                                                # Set to "unlimited" scenario since we can't check quota
                                                $availableMNodeVCPUs = [int]::MaxValue
                                            }
                                        else
                                            {
                                                $availableMNodeVCPUs = $mNodeSKUFamilyQuota.Limit - $mNodeSKUFamilyQuota.CurrentValue
                                            }

                                        if ($availableMNodeVCPUs -lt $mNodeFamilyvCPUCount)
                                            {
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
                                                                $quotaErrorMessage = $("Partial MNode quota available for {0} TiB ({1}{2}{3}). Requested: {4} DNodes, Available quota: {5} vCPU, Deploying: {6} DNode(s)" -f $mNodeType.PhysicalSize, $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix, $requestedDNodes, $availableMNodeVCPUs, $maxDNodesFromQuota)
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
                                                                $quotaErrorMessage = $("Insufficient vCPU quota for MNode {0} TiB ({1}{2}{3}). Required: {4} vCPU per DNode, Available: {5} vCPU. MNode group will be skipped." -f $mNodeType.PhysicalSize, $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix, $vCPUPerDNode, $availableMNodeVCPUs)
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
                                                Write-Verbose -Message $("Sufficient vCPU quota available for MNode SKU {0} of Family: {1}. Required: {2} -> Limit: {3}, Consumed: {4}, Available: {5}" -f $(($mNodeFamily.group | ForEach-Object { "{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix }) -join ', '), $mNodeFamily.Name, $mNodeFamilyvCPUCount, $mNodeSKUFamilyQuota.Limit, $mNodeSKUFamilyQuota.CurrentValue, $availableMNodeVCPUs)

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
                                $quotaErrorMessage = $("Insufficient VM quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVMCount, $totalVMQuota.Limit, $totalVMQuota.CurrentValue, ($totalVMQuota.Limit - $totalVMQuota.CurrentValue))
                                Write-Warning $quotaErrorMessage
                            } `
                        else
                            {
                                Write-Verbose $("Sufficient VM quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVMCount, $totalVMQuota.Limit, $totalVMQuota.CurrentValue, ($totalVMQuota.Limit - $totalVMQuota.CurrentValue))
                            }

                        # check regional vcpu quota
                        $totalVCPUQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Total Regional vCPUs" }
                        if($totalVCPUCount -gt ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue))
                            {
                                $quotaErrorMessage = $("Insufficient vCPU quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVCPUCount, $totalVCPUQuota.Limit, $totalVCPUQuota.CurrentValue, ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue))
                                Write-Warning $quotaErrorMessage
                            } `
                        else
                            {
                                Write-Verbose $("Sufficient vCPU quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalVCPUCount, $totalVCPUQuota.Limit, $totalVCPUQuota.CurrentValue, ($totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue))
                            }

                        # check availability set quota
                        $totalAvailabilitySetQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq "Availability Sets" }
                        if($totalAvailabilitySetCount -gt ($totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue))
                            {
                                $quotaErrorMessage = $("Insufficient Availability Set quota available. Required: {0} -> Limit: {1}, Consumed: {2}, Available: {3}" -f $totalAvailabilitySetCount, $totalAvailabilitySetQuota.Limit, $totalAvailabilitySetQuota.CurrentValue, ($totalAvailabilitySetQuota.Limit - $totalAvailabilitySetQuota.CurrentValue))
                                Write-Warning $quotaErrorMessage
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
                                        $quotaAdjustmentMessages += $("  → CNode: Cannot deploy any VMs due to insufficient quota")
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
                                                        $quotaAdjustmentMessages += $("  → MNode ({0}): Deploying {1} of {2} requested DNodes (quota constrained)" -f $physicalSize, $adjustment.AdjustedCount, $adjustment.OriginalCount)
                                                    } `
                                                else
                                                    {
                                                        Write-Verbose $("MNode ({0}): All {1} requested DNodes can be deployed" -f $physicalSize, $adjustment.AdjustedCount)
                                                    }
                                            } `
                                        else
                                            {
                                                $quotaAdjustmentMessages += $("  → MNode ({0}): Cannot deploy any DNodes due to insufficient quota" -f $physicalSize)
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
                        if(-not $anyDeploymentPossible -and -not $TestAllSKUFamilies)
                            {
                                Write-Warning $("⚠ Zero VM deployment mode: Function will analyze environment and report quota deficiencies without deploying resources.")
                                # Set adjusted counts to 0 to ensure no deployment attempts
                                $adjustedCNodeCount = 0
                            }

                        # Update progress: Quota analysis complete
                        Update-StagedProgress -SectionName 'QuotaAnalysis' -SectionCurrentStep 3 -SectionTotalSteps 3 `
                            -DetailMessage $("Quota validation finished...")

                    } `
                catch
                    {
                        Write-Error $("Error occurred while checking compute quota: {0}" -f $_)
                    }

                # ===============================================================================
                # SKU Support & Quota Reference - All Silk-Supported Families
                # ===============================================================================
                # Always iterate ALL entries in cNodeSizeObject and mNodeSizeObject to produce
                # a complete support matrix for the target region and zone. Results feed into
                # the SKUFamilyTesting report section for every report mode.
                Write-Verbose -Message $("Analyzing all Silk-supported VM families for region '{0}'" -f $Region)

                        $skuFamilyResults = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

                        # ----- CNode Family Analysis (always uses full-size production SKUs) -----
                        foreach ($cNodeEntry in $cNodeSizeObjectFullSize)
                            {
                                $skuName = $("{0}{1}{2}" -f $cNodeEntry.vmSkuPrefix, $cNodeEntry.vCPU, $cNodeEntry.vmSkuSuffix)
                                $supportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $skuName -and $_.ResourceType -eq $("virtualMachines") }
                                $familyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeEntry.QuotaFamily }

                                # Determine zone support
                                $zoneSupport = $("✗ Not available in region")
                                $zoneSupportStatus = $("Error")
                                $availableZones = @()

                                if ($supportedSKU)
                                    {
                                        $availableZones = if ($supportedSKU.LocationInfo.Zones) { @($supportedSKU.LocationInfo.Zones | Sort-Object) } else { @() }
                                        if ($Zone -eq $("Zoneless"))
                                            {
                                                $zoneSupport = $("✓ Available (Zoneless)")
                                                $zoneSupportStatus = $("Success")
                                            } `
                                        elseif ($availableZones -contains $Zone)
                                            {
                                                $zoneSupport = $("✓ Available in zone {0}" -f $Zone)
                                                $zoneSupportStatus = $("Success")
                                            } `
                                        else
                                            {
                                                $zoneSupport = $("⚠ Not in zone {0} (available: {1})" -f $Zone, $(if ($availableZones.Count -gt 0) { $availableZones -join $(", ") } else { $("none") }))
                                                $zoneSupportStatus = $("Warning")
                                            }
                                    }

                                # Determine quota status
                                $quotaStatus = $("Unknown")
                                $quotaStatusLevel = $("Warning")
                                $quotaAvailable = $null
                                $quotaLimit = $null

                                if ($familyQuota)
                                    {
                                        $quotaAvailable = $familyQuota.Limit - $familyQuota.CurrentValue
                                        $quotaLimit = $familyQuota.Limit
                                        $quotaStatus = $("{0}/{1} available" -f $quotaAvailable, $quotaLimit)
                                        $quotaStatusLevel = if ($quotaAvailable -gt 0) { $("Success") } else { $("Error") }
                                    } `
                                elseif ($knownPreviewSkuFamilies -contains $cNodeEntry.QuotaFamily)
                                    {
                                        $quotaStatus = $("Preview/Unregistered family")
                                        $quotaStatusLevel = $("Warning")
                                    } `
                                else
                                    {
                                        $quotaStatus = $("No quota data available")
                                        $quotaStatusLevel = $("Warning")
                                    }

                                $skuFamilyResults.Add([PSCustomObject]@{
                                    ComponentType       = $("CNode")
                                    FriendlyName        = $cNodeEntry.cNodeFriendlyName
                                    SKUName             = $skuName
                                    QuotaFamily         = $cNodeEntry.QuotaFamily
                                    vCPU                = $cNodeEntry.vCPU
                                    ZoneSupport         = $zoneSupport
                                    ZoneSupportStatus   = $zoneSupportStatus
                                    AvailableZones      = $availableZones
                                    QuotaStatus         = $quotaStatus
                                    QuotaStatusLevel    = $quotaStatusLevel
                                    QuotaAvailable      = $quotaAvailable
                                    QuotaLimit          = $quotaLimit
                                    MinDeploymentVcpu   = $(2 * $cNodeEntry.vCPU)
                                })

                                Write-Verbose -Message $("  CNode {0} ({1}): {2} | Quota: {3}" -f $cNodeEntry.cNodeFriendlyName, $skuName, $zoneSupport, $quotaStatus)
                            }

                        # ----- MNode Family Analysis (always uses full-size production SKUs) -----
                        foreach ($mNodeEntry in $mNodeSizeObjectFullSize)
                            {
                                $skuName = $("{0}{1}{2}" -f $mNodeEntry.vmSkuPrefix, $mNodeEntry.vCPU, $mNodeEntry.vmSkuSuffix)
                                $supportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $skuName -and $_.ResourceType -eq $("virtualMachines") }
                                $familyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeEntry.QuotaFamily }

                                # Determine zone support
                                $zoneSupport = $("✗ Not available in region")
                                $zoneSupportStatus = $("Error")
                                $availableZones = @()

                                if ($supportedSKU)
                                    {
                                        $availableZones = if ($supportedSKU.LocationInfo.Zones) { @($supportedSKU.LocationInfo.Zones | Sort-Object) } else { @() }
                                        if ($Zone -eq $("Zoneless"))
                                            {
                                                $zoneSupport = $("✓ Available (Zoneless)")
                                                $zoneSupportStatus = $("Success")
                                            } `
                                        elseif ($availableZones -contains $Zone)
                                            {
                                                $zoneSupport = $("✓ Available in zone {0}" -f $Zone)
                                                $zoneSupportStatus = $("Success")
                                            } `
                                        else
                                            {
                                                $zoneSupport = $("⚠ Not in zone {0} (available: {1})" -f $Zone, $(if ($availableZones.Count -gt 0) { $availableZones -join $(", ") } else { $("none") }))
                                                $zoneSupportStatus = $("Warning")
                                            }
                                    }

                                # Determine quota status
                                $quotaStatus = $("Unknown")
                                $quotaStatusLevel = $("Warning")
                                $quotaAvailable = $null
                                $quotaLimit = $null

                                if ($familyQuota)
                                    {
                                        $quotaAvailable = $familyQuota.Limit - $familyQuota.CurrentValue
                                        $quotaLimit = $familyQuota.Limit
                                        $quotaStatus = $("{0}/{1} available" -f $quotaAvailable, $quotaLimit)
                                        $quotaStatusLevel = if ($quotaAvailable -gt 0) { $("Success") } else { $("Error") }
                                    } `
                                elseif ($knownPreviewSkuFamilies -contains $mNodeEntry.QuotaFamily)
                                    {
                                        $quotaStatus = $("Preview/Unregistered family")
                                        $quotaStatusLevel = $("Warning")
                                    } `
                                else
                                    {
                                        $quotaStatus = $("No quota data available")
                                        $quotaStatusLevel = $("Warning")
                                    }

                                $skuFamilyResults.Add([PSCustomObject]@{
                                    ComponentType       = $("MNode")
                                    FriendlyName        = $("{0} TiB" -f $mNodeEntry.PhysicalSize)
                                    SKUName             = $skuName
                                    QuotaFamily         = $mNodeEntry.QuotaFamily
                                    vCPU                = $mNodeEntry.vCPU
                                    DNodeCount          = $mNodeEntry.dNodeCount
                                    PhysicalSize        = $mNodeEntry.PhysicalSize
                                    ZoneSupport         = $zoneSupport
                                    ZoneSupportStatus   = $zoneSupportStatus
                                    AvailableZones      = $availableZones
                                    QuotaStatus         = $quotaStatus
                                    QuotaStatusLevel    = $quotaStatusLevel
                                    QuotaAvailable      = $quotaAvailable
                                    QuotaLimit          = $quotaLimit
                                    MinDeploymentVcpu   = $($mNodeEntry.dNodeCount * $mNodeEntry.vCPU)
                                })

                                Write-Verbose -Message $("  MNode {0} TiB ({1}): {2} | Quota: {3}" -f $mNodeEntry.PhysicalSize, $skuName, $zoneSupport, $quotaStatus)
                            }

                        Write-Verbose -Message $("SKU support analysis complete - {0} total entries analyzed ({1} CNode, {2} MNode)" -f $skuFamilyResults.Count, ($skuFamilyResults | Where-Object { $_.ComponentType -eq $("CNode") }).Count, ($skuFamilyResults | Where-Object { $_.ComponentType -eq $("MNode") }).Count)

                        # Post-process: Recalculate quota status using minimum deployment requirements
                        # A family's quota is only truly "sufficient" if it can support the smallest
                        # possible deployment of any component that uses that family
                        # CNode minimum: 2 CNodes (production architecture requirement)
                        # MNode minimum: 1 MNode worth of DNodes (dNodeCount x vCPU)
                        foreach ($familyResultGroup in ($skuFamilyResults | Group-Object -Property QuotaFamily))
                            {
                                $minFamilyDeploy = ($familyResultGroup.Group | Measure-Object -Property MinDeploymentVcpu -Minimum).Minimum
                                foreach ($entry in $familyResultGroup.Group)
                                    {
                                        $entry | Add-Member -NotePropertyName MinFamilyDeployVcpu -NotePropertyValue $minFamilyDeploy -Force
                                        if ($null -ne $entry.QuotaAvailable)
                                            {
                                                if ($entry.QuotaAvailable -ge $minFamilyDeploy)
                                                    {
                                                        $entry.QuotaStatus = $("{0}/{1} available" -f $entry.QuotaAvailable, $entry.QuotaLimit)
                                                        $entry.QuotaStatusLevel = $("Success")
                                                    }
                                                elseif ($entry.QuotaAvailable -gt 0)
                                                    {
                                                        $entry.QuotaStatus = $("{0}/{1} available (min deploy: {2} vCPU)" -f $entry.QuotaAvailable, $entry.QuotaLimit, $minFamilyDeploy)
                                                        $entry.QuotaStatusLevel = $("Warning")
                                                    }
                                                else
                                                    {
                                                        $entry.QuotaStatus = $("0/{0} exhausted" -f $entry.QuotaLimit)
                                                        $entry.QuotaStatusLevel = $("Error")
                                                    }
                                            }
                                    }
                                Write-Verbose -Message $("  Quota family '{0}': min deployment {1} vCPU, available {2} vCPU → {3}" -f $familyResultGroup.Name, $minFamilyDeploy, $(if ($familyResultGroup.Group[0].QuotaAvailable) { $familyResultGroup.Group[0].QuotaAvailable } else { "N/A" }), $familyResultGroup.Group[0].QuotaStatusLevel)
                            }

                # ===============================================================================
                # Multi-Zone Analysis - Per-SKU Zone Support Matrix
                # ===============================================================================
                # When TestAllZones is specified, build a matrix of which zones support each
                # CNode and MNode SKU. Each SKU gets a ZoneSupport hashtable (zone → bool)
                # plus regional quota data (quota is per-region, not per-zone).
                if ($TestAllZones)
                    {
                        # Build sorted list of all zones in the region
                        $allRegionZones = @($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique)
                        Write-Verbose -Message $("Multi-Zone Analysis mode - checking all {0} zones in region '{1}': {2}" -f $allRegionZones.Count, $Region, ($allRegionZones -join $(", ")))

                        $zoneMatrixCNode = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'
                        $zoneMatrixMNode = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

                        # ----- CNode Families Zone Matrix -----
                        foreach ($cNodeEntry in $cNodeSizeObject)
                            {
                                $skuName = $("{0}{1}{2}" -f $cNodeEntry.vmSkuPrefix, $cNodeEntry.vCPU, $cNodeEntry.vmSkuSuffix)
                                $supportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $skuName -and $_.ResourceType -eq $("virtualMachines") }
                                $familyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeEntry.QuotaFamily }

                                # Build zone support map
                                $perZoneSupport = @{}
                                $skuZones = @()
                                if ($supportedSKU)
                                    {
                                        $skuZones = if ($supportedSKU.LocationInfo.Zones) { @($supportedSKU.LocationInfo.Zones | Sort-Object) } else { @() }
                                    }
                                foreach ($z in $allRegionZones)
                                    {
                                        $perZoneSupport[$z] = ($skuZones -contains $z)
                                    }

                                # Regional quota
                                $quotaAvailable = $null
                                $quotaLimit = $null
                                $quotaDisplay = $("-")
                                if ($familyQuota)
                                    {
                                        $quotaAvailable = $familyQuota.Limit - $familyQuota.CurrentValue
                                        $quotaLimit = $familyQuota.Limit
                                        $quotaDisplay = $("{0}/{1}" -f $quotaAvailable, $quotaLimit)
                                    }

                                $supportedZoneCount = ($perZoneSupport.Values | Where-Object { $_ }).Count

                                $zoneMatrixCNode.Add([PSCustomObject]@{
                                    FriendlyName        = $cNodeEntry.cNodeFriendlyName
                                    SKUName             = $skuName
                                    QuotaFamily         = $cNodeEntry.QuotaFamily
                                    vCPU                = $cNodeEntry.vCPU
                                    ZoneSupport         = $perZoneSupport
                                    SupportedZoneCount  = $supportedZoneCount
                                    InRegion            = ($supportedSKU -ne $null)
                                    QuotaAvailable      = $quotaAvailable
                                    QuotaLimit          = $quotaLimit
                                    QuotaDisplay        = $quotaDisplay
                                })

                                Write-Verbose -Message $("  CNode {0} ({1}): {2}/{3} zones supported" -f $cNodeEntry.cNodeFriendlyName, $skuName, $supportedZoneCount, $allRegionZones.Count)
                            }

                        # ----- MNode Families Zone Matrix -----
                        foreach ($mNodeEntry in $mNodeSizeObject)
                            {
                                $skuName = $("{0}{1}{2}" -f $mNodeEntry.vmSkuPrefix, $mNodeEntry.vCPU, $mNodeEntry.vmSkuSuffix)
                                $supportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $skuName -and $_.ResourceType -eq $("virtualMachines") }
                                $familyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeEntry.QuotaFamily }

                                # Build zone support map
                                $perZoneSupport = @{}
                                $skuZones = @()
                                if ($supportedSKU)
                                    {
                                        $skuZones = if ($supportedSKU.LocationInfo.Zones) { @($supportedSKU.LocationInfo.Zones | Sort-Object) } else { @() }
                                    }
                                foreach ($z in $allRegionZones)
                                    {
                                        $perZoneSupport[$z] = ($skuZones -contains $z)
                                    }

                                # Regional quota
                                $quotaAvailable = $null
                                $quotaLimit = $null
                                $quotaDisplay = $("-")
                                if ($familyQuota)
                                    {
                                        $quotaAvailable = $familyQuota.Limit - $familyQuota.CurrentValue
                                        $quotaLimit = $familyQuota.Limit
                                        $quotaDisplay = $("{0}/{1}" -f $quotaAvailable, $quotaLimit)
                                    }

                                $supportedZoneCount = ($perZoneSupport.Values | Where-Object { $_ }).Count

                                $zoneMatrixMNode.Add([PSCustomObject]@{
                                    FriendlyName        = $("{0} TiB" -f $mNodeEntry.PhysicalSize)
                                    SKUName             = $skuName
                                    QuotaFamily         = $mNodeEntry.QuotaFamily
                                    vCPU                = $mNodeEntry.vCPU
                                    DNodeCount          = $mNodeEntry.dNodeCount
                                    PhysicalSize        = $mNodeEntry.PhysicalSize
                                    ZoneSupport         = $perZoneSupport
                                    SupportedZoneCount  = $supportedZoneCount
                                    InRegion            = ($supportedSKU -ne $null)
                                    QuotaAvailable      = $quotaAvailable
                                    QuotaLimit          = $quotaLimit
                                    QuotaDisplay        = $quotaDisplay
                                })

                                Write-Verbose -Message $("  MNode {0} TiB ({1}): {2}/{3} zones supported" -f $mNodeEntry.PhysicalSize, $skuName, $supportedZoneCount, $allRegionZones.Count)
                            }

                        # Package results as a single object with the zone list and matrix data
                        $zoneResults = [PSCustomObject]@{
                            Zones           = $allRegionZones
                            CNodeMatrix     = @($zoneMatrixCNode)
                            MNodeMatrix     = @($zoneMatrixMNode)
                        }

                        Write-Verbose -Message $("Multi-Zone Analysis complete - {0} zones, {1} CNode entries, {2} MNode entries" -f $allRegionZones.Count, $zoneMatrixCNode.Count, $zoneMatrixMNode.Count)
                    }

                # ===============================================================================
                # Report/Analysis Mode - Early Return from Begin Block
                # ===============================================================================
                # In report-only mode, all needed data has been collected. Skip VM image
                # discovery and remaining begin block setup. The process block will populate
                # $reportData, render reports, and return.
                #
                # Report-only gate: only GenerateReportOnly triggers the early return.
                # TestAllZones now proceeds to deployment when combined with deployment
                # parameter sets (CNode, MNode, SKU Family Test) to enable per-zone
                # allocation testing.
                if ($GenerateReportOnly)
                    {
                        Write-Verbose -Message $("Report/analysis mode - environment validation and SKU/quota data collection complete. Skipping VM image discovery.")
                        return
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
                                                                        Write-Verbose -Message $("Primary offer unavailable, using alternative offer for VM image discovery")
                                                                        Write-Host $("Using alternative offer: {0} with SKU: {1}" -f $offer, $VMImageSku)
                                                                        Write-Verbose -Message $("Alternative offer '{0}' successfully located with SKU '{1}' for image deployment" -f $offer, $VMImageSku)
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

                        $reportRegionPart = if ($Region) { $("-{0}" -f $Region) } else { $("") }
                        $reportZonePart   = if ($Zone)   { $("-{0}" -f $Zone)   } else { $("") }
                        $ReportFullPath = Join-Path -Path $ReportOutputPath -ChildPath $("{0}{1}{2}-DeploymentReport_{3}.html" -f $ReportLabel, $reportRegionPart, $reportZonePart, $StartTime.ToString("yyyyMMdd_HHmmss"))
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
                if($mNodeObject.Count -gt 0)
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

                # ===============================================================================
                # Report Only Mode - Generate Report Without Deployment
                # ===============================================================================
                # Populates the centralized report data object with all available analysis
                # data collected during the begin block, then renders reports and returns.
                # Report-only gate: only GenerateReportOnly triggers report-only mode.
                # TestAllZones with deployment parameters proceeds to deployment.
                if ($GenerateReportOnly)
                    {
                        Write-Verbose -Message $("Report/analysis mode - generating report without deployment")

                        # Report metadata
                        $reportData.Metadata.ReportMode         = if ($TestAllSKUFamilies -and $TestAllZones) { $("SKU Family Test + Multi-Zone") } elseif ($TestAllSKUFamilies) { $("SKU Family Test") } elseif ($TestAllZones) { $("Multi-Zone Analysis") } else { $("Report Only") }
                        $reportData.Metadata.StartTime          = Get-Date
                        $reportData.Metadata.ParameterSetName   = $PSCmdlet.ParameterSetName

                        # Configuration (populate what is available)
                        $reportData.Configuration.SubscriptionId        = $SubscriptionId
                        $reportData.Configuration.ResourceGroupName     = if ($ResourceGroupName) { $ResourceGroupName } else { $("N/A - Report Only") }
                        $reportData.Configuration.Region                = $Region
                        $reportData.Configuration.Zone                  = $Zone
                        $reportData.Configuration.CNodeSKU              = if ($cNodeObject) { $("{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix) } else { $("") }
                        $reportData.Configuration.CNodeFriendlyName     = if ($cNodeObject) { $cNodeObject.cNodeFriendlyName } else { $("") }
                        $reportData.Configuration.CNodeCount            = $CNodeCount
                        $reportData.Configuration.CNodeCountAdjusted    = if ($adjustedCNodeCount) { $adjustedCNodeCount } else { 0 }
                        $reportData.Configuration.MNodeSizes            = if ($MNodeSize) { @($MNodeSize) } else { @() }
                        $reportData.Configuration.MNodeSKUs             = if ($mNodeObjectUnique) { @($mNodeObjectUnique) } else { @() }
                        $reportData.Configuration.IPRange               = $IPRangeCIDR
                        $reportData.Configuration.ResourceNamePrefix    = $ResourceNamePrefix
                        $reportData.Configuration.DevelopmentMode       = [bool]$Development
                        $reportData.Configuration.NoHTMLReport          = [bool]$NoHTMLReport

                        # Raw data from begin block
                        $reportData.SKUSupport.RawRegionSKUs            = $locationSupportedSKU
                        $reportData.QuotaAnalysis.RawQuotaData          = $computeQuotaUsage

                        # Build SKU support data if CNode/MNode were specified
                        $skuSupportData = @()
                        if ($cNodeObject)
                            {
                                $cNodeVMSku = $("{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix)
                                $cNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $cNodeVMSku -and $_.ResourceType -eq $("virtualMachines") }
                                $cNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }

                                $cNodeZoneSupport = $("✗ Not supported in region")
                                $cNodeZoneSupportStatus = $("Error")
                                if ($cNodeSupportedSKU)
                                    {
                                        if ($Zone -eq $("Zoneless"))
                                            {
                                                $cNodeZoneSupport = $("✓ Supported (Zoneless deployment)")
                                                $cNodeZoneSupportStatus = $("Success")
                                            } `
                                        elseif ($cNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                            {
                                                $cNodeZoneSupport = $("✓ Supported in target zone {0}" -f $Zone)
                                                $cNodeZoneSupportStatus = $("Success")
                                            } `
                                        else
                                            {
                                                $cNodeZoneSupport = $("⚠ Not supported in target zone {0}" -f $Zone)
                                                $cNodeZoneSupportStatus = $("Warning")
                                            }
                                    }

                                $skuSupportData += [PSCustomObject]@{
                                    ComponentType       = $("CNode")
                                    SKUName             = $cNodeVMSku
                                    SupportedSKU        = $cNodeSupportedSKU
                                    ZoneSupport         = $cNodeZoneSupport
                                    ZoneSupportStatus   = $cNodeZoneSupportStatus
                                    vCPUCount           = $cNodeObject.vCPU * $CNodeCount
                                    SKUFamilyQuota      = $cNodeSKUFamilyQuota
                                    QuotaFamilyName     = $cNodeObject.QuotaFamily
                                    InstanceCount       = $CNodeCount
                                    AvailableZones      = if ($cNodeSupportedSKU.LocationInfo.Zones) { $cNodeSupportedSKU.LocationInfo.Zones } else { @() }
                                }
                            }

                        if ($mNodeObjectUnique)
                            {
                                foreach ($mNodeType in $mNodeObjectUnique)
                                    {
                                        $mNodeSkuName = $("{0}{1}{2}" -f $mNodeType.vmSkuPrefix, $mNodeType.vCPU, $mNodeType.vmSkuSuffix)
                                        $mNodevCPUCount = $mNodeType.vCPU * $mNodeType.dNodeCount
                                        $mNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $mNodeSkuName -and $_.ResourceType -eq $("virtualMachines") }
                                        $mNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $mNodeType.QuotaFamily }

                                        $mNodeZoneSupport = $("✗ Not supported in region")
                                        $mNodeZoneSupportStatus = $("Error")
                                        if ($mNodeSupportedSKU)
                                            {
                                                if ($Zone -eq $("Zoneless"))
                                                    {
                                                        $mNodeZoneSupport = $("✓ Supported (Zoneless deployment)")
                                                        $mNodeZoneSupportStatus = $("Success")
                                                    } `
                                                elseif ($mNodeSupportedSKU.LocationInfo.Zones -contains $Zone)
                                                    {
                                                        $mNodeZoneSupport = $("✓ Supported in target zone {0}" -f $Zone)
                                                        $mNodeZoneSupportStatus = $("Success")
                                                    } `
                                                else
                                                    {
                                                        $mNodeZoneSupport = $("⚠ Not supported in target zone {0}" -f $Zone)
                                                        $mNodeZoneSupportStatus = $("Warning")
                                                    }
                                            }

                                        $skuSupportData += [PSCustomObject]@{
                                            ComponentType       = $("MNode")
                                            SKUName             = $mNodeSkuName
                                            SupportedSKU        = $mNodeSupportedSKU
                                            ZoneSupport         = $mNodeZoneSupport
                                            ZoneSupportStatus   = $mNodeZoneSupportStatus
                                            vCPUCount           = $mNodevCPUCount
                                            SKUFamilyQuota      = $mNodeSKUFamilyQuota
                                            QuotaFamilyName     = $mNodeType.QuotaFamily
                                            InstanceCount       = $mNodeType.dNodeCount
                                            PhysicalSize        = $mNodeType.PhysicalSize
                                            AvailableZones      = if ($mNodeSupportedSKU.LocationInfo.Zones) { $mNodeSupportedSKU.LocationInfo.Zones } else { @() }
                                        }
                                    }
                            }

                        $reportData.SKUSupportData = $skuSupportData

                        # Build quota analysis data (general quotas available even without CNode/MNode)
                        $quotaAnalysisData = @()
                        $totalVMQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $("Virtual Machines") }
                        if ($totalVMQuota)
                            {
                                $availableVMQuota = $totalVMQuota.Limit - $totalVMQuota.CurrentValue
                                $quotaAnalysisData += [PSCustomObject]@{
                                    QuotaType   = $("Virtual Machines")
                                    Required    = $("N/A")
                                    Available   = $availableVMQuota
                                    Limit       = $totalVMQuota.Limit
                                    Status      = $("ℹ Available: {0}/{1}" -f $availableVMQuota, $totalVMQuota.Limit)
                                    StatusLevel = $("Success")
                                }
                            }

                        $totalVCPUQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $("Total Regional vCPUs") }
                        if ($totalVCPUQuota)
                            {
                                $availableVCPUQuota = $totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue
                                $quotaAnalysisData += [PSCustomObject]@{
                                    QuotaType   = $("Regional vCPUs")
                                    Required    = $("N/A")
                                    Available   = $availableVCPUQuota
                                    Limit       = $totalVCPUQuota.Limit
                                    Status      = $("ℹ Available: {0}/{1}" -f $availableVCPUQuota, $totalVCPUQuota.Limit)
                                    StatusLevel = $("Success")
                                }
                            }

                        $reportData.QuotaAnalysisData = $quotaAnalysisData

                        # SKU Family Testing results (always populated from begin block analysis)
                        if ($skuFamilyResults)
                            {
                                $reportData.SKUFamilyTesting.Results = @($skuFamilyResults)
                            }

                        # Multi-Zone Analysis results (populated in begin block)
                        if ($TestAllZones -and $zoneResults)
                            {
                                $reportData.ZoneResults = $zoneResults
                            }

                        # Zone alignment - reuse begin block variables to build full alignment info
                        $zoneAlignmentInfo =    @{
                                                    AlignmentPerformed      = $false
                                                    AlignmentDisabled       = $DisableZoneAlignment
                                                    AlignmentSubscription   = $ZoneAlignmentSubscriptionId
                                                    OriginalZone            = $("")
                                                    FinalZone               = $Zone
                                                    ZoneMappings            = @()
                                                    AlignmentReason         = $("Not applicable")
                                                }

                        if ($ZoneAlignmentSubscriptionId -and $Zone -ne "Zoneless" -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                            {
                                $zoneAlignmentInfo.AlignmentSubscription = $ZoneAlignmentSubscriptionId

                                if ($originalZone)
                                    {
                                        $zoneAlignmentInfo.AlignmentPerformed = $true
                                        $zoneAlignmentInfo.OriginalZone = $originalZone
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment applied")
                                    } `
                                elseif ($DisableZoneAlignment -and $alignedZone)
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment available but disabled by parameter")
                                        $zoneAlignmentInfo.OriginalZone = $Zone
                                    } `
                                elseif ($alignedZone -eq $Zone)
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone already aligned - no adjustment needed")
                                    } `
                                else
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment data unavailable or inconclusive")
                                    }
                            } `
                        elseif ($Zone -ne "Zoneless" -and $zoneAlignmentResponse)
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zone mapping retrieved (subscription self-reference)")
                            } `
                        elseif ($Zone -eq "Zoneless")
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zoneless deployment - alignment not applicable")
                            } `
                        else
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("No alignment subscription specified")
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

                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentPerformed  = $zoneAlignmentInfo.AlignmentPerformed
                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentDisabled   = $zoneAlignmentInfo.AlignmentDisabled
                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentSubId      = if ($zoneAlignmentInfo.AlignmentSubscription) { $zoneAlignmentInfo.AlignmentSubscription } else { $("") }
                        $reportData.EnvironmentValidation.ZoneAlignment.OriginalZone        = $zoneAlignmentInfo.OriginalZone
                        $reportData.EnvironmentValidation.ZoneAlignment.FinalZone           = $zoneAlignmentInfo.FinalZone
                        $reportData.EnvironmentValidation.ZoneAlignment.ZoneMappings        = $zoneAlignmentInfo.ZoneMappings
                        $reportData.EnvironmentValidation.ZoneAlignment.Reason              = $zoneAlignmentInfo.AlignmentReason

                        # Timing
                        $reportData.Metadata.EndTime    = Get-Date
                        $reportData.Metadata.Duration   = (Get-Date) - $reportData.Metadata.StartTime

                        # Render reports
                        Write-SilkConsoleReport -ReportData $reportData

                        if (-not $NoHTMLReport)
                            {
                                # Ensure report output directory exists
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

                                $reportRegionPart = if ($Region) { $("-{0}" -f $Region) } else { $("") }
                                $reportZonePart   = if ($Zone)   { $("-{0}" -f $Zone)   } else { $("") }
                                $ReportFullPath = Join-Path -Path $ReportOutputPath -ChildPath $("{0}{1}{2}-DeploymentReport_{3}.html" -f $ReportLabel, $reportRegionPart, $reportZonePart, $StartTime.ToString("yyyyMMdd_HHmmss"))
                                Write-Verbose -Message $("Report Only mode - HTML report will be generated at: {0}" -f $ReportFullPath)
                                Write-SilkHTMLReport -ReportData $reportData -OutputPath $ReportFullPath
                            }

                        return
                    }

                # ===============================================================================
                # SKU Family Deployment Test - Actual VM Allocation Testing
                # ===============================================================================
                # When TestAllSKUFamilies is set WITHOUT GenerateReportOnly, deploy one test VM
                # per SKU family to validate real allocation availability. Each VM is deployed
                # as a standalone instance (no PPG or Availability Set) since we are testing
                # individual SKU families that cannot share placement constraints.
                if ($TestAllSKUFamilies)
                    {
                        Write-Verbose -Message $("SKU Family Deployment Test mode - deploying one test VM per SKU family")

                        # Report metadata
                        $reportData.Metadata.ReportMode         = if ($TestAllZones) { $("SKU Family Deployment Test + Multi-Zone") } else { $("SKU Family Deployment Test") }
                        $reportData.Metadata.StartTime          = Get-Date
                        $reportData.Metadata.ParameterSetName   = $PSCmdlet.ParameterSetName

                        # Configuration
                        $reportData.Configuration.SubscriptionId        = $SubscriptionId
                        $reportData.Configuration.ResourceGroupName     = $ResourceGroupName
                        $reportData.Configuration.Region                = $Region
                        $reportData.Configuration.Zone                  = $Zone
                        $reportData.Configuration.CNodeSKU              = $("All Families")
                        $reportData.Configuration.CNodeFriendlyName     = $("SKU Family Deployment Test")
                        $reportData.Configuration.CNodeCount            = 0
                        $reportData.Configuration.CNodeCountAdjusted    = 0
                        $reportData.Configuration.MNodeSizes            = @($mNodeSizeObject | ForEach-Object { $_.PhysicalSize })
                        $reportData.Configuration.MNodeSKUs             = @($mNodeSizeObject)
                        $reportData.Configuration.IPRange               = $IPRangeCIDR
                        $reportData.Configuration.ResourceNamePrefix    = $ResourceNamePrefix
                        $reportData.Configuration.DevelopmentMode       = [bool]$Development
                        $reportData.Configuration.NoHTMLReport          = [bool]$NoHTMLReport

                        # Raw data from begin block
                        $reportData.SKUSupport.RawRegionSKUs            = $locationSupportedSKU
                        $reportData.QuotaAnalysis.RawQuotaData          = $computeQuotaUsage

                        # SKU Family Testing results (from begin block analysis)
                        if ($skuFamilyResults)
                            {
                                $reportData.SKUFamilyTesting.Results = @($skuFamilyResults)
                            }

                        # Multi-Zone Analysis results (from begin block)
                        if ($TestAllZones -and $zoneResults)
                            {
                                $reportData.ZoneResults = $zoneResults
                            }

                        # Build quota analysis
                        $quotaAnalysisData = @()
                        $totalVMQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $("Virtual Machines") }
                        if ($totalVMQuota)
                            {
                                $availableVMQuota = $totalVMQuota.Limit - $totalVMQuota.CurrentValue
                                $quotaAnalysisData += [PSCustomObject]@{
                                    QuotaType   = $("Virtual Machines")
                                    Required    = $("N/A")
                                    Available   = $availableVMQuota
                                    Limit       = $totalVMQuota.Limit
                                    Status      = $("ℹ Available: {0}/{1}" -f $availableVMQuota, $totalVMQuota.Limit)
                                    StatusLevel = $("Success")
                                }
                            }
                        $totalVCPUQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $("Total Regional vCPUs") }
                        if ($totalVCPUQuota)
                            {
                                $availableVCPUQuota = $totalVCPUQuota.Limit - $totalVCPUQuota.CurrentValue
                                $quotaAnalysisData += [PSCustomObject]@{
                                    QuotaType   = $("Regional vCPUs")
                                    Required    = $("N/A")
                                    Available   = $availableVCPUQuota
                                    Limit       = $totalVCPUQuota.Limit
                                    Status      = $("ℹ Available: {0}/{1}" -f $availableVCPUQuota, $totalVCPUQuota.Limit)
                                    StatusLevel = $("Success")
                                }
                            }
                        $reportData.QuotaAnalysisData = $quotaAnalysisData

                        # Zone alignment - reuse begin block variables to build full alignment info
                        $zoneAlignmentInfo =    @{
                                                    AlignmentPerformed      = $false
                                                    AlignmentDisabled       = $DisableZoneAlignment
                                                    AlignmentSubscription   = $ZoneAlignmentSubscriptionId
                                                    OriginalZone            = $("")
                                                    FinalZone               = $Zone
                                                    ZoneMappings            = @()
                                                    AlignmentReason         = $("Not applicable")
                                                }

                        if ($ZoneAlignmentSubscriptionId -and $Zone -ne "Zoneless" -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                            {
                                $zoneAlignmentInfo.AlignmentSubscription = $ZoneAlignmentSubscriptionId

                                if ($originalZone)
                                    {
                                        $zoneAlignmentInfo.AlignmentPerformed = $true
                                        $zoneAlignmentInfo.OriginalZone = $originalZone
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment applied")
                                    } `
                                elseif ($DisableZoneAlignment -and $alignedZone)
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment available but disabled by parameter")
                                        $zoneAlignmentInfo.OriginalZone = $Zone
                                    } `
                                elseif ($alignedZone -eq $Zone)
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone already aligned - no adjustment needed")
                                    } `
                                else
                                    {
                                        $zoneAlignmentInfo.AlignmentReason = $("Zone alignment data unavailable or inconclusive")
                                    }
                            } `
                        elseif ($Zone -ne "Zoneless" -and $zoneAlignmentResponse)
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zone mapping retrieved (subscription self-reference)")
                            } `
                        elseif ($Zone -eq "Zoneless")
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zoneless deployment - alignment not applicable")
                            } `
                        else
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("No alignment subscription specified")
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

                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentPerformed  = $zoneAlignmentInfo.AlignmentPerformed
                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentDisabled   = $zoneAlignmentInfo.AlignmentDisabled
                        $reportData.EnvironmentValidation.ZoneAlignment.AlignmentSubId      = if ($zoneAlignmentInfo.AlignmentSubscription) { $zoneAlignmentInfo.AlignmentSubscription } else { $("") }
                        $reportData.EnvironmentValidation.ZoneAlignment.OriginalZone        = $zoneAlignmentInfo.OriginalZone
                        $reportData.EnvironmentValidation.ZoneAlignment.FinalZone           = $zoneAlignmentInfo.FinalZone
                        $reportData.EnvironmentValidation.ZoneAlignment.ZoneMappings        = $zoneAlignmentInfo.ZoneMappings
                        $reportData.EnvironmentValidation.ZoneAlignment.Reason              = $zoneAlignmentInfo.AlignmentReason

                        # ---------------------------------------------------------------
                        # Create Shared Network Infrastructure (NSG + VNet + Subnet)
                        # ---------------------------------------------------------------
                        $deploymentStarted = $true
                        Write-Host $("Creating shared network infrastructure for SKU family deployment tests...") -ForegroundColor Yellow

                        try
                            {
                                # NSG with deny-all rules for complete isolation
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

                                $nSG = New-AzNetworkSecurityGroup `
                                        -ResourceGroupName $ResourceGroupName `
                                        -Location $Region `
                                        -Name $("{0}-nsg" -f $ResourceNamePrefix) `
                                        -SecurityRules $nSGDenyAllOutboundRule, $nSGDenyAllInboundRule

                                Write-Verbose -Message $("✓ NSG '{0}' created" -f $nSG.Name)

                                # Subnet + VNet
                                $mGMTSubnet = New-AzVirtualNetworkSubnetConfig `
                                                -Name $("{0}-mgmt-subnet" -f $ResourceNamePrefix) `
                                                -AddressPrefix $IPRangeCIDR `
                                                -NetworkSecurityGroup $nSG

                                $vNET = New-AzVirtualNetwork `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Location $Region `
                                            -Name $("{0}-vnet" -f $ResourceNamePrefix) `
                                            -AddressPrefix $IPRangeCIDR `
                                            -Subnet $mGMTSubnet

                                $mGMTSubnetID = $vNET.Subnets | Where-Object { $_.Name -eq $mGMTSubnet.Name } | Select-Object -ExpandProperty Id

                                Write-Verbose -Message $("✓ VNet '{0}' created with subnet '{1}'" -f $vNET.Name, $mGMTSubnet.Name)
                                Write-Host $("✓ Shared network infrastructure created") -ForegroundColor Green
                            } `
                        catch
                            {
                                Write-Error $("Failed to create shared infrastructure for SKU family deployment tests: {0}" -f $_)
                                return
                            }

                        # ---------------------------------------------------------------
                        # Deploy One Test VM Per Unique SKU (No PPG / No Availability Set)
                        # ---------------------------------------------------------------
                        # Deduplicate: only deploy one VM per unique SKU name across CNode + MNode
                        # If a SKU is used by both CNode and MNode configs, one test covers both
                        Get-Job | Remove-Job -Force
                        $vmJobMapping = @{}
                        $skuDeploymentResults = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'
                        $testedSKUs = @{}
                        $skippedEntries = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

                        # Build unique SKU deploy list from CNode entries first, then MNode
                        $uniqueSKUDeploys = @()
                        $vmCounter = 0

                        foreach ($cNodeEntry in $cNodeSizeObject)
                            {
                                $skuName = $("{0}{1}{2}" -f $cNodeEntry.vmSkuPrefix, $cNodeEntry.vCPU, $cNodeEntry.vmSkuSuffix)
                                if ($testedSKUs.ContainsKey($skuName))
                                    {
                                        Write-Verbose -Message $("Skipping duplicate CNode SKU {0} ({1}) - already tested" -f $skuName, $cNodeEntry.cNodeFriendlyName)
                                        $skippedEntries.Add([PSCustomObject]@{
                                            NodeType        = $("CNode")
                                            FriendlyName    = $cNodeEntry.cNodeFriendlyName
                                            SKUName         = $skuName
                                            QuotaFamily     = $cNodeEntry.QuotaFamily
                                            vCPU            = $cNodeEntry.vCPU
                                            TestedBy        = $testedSKUs[$skuName]
                                        })
                                        continue
                                    }

                                $vmCounter++
                                $testedSKUs[$skuName] = $cNodeEntry.cNodeFriendlyName
                                $uniqueSKUDeploys += [PSCustomObject]@{
                                    NodeType        = $("CNode")
                                    FriendlyName    = $cNodeEntry.cNodeFriendlyName
                                    SKUName         = $skuName
                                    QuotaFamily     = $cNodeEntry.QuotaFamily
                                    vCPU            = $cNodeEntry.vCPU
                                    Zone            = $Zone
                                    VMNumber        = $vmCounter
                                    VMName          = $("{0}-skutest-{1:D2}" -f $ResourceNamePrefix, $vmCounter)
                                    NICName         = $("{0}-skutest-nic-{1:D2}" -f $ResourceNamePrefix, $vmCounter)
                                }
                            }

                        foreach ($mNodeEntry in $mNodeSizeObject)
                            {
                                $skuName = $("{0}{1}{2}" -f $mNodeEntry.vmSkuPrefix, $mNodeEntry.vCPU, $mNodeEntry.vmSkuSuffix)
                                if ($testedSKUs.ContainsKey($skuName))
                                    {
                                        Write-Verbose -Message $("Skipping duplicate MNode SKU {0} ({1} TiB) - already tested via {2}" -f $skuName, $mNodeEntry.PhysicalSize, $testedSKUs[$skuName])
                                        $skippedEntries.Add([PSCustomObject]@{
                                            NodeType        = $("MNode")
                                            FriendlyName    = $("{0} TiB" -f $mNodeEntry.PhysicalSize)
                                            SKUName         = $skuName
                                            QuotaFamily     = $mNodeEntry.QuotaFamily
                                            vCPU            = $mNodeEntry.vCPU
                                            TestedBy        = $testedSKUs[$skuName]
                                        })
                                        continue
                                    }

                                $vmCounter++
                                $testedSKUs[$skuName] = $("{0} TiB" -f $mNodeEntry.PhysicalSize)
                                $uniqueSKUDeploys += [PSCustomObject]@{
                                    NodeType        = $("MNode")
                                    FriendlyName    = $("{0} TiB" -f $mNodeEntry.PhysicalSize)
                                    SKUName         = $skuName
                                    QuotaFamily     = $mNodeEntry.QuotaFamily
                                    vCPU            = $mNodeEntry.vCPU
                                    Zone            = $Zone
                                    VMNumber        = $vmCounter
                                    VMName          = $("{0}-skutest-{1:D2}" -f $ResourceNamePrefix, $vmCounter)
                                    NICName         = $("{0}-skutest-nic-{1:D2}" -f $ResourceNamePrefix, $vmCounter)
                                }
                            }

                        $totalOriginalEntries = $cNodeSizeObject.Count + $mNodeSizeObject.Count
                        $uniqueSKUCount = $uniqueSKUDeploys.Count

                        if ($skippedEntries.Count -gt 0)
                            {
                                Write-Verbose -Message $("Deduplicated {0} configurations to {1} unique SKUs ({2} shared)" -f $totalOriginalEntries, $uniqueSKUCount, $skippedEntries.Count)
                            }

                        # ---------------------------------------------------------------
                        # Multi-Zone Expansion: Deploy Each Unique SKU Per Supported Zone
                        # ---------------------------------------------------------------
                        # When TestAllZones is specified, expand the deploy list so each
                        # unique SKU gets one VM per zone it supports. The zone support
                        # is looked up from the region SKU data already collected.
                        $isMultiZoneDeploy = $false
                        $testedZones = @($Zone)

                        if ($TestAllZones -and $zoneResults)
                            {
                                $isMultiZoneDeploy = $true
                                $allRegionZones = $zoneResults.Zones
                                $expandedDeploys = @()
                                $perZoneCounter = @{}

                                foreach ($skuDeploy in $uniqueSKUDeploys)
                                    {
                                        # Look up which zones this SKU supports
                                        $supportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $skuDeploy.SKUName -and $_.ResourceType -eq $("virtualMachines") }
                                        $skuZones = if ($supportedSKU.LocationInfo.Zones) { @($supportedSKU.LocationInfo.Zones | Sort-Object) } else { @() }

                                        if ($skuZones.Count -eq 0)
                                            {
                                                Write-Verbose -Message $("  SKU {0} has no zone data — deploying to target zone {1}" -f $skuDeploy.SKUName, $Zone)
                                                $skuZones = @($Zone)
                                            }

                                        foreach ($testZone in $skuZones)
                                            {
                                                if (-not $perZoneCounter.ContainsKey($testZone)) { $perZoneCounter[$testZone] = 0 }
                                                $perZoneCounter[$testZone]++
                                                $zoneNN = $perZoneCounter[$testZone]

                                                $expandedDeploys += [PSCustomObject]@{
                                                    NodeType        = $skuDeploy.NodeType
                                                    FriendlyName    = $skuDeploy.FriendlyName
                                                    SKUName         = $skuDeploy.SKUName
                                                    QuotaFamily     = $skuDeploy.QuotaFamily
                                                    vCPU            = $skuDeploy.vCPU
                                                    Zone            = $testZone
                                                    VMNumber        = 0
                                                    VMName          = $("{0}-skutest-z{1}-{2:D2}" -f $ResourceNamePrefix, $testZone, $zoneNN)
                                                    NICName         = $("{0}-skutest-nic-z{1}-{2:D2}" -f $ResourceNamePrefix, $testZone, $zoneNN)
                                                }
                                            }
                                    }

                                # Assign global sequential VMNumber for progress tracking
                                $globalCounter = 0
                                foreach ($entry in $expandedDeploys)
                                    {
                                        $globalCounter++
                                        $entry.VMNumber = $globalCounter
                                    }

                                $uniqueSKUDeploys = $expandedDeploys
                                $testedZones = @($allRegionZones)

                                Write-Verbose -Message $("Multi-zone expansion: {0} unique SKUs × {1} zones = {2} deployment entries" -f $uniqueSKUCount, $allRegionZones.Count, $expandedDeploys.Count)
                            }

                        $totalTestVMs = $uniqueSKUDeploys.Count

                        # Deploy using Write-Progress
                        $deployStatusMsg = if ($isMultiZoneDeploy) { $("Deploying {0} test VMs ({1} SKUs × {2} zones)..." -f $totalTestVMs, $uniqueSKUCount, $testedZones.Count) } else { $("Deploying {0} unique SKU test VMs..." -f $totalTestVMs) }
                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 0 -SectionTotalSteps 3 `
                            -DetailMessage $deployStatusMsg

                        Write-Progress `
                            -Id 3 `
                            -ParentId 1 `
                            -Activity $("SKU Family Deployment Test") `
                            -Status $deployStatusMsg `
                            -PercentComplete 0

                        foreach ($skuFamily in $uniqueSKUDeploys)
                            {
                                $progressStatus = if ($isMultiZoneDeploy) { $("Creating {0} {1}/{2} ({3} - zone {4})" -f $skuFamily.NodeType, $skuFamily.VMNumber, $totalTestVMs, $skuFamily.SKUName, $skuFamily.Zone) } else { $("Creating {0} {1}/{2} ({3})" -f $skuFamily.NodeType, $skuFamily.VMNumber, $totalTestVMs, $skuFamily.SKUName) }
                                Write-Progress `
                                    -Id 4 `
                                    -ParentId 3 `
                                    -Activity $("SKU Test VM Creation") `
                                    -Status $progressStatus `
                                    -CurrentOperation $("{0} - vCPU: {1}" -f $skuFamily.FriendlyName, $skuFamily.vCPU) `
                                    -PercentComplete $(($skuFamily.VMNumber / $totalTestVMs) * 100)

                                try
                                    {
                                        # Create NIC
                                        $testNIC = New-AzNetworkInterface `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -Name $skuFamily.NICName `
                                                        -SubnetId $mGMTSubnetID

                                        Write-Verbose -Message $("  ✓ NIC '{0}' created" -f $testNIC.Name)

                                        # Build VM config — NO AvailabilitySetId, standalone instance
                                        $vmConfig = New-AzVMConfig `
                                                        -VMName $skuFamily.VMName `
                                                        -VMSize $skuFamily.SKUName

                                        $vmConfig = Set-AzVMOperatingSystem `
                                                        -VM $vmConfig `
                                                        -Linux `
                                                        -ComputerName $skuFamily.VMName `
                                                        -Credential $VMInstanceCredential `
                                                        -DisablePasswordAuthentication:$false

                                        # Set VM image (same logic as existing deployment)
                                        if ($VMImageOffer -eq "Ubuntu2204" -or $VMImageOffer -eq "Ubuntu2404" -or $VMImageOffer -eq "UbuntuLTS")
                                            {
                                                $vmConfig = Set-AzVMSourceImage `
                                                                -VM $vmConfig `
                                                                -Image $VMImageOffer
                                            } `
                                        else
                                            {
                                                $vmConfig = Set-AzVMSourceImage `
                                                                -VM $vmConfig `
                                                                -PublisherName $vMImage.PublisherName `
                                                                -Offer $vMImage.Offer `
                                                                -Skus $vMImage.Skus `
                                                                -Version $vMImage.Version
                                            }

                                        $vmConfig = Set-AzVMOSDisk `
                                                        -VM $vmConfig `
                                                        -CreateOption FromImage `
                                                        -DeleteOption "Delete"

                                        $vmConfig = Set-AzVMBootDiagnostic `
                                                        -VM $vmConfig `
                                                        -Disable:$true

                                        $vmConfig = Add-AzVMNetworkInterface `
                                                        -VM $vmConfig `
                                                        -Id $testNIC.Id `
                                                        -Primary:$true `
                                                        -DeleteOption "Delete"

                                        # Deploy as background job
                                        $vmJob = New-AzVM `
                                                        -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -VM $vmConfig `
                                                        -Zone $skuFamily.Zone `
                                                        -AsJob `
                                                        -WarningAction SilentlyContinue

                                        $vmJobMapping[$vmJob.Id] = @{
                                            VMName          = $skuFamily.VMName
                                            VMSku           = $skuFamily.SKUName
                                            NodeType        = $skuFamily.NodeType
                                            FriendlyName    = $skuFamily.FriendlyName
                                            QuotaFamily     = $skuFamily.QuotaFamily
                                            vCPU            = $skuFamily.vCPU
                                            Zone            = $skuFamily.Zone
                                        }

                                        Write-Verbose -Message $("  ✓ VM creation job submitted for '{0}'" -f $skuFamily.VMName)
                                    } `
                                catch
                                    {
                                        Write-Warning $("  ✗ Failed to submit job for {0} ({1}): {2}" -f $skuFamily.FriendlyName, $skuFamily.SKUName, $_.Exception.Message)

                                        # Record pre-deployment failure
                                        $skuDeploymentResults.Add([PSCustomObject]@{
                                            NodeType        = $skuFamily.NodeType
                                            FriendlyName    = $skuFamily.FriendlyName
                                            SKUName         = $skuFamily.SKUName
                                            QuotaFamily     = $skuFamily.QuotaFamily
                                            vCPU            = $skuFamily.vCPU
                                            Zone            = $skuFamily.Zone
                                            VMName          = $skuFamily.VMName
                                            DeploymentResult = $("Failed")
                                            FailureCategory = $("Pre-Deployment")
                                            ErrorCode       = $("SubmissionFailure")
                                            ErrorMessage    = $_.Exception.Message
                                        })
                                    }
                            }

                        Write-Progress -Id 4 -Activity $("SKU Test VM Creation") -Completed

                        # ---------------------------------------------------------------
                        # Monitor All SKU Test VM Deployment Jobs
                        # ---------------------------------------------------------------
                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 2 -SectionTotalSteps 3 `
                            -DetailMessage $("Monitoring {0} deployment jobs..." -f $vmJobMapping.Count)

                        Write-Progress `
                            -Id 3 `
                            -ParentId 1 `
                            -Activity $("SKU Family Deployment Test") `
                            -Status $("Monitoring {0} VM creation jobs..." -f $vmJobMapping.Count) `
                            -PercentComplete 50

                        $allVMJobs = Get-Job
                        if ($allVMJobs.Count -gt 0)
                            {
                                # Initial status
                                $currentVMJobs = Get-Job
                                $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                                $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }

                                Write-Progress `
                                    -Id 3 `
                                    -ParentId 1 `
                                    -Activity $("SKU Family Deployment Test") `
                                    -Status $("Monitoring VM creation jobs") `
                                    -CurrentOperation $("{0} completed, {1} remaining" -f $completedJobs.Count, $runningJobs.Count) `
                                    -PercentComplete $(if ($allVMJobs.Count -gt 0) { [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100) } else { 100 })

                                do
                                    {
                                        Start-Sleep -Seconds 3
                                        $currentVMJobs = Get-Job
                                        $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                                        $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                                        $completionPercent = if ($allVMJobs.Count -gt 0) { [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100) } else { 100 }
                                        $remainingJobs = [Math]::Max($allVMJobs.Count - $completedJobs.Count, 0)

                                        Write-Progress `
                                            -Id 3 `
                                            -ParentId 1 `
                                            -Activity $("SKU Family Deployment Test") `
                                            -Status $("Monitoring VM creation jobs") `
                                            -CurrentOperation $("{0} completed, {1} remaining (running: {2})" -f $completedJobs.Count, $remainingJobs, $runningJobs.Count) `
                                            -PercentComplete $completionPercent
                                    } `
                                while ($runningJobs.Count -gt 0)

                                Write-Progress `
                                    -Id 3 `
                                    -ParentId 1 `
                                    -Activity $("SKU Family Deployment Test") `
                                    -Status $("All deployment jobs complete") `
                                    -PercentComplete 100

                                Start-Sleep -Seconds 2
                                Write-Progress -Id 3 -Activity $("SKU Family Deployment Test") -Completed

                                # ---------------------------------------------------------------
                                # Analyze Results Per SKU
                                # ---------------------------------------------------------------
                                $finalVMJobs = Get-Job
                                foreach ($job in $finalVMJobs)
                                    {
                                        $vmDetails = $vmJobMapping[$job.Id]
                                        if (-not $vmDetails) { continue }

                                        if ($job.State -eq 'Completed')
                                            {
                                                $skuDeploymentResults.Add([PSCustomObject]@{
                                                    NodeType        = $vmDetails.NodeType
                                                    FriendlyName    = $vmDetails.FriendlyName
                                                    SKUName         = $vmDetails.VMSku
                                                    QuotaFamily     = $vmDetails.QuotaFamily
                                                    vCPU            = $vmDetails.vCPU
                                                    VMName          = $vmDetails.VMName
                                                    DeploymentResult = $("Success")
                                                    FailureCategory = $("")
                                                    ErrorCode       = $("")
                                                    ErrorMessage    = $("")
                                                })
                                            } `
                                        else
                                            {
                                                # Extract error details from multiple sources
                                                # IMPORTANT: Check child job streams BEFORE Receive-Job to avoid data consumption
                                                $errorSources = @()

                                                # Source 1: Child job streams (check BEFORE Receive-Job)
                                                if ($job.ChildJobs -and $job.ChildJobs.Count -gt 0)
                                                    {
                                                        foreach ($childJob in $job.ChildJobs)
                                                            {
                                                                if ($childJob.Error -and $childJob.Error.Count -gt 0)
                                                                    {
                                                                        $errorSources += ($childJob.Error | Out-String)
                                                                    }
                                                                if ($childJob.Output -and $childJob.Output.Count -gt 0)
                                                                    {
                                                                        $outputStr = $childJob.Output | Out-String
                                                                        if ($outputStr -match 'error|fail|exception|allocat|capacity|quota|constrained')
                                                                            {
                                                                                $errorSources += $outputStr
                                                                            }
                                                                    }
                                                                if ($childJob.Warning -and $childJob.Warning.Count -gt 0)
                                                                    {
                                                                        $warnStr = $childJob.Warning | Out-String
                                                                        if ($warnStr.Trim().Length -gt 0) { $errorSources += $warnStr }
                                                                    }
                                                                if ($childJob.JobStateInfo.Reason)
                                                                    {
                                                                        $errorSources += $childJob.JobStateInfo.Reason.ToString()
                                                                        $innerEx = $childJob.JobStateInfo.Reason.InnerException
                                                                        while ($innerEx) { $errorSources += $innerEx.Message; $innerEx = $innerEx.InnerException }
                                                                    }
                                                                if ($childJob.ChildJobs -and $childJob.ChildJobs.Count -gt 0)
                                                                    {
                                                                        foreach ($nested in $childJob.ChildJobs)
                                                                            {
                                                                                if ($nested.Error -and $nested.Error.Count -gt 0) { $errorSources += ($nested.Error | Out-String) }
                                                                                if ($nested.JobStateInfo.Reason) { $errorSources += $nested.JobStateInfo.Reason.ToString() }
                                                                            }
                                                                    }
                                                            }
                                                    }

                                                # Source 2: Receive-Job with -Keep
                                                $jobErrorRaw = $null
                                                try { $jobErrorRaw = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue 2>&1 }
                                                catch { $errorSources += $_.Exception.Message }
                                                $receiveJobString = $jobErrorRaw | Out-String
                                                if ($receiveJobString -and $receiveJobString.Trim().Length -gt 0)
                                                    {
                                                        $errorSources += $receiveJobString
                                                    }

                                                # Source 3: Main job state reason
                                                if ($job.JobStateInfo.Reason)
                                                    {
                                                        $errorSources += $job.JobStateInfo.Reason.ToString()
                                                        if ($job.JobStateInfo.Reason.InnerException)
                                                            {
                                                                $innerEx = $job.JobStateInfo.Reason.InnerException
                                                                while ($innerEx) { $errorSources += $innerEx.Message; $innerEx = $innerEx.InnerException }
                                                            }
                                                    }

                                                # Source 4: StatusMessage
                                                if ($job.StatusMessage -and $job.StatusMessage.Trim().Length -gt 0)
                                                    {
                                                        $errorSources += $job.StatusMessage
                                                    }

                                                $jobErrorString = ($errorSources | Where-Object { $_ -and $_.Trim().Length -gt 0 }) -join "`n"

                                                # Log raw error output for debugging
                                                $rawPreview = if ($jobErrorString.Trim().Length -gt 0) { $jobErrorString.Trim().Substring(0, [Math]::Min(500, $jobErrorString.Trim().Length)) } else { "(no error output captured)" }
                                                Write-Verbose -Message $("  SKU test VM '{0}' job error: {1}" -f $vmDetails.VMName, $rawPreview)

                                                $errorCode = $("")
                                                $errorMessage = $("")
                                                $failureCategory = $("Unknown")

                                                if ($jobErrorString)
                                                    {
                                                        if ($jobErrorString -match "ErrorCode[:\s]*([^\s,\r\n]+)")
                                                            {
                                                                $errorCode = $matches[1]
                                                            }
                                                        if ($jobErrorString -match "ErrorMessage[:\s]*([^\r\n]+)")
                                                            {
                                                                $errorMessage = $matches[1].Trim()
                                                                $errorMessage = $errorMessage -replace "\s*Read more about.*$", ""
                                                                $errorMessage = $errorMessage -replace "\s*For more information.*$", ""
                                                            }

                                                        if ($jobErrorString -match "AllocationFailed" -or $jobErrorString -match "allocation.*failed" -or $jobErrorString -match "OverconstrainedAllocationRequest" -or $jobErrorString -match "OverconstrainedZonalAllocationRequest")
                                                            {
                                                                $failureCategory = $("Allocation Failed")
                                                                if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = $("AllocationFailed") }
                                                                if ([string]::IsNullOrWhiteSpace($errorMessage)) { $errorMessage = $("No capacity available for this SKU in the target zone") }
                                                            } `
                                                        elseif ($jobErrorString -match "quota|limit" -and $jobErrorString -notmatch "AllocationFailed")
                                                            {
                                                                $failureCategory = $("Quota Exceeded")
                                                            } `
                                                        elseif ($jobErrorString -match "SKUNotAvailable|NotAvailableForSubscription")
                                                            {
                                                                $failureCategory = $("SKU Not Available")
                                                            } `
                                                        else
                                                            {
                                                                $failureCategory = $("Other")
                                                            }

                                                        # Fallback error message
                                                        if ([string]::IsNullOrWhiteSpace($errorMessage))
                                                            {
                                                                $errorLines = $jobErrorString -split "`n" | Where-Object { $_ -match "error|failed|exception|capacity|allocation|quota|constrained" -and $_ -notmatch "^VERBOSE:|^DEBUG:" } | Select-Object -First 2
                                                                if ($errorLines)
                                                                    {
                                                                        $errorMessage = ($errorLines -join "; ").Trim()
                                                                        if ($errorMessage.Length -gt 200) { $errorMessage = $errorMessage.Substring(0, 200) + "..." }
                                                                    } `
                                                                else
                                                                    {
                                                                        # Last resort: take first non-empty line
                                                                        $firstLine = ($jobErrorString -split "`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
                                                                        if ($firstLine)
                                                                            {
                                                                                $errorMessage = $firstLine.Trim()
                                                                                if ($errorMessage.Length -gt 200) { $errorMessage = $errorMessage.Substring(0, 200) + "..." }
                                                                            } `
                                                                        else
                                                                            {
                                                                                $errorMessage = $("Deployment failed - use -DisableCleanup and check Azure portal for details")
                                                                            }
                                                                    }
                                                            }
                                                    }

                                                $skuDeploymentResults.Add([PSCustomObject]@{
                                                    NodeType        = $vmDetails.NodeType
                                                    FriendlyName    = $vmDetails.FriendlyName
                                                    SKUName         = $vmDetails.VMSku
                                                    QuotaFamily     = $vmDetails.QuotaFamily
                                                    vCPU            = $vmDetails.vCPU
                                                    VMName          = $vmDetails.VMName
                                                    DeploymentResult = $("Failed")
                                                    FailureCategory = $failureCategory
                                                    ErrorCode       = $errorCode
                                                    ErrorMessage    = $errorMessage
                                                })
                                            }
                                    }
                            }

                        # Add results for skipped entries (inherit result from the tested SKU)
                        foreach ($skipped in $skippedEntries)
                            {
                                $testedResult = $skuDeploymentResults | Where-Object { $_.SKUName -eq $skipped.SKUName } | Select-Object -First 1
                                if ($testedResult)
                                    {
                                        $skuDeploymentResults.Add([PSCustomObject]@{
                                            NodeType        = $skipped.NodeType
                                            FriendlyName    = $skipped.FriendlyName
                                            SKUName         = $skipped.SKUName
                                            QuotaFamily     = $skipped.QuotaFamily
                                            vCPU            = $skipped.vCPU
                                            VMName          = $("(shared: {0})" -f $skipped.TestedBy)
                                            DeploymentResult = $testedResult.DeploymentResult
                                            FailureCategory = $testedResult.FailureCategory
                                            ErrorCode       = $testedResult.ErrorCode
                                            ErrorMessage    = $testedResult.ErrorMessage
                                        })
                                    }
                            }

                        # Store results in report data
                        $reportData.SKUFamilyTesting.DeploymentResults = @($skuDeploymentResults)

                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 3 -SectionTotalSteps 3 `
                            -DetailMessage $("")

                        # Timing
                        $reportData.Metadata.EndTime    = Get-Date
                        $reportData.Metadata.Duration   = (Get-Date) - $reportData.Metadata.StartTime

                        # Render reports
                        Write-SilkConsoleReport -ReportData $reportData

                        if (-not $NoHTMLReport)
                            {
                                if (-not (Test-Path $ReportOutputPath))
                                    {
                                        try
                                            {
                                                New-Item -Path $ReportOutputPath -ItemType Directory -Force | Out-Null
                                            } `
                                        catch
                                            {
                                                Write-Warning -Message $("Failed to create report output directory '{0}': {1}. Using current directory." -f $ReportOutputPath, $_.Exception.Message)
                                                $ReportOutputPath = (Get-Location).Path
                                            }
                                    }

                                $reportRegionPart = if ($Region) { $("-{0}" -f $Region) } else { $("") }
                                $reportZonePart   = if ($Zone)   { $("-{0}" -f $Zone)   } else { $("") }
                                $ReportFullPath = Join-Path -Path $ReportOutputPath -ChildPath $("{0}{1}{2}-DeploymentReport_{3}.html" -f $ReportLabel, $reportRegionPart, $reportZonePart, $StartTime.ToString("yyyyMMdd_HHmmss"))
                                Write-SilkHTMLReport -ReportData $reportData -OutputPath $ReportFullPath
                            }

                        # NOTE: Cleanup proceeds in the end block since $deploymentStarted = $true
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
                # Multi-Zone Deployment: Determine Target Zones
                # ===============================================================================
                # When TestAllZones is specified, find every zone in the region where ALL
                # requested SKUs are simultaneously supported and deploy only into those zones.
                # Zones excluded by the SKU intersection are captured as $skippedZoneEntries
                # and surfaced in the deployment report so the user understands why each zone
                # was not a valid deployment target for this configuration.
                # Without TestAllZones, deploy only into the user-specified $Zone.
                $isMultiZoneDeploy = $false
                $zonesToDeploy = @($Zone)
                $skippedZoneEntries = @()

                if ($TestAllZones)
                    {
                        # Determine all availability zones present in this region
                        $allRegionZones = if ($zoneResults -and $zoneResults.Zones.Count -gt 0) `
                            {
                                @($zoneResults.Zones)
                            } `
                        else
                            {
                                @($locationSupportedSKU.LocationInfo.Zones | Sort-Object | Select-Object -Unique)
                            }

                        if ($allRegionZones.Count -gt 0)
                            {
                                # Gather all unique SKUs required by this deployment configuration
                                $allRequestedSkus = @()
                                if ($cNodeObject)
                                    {
                                        $allRequestedSkus += $cNodeVMSku
                                    }
                                foreach ($mn in $mNodeObject)
                                    {
                                        $allRequestedSkus += $("{0}{1}{2}" -f $mn.vmSkuPrefix, $mn.vCPU, $mn.vmSkuSuffix)
                                    }
                                $allRequestedSkus = @($allRequestedSkus | Select-Object -Unique)

                                # Build per-SKU zone support map from region SKU data
                                $regionSkuZones = @{}
                                foreach ($sku in $allRequestedSkus)
                                    {
                                        $skuInfo = $locationSupportedSKU | Where-Object { $_.Name -eq $sku -and $_.ResourceType -eq $("virtualMachines") }
                                        $regionSkuZones[$sku] = if ($skuInfo -and $skuInfo.LocationInfo.Zones) { @($skuInfo.LocationInfo.Zones | Sort-Object) } else { @() }
                                    }

                                # Intersect zones — only deploy where ALL requested SKUs are supported.
                                # A zone where even one SKU is unsupported cannot host the full Silk configuration.
                                $commonZones = $null
                                foreach ($sku in $allRequestedSkus)
                                    {
                                        if ($null -eq $commonZones)
                                            {
                                                $commonZones = @($regionSkuZones[$sku])
                                            } `
                                        else
                                            {
                                                $commonZones = @($commonZones | Where-Object { $regionSkuZones[$sku] -contains $_ })
                                            }
                                    }
                                $commonZones = @($commonZones | Sort-Object)

                                # For every region zone excluded by the intersection, record which SKUs prevented deployment
                                foreach ($z in $allRegionZones)
                                    {
                                        if ($commonZones -notcontains $z)
                                            {
                                                $unsupportedSkus = @($allRequestedSkus | Where-Object { $regionSkuZones[$_] -notcontains $z })
                                                $skippedZoneEntries += [PSCustomObject]@{
                                                    Zone            = $z
                                                    UnsupportedSKUs = $unsupportedSkus
                                                    Reason          = $("Not a valid configuration zone — {0} not available in Zone {1}" -f ($unsupportedSkus -join $(", ")), $z)
                                                }
                                                Write-Verbose -Message $("Zone {0} skipped: {1} SKU(s) not supported here ({2})" -f $z, $unsupportedSkus.Count, ($unsupportedSkus -join $(", ")))
                                            }
                                    }

                                if ($commonZones.Count -gt 0)
                                    {
                                        $isMultiZoneDeploy = $true
                                        $zonesToDeploy = @($commonZones)
                                        Write-Verbose -Message $("Multi-zone deployment: {0}/{1} zones qualify ({2}) — {3} zone(s) skipped (invalid configuration for this SKU set)" -f $zonesToDeploy.Count, $allRegionZones.Count, ($zonesToDeploy -join $(", ")), $skippedZoneEntries.Count)
                                    } `
                                else
                                    {
                                        Write-Warning $("No zones found where ALL requested SKUs are supported. Deploying to target zone {0} only." -f $Zone)
                                    }
                            } `
                        else
                            {
                                Write-Warning $("No availability zones detected in region '{0}'. Deploying to target zone {1} only." -f $Region, $Zone)
                            }
                    }

                # ===============================================================================
                # Virtual Network Infrastructure Creation
                # ===============================================================================
                # Creates a completely isolated network environment for testing VM deployments
                # This ensures no accidental internet access and validates Azure resource availability
                try
                    {
                        # Update progress: Starting network creation
                        Update-StagedProgress -SectionName 'NetworkCreation' -SectionCurrentStep 0 -SectionTotalSteps 2 `
                            -DetailMessage $("Setting up network security group...")

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

                        # Update progress: Virtual network creation
                        Update-StagedProgress -SectionName 'NetworkCreation' -SectionCurrentStep 1 -SectionTotalSteps 2 `
                            -DetailMessage $("Creating virtual network and subnets...")

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

                        # Update progress: Network creation complete
                        Update-StagedProgress -SectionName 'NetworkCreation' -SectionCurrentStep 2 -SectionTotalSteps 2 `
                            -DetailMessage $("Network and security groups created...")

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
                                $totalVMsPerZone = $CNodeCount + $totalDNodes
                            } `
                        else
                            {
                                $totalVMsPerZone = $totalDNodes
                            }
                        $totalVMs = $totalVMsPerZone * $zonesToDeploy.Count

                        # Update staged progress: VM deployment starting
                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 0 -SectionTotalSteps 3 `
                            -DetailMessage $("")

                        # Start main VM creation progress
                        $deployProgressMsg = if ($isMultiZoneDeploy) { $("Preparing deployment for {0} VM(s) across {1} zones ({2} per zone)..." -f $totalVMs, $zonesToDeploy.Count, $totalVMsPerZone) } else { $("Preparing deployment for {0} VM(s) ({1} CNodes, {2} DNodes)..." -f $totalVMs, $adjustedCNodeCount, $totalDNodes) }
                        Write-Progress `
                            -Status $("Initializing VM Deployment") `
                            -CurrentOperation $deployProgressMsg `
                            -PercentComplete 0 `
                            -Activity $("VM Deployment") `
                            -ParentId 1 `
                            -Id 3

                        # ---------------------------------------------------------------
                        # Zone Deployment Loop
                        # ---------------------------------------------------------------
                        # Deploy the full configuration into each target zone.
                        # For single-zone (no TestAllZones), this loops once with the user-specified zone.
                        $zoneLoopIndex = 0
                        foreach ($deployZone in $zonesToDeploy)
                            {
                                $zoneLoopIndex++
                                $zonePrefix = if ($isMultiZoneDeploy) { $("-z{0}" -f $deployZone) } else { $("") }
                                $zoneLabel = if ($isMultiZoneDeploy) { $(" [Zone {0} — {1}/{2}]" -f $deployZone, $zoneLoopIndex, $zonesToDeploy.Count) } else { $("") }

                                if ($isMultiZoneDeploy)
                                    {
                                        Write-Progress `
                                            -Status $("Deploying to Zone {0} ({1}/{2})" -f $deployZone, $zoneLoopIndex, $zonesToDeploy.Count) `
                                            -CurrentOperation $("Creating infrastructure for zone {0}..." -f $deployZone) `
                                            -PercentComplete ([Math]::Round((($zoneLoopIndex - 1) / $zonesToDeploy.Count) * 100)) `
                                            -Activity $("VM Deployment") `
                                            -ParentId 1 `
                                            -Id 3
                                    }

                                # Reset per-zone DNode tracking
                                $dNodeStartCount = 0

                        if($adjustedCNodeCount -gt 0)
                            {
                                # Update progress for availability set creation
                                Write-Progress `
                                    -Status $("Creating CNode Infrastructure{0}" -f $zoneLabel) `
                                    -CurrentOperation $("Creating CNode availability set...") `
                                    -PercentComplete 2 `
                                    -Activity $("VM Deployment") `
                                    -ParentId 1 `
                                    -Id 3

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
                                        if ($deployZone -ne $("Zoneless"))
                                            {
                                                Write-Verbose -Message $("Creating CNode Proximity Placement Group in region '{0}' with zone '{1}' and VM SKU: {2}" -f $Region, $deployZone, $cNodeVMSku)
                                                $cNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -Location $Region `
                                                                            -Zone $deployZone `
                                                                            -Name $("{0}{1}-cnode-ppg" -f $ResourceNamePrefix, $zonePrefix) `
                                                                            -ProximityPlacementGroupType "Standard" `
                                                                            -IntentVMSize $cNodeVMSku
                                            } `
                                        else
                                            {
                                                Write-Verbose -Message $("Creating CNode Proximity Placement Group in region '{0}' without zones" -f $Region)
                                                $cNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                            -ResourceGroupName $ResourceGroupName `
                                                                            -Location $Region `
                                                                            -Name $("{0}{1}-cnode-ppg" -f $ResourceNamePrefix, $zonePrefix) `
                                                                            -ProximityPlacementGroupType "Standard"
                                            }

                                        Write-Verbose -Message $("✓ CNode Proximity Placement Group '{0}' created" -f $cNodeProximityPlacementGroup.Name)

                                        # create an availability set for the c-node group
                                        $cNodeAvailabilitySet = New-AzAvailabilitySet `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Name $("{0}{1}-cnode-avset" -f $ResourceNamePrefix, $zonePrefix) `
                                                            -Location $Region `
                                                            -ProximityPlacementGroupId $cNodeProximityPlacementGroup.Id `
                                                            -Sku "Aligned" `
                                                            -PlatformFaultDomainCount $maximumFaultDomains `
                                                            -PlatformUpdateDomainCount 20

                                        Write-Verbose -Message $("✓ CNode availability set '{0}' created." -f $cNodeAvailabilitySet.Name)
                                    }

                                # CNode creation phase with updated progress
                                Write-Progress `
                                    -Status $("Creating CNodes") `
                                    -CurrentOperation $("Preparing to create {0} CNode VM(s) in availability set..." -f $adjustedCNodeCount) `
                                    -PercentComplete 5 `
                                    -Activity $("VM Deployment") `
                                    -ParentId 1 `
                                    -Id 3

                                for ($cNode = 1; $cNode -le $adjustedCNodeCount; $cNode++)
                                    {
                                        # Calculate CNode SKU for display
                                        $currentCNodeSku = "{0}" -f $CNodeSku

                                        # Update sub-progress for CNode creation
                                        Write-Progress `
                                            -Status $("Creating CNode {0} of {1} ({2})" -f $cNode, $adjustedCNodeCount, $currentCNodeSku) `
                                            -CurrentOperation $("Configuring CNode {0} with SKU {1}..." -f $cNode, $currentCNodeSku) `
                                            -PercentComplete $(($cNode / $adjustedCNodeCount) * 100) `
                                            -Activity $("CNode Creation") `
                                            -ParentId 3 `
                                            -Id 4

                                        # create the cnode management NIC
                                        $cNodeMGMTNIC = New-AzNetworkInterface `
                                                            -ResourceGroupName $ResourceGroupName `
                                                            -Location $Region `
                                                            -Name $("{0}{1}-cnode-mgmt-nic-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $cNode) `
                                                            -SubnetId $mGMTSubnetID

                                        Write-Verbose -Message $("✓ CNode {0} management NIC '{1}' successfully created with IP '{2}'" -f $cNode, $cNodeMGMTNIC.Name, $cNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)

                                        # create the cnode vm configuration
                                        # Use availability sets
                                        $cNodeConfig = New-AzVMConfig `
                                                        -VMName $("{0}{1}-cnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $cNode) `
                                                        -VMSize $cNodeVMSku `
                                                        -AvailabilitySetId $cNodeAvailabilitySet.Id

                                        # set operating system details
                                        $cNodeConfig = Set-AzVMOperatingSystem `
                                                        -VM $cNodeConfig `
                                                        -Linux `
                                                        -ComputerName $("{0}{1}-cnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $cNode) `
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
                                                    VMName = $("{0}{1}-cnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $cNode)
                                                    VMSku = $cNodeVMSku
                                                    NodeType = "CNode"
                                                    NodeNumber = $cNode
                                                    Zone = $deployZone
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
                                        # Use $cNodeAvailabilitySet.Name to support both newly created and existing infrastructure paths
                                        $cNodeAvailabilitySetComplete = Get-AzAvailabilitySet -ResourceGroupName $ResourceGroupName -Name $cNodeAvailabilitySet.Name
                                        Write-Verbose -Message $("✓ CNode availability set '{0}' created with {1} CNodes." -f $cNodeAvailabilitySetComplete.Name, $cNodeAvailabilitySetComplete)
                                        Write-Verbose -Message $("✓ CNode availability set '{0}' is assigned to proximity placement group '{1}'." -f $cNodeAvailabilitySetComplete.Name, $cNodeProximityPlacementGroup.Name)
                                    }

                                # Clean up CNode creation sub-progress bar as this phase is complete
                                Write-Progress -Activity $("CNode Creation") -Id 4 -Completed
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
                                        if ($deployZone -ne $("Zoneless"))
                                            {
                                                Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' with zone '{1}' and VM SKUs: {2}" -f $Region, $deployZone, $currentMNodeSku)
                                                $mNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                                -ResourceGroupName $ResourceGroupName `
                                                                                -Location $Region `
                                                                                -Zone $deployZone `
                                                                                -Name $("{0}{1}-mNode-{2}-ppg" -f $ResourceNamePrefix, $zonePrefix, $currentMNode) `
                                                                                -ProximityPlacementGroupType "Standard" `
                                                                                -IntentVMSize $currentMNodeSku
                                            } `
                                        else
                                            {
                                                Write-Verbose -Message $("Creating Proximity Placement Group in region '{0}' without zones" -f $Region)
                                                $mNodeProximityPlacementGroup = New-AzProximityPlacementGroup `
                                                                                -ResourceGroupName $ResourceGroupName `
                                                                                -Location $Region `
                                                                                -Name $("{0}{1}-mNode-{2}-ppg" -f $ResourceNamePrefix, $zonePrefix, $currentMNode) `
                                                                                -ProximityPlacementGroupType "Standard"
                                            }

                                        Write-Verbose -Message $("✓ Proximity Placement Group '{0}' created" -f $mNodeProximityPlacementGroup.Name)

                                        # create availability set for current mNode
                                        $mNodeAvailabilitySet = New-AzAvailabilitySet `
                                                                    -ResourceGroupName $ResourceGroupName `
                                                                    -Location $Region `
                                                                    -Name $("{0}{1}-mNode-{2}-avset" -f $ResourceNamePrefix, $zonePrefix, $currentMNode) `
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
                                            -CurrentOperation $("Creating {0} DNode VM(s) for {1} TiB MNode..." -f $currentDNodeCount, $currentMNodePhysicalSize) `
                                            -PercentComplete $mainPercentComplete `
                                            -Activity $("VM Deployment") `
                                            -ParentId 1 `
                                            -Id 3

                                        for ($dNode = 1; $dNode -le $currentDNodeCount; $dNode++)
                                            {
                                                # Update sub-progress for DNode creation
                                                Write-Progress `
                                                    -Status $("Creating DNode {0} of {1} - {2} TiB ({3})" -f $dNode, $currentDNodeCount, $currentMNodePhysicalSize, $currentMNodeSku) `
                                                    -CurrentOperation $("Configuring DNode {0} with SKU {1}..." -f ($dNode + $dNodeStartCount), $currentMNodeSku) `
                                                    -PercentComplete $(($dNode / $currentDNodeCount) * 100) `
                                                    -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) `
                                                    -ParentId 3 `
                                                    -Id 5

                                                # set dnode number to use for naming
                                                $dNodeNumber = $dNode + $dNodeStartCount

                                                # create the dnode management
                                                $dNodeMGMTNIC = New-AzNetworkInterface `
                                                                    -ResourceGroupName $ResourceGroupName `
                                                                -Location $Region `
                                                                -Name $("{0}{1}-dnode-{2:D2}-mgmt-nic" -f $ResourceNamePrefix, $zonePrefix, $dNodeNumber) `
                                                                -SubnetId $mGMTSubnetID

                                                Write-Verbose -Message $("✓ DNode {0} management NIC '{1}' successfully created with IP '{2}'" -f $dNodeNumber, $dNodeMGMTNIC.Name, $dNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)

                                                # create the dnode vm configuration
                                                $dNodeConfig = New-AzVMConfig `
                                                                -VMName $("{0}{1}-dnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $dNodeNumber) `
                                                                -VMSize $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix) `
                                                                -AvailabilitySetId $mNodeAvailabilitySet.Id

                                                # set operating system details
                                                $dNodeConfig = Set-AzVMOperatingSystem `
                                                                -VM $dNodeConfig `
                                                                -Linux `
                                                                -ComputerName $("{0}{1}-dnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $dNodeNumber) `
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
                                                    -ParentId 3 `
                                                    -Id 5

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
                                                                                            VMName = $("{0}{1}-dnode-{2:D2}" -f $ResourceNamePrefix, $zonePrefix, $dNodeNumber)
                                                                                            VMSku = $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix)
                                                                                            NodeType = "DNode"
                                                                                            NodeNumber = $dNodeNumber
                                                                                            MNodeGroup = $currentMNode
                                                                                            MNodePhysicalSize = $currentMNodePhysicalSize
                                                                                            Zone = $deployZone
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
                                        Write-Progress -Activity $("MNode Group {0} DNode Creation" -f $currentMNode) -Id 5 -Completed
                                    }
                            }

                            } # end foreach ($deployZone in $zonesToDeploy)

                        # ========================================================================================================
                        # begin vm creation job monitoring
                        # ========================================================================================================
                        # Initialize deployment validation tracking for reporting
                        $deploymentValidationResults = @()

                        # Validate all network interfaces were created successfully
                        Write-Verbose -Message $("✓ All network interfaces created successfully: {0} total NICs" -f (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }).Count)

                        # Wait for all VMs to be created - Final phase of VM deployment
                        $allVMJobs = Get-Job

                        # Update staged progress: monitoring VM creation
                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 2 -SectionTotalSteps 3 `
                            -DetailMessage $("")

                        # Update main progress to show completion phase and immediately show monitoring sub-progress
                        Write-Progress `
                            -Status $("Monitoring VM Creation Jobs") `
                            -CurrentOperation $("Waiting for all VMs to be deployed...") `
                            -PercentComplete 95 `
                            -Activity $("VM Deployment") `
                            -ParentId 1 `
                            -Id 3

                        # Initial status check to show immediate progress
                        $currentVMJobs = Get-Job
                        $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                        $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                        $initialCompletionPercent = if ($allVMJobs.Count -gt 0) { [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100) } else { 100 }
                        $initialRemainingJobs = [Math]::Max($allVMJobs.Count - $completedJobs.Count, 0)

                        # Update VM deployment progress immediately with current status
                        Write-Progress `
                            -Status $("Monitoring VM creation jobs") `
                            -CurrentOperation $("{0} completed, {1} remaining (running: {2})" -f $completedJobs.Count, $initialRemainingJobs, $runningJobs.Count) `
                            -PercentComplete $initialCompletionPercent `
                            -Activity $("VM Deployment") `
                            -ParentId 1 `
                            -Id 3

                        do
                            {
                                # Regular monitoring interval
                                Start-Sleep -Seconds 3
                                $currentVMJobs = Get-Job
                                $completedJobs = $currentVMJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
                                $runningJobs = $currentVMJobs | Where-Object { $_.State -in @('Running', 'NotStarted') }
                                $completionPercent = if ($allVMJobs.Count -gt 0) { [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100) } else { 100 }
                                $remainingJobs = [Math]::Max($allVMJobs.Count - $completedJobs.Count, 0)

                                # Update VM deployment progress
                                Write-Progress `
                                    -Status $("Monitoring VM creation jobs") `
                                    -CurrentOperation $("{0} completed, {1} remaining (running: {2})" -f $completedJobs.Count, $remainingJobs, $runningJobs.Count) `
                                    -PercentComplete $completionPercent `
                                    -Activity $("VM Deployment") `
                                    -ParentId 1 `
                                    -Id 3
                            } `
                        while
                            (
                                $runningJobs.Count -gt 0
                            )

                        # Final progress updates
                        Write-Progress `
                            -Status $("VM Deployment Complete") `
                            -CurrentOperation $("All VMs have been successfully deployed") `
                            -PercentComplete 100 `
                            -Activity $("VM Deployment") `
                            -ParentId 1 `
                            -Id 3

                        Start-Sleep -Seconds 2

                        # Complete all progress bars
                        Write-Progress -Activity $("VM Deployment") -Id 3 -Completed

                        # Update staged progress: VM deployment complete
                        Update-StagedProgress -SectionName 'VMDeployment' -SectionCurrentStep 3 -SectionTotalSteps 3 `
                            -DetailMessage $("")

                        # Analyze failed jobs AFTER monitoring is complete
                        $finalVMJobs = Get-Job
                        $failedJobs = $finalVMJobs | Where-Object { $_.State -eq 'Failed' }

                        if ($failedJobs.Count -gt 0)
                            {
                                foreach ($failedJob in $failedJobs)
                                    {
                                        # Get the job error details from multiple sources for robust error extraction
                                        # IMPORTANT: Check child job streams BEFORE Receive-Job, which can consume them
                                        $errorSources = @()

                                        # Source 1: Child job streams (check BEFORE Receive-Job to avoid data consumption)
                                        if ($failedJob.ChildJobs -and $failedJob.ChildJobs.Count -gt 0)
                                            {
                                                foreach ($childJob in $failedJob.ChildJobs)
                                                    {
                                                        # Error stream - primary source for Azure PowerShell job failures
                                                        if ($childJob.Error -and $childJob.Error.Count -gt 0)
                                                            {
                                                                $errorSources += ($childJob.Error | Out-String)
                                                            }

                                                        # Output stream - Azure may return error info as output objects
                                                        if ($childJob.Output -and $childJob.Output.Count -gt 0)
                                                            {
                                                                $outputString = $childJob.Output | Out-String
                                                                if ($outputString -match 'error|fail|exception|allocat|capacity|quota|constrained')
                                                                    {
                                                                        $errorSources += $outputString
                                                                    }
                                                            }

                                                        # Warning stream - may contain allocation warnings
                                                        if ($childJob.Warning -and $childJob.Warning.Count -gt 0)
                                                            {
                                                                $warningString = $childJob.Warning | Out-String
                                                                if ($warningString.Trim().Length -gt 0)
                                                                    {
                                                                        $errorSources += $warningString
                                                                    }
                                                            }

                                                        # Information stream
                                                        if ($childJob.Information -and $childJob.Information.Count -gt 0)
                                                            {
                                                                $infoString = $childJob.Information | Out-String
                                                                if ($infoString -match 'error|fail|exception|allocat|capacity|quota|constrained')
                                                                    {
                                                                        $errorSources += $infoString
                                                                    }
                                                            }

                                                        # JobStateInfo.Reason (contains the terminating exception - NOT consumed by Receive-Job)
                                                        if ($childJob.JobStateInfo.Reason)
                                                            {
                                                                $errorSources += $childJob.JobStateInfo.Reason.ToString()
                                                                # Walk inner exceptions for full error chain
                                                                $innerEx = $childJob.JobStateInfo.Reason.InnerException
                                                                while ($innerEx)
                                                                    {
                                                                        $errorSources += $innerEx.Message
                                                                        $innerEx = $innerEx.InnerException
                                                                    }
                                                            }

                                                        # Check for nested child jobs (ARM deployment jobs can be hierarchical)
                                                        if ($childJob.ChildJobs -and $childJob.ChildJobs.Count -gt 0)
                                                            {
                                                                foreach ($nestedChild in $childJob.ChildJobs)
                                                                    {
                                                                        if ($nestedChild.Error -and $nestedChild.Error.Count -gt 0)
                                                                            {
                                                                                $errorSources += ($nestedChild.Error | Out-String)
                                                                            }
                                                                        if ($nestedChild.JobStateInfo.Reason)
                                                                            {
                                                                                $errorSources += $nestedChild.JobStateInfo.Reason.ToString()
                                                                            }
                                                                    }
                                                            }
                                                    }
                                            }

                                        # Source 2: Receive-Job output (use -Keep to preserve streams for diagnostics)
                                        $jobErrorRaw = $null
                                        try
                                            {
                                                $jobErrorRaw = Receive-Job -Job $failedJob -Keep -ErrorAction SilentlyContinue 2>&1
                                            }
                                        catch
                                            {
                                                # Receive-Job itself threw - capture this error
                                                $errorSources += $_.Exception.Message
                                            }
                                        $receiveJobString = $jobErrorRaw | Out-String
                                        if ($receiveJobString -and $receiveJobString.Trim().Length -gt 0)
                                            {
                                                $errorSources += $receiveJobString
                                            }

                                        # Source 3: Main job state reason (not affected by Receive-Job)
                                        if ($failedJob.JobStateInfo.Reason)
                                            {
                                                $errorSources += $failedJob.JobStateInfo.Reason.ToString()
                                                if ($failedJob.JobStateInfo.Reason.InnerException)
                                                    {
                                                        $innerEx = $failedJob.JobStateInfo.Reason.InnerException
                                                        while ($innerEx)
                                                            {
                                                                $errorSources += $innerEx.Message
                                                                $innerEx = $innerEx.InnerException
                                                            }
                                                    }
                                            }

                                        # Source 4: StatusMessage property
                                        if ($failedJob.StatusMessage -and $failedJob.StatusMessage.Trim().Length -gt 0)
                                            {
                                                $errorSources += $failedJob.StatusMessage
                                            }

                                        $jobErrorString = ($errorSources | Where-Object { $_ -and $_.Trim().Length -gt 0 }) -join "`n"

                                        # Extract VM details from job mapping
                                        $vmDetails = $vmJobMapping[$failedJob.Id]
                                        $vmName = if ($vmDetails) { $vmDetails.VMName } else { "Unknown VM" }
                                        $vmSku = if ($vmDetails) { $vmDetails.VMSku } else { "Unknown SKU" }
                                        $jobZone = if ($vmDetails -and $vmDetails.Zone) { $vmDetails.Zone } else { $Zone }

                                        # Log raw error output for debugging (truncated for readability)
                                        $rawErrorPreview = if ($jobErrorString.Trim().Length -gt 0) { $jobErrorString.Trim().Substring(0, [Math]::Min(800, $jobErrorString.Trim().Length)) } else { "(no error output captured)" }
                                        Write-Verbose -Message $("  VM '{0}' job error output: {1}" -f $vmName, $rawErrorPreview)

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

                                                # Also look for allocation failure patterns (multiple Azure error codes)
                                                if ($jobErrorString -match "AllocationFailed" -or $jobErrorString -match "allocation.*failed" -or $jobErrorString -match "OverconstrainedAllocationRequest" -or $jobErrorString -match "OverconstrainedZonalAllocationRequest")
                                                    {
                                                        if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = "AllocationFailed" }
                                                        if ([string]::IsNullOrWhiteSpace($errorMessage))
                                                            {
                                                                $errorMessage = "VM allocation failed - no capacity available for this SKU in the target zone/region"
                                                            }
                                                    }

                                                # Categorize the failure type for better reporting
                                                if ($errorCode -match "AllocationFailed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest" -or $errorMessage -match "sufficient capacity|allocation failed|overconstrained")
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
                                                                        $alternativeZones = $skuInfo.LocationInfo.Zones | Where-Object { $_ -ne $jobZone }
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
                                                        $errorLines = $jobErrorString -split "`n" | Where-Object { $_ -match "error|failed|exception|capacity|allocation|quota|constrained" -and $_ -notmatch "^VERBOSE:|^DEBUG:" } | Select-Object -First 3
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
                                                                # Last resort: take first non-empty line from error output
                                                                $firstLine = ($jobErrorString -split "`n" | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1)
                                                                if ($firstLine)
                                                                    {
                                                                        $errorMessage = $firstLine.Trim()
                                                                        if ($errorMessage.Length -gt 300) { $errorMessage = $errorMessage.Substring(0, 300) + "..." }
                                                                    } `
                                                                else
                                                                    {
                                                                        $errorMessage = "Deployment failed — no classifiable error returned by Azure"
                                                                    }
                                                            }
                                                    }
                                            } `
                                        else
                                            {
                                                $errorMessage = "Deployment failed — no error details captured from job"
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
                                            TestedZone = $jobZone
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

                        # Clear all active Write-Progress bars on error (using generic activity names)
                        1..4 | ForEach-Object { Write-Progress -Id $_ -Completed }
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
                Write-Verbose -Message $("Initiating post-deployment validation process for resource verification")
                Update-StagedProgress -SectionName 'Reporting' -SectionCurrentStep 0 -SectionTotalSteps 2 `
                    -DetailMessage $("Validating deployed resources...")
                Write-Host $("`n=== Post-Deployment Validation ===") -ForegroundColor Cyan
                Write-Verbose -Message $("Querying Azure Resource Manager for deployed resources in resource group '{0}'" -f $ResourceGroupName)

                # Get all deployed resources for validation
                $deployedVMs = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                $deployedNICs = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                $deployedVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                # ---------------------------------------------------------------
                # Enrich validation findings for VMs with ProvisioningState='Failed'
                # Query Azure directly for the provisioning error when job-level
                # error extraction returned Unknown or when no finding exists yet
                # (e.g., job completed but VM provisioning failed)
                # ---------------------------------------------------------------
                $failedProvisioningVMs = $deployedVMs | Where-Object { $_.ProvisioningState -eq "Failed" }
                if ($failedProvisioningVMs)
                    {
                        Write-Verbose -Message $("Querying Azure for detailed provisioning errors on {0} failed VM(s)..." -f @($failedProvisioningVMs).Count)
                        foreach ($failedVM in $failedProvisioningVMs)
                            {
                                try
                                    {
                                        $vmStatusDetail = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $failedVM.Name -Status -ErrorAction SilentlyContinue
                                        $provisioningError = $null
                                        $azureErrorCode = ""
                                        $azureErrorMessage = ""

                                        if ($vmStatusDetail -and $vmStatusDetail.Statuses)
                                            {
                                                # Look for the provisioning failure status
                                                $failedStatus = $vmStatusDetail.Statuses | Where-Object { $_.Code -like "ProvisioningState/failed*" -or ($_.Level -and $_.Level.ToString() -eq "Error") }
                                                if ($failedStatus)
                                                    {
                                                        $azureErrorMessage = ($failedStatus | Select-Object -First 1).DisplayStatus
                                                        if (-not $azureErrorMessage) { $azureErrorMessage = ($failedStatus | Select-Object -First 1).Message }
                                                    }
                                            }

                                        # Also check the VM's InstanceView for more details
                                        if ($vmStatusDetail.InstanceView -and $vmStatusDetail.InstanceView.Statuses)
                                            {
                                                $instanceFailedStatus = $vmStatusDetail.InstanceView.Statuses | Where-Object { $_.Code -like "*failed*" -or $_.Code -like "*error*" }
                                                if ($instanceFailedStatus -and -not $azureErrorMessage)
                                                    {
                                                        $azureErrorMessage = ($instanceFailedStatus | Select-Object -First 1).Message
                                                        if (-not $azureErrorMessage) { $azureErrorMessage = ($instanceFailedStatus | Select-Object -First 1).DisplayStatus }
                                                    }
                                            }

                                        # Categorize the Azure error
                                        $azureFailureCategory = "Other"
                                        if ($azureErrorMessage)
                                            {
                                                if ($azureErrorMessage -match "AllocationFailed|allocation.*failed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest|capacity")
                                                    {
                                                        $azureFailureCategory = "No SKU Capacity Available"
                                                        $azureErrorCode = "AllocationFailed"
                                                    } `
                                                elseif ($azureErrorMessage -match "quota|limit")
                                                    {
                                                        $azureFailureCategory = "Quota Exceeded"
                                                        $azureErrorCode = "QuotaExceeded"
                                                    } `
                                                elseif ($azureErrorMessage -match "SKUNotAvailable|NotAvailableForSubscription")
                                                    {
                                                        $azureFailureCategory = "SKU Support"
                                                        $azureErrorCode = "SKUNotAvailable"
                                                    }
                                            }

                                        # Check if there's an existing validation finding for this VM
                                        $existingFinding = $deploymentValidationResults | Where-Object { $_.VMName -eq $failedVM.Name }
                                        if ($existingFinding)
                                            {
                                                # Update existing finding if it was "Unknown" and we now have better info
                                                if ($existingFinding.FailureCategory -eq "Unknown" -and $azureErrorMessage)
                                                    {
                                                        $existingFinding.FailureCategory = $azureFailureCategory
                                                        $existingFinding.ErrorMessage = $azureErrorMessage
                                                        if ($azureErrorCode) { $existingFinding.ErrorCode = $azureErrorCode }
                                                        Write-Verbose -Message $("  Updated validation finding for '{0}' from Azure VM status: {1} - {2}" -f $failedVM.Name, $azureFailureCategory, $azureErrorMessage)
                                                    }
                                            } `
                                        else
                                            {
                                                # No finding exists - create one from Azure VM status
                                                # This covers cases where the job completed but VM provisioning failed
                                                $vmSku = if ($failedVM.HardwareProfile) { $failedVM.HardwareProfile.VmSize } else { "Unknown" }
                                                # Try to extract zone from VM name pattern (e.g. prefix-z2-cnode-01)
                                                $vmTestedZone = $Zone
                                                if ($failedVM.Name -match '-z(\d+)-')
                                                    {
                                                        $vmTestedZone = $Matches[1]
                                                    } `
                                                elseif ($failedVM.Zones -and $failedVM.Zones.Count -gt 0)
                                                    {
                                                        $vmTestedZone = $failedVM.Zones[0]
                                                    }
                                                $deploymentValidationResults += [PSCustomObject]@{
                                                    VMName = $failedVM.Name
                                                    VMSku = $vmSku
                                                    JobName = ""
                                                    ErrorCode = $azureErrorCode
                                                    ErrorMessage = if ($azureErrorMessage) { $azureErrorMessage } else { "VM provisioning failed - check Azure portal Activity Log for details" }
                                                    FailureCategory = if ($azureErrorMessage) { $azureFailureCategory } else { "Unknown" }
                                                    AlternativeZones = @()
                                                    TestedZone = $vmTestedZone
                                                    TestedRegion = $Region
                                                    Timestamp = $StartTime
                                                }
                                                Write-Verbose -Message $("  Created validation finding for '{0}' from Azure VM status: {1}" -f $failedVM.Name, $(if ($azureErrorMessage) { $azureErrorMessage } else { "No detailed status available" }))
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose -Message $("  Could not query Azure VM status for '{0}': {1}" -f $failedVM.Name, $_.Exception.Message)
                                    }
                            }
                    }
                # ---------------------------------------------------------------
                # Azure Activity Log fallback for "Not Found" VMs
                # When VMs were never created (job failed, no VM in Azure),
                # Get-AzVM -Status can't help. Query the Activity Log instead
                # to find the actual ARM deployment error.
                # ---------------------------------------------------------------
                $unknownFindings = @($deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Unknown" })
                if ($unknownFindings.Count -gt 0)
                    {
                        Write-Verbose -Message $("Querying Azure Activity Log for {0} remaining unknown failure(s)..." -f $unknownFindings.Count)
                        try
                            {
                                # Query activity log for failed VM creation operations in this resource group
                                $activityLogStartTime = $StartTime.AddMinutes(-2)
                                $activityLogs = Get-AzLog -ResourceGroupName $ResourceGroupName -StartTime $activityLogStartTime -WarningAction SilentlyContinue -ErrorAction SilentlyContinue |
                                    Where-Object {
                                        $_.Status.Value -eq "Failed" -and
                                        $_.OperationName.Value -like "*Microsoft.Compute/virtualMachines/write*"
                                    }

                                if ($activityLogs)
                                    {
                                        Write-Verbose -Message $("  Found {0} failed VM creation activity log entries" -f @($activityLogs).Count)
                                        foreach ($logEntry in $activityLogs)
                                            {
                                                # Extract VM name from resource ID (last segment)
                                                $logVMName = ""
                                                if ($logEntry.ResourceId)
                                                    {
                                                        $logVMName = ($logEntry.ResourceId -split '/')[-1]
                                                    }

                                                # Match to an unknown finding
                                                $matchingFinding = $unknownFindings | Where-Object { $_.VMName -eq $logVMName }
                                                if ($matchingFinding)
                                                    {
                                                        # Extract error details from the activity log properties
                                                        $logErrorMessage = ""
                                                        $logErrorCode = ""

                                                        # Try Properties.statusMessage (contains JSON error details)
                                                        if ($logEntry.Properties -and $logEntry.Properties.ContainsKey("statusMessage"))
                                                            {
                                                                $statusMsgRaw = $logEntry.Properties["statusMessage"]
                                                                try
                                                                    {
                                                                        $statusMsgObj = $statusMsgRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
                                                                        if ($statusMsgObj.error)
                                                                            {
                                                                                $logErrorCode = $statusMsgObj.error.code
                                                                                $logErrorMessage = $statusMsgObj.error.message
                                                                                # Check for inner error details
                                                                                if ($statusMsgObj.error.details -and $statusMsgObj.error.details.Count -gt 0)
                                                                                    {
                                                                                        $innerDetail = $statusMsgObj.error.details[0]
                                                                                        if ($innerDetail.code) { $logErrorCode = $innerDetail.code }
                                                                                        if ($innerDetail.message) { $logErrorMessage = $innerDetail.message }
                                                                                    }
                                                                            }
                                                                    }
                                                                catch
                                                                    {
                                                                        # Not JSON — use raw string
                                                                        $logErrorMessage = $statusMsgRaw.ToString()
                                                                    }
                                                            }

                                                        # Fallback to SubStatus if statusMessage empty
                                                        if (-not $logErrorMessage -and $logEntry.SubStatus -and $logEntry.SubStatus.Value)
                                                            {
                                                                $logErrorMessage = $logEntry.SubStatus.LocalizedValue
                                                                if (-not $logErrorMessage) { $logErrorMessage = $logEntry.SubStatus.Value }
                                                            }

                                                        # Categorize the error
                                                        $logCategory = "Other"
                                                        if ($logErrorCode -match "AllocationFailed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest" -or
                                                            $logErrorMessage -match "AllocationFailed|allocation.*failed|OverconstrainedAllocationRequest|OverconstrainedZonalAllocationRequest|sufficient capacity|over.?constrained")
                                                            {
                                                                $logCategory = "No SKU Capacity Available"
                                                            } `
                                                        elseif ($logErrorCode -match "Quota|OperationNotAllowed" -or $logErrorMessage -match "quota|limit|exceeded")
                                                            {
                                                                $logCategory = "Quota Exceeded"
                                                            } `
                                                        elseif ($logErrorCode -match "SKUNotAvailable|NotAvailableForSubscription" -or $logErrorMessage -match "sku.*not.*available|not.*available.*subscription")
                                                            {
                                                                $logCategory = "SKU Support"
                                                            }

                                                        # Clean up error message
                                                        if ($logErrorMessage)
                                                            {
                                                                $logErrorMessage = $logErrorMessage -replace "\s*Read more about.*$", ""
                                                                $logErrorMessage = $logErrorMessage -replace "\s*For more information.*$", ""
                                                                if ($logErrorMessage.Length -gt 400) { $logErrorMessage = $logErrorMessage.Substring(0, 400) + "..." }
                                                            }

                                                        # Update the finding
                                                        if ($logErrorMessage)
                                                            {
                                                                $matchingFinding.FailureCategory = $logCategory
                                                                $matchingFinding.ErrorMessage = $logErrorMessage
                                                                if ($logErrorCode) { $matchingFinding.ErrorCode = $logErrorCode }
                                                                Write-Verbose -Message $("  Updated validation finding for '{0}' from Activity Log: [{1}] {2}" -f $logVMName, $logCategory, $logErrorMessage.Substring(0, [Math]::Min(200, $logErrorMessage.Length)))
                                                            } `
                                                        else
                                                            {
                                                                Write-Verbose -Message $("  Activity Log entry found for '{0}' but no error details extracted" -f $logVMName)
                                                            }
                                                    }
                                            }
                                    } `
                                else
                                    {
                                        Write-Verbose -Message $("  No failed VM creation entries found in Activity Log")
                                    }
                            }
                        catch
                            {
                                Write-Verbose -Message $("  Could not query Azure Activity Log: {0}" -f $_.Exception.Message)
                            }
                    }

                $deployedNSG = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                # Create deployment report
                $deploymentReport = @()

                # Build deployment report — iterate per zone for multi-zone deployments
                foreach ($reportZone in $zonesToDeploy)
                    {
                        $reportZonePrefix = if ($isMultiZoneDeploy) { $("-z{0}" -f $reportZone) } else { $("") }
                        $reportZoneLabel = if ($isMultiZoneDeploy) { $(" (Zone {0})" -f $reportZone) } else { $("") }

                # Build CNode deployment report
                for ($cNode = 1; $cNode -le $adjustedCNodeCount; $cNode++)
                    {
                        $expectedVMName = $("{0}{1}-cnode-{2:D2}" -f $ResourceNamePrefix, $reportZonePrefix, $cNode)
                        $expectedNICName = $("{0}{1}-cnode-mgmt-nic-{2:D2}" -f $ResourceNamePrefix, $reportZonePrefix, $cNode)

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
                                                    # Job was submitted but VM was never created — allocation failure, NOT "not found"
                                                    "✗ Allocation Rejected ($($vmValidationFinding.FailureCategory))"
                                                }
                                            else
                                                {
                                                    "✗ Deployment Failed (No Error Captured)"
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
                                                    "✗ Provisioning Failed ($($vmValidationFinding.FailureCategory))"
                                                }
                                            else
                                                {
                                                    "✗ Provisioning Failed (No Error Captured)"
                                                }
                                        } `
                                    else
                                        {
                                            "⚠ Unexpected State: $($vm.ProvisioningState)"
                                        }

                        $deploymentReport +=  [PSCustomObject]@{
                                                                    ResourceType = "CNode"
                                                                    GroupNumber = $("CNode Group{0}" -f $reportZoneLabel)
                                                                    NodeNumber = $cNode
                                                                    VMName = $expectedVMName
                                                                    ExpectedSKU = $cNodeVMSku
                                                                    DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } elseif ($vmValidationFinding) { "Not Allocated" } else { "Not Found" }
                                                                    VMStatus = $vmStatus
                                                                    ProvisioningState = if ($vm) { $vm.ProvisioningState } elseif ($vmValidationFinding) { "Allocation Failed" } else { "Not Found" }
                                                                    NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                    AvailabilitySet = $avSetStatus
                                                                    ValidationFinding = if ($vmValidationFinding) { $vmValidationFinding.ErrorMessage } else { "" }
                                                                    FailureCategory = if ($vmValidationFinding) { $vmValidationFinding.FailureCategory } else { "" }
                                                                    Zone = $reportZone
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
                                $expectedVMName = $("{0}{1}-dnode-{2:D2}" -f $ResourceNamePrefix, $reportZonePrefix, $dNodeNumber)
                                $expectedNICName = $("{0}{1}-dnode-{2:D2}-mgmt-nic" -f $ResourceNamePrefix, $reportZonePrefix, $dNodeNumber)

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
                                                            # Job was submitted but VM was never created — allocation failure, NOT "not found"
                                                            "✗ Allocation Rejected ($($vmValidationFinding.FailureCategory))"
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
                                                            "✗ Provisioning Failed ($($vmValidationFinding.FailureCategory))"
                                                        }
                                                    else
                                                        {
                                                            "✗ Provisioning Failed (No Error Captured)"
                                                        }
                                                } `
                                            else
                                                {
                                                    "⚠ Unexpected State: $($vm.ProvisioningState)"
                                                }

                                $deploymentReport +=   [PSCustomObject]@{
                                                                            ResourceType = "DNode"
                                                                            GroupNumber = $("MNode {0} ({1} TiB){2}" -f $currentMNode, $currentMNodePhysicalSize, $reportZoneLabel)
                                                                            NodeNumber = $dNodeNumber
                                                                            VMName = $expectedVMName
                                                                            ExpectedSKU = $reportMNodeSku
                                                                            DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } elseif ($vmValidationFinding) { "Not Allocated" } else { "Not Found" }
                                                                            VMStatus = $vmStatus
                                                                            ProvisioningState = if ($vm) { $vm.ProvisioningState } elseif ($vmValidationFinding) { "Allocation Failed" } else { "Not Found" }
                                                                            NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                                                                            AvailabilitySet = $avSetStatus
                                                                            ValidationFinding = if ($vmValidationFinding) { $vmValidationFinding.ErrorMessage } else { "" }
                                                                            FailureCategory = if ($vmValidationFinding) { $vmValidationFinding.FailureCategory } else { "" }
                                                                            Zone = $reportZone
                                                                        }
                            }

                        $dNodeStartCount += $reportDNodeCount
                    }

                    } # end foreach ($reportZone in $zonesToDeploy)

                # ===============================================================================
                # Skipped Zone Phantom Report Entries
                # ===============================================================================
                # For each zone excluded by the SKU intersection, append informational VMReport
                # objects so those zones surface as "Not Attempted" rows in the CNode/DNode tables
                # rather than silently disappearing from the report.
                if ($skippedZoneEntries.Count -gt 0)
                    {
                        foreach ($skippedEntry in $skippedZoneEntries)
                            {
                                $skippedZone        = $skippedEntry.Zone
                                $skippedReason      = $skippedEntry.Reason
                                $skippedSkuList     = if ($skippedEntry.UnsupportedSKUs) { $($skippedEntry.UnsupportedSKUs -join $(", ")) } else { $("Unknown") }
                                $skippedZonePrefix  = $("-z{0}" -f $skippedZone)
                                $notAttemptedStatus = $("⚠ Not Attempted — {0} not available in Zone {1}" -f $skippedSkuList, $skippedZone)

                                # Phantom CNode rows
                                if ($adjustedCNodeCount -gt 0 -and $cNodeVMSku)
                                    {
                                        for ($cNode = 1; $cNode -le $adjustedCNodeCount; $cNode++)
                                            {
                                                $deploymentReport += [PSCustomObject]@{
                                                    ResourceType        = $("CNode")
                                                    GroupNumber         = $("CNode Group (Zone {0})" -f $skippedZone)
                                                    NodeNumber          = $cNode
                                                    VMName              = $("{0}{1}-cnode-{2:D2}" -f $ResourceNamePrefix, $skippedZonePrefix, $cNode)
                                                    ExpectedSKU         = $cNodeVMSku
                                                    DeployedSKU         = $("—")
                                                    VMStatus            = $notAttemptedStatus
                                                    ProvisioningState   = $("Not Attempted")
                                                    NICStatus           = $("—")
                                                    AvailabilitySet     = $("—")
                                                    ValidationFinding   = $skippedReason
                                                    FailureCategory     = $("SKU Not In Zone")
                                                    Zone                = $skippedZone
                                                }
                                            }
                                    }

                                # Phantom DNode rows — one group per MNode config per skipped zone
                                $skippedDNodeStart  = 0
                                $skippedMNodeIndex  = 0
                                foreach ($mNode in $mNodeObject)
                                    {
                                        $skippedMNodeIndex++
                                        $reportMNodeSku   = $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix)
                                        $reportDNodeCount = $mNode.dNodeCount
                                        if ($mNodeQuotaAdjustments.ContainsKey($mNode.PhysicalSize))
                                            {
                                                $reportDNodeCount = $mNodeQuotaAdjustments[$mNode.PhysicalSize].AdjustedCount
                                            }

                                        for ($dNode = 1; $dNode -le $reportDNodeCount; $dNode++)
                                            {
                                                $dNodeNumber = $dNode + $skippedDNodeStart
                                                $deploymentReport += [PSCustomObject]@{
                                                    ResourceType        = $("DNode")
                                                    GroupNumber         = $("MNode {0} ({1} TiB) (Zone {2})" -f $skippedMNodeIndex, $mNode.PhysicalSize, $skippedZone)
                                                    NodeNumber          = $dNodeNumber
                                                    VMName              = $("{0}{1}-dnode-{2:D2}" -f $ResourceNamePrefix, $skippedZonePrefix, $dNodeNumber)
                                                    ExpectedSKU         = $reportMNodeSku
                                                    DeployedSKU         = $("—")
                                                    VMStatus            = $notAttemptedStatus
                                                    ProvisioningState   = $("Not Attempted")
                                                    NICStatus           = $("—")
                                                    AvailabilitySet     = $("—")
                                                    ValidationFinding   = $skippedReason
                                                    FailureCategory     = $("SKU Not In Zone")
                                                    Zone                = $skippedZone
                                                }
                                            }
                                        $skippedDNodeStart += $reportDNodeCount
                                    }
                            }
                    }

                # ===============================================================================
                # Report Data Processing and Analysis
                # ===============================================================================
                # Centralized data processing for both console and HTML reports
                # This section calculates all report data once to ensure consistency

                # Infrastructure Summary Data
                $totalExpectedVMs = ($CNodeCount + ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum) * $zonesToDeploy.Count
                $successfulVMs = ($deploymentReport | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                $failedVMs = ($deploymentReport | Where-Object { $_.VMStatus -like "*Failed*" -or $_.VMStatus -like "*Not Allocated*" -or $_.VMStatus -like "*Allocation Rejected*" }).Count
                $nonSuccessfulVMs = $deploymentReport | Where-Object { $_.ProvisioningState -ne "Succeeded" -and $_.ProvisioningState -ne "Not Found" -and $_.ProvisioningState -ne "Allocation Failed" }

                # Zone Alignment Reporting Information
                # Capture zone alignment details for console and HTML reporting
                $zoneAlignmentInfo =    @{
                                            AlignmentPerformed      = $false
                                            AlignmentDisabled       = $DisableZoneAlignment
                                            AlignmentSubscription   = $ZoneAlignmentSubscriptionId
                                            OriginalZone            = $("")
                                            FinalZone               = $Zone
                                            ZoneMappings            = @()
                                            AlignmentReason         = $("Not applicable")
                                        }

                # Determine alignment status and populate reporting information
                if ($ZoneAlignmentSubscriptionId -and $Zone -ne "Zoneless" -and $ZoneAlignmentSubscriptionId -ne $SubscriptionId)
                    {
                        $zoneAlignmentInfo.AlignmentSubscription = $ZoneAlignmentSubscriptionId

                        if ($originalZone)
                            {
                                $zoneAlignmentInfo.AlignmentPerformed = $true
                                $zoneAlignmentInfo.OriginalZone = $originalZone
                                $zoneAlignmentInfo.AlignmentReason = $("Zone alignment applied")
                            } `
                        elseif ($DisableZoneAlignment -and $alignedZone)
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zone alignment available but disabled by parameter")
                                $zoneAlignmentInfo.OriginalZone = $Zone
                            } `
                        elseif ($alignedZone -eq $Zone)
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zone already aligned - no adjustment needed")
                            } `
                        else
                            {
                                $zoneAlignmentInfo.AlignmentReason = $("Zone alignment data unavailable or inconclusive")
                            }
                    } `
                elseif ($Zone -ne "Zoneless" -and $zoneAlignmentResponse)
                    {
                        $zoneAlignmentInfo.AlignmentReason = $("Zone mapping retrieved (subscription self-reference)")
                    } `
                elseif ($Zone -eq "Zoneless")
                    {
                        $zoneAlignmentInfo.AlignmentReason = $("Zoneless deployment - alignment not applicable")
                    } `
                else
                    {
                        $zoneAlignmentInfo.AlignmentReason = $("No alignment subscription specified")
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

                # SKU Support Analysis Data
                $skuSupportData = @()

                # CNode SKU Support Analysis
                if($cNodeObject)
                    {
                        $cNodeSupportedSKU = $locationSupportedSKU | Where-Object { $_.Name -eq $cNodeVMSku }
                        $cNodevCPUCount = $cNodeObject.vCPU * $CNodeCount
                        $cNodeSKUFamilyQuota = $computeQuotaUsage | Where-Object { $_.Name.LocalizedValue -eq $cNodeObject.QuotaFamily }

                        # Check if quota family exists in Azure
                        if (-not $cNodeSKUFamilyQuota)
                            {
                                Write-Verbose -Message $("WARNING: Quota family '{0}' for CNode SKU '{1}' not found in Azure quota data. This SKU family may be in preview or not yet registered in the quota system." -f $cNodeObject.QuotaFamily, $cNodeVMSku)
                            }

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
                            QuotaFamilyName = $cNodeObject.QuotaFamily
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

                                # Check if quota family exists in Azure
                                if (-not $mNodeSKUFamilyQuota)
                                    {
                                        Write-Verbose -Message $("WARNING: Quota family '{0}' for MNode SKU '{1}' not found in Azure quota data. This SKU family may be in preview or not yet registered in the quota system." -f $mNodeType.QuotaFamily, $mNodeSkuName)
                                    }

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
                                    QuotaFamilyName = $mNodeType.QuotaFamily
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
                $totalResourcesCreated = $deployedVMs.Count + $deployedNICs.Count + $(if($deployedPPG){@($deployedPPG).Count}else{0}) + $deployedAvailabilitySets.Count + $(if($deployedVNet){1}else{0}) + $(if($deployedNSG){1}else{0})

                # Deployment Validation Findings Analysis
                # ---------------------------------------------------------------
                # Smart failure reclassification: If SKU quota is sufficient AND
                # the SKU is supported in the target zone, but deployment still
                # failed with Unknown/Other, it's almost certainly a capacity
                # allocation issue. Azure often doesn't return meaningful errors
                # from job streams for allocation failures.
                # ---------------------------------------------------------------
                if ($deploymentValidationResults.Count -gt 0)
                    {
                        # Build lookup tables for SKU quota sufficiency and available zones
                        $skuQuotaSufficient = @{}
                        $skuAvailableZones = @{}

                        foreach ($skuData in $skuSupportData)
                            {
                                $skuQuotaSufficient[$skuData.SKUName] = $false
                                $skuAvailableZones[$skuData.SKUName] = if ($skuData.AvailableZones) { @($skuData.AvailableZones) } else { @() }

                                # Check family quota sufficiency
                                if ($skuData.SKUFamilyQuota)
                                    {
                                        $availableQuota = $skuData.SKUFamilyQuota.Limit - $skuData.SKUFamilyQuota.CurrentValue
                                        $skuQuotaSufficient[$skuData.SKUName] = ($availableQuota -ge $skuData.vCPUCount)
                                    }
                            }

                        foreach ($finding in $deploymentValidationResults)
                            {
                                if ($finding.FailureCategory -in @("Unknown", "Other"))
                                    {
                                        $sku = $finding.VMSku
                                        $vmZone = $finding.TestedZone
                                        $quotaOk = $skuQuotaSufficient.ContainsKey($sku) -and $skuQuotaSufficient[$sku]
                                        # Check zone support for the SPECIFIC zone this VM was deployed to
                                        $zoneOk = $skuAvailableZones.ContainsKey($sku) -and ($skuAvailableZones[$sku] -contains "$vmZone")

                                        $originalCategory = $finding.FailureCategory
                                        if ($quotaOk -and $zoneOk)
                                            {
                                                # SKU is supported in this zone, quota is available, but VM still failed — capacity allocation issue
                                                $finding.FailureCategory = "No SKU Capacity Available"
                                                if ([string]::IsNullOrWhiteSpace($finding.ErrorCode)) { $finding.ErrorCode = "AllocationFailed" }
                                                $finding.ErrorMessage = "Unable to allocate capacity in zone $vmZone — SKU is supported and quota is sufficient, but Azure could not fulfill the allocation request."
                                                Write-Verbose -Message $("  Reclassified '{0}' (zone {1}) from {2} → No SKU Capacity Available (quota sufficient, SKU zone-supported)" -f $finding.VMName, $vmZone, $originalCategory)
                                            } `
                                        elseif ($quotaOk -and -not $zoneOk)
                                            {
                                                $finding.FailureCategory = "SKU Support"
                                                $finding.ErrorMessage = "SKU $sku is not supported in zone $vmZone"
                                                Write-Verbose -Message $("  Reclassified '{0}' (zone {1}) from {2} → SKU Support" -f $finding.VMName, $vmZone, $originalCategory)
                                            } `
                                        elseif (-not $quotaOk -and $zoneOk)
                                            {
                                                $finding.FailureCategory = "Quota Exceeded"
                                                $finding.ErrorMessage = "Insufficient quota for the $sku SKU family"
                                                Write-Verbose -Message $("  Reclassified '{0}' (zone {1}) from {2} → Quota Exceeded" -f $finding.VMName, $vmZone, $originalCategory)
                                            }
                                        # If both quota and zone support are unknown/unresolvable, leave as-is
                                    }
                            }

                        # Also update the deployment report entries to reflect reclassified findings
                        foreach ($reportEntry in $deploymentReport)
                            {
                                if ($reportEntry.VMStatus -like "*Unknown*" -or $reportEntry.VMStatus -like "*Other*" -or $reportEntry.FailureCategory -in @("Unknown", "Other"))
                                    {
                                        $matchingFinding = $deploymentValidationResults | Where-Object { $_.VMName -eq $reportEntry.VMName } | Select-Object -First 1
                                        if ($matchingFinding -and $matchingFinding.FailureCategory -notin @("Unknown", "Other"))
                                            {
                                                # Update the VMStatus display text — use "Not Allocated" when job ran but VM doesn't exist
                                                if ($reportEntry.VMStatus -like "*Not Allocated*" -or $reportEntry.VMStatus -like "*Deployment Failed*" -or $reportEntry.VMStatus -like "*Allocation Rejected*")
                                                    {
                                                        $reportEntry.VMStatus = $("✗ Allocation Rejected ({0})" -f $matchingFinding.FailureCategory)
                                                        $reportEntry.DeployedSKU = "Not Allocated"
                                                        $reportEntry.ProvisioningState = "Allocation Failed"
                                                    } `
                                                elseif ($reportEntry.VMStatus -like "*Failed*")
                                                    {
                                                        $reportEntry.VMStatus = $("✗ Provisioning Failed ({0})" -f $matchingFinding.FailureCategory)
                                                    }
                                                $reportEntry.FailureCategory = $matchingFinding.FailureCategory
                                                $reportEntry.ValidationFinding = $matchingFinding.ErrorMessage
                                            }
                                    }
                            }
                    }

                $validationFindings = @{
                    NoCapacityIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "No SKU Capacity Available" }
                    QuotaIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Quota Exceeded" }
                    SKUSupportIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "SKU Support" }
                    OtherIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Other" }
                    UnknownIssues = $deploymentValidationResults | Where-Object { $_.FailureCategory -eq "Unknown" }
                }

                # Silk Component Summary Data
                $cNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq $("CNode") }
                $successfulCNodes = ($cNodeReport | Where-Object { $_.VMStatus -eq $("✓ Deployed") }).Count
                $cNodeSummaryLabel = if ($cNodeReport)
                                        {
                                            $cNodeReport[0].ExpectedSKU
                                        } `
                                    else
                                        {
                                            $("Unknown")
                                        }

                $dNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq $("DNode") }
                $mNodeGroups = $dNodeReport | Group-Object GroupNumber

                $silkSummary = @()

                if ($CNodeCount)
                    {
                        $expectedCNodeTotal = $CNodeCount * $zonesToDeploy.Count
                        $silkSummary += [PSCustomObject]@{
                                            Component       = $("CNode")
                                            DeployedCount   = $successfulCNodes
                                            ExpectedCount   = $expectedCNodeTotal
                                            SKU             = $cNodeSummaryLabel
                                            Status          = if ($successfulCNodes -eq $expectedCNodeTotal) { $("✓ Complete") } elseif ($successfulCNodes -eq 0) { $("✗ Failed") } else { $("⚠ Partial") }
                                        }
                    }

                if ($mNodeGroups.Count -gt 0)
                    {
                        foreach ($group in $mNodeGroups)
                            {
                                $groupSuccessful = ($group.Group | Where-Object { $_.VMStatus -eq $("✓ Deployed") }).Count
                                $groupExpected = $group.Group.Count
                                $groupSku = $group.Group[0].ExpectedSKU
                                $groupName = $group.Name.Replace($("MNode "), $("M")).Replace($(" TiB)"), $("TB)"))

                                $silkSummary += [PSCustomObject]@{
                                                    Component       = $groupName
                                                    DeployedCount   = $groupSuccessful
                                                    ExpectedCount   = $groupExpected
                                                    SKU             = $groupSku
                                                    Status          = if ($groupSuccessful -eq $groupExpected) { $("✓ Complete") } elseif ($groupSuccessful -eq 0) { $("✗ Failed") } else { $("⚠ Partial") }
                                                }
                            }
                    }

                # ===============================================================================
                # Populate Report Data Object
                # ===============================================================================
                # Wire up all collected data into the centralized report object before
                # rendering console and HTML reports

                # Configuration
                $reportData.Configuration.SubscriptionId        = $SubscriptionId
                $reportData.Configuration.ResourceGroupName     = $ResourceGroupName
                $reportData.Configuration.Region                = $Region
                $reportData.Configuration.Zone                  = $Zone
                $reportData.Metadata.ReportMode                 = if ($TestAllZones) { $("Deployment + Multi-Zone") } else { $("Deployment") }
                $reportData.Configuration.CNodeSKU              = if ($cNodeObject) { $cNodeVMSku } else { $("") }
                $reportData.Configuration.CNodeFriendlyName     = if ($cNodeObject) { $cNodeObject.cNodeFriendlyName } else { $("") }
                $reportData.Configuration.CNodeCount            = $CNodeCount
                $reportData.Configuration.CNodeCountAdjusted    = $adjustedCNodeCount
                $reportData.Configuration.MNodeSizes            = if ($MNodeSize) { @($MNodeSize) } else { @() }
                $reportData.Configuration.MNodeSKUs             = if ($mNodeObjectUnique) { @($mNodeObjectUnique) } else { @() }
                $reportData.Configuration.IPRange               = $IPRangeCIDR
                $reportData.Configuration.ResourceNamePrefix    = $ResourceNamePrefix
                $reportData.Configuration.UseExistingInfra      = [bool]$UseExistingVNet
                $reportData.Configuration.ZoneAlignmentSubId    = if ($ZoneAlignmentSubscriptionId) { $ZoneAlignmentSubscriptionId } else { $("") }
                $reportData.Configuration.DisableZoneAlignment  = $DisableZoneAlignment
                $reportData.Configuration.DisableCleanup        = $DisableCleanup
                $reportData.Configuration.NoHTMLReport          = $NoHTMLReport

                # SKU Support raw data
                $reportData.SKUSupport.RawRegionSKUs            = $locationSupportedSKU

                # Quota raw data
                $reportData.QuotaAnalysis.RawQuotaData          = $computeQuotaUsage

                # SKU Support and Quota analysis arrays
                $reportData.SKUSupportData                      = $skuSupportData
                $reportData.QuotaAnalysisData                   = $quotaAnalysisData

                # Deployment data
                $reportData.Deployment.Attempted                = $true
                $reportData.Deployment.TotalExpectedVMs         = $totalExpectedVMs
                $reportData.Deployment.TotalDeployedVMs         = $successfulVMs
                $reportData.Deployment.TotalFailedVMs           = $failedVMs
                $reportData.Deployment.VMReport                 = $deploymentReport
                $reportData.Deployment.SkippedZones             = if ($skippedZoneEntries) { $skippedZoneEntries } else { @() }
                $reportData.Deployment.ValidationFindings       = if ($deploymentValidationResults) { $deploymentValidationResults } else { @() }
                $reportData.Deployment.FindingsAnalysis         = [PSCustomObject]@{
                                                                        NoCapacityIssues    = $validationFindings.NoCapacityIssues
                                                                        QuotaIssues         = $validationFindings.QuotaIssues
                                                                        SKUSupportIssues    = $validationFindings.SKUSupportIssues
                                                                        OtherIssues         = $validationFindings.OtherIssues
                                                                        UnknownIssues       = $validationFindings.UnknownIssues
                                                                    }

                # Infrastructure
                $reportData.Deployment.Infrastructure.VNetCreated       = [bool]$deployedVNet
                $reportData.Deployment.Infrastructure.VNetName          = if ($deployedVNet) { $deployedVNet.Name } else { $("") }
                $reportData.Deployment.Infrastructure.VNetAddressSpace  = if ($deployedVNet) { ($deployedVNet.AddressSpace.AddressPrefixes -join $(", ")) } else { $("") }
                $reportData.Deployment.Infrastructure.NSGCreated        = [bool]$deployedNSG
                $reportData.Deployment.Infrastructure.NSGName           = if ($deployedNSG) { $deployedNSG.Name } else { $("") }
                $reportData.Deployment.Infrastructure.PPGsCreated       = if ($deployedPPG) { @($deployedPPG) } else { @() }
                $reportData.Deployment.Infrastructure.AvSetsCreated     = if ($deployedAvailabilitySets) { @($deployedAvailabilitySets) } else { @() }
                $reportData.Deployment.Infrastructure.PPGsReferenced    = if ($existingProximityPlacementGroup) { @($existingProximityPlacementGroup) } else { @() }
                $reportData.Deployment.Infrastructure.AvSetsReferenced  = if ($existingAvailabilitySet) { @($existingAvailabilitySet) } else { @() }
                $reportData.Deployment.Infrastructure.NICsCreated       = $deployedNICs.Count
                $reportData.Deployment.Infrastructure.TotalResources    = $totalResourcesCreated

                # Silk Component Summary
                $reportData.SilkSummary                                 = $silkSummary

                # Zone Alignment
                $reportData.EnvironmentValidation.ZoneAlignment.AlignmentPerformed  = $zoneAlignmentInfo.AlignmentPerformed
                $reportData.EnvironmentValidation.ZoneAlignment.AlignmentDisabled   = $zoneAlignmentInfo.AlignmentDisabled
                $reportData.EnvironmentValidation.ZoneAlignment.AlignmentSubId      = if ($zoneAlignmentInfo.AlignmentSubscription) { $zoneAlignmentInfo.AlignmentSubscription } else { $("") }
                $reportData.EnvironmentValidation.ZoneAlignment.OriginalZone        = $zoneAlignmentInfo.OriginalZone
                $reportData.EnvironmentValidation.ZoneAlignment.FinalZone           = $zoneAlignmentInfo.FinalZone
                $reportData.EnvironmentValidation.ZoneAlignment.ZoneMappings        = $zoneAlignmentInfo.ZoneMappings
                $reportData.EnvironmentValidation.ZoneAlignment.Reason              = $zoneAlignmentInfo.AlignmentReason

                # SKU Family Testing results (always populated from begin block analysis)
                $reportData.SKUFamilyTesting.Results = if ($skuFamilyResults) { @($skuFamilyResults) } else { @() }

                # Timing
                $reportData.Metadata.EndTime                    = Get-Date
                $reportData.Metadata.Duration                   = $DeploymentTimespan

                # ===============================================================================
                # Console Report (from centralized report data object)
                # ===============================================================================
                Write-SilkConsoleReport -ReportData $reportData

                # ===============================================================================
                # Console Output Buffer Management
                # ===============================================================================
                # Add buffer space to prevent console output overlap in Azure Cloud Shell
                Write-Host $("")
                Write-Host $("")
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

                        Update-StagedProgress -SectionName 'Reporting' -SectionCurrentStep 1 -SectionTotalSteps 2 `
                            -DetailMessage $("Generating HTML report...")

                        Write-SilkHTMLReport -ReportData $reportData -OutputPath $ReportFullPath

                        # ===============================================================================
                        # Post-HTML Generation Buffer
                        # ===============================================================================
                        # Final console stabilization for clean output

                        Write-Host $("")
                        Start-Sleep -Milliseconds 200
                        [System.Console]::Out.Flush()
                    }
                else
                    {
                        Update-StagedProgress -SectionName 'Reporting' -SectionCurrentStep 1 -SectionTotalSteps 2 `
                            -DetailMessage $("HTML report generation skipped")
                    }

                Start-Sleep -Seconds 2

                Write-Verbose -Message $("Deployment completed. Resources have been created in the resource group: {0}." -f $ResourceGroupName)

                Update-StagedProgress -SectionName 'Reporting' -SectionCurrentStep 2 -SectionTotalSteps 2 `
                    -DetailMessage $("Reporting complete")
                Write-Progress -Id 2 -Completed
                Write-Progress -Id 1 -Completed

                if (!$DisableCleanup)
                    {
                        # Build the cleanup-only command so the user can copy it if they Ctrl+C
                        $cleanupCmd = $("Test-SilkResourceDeployment -SubscriptionId '{0}' -ResourceGroupName '{1}' -RunCleanupOnly" -f $SubscriptionId, $ResourceGroupName)
                        if ($ResourceNamePrefix -ne $("sdp-test"))
                            {
                                $cleanupCmd = $("{0} -ResourceNamePrefix '{1}'" -f $cleanupCmd, $ResourceNamePrefix)
                            }

                        Write-Host $("")
                        Write-Host $("If you need to run cleanup manually later, use the following command:") -ForegroundColor Yellow
                        Write-Host $("")
                        Write-Host $("  {0}" -f $cleanupCmd) -ForegroundColor Cyan
                        Write-Host $("")
                        Write-Host $("Cleanup will begin automatically in 60 seconds.") -ForegroundColor Yellow
                        Write-Host $("Press [Enter] to proceed immediately, or [Ctrl+C] to exit without cleanup.") -ForegroundColor Yellow
                        Write-Host $("")

                        # 60-second countdown with keypress detection
                        $countdownSeconds = 60
                        $userProceeded = $false

                        for ($i = $countdownSeconds; $i -gt 0; $i--)
                            {
                                # Overwrite the same line with updated countdown
                                Write-Host $("`r  Cleanup begins in {0,2} seconds...  " -f $i) -NoNewline -ForegroundColor DarkGray

                                # Poll for Enter keypress once per second (10 checks x 100ms)
                                for ($poll = 0; $poll -lt 10; $poll++)
                                    {
                                        if ([Console]::KeyAvailable)
                                            {
                                                $key = [Console]::ReadKey($true)
                                                if ($key.Key -eq [ConsoleKey]::Enter)
                                                    {
                                                        $userProceeded = $true
                                                        break
                                                    }
                                            }
                                        Start-Sleep -Milliseconds 100
                                    }

                                if ($userProceeded)
                                    {
                                        break
                                    }
                            }

                        # Clear the countdown line and confirm
                        Write-Host $("`r{0}`r" -f $(" " * 60)) -NoNewline
                        if ($userProceeded)
                            {
                                Write-Host $("Proceeding with cleanup...") -ForegroundColor Green
                            }
                        else
                            {
                                Write-Host $("Countdown complete. Proceeding with cleanup...") -ForegroundColor Green
                            }
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

                # Ensure staged progress bars are cleared before cleanup progress begins
                Write-Progress -Id 2 -Completed
                Write-Progress -Id 1 -Completed

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
                                Write-Progress -Id 5 -Activity $("Cleaning up test resources...") -Status $("Removing network interfaces...") -PercentComplete 55

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

