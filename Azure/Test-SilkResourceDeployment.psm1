

function Test-SilkResourceDeployment
    {

        <#
            .SYNOPSIS
                Checks availability of Azure resources for a Silk Infrastructure Deployment.

            .DESCRIPTION
                Deploys sets of Azure resources to confirm the required SKUs will be available to deploy Silk infrastructure components.

            .PARAMETER  ParameterA
                The description of the ParameterA parameter.

            .PARAMETER  ParameterB
                The description of the ParameterB parameter.

            .EXAMPLE
                PS C:> Get-Something -ParameterA 'One value' -ParameterB 32

            .EXAMPLE
                PS C:> Get-Something 'One value' 32

            .INPUTS
                System.String,System.Int32

            .OUTPUTS
                System.String

            .NOTES
                Additional information about the function go here.

            .LINK
                about_functions_advanced

            .LINK
                about_comment_based_help
        #>

        [CmdletBinding  ()]
        param
            (
                # Subscription ID deployment should be run against.
                # will override json imported values
                [Parameter( ParameterSetName = 'ConfigurationJson', Mandatory = $false )]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false )]
                [Parameter(ParameterSetName = "Cleanup Only", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [string]
                $SubscriptionId,

                # Resource Group ID deployment should be run against.
                # will override json imported values
                [Parameter( ParameterSetName = 'ConfigurationJson', Mandatory = $false )]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false )]
                [Parameter(ParameterSetName = "Cleanup Only", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceGroupName,

                # Location to deploy resources
                # will override json imported values
                [Parameter( ParameterSetName = 'ConfigurationJson', Mandatory = $false )]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false )]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter(ParameterSetName = "Cleanup Only", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("asia", "asiapacific", "australia", "australiacentral", "australiacentral2", "australiaeast", "australiasoutheast", "austriaeast", "brazil", "brazilsouth", "brazilsoutheast", "canada", "canadacentral", "canadaeast", "centralindia", "centralus", "centraluseuap", "chilecentral", "eastasia", "eastus", "eastus2", "eastus2euap", "europe", "france", "francecentral", "francesouth", "germany", "germanynorth", "germanywestcentral", "global", "india", "indonesiacentral", "israel", "israelcentral", "italy", "italynorth", "japan", "japaneast", "japanwest", "korea", "koreacentral", "koreasouth", "malaysiawest", "mexicocentral", "newzealand", "newzealandnorth", "northcentralus", "northeurope", "norway", "norwayeast", "norwaywest", "poland", "polandcentral", "qatar", "qatarcentral", "singapore", "southafrica", "southafricanorth", "southafricawest", "southcentralus", "southeastasia", "southindia", "spaincentral", "sweden", "swedencentral", "switzerland", "switzerlandnorth", "switzerlandwest", "uaecentral", "uaenorth", "uksouth", "ukwest", "unitedstates", "westcentralus", "westeurope", "westindia", "westus", "westus2", "westus3")]
                [string]
                $Region,

                # zone of region to deploy to
                # will override json imported values
                [Parameter( ParameterSetName = 'ConfigurationJson', Mandatory = $false )]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $false )]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter(ParameterSetName = "Cleanup Only", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Lsv3", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Laosv4", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode by SKU", Mandatory = $true )]
                [ValidateNotNullOrEmpty()]
                [ValidateSet("1", "2", "3", "Zoneless")]
                [string]
                $Zone,

                # Ignore all above parameters input through JSON import instead
                [Parameter(ParameterSetName = "Cleanup Only ConfigurationJson", Mandatory = $true )]
                [Parameter( ParameterSetName = 'ConfigurationJson', Mandatory = $true )]
                [string]
                $ConfigurationJson,

                # define cnode sku based off friendly description, generally Increased_Logical_Capacity is default and generally No_Increased_Logical_Capacity is not used
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3")]
                [ValidateSet("Increased_Logical_Capacity", "Read_Cache_Enabled", "No_Increased_Logical_Capacity")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4")]
                [ValidateSet("Increased_Logical_Capacity", "Read_Cache_Enabled", "No_Increased_Logical_Capacity")]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU")]
                [ValidateSet("Increased_Logical_Capacity", "Read_Cache_Enabled", "No_Increased_Logical_Capacity")]
                [string]
                $CNodeFriendlyName,

                # define cnode sku based off SKU, generally Standard_E64s_v5 is default and generally Standard_D64s_v5 is not used
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3")]
                [ValidateSet("Standard_D64s_v5", "Standard_L64s_v3", "Standard_E64s_v5")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4")]
                [ValidateSet("Standard_D64s_v5", "Standard_L64s_v3", "Standard_E64s_v5")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU")]
                [ValidateSet("Standard_E64s_v5", "Standard_L64s_v3", "Standard_D64s_v5")]
                [string]
                $CNodeSku,

                # number of cnode sku instances to deploy minimum of 2 and maximum of 8
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(2,8)]
                [int]
                $CNodeCount,

                # identify Lsv3 mnode type by size
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Lsv3")]
                [ValidateSet("19.5", "39.1", "78.2")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Lsv3")]
                [ValidateSet("19.5", "39.1", "78.2")]
                [string[]]
                $MnodeSizeLsv3,

                # identify Lsv4 mnode type by size
                [Parameter(ParameterSetName = "Friendly Cnode Mnode Laosv4")]
                [ValidateSet("14.67", "29.34", "58.67", "88.01", "117.35")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode Laosv4")]
                [ValidateSet("14.67", "29.34", "58.67", "88.01", "117.35")]
                [string[]]
                $MnodeSizeLaosv4,

                # identify mnode type and size by sku, Lsv3 or Lsv4
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU")]
                [ValidateSet("Standard_L2aos_v4", "Standard_L4aos_v4", "Standard_L8aos_v4", "Standard_L12aos_v4", "Standard_L16aos_v4", "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3")]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU")]
                [ValidateSet("Standard_L2aos_v4", "Standard_L4aos_v4", "Standard_L8aos_v4", "Standard_L12aos_v4", "Standard_L16aos_v4", "Standard_L8s_v3", "Standard_L16s_v3", "Standard_L32s_v3")]
                [string[]]
                $MNodeSku,

                # number of mnode instances to determine how many dnode sku vms to deploy, minimum of 1 and maximum of 4
                [Parameter(ParameterSetName = "Friendly Cnode Mnode by SKU")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(1, 4)]
                [Parameter(ParameterSetName = "Cnode by SKU Mnode by SKU")]
                [ValidateNotNullOrEmpty()]
                [ValidateRange(1, 4)]
                [int]
                $MNodeCount,

                # switch to disable cleanup at the end
                [Parameter( ParameterSetName = 'ConfigurationJson' )]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Lsv3" )]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode Laosv4" )]
                [Parameter( ParameterSetName = "Friendly Cnode Mnode by SKU" )]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Lsv3" )]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode Laosv4" )]
                [Parameter( ParameterSetName = "Cnode by SKU Mnode by SKU" )]
                [Switch]
                $DisableCleanup,

                # switch to only run the cleanup
                [Parameter(ParameterSetName = "Cleanup Only")]
                [Switch]
                $RunCleanupOnly,

                # ip range cidr used both for vnet ip scope and subnet range
                # will override json imported values
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string]
                $IPRangeCIDR,

                # Azure image Offer to use for the deployment.
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageOffer = "0001-com-ubuntu-server-jammy",

                # Azure image Publisher to use for the deployment.
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImagePublisher = "Canonical",

                # Azure image SKU to use for the deployment will default to the latest available for the specified publisher and offer.
                [Parameter()]
                [string]
                $VMImageSku,

                # Azure image version to use for the deployment will default to the latest available for the specified publisher, offer, and SKU.
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string]
                $VMImageVersion = "latest",

                # # cnode core count per VM
                # [Parameter()]
                # [int]
                # $CNodeCoreCount,

                # # mnode core count per VM
                # [Parameter()]
                # [int]
                # $MNodeCoreCount,

                # naming variable used when generating resource names
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string]
                $ResourceNamePrefix = "sdp-test",

                # credential object to pass during vm creation
                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [pscredential]
                $VMInstanceCredential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "azureuser", (ConvertTo-SecureString 'sdpD3ploym3ntT3$t' -AsPlainText -Force))
            )

        # This block is used to provide optional one-time pre-processing for the function.
        begin
            {

                # initialize the c node size object with sku details
                # $cNodeSizeObject = @(
                #                         [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 64; vmSkuSuffix = "v5"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                #                         [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 64; vmSkuSuffix = "v3"; cNodeFriendlyName = "Read_Cache_Enabled"};
                #                         [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 64; vmSkuSuffix = "v5"; cNodeFriendlyName = "Increased_Logical_Capacity"}
                #                     )

                $cNodeSizeObject = @(
                                        [pscustomobject]@{vmSkuPrefix = "Standard_D"; vCPU = 2; vmSkuSuffix = "s_v5"; cNodeFriendlyName = "No_Increased_Logical_Capacity"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_L"; vCPU = 2; vmSkuSuffix = "s_v3"; cNodeFriendlyName = "Read_Cache_Enabled"};
                                        [pscustomobject]@{vmSkuPrefix = "Standard_E"; vCPU = 2; vmSkuSuffix = "s_v5"; cNodeFriendlyName = "Increased_Logical_Capacity"}
                                    )

                # Initialize the mNodeSizeObject array with mnode VM SKU details
                $mNodeSizeObject = @(
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01};
                                        [pscustomobject]@{dNodeCount = 1; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35}
                                    )

                # $mNodeSizeObject = @(
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01};
                #                         [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35}
                #                     )

                # ensure that the Az module is imported and the user is logged in
                try
                    {
                        # if (-not (Get-Module -Name Az -ListAvailable))
                        #     {
                        #         Write-Error "Az module is not installed. Please install the Az module to use this function."
                        #         return
                        #     }

                        # Import-Module Az -Force

                        if (-not (Get-AzContext))
                            {
                                Write-Error "You are not logged in to Azure. Please log in using Connect-AzAccount."
                                return
                            }
                    }
                catch
                    {
                        Write-Error "An error occurred while importing the Az module or checking the Azure context: $_"
                        returnWorkspace 1
                    }

                # check if $configurationJson is set, if so, load the configuration from the JSON file
                if ($ConfigurationJson)
                    {
                        # Load the configuration from the JSON file
                        $ConfigImport = Get-Content -Path $ConfigurationJson | ConvertFrom-Json

                        # if subscription id is not set, use the json
                        if (!$SubscriptionId)
                            {
                                $SubscriptionId = $ConfigImport.azure_environment.subscription_id
                            } `
                        else
                            {
                                Write-Warning -Message "Subscription ID parameter is set to '$SubscriptionId', ignoring subscription ID in JSON configuration."
                            }

                        # if resource group name is not set, use the json
                        if (!$ResourceGroupName)
                            {
                                $ResourceGroupName = $ConfigImport.azure_environment.resource_group_name
                            } `
                        else
                            {
                                Write-Warning -Message "Resource Group Name parameter is set to '$ResourceGroupName', ignoring resource group name in JSON configuration."
                            }

                        # if region is not set, use the json
                        if(!$Region)
                            {
                                $Region = $ConfigImport.azure_environment.region
                            } `
                        else
                            {
                                Write-Warning -Message "Region parameter is set to '$Region', ignoring region in JSON configuration."
                            }

                        # if zone is not set, use the json
                        if(!$Zone)
                            {
                                $Zone = $ConfigImport.azure_environment.zone
                            } `
                        else
                            {
                                Write-Warning -Message "Zone parameter is set to '$Zone', ignoring zone in JSON configuration."
                            }

                        # identify cnode count
                        $CNodeCount = $ConfigImport.sdp.c_node_count


                        # identify mnode configuration
                        $MNodeCount = $ConfigImport.sdp.m_node_count
                    }


                # do not run the rest of begin block if cleanup Only
                if($RunCleanupOnly)
                    {
                        return
                    }


                # set IP space for the vnet and subnet if not provided by importing from json or using generic value
                if (!$IPRangeCIDR -and $ConfigImport -and $ConfigImport.cluster.ip_range)
                    {
                        $IPRangeCIDR = $ConfigImport.cluster.ip_range
                    }
                elseif (!$IPRangeCIDR -and !$ConfigImport.cluster.ip_range)
                    {
                        $IPRangeCIDR = "10.0.0.0/24"
                    }

                # identify cnode sku details
                if($CNodeCount -and ($CNodeFriendlyName -eq "Read_Cache_Enabled" -or $ConfigImport.sdp.read_cache_enabled))
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "Read_Cache_Enabled" }
                    } `
                elseif($CNodeCount -and ($CNodeFriendlyName -eq "Increased_Logical_Capacity" -or $ConfigImport.sdp.increased_logical_capacity))
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "Increased_Logical_Capacity" }
                    } `
                elseif($CNodeCount -and $CNodeFriendlyName -eq "No_Increased_Logical_Capacity")
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $_.cNodeFriendlyName -eq "No_Increased_Logical_Capacity" }
                    } `
                elseif ($CNodeCount -and $CNodeSku)
                    {
                        $cNodeObject = $cNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $CNodeSku }
                    } `
                else
                    {
                        Write-Error "CNode configuration is not valid. Please specify either CNodeFriendlyName with Friendly parameter or CNodeSku with CNodebySKU parameter set."
                        return
                    }

                # Set MNodeSize from parameter values when not using JSON configuration
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

                # initialize mnode object list to hold configuration for each mnode type
                $mNodeObject = New-Object -TypeName 'System.Collections.Generic.List[PSCustomObject]'

                # identify mnode sku details
                if($MNodeSize)
                    {
                        $MNodeSize | % { $nodeSize = $_; $mNodeObject.Add($($MNodeSizeObject | Where-Object { $_.PhysicalSize -eq $nodeSize })) }
                    } `
                elseif ($MNodeCount -and $MNodeSku)
                    {
                        for ($node = 1; $node -le $MNodeCount; $node++)
                            {
                                $mNodeObject.Add($($MNodeSizeObject | Where-Object { $("{0}{1}{2}" -f $_.vmSkuPrefix, $_.vCPU, $_.vmSkuSuffix) -eq $MNodeSku }))
                            }
                    } `
                else
                    {
                        Write-Error "MNode configuration is not valid. Please specify either MNodeSize with Friendly parameter or MNodeSku with MNodebySKU parameter set."
                        return
                    }

                # identify the vm image sku
                if (-not $VMImageSku)
                    {
                        # Get the latest available SKU for the specified publisher and offer
                        try
                            {
                                $availableSkus = Get-AzVMImageSku -Location $Region -PublisherName $VMImagePublisher -Offer $VMImageOffer -ErrorAction Stop

                                if ($availableSkus)
                                    {
                                        # Prefer Gen2 SKUs if available, otherwise use the latest available
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
                                    } `
                                else
                                    {
                                        Write-Warning "No SKUs found for offer '$VMImageOffer' from publisher '$VMImagePublisher' in region '$Region'. Trying alternative Ubuntu offers..."

                                        # Try alternative Ubuntu offers
                                        $alternativeOffers = @("0001-com-ubuntu-server-jammy", "0001-com-ubuntu-server-noble", "UbuntuServer")
                                        foreach ($offer in $alternativeOffers)
                                            {
                                                    # Skip the current offer if it is the same as the one already set
                                                if ($offer -ne $VMImageOffer)
                                                    {
                                                        try
                                                            {
                                                                $availableSkus = Get-AzVMImageSku -Location $Region -PublisherName $VMImagePublisher -Offer $offer -ErrorAction Stop
                                                                if ($availableSkus)
                                                                    {
                                                                        $VMImageOffer = $offer
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
                                                                        Write-Host "Using alternative offer: $offer with SKU: $VMImageSku"
                                                                        break
                                                                    }
                                                            } `
                                                        catch
                                                            {
                                                                continue
                                                            }
                                                    }
                                            }
                                    }
                            } `
                        catch
                            {
                                Write-Warning "Failed to get VM image SKUs: $($_.Exception.Message). Trying Ubuntu image alias as fallback..."
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
                        Write-Error "The specified VM image '$VMImageOffer' from publisher '$VMImagePublisher' with SKU '$VMImageSku' and version '$VMImageVersion' is not available in the region '$Region'."
                        return
                    }
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


                # create a vnet to deploy test vm instances into
                try
                    {
                        # create the virtual network and subnet
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

                        Write-Verbose -Message "✓ Network Security Group '$($nSG.Name)' created with isolation rules:"

                        # Get detailed rule information for verbose output (using independent variables)
                        $verboseInboundRule = $nSG.SecurityRules | Where-Object Direction -eq 'Inbound'
                        $verboseOutboundRule = $nSG.SecurityRules | Where-Object Direction -eq 'Outbound'

                        Write-Verbose -Message "  - Inbound Rule: '$($verboseInboundRule.Name)' - $($verboseInboundRule.Access) traffic from source '$($verboseInboundRule.SourceAddressPrefix)' ports '$($verboseInboundRule.SourcePortRange)' to destination '$($verboseInboundRule.DestinationAddressPrefix)' ports '$($verboseInboundRule.DestinationPortRange)' protocol '$($verboseInboundRule.Protocol)' [Priority: $($verboseInboundRule.Priority)]"
                        Write-Verbose -Message "  - Outbound Rule: '$($verboseOutboundRule.Name)' - $($verboseOutboundRule.Access) traffic from source '$($verboseOutboundRule.SourceAddressPrefix)' ports '$($verboseOutboundRule.SourcePortRange)' to destination '$($verboseOutboundRule.DestinationAddressPrefix)' ports '$($verboseOutboundRule.DestinationPortRange)' protocol '$($verboseOutboundRule.Protocol)' [Priority: $($verboseOutboundRule.Priority)]"

                        Write-Verbose -Message "  - Security Impact: Complete network isolation - NO traffic allowed in any direction"

                        $mGMTSubnet = New-AzVirtualNetworkSubnetConfig `
                                        -Name $("{0}-mgmt-subnet" -f $ResourceNamePrefix) `
                                        -AddressPrefix $IPRangeCIDR `
                                        -NetworkSecurityGroup $nSG

                        Write-Verbose -Message "✓ Management subnet '$($mGMTSubnet.Name)' configured with address range $($mGMTSubnet.AddressPrefix)"

                        # $storageSubnet = New-AzVirtualNetworkSubnetConfig `
                        #                 -Name $("{0}-storage-subnet" -f $ResourceNamePrefix) `
                        #                 -AddressPrefix $StorageIPRangeCIDR `
                        #                 -NetworkSecurityGroup $nSG

                        $vNET = New-AzVirtualNetwork `
                                    -ResourceGroupName $ResourceGroupName `
                                    -Location $Region `
                                    -Name $("{0}-vnet" -f $ResourceNamePrefix) `
                                    -AddressPrefix $IPRangeCIDR `
                                    -Subnet $mGMTSubnet #, $storageSubnet

                        Write-Verbose -Message "✓ Virtual Network '$($vNET.Name)' created with address space $IPRangeCIDR"
                        Write-Verbose -Message "✓ Network isolation configured: All VMs will be deployed with NO internet access"

                        $mGMTSubnetID = $vNET.Subnets | Where-Object { $_.Name -eq $mGMTSubnet.Name } | Select-Object -ExpandProperty Id
                        # $storageSubnetID = $vNET.Subnets | Where-Object { $_.Name -eq $storageSubnet.Name } | Select-Object -ExpandProperty Id
                    }
                catch
                    {
                        Write-Error "An error occurred while creating the virtual network or subnet: $_"
                        returnWorkspace 1
                    }

                # # create standard storage account for the resource group os diagnostics
                # try {
                #         $bootDiagStorageAccount = New-AzStorageAccount `
                #                                     -ResourceGroupName $ResourceGroupName `
                #                                     -Name $("{0}osdiag" -f $ResourceNamePrefix -replace "-","") `
                #                                     -Location $Region `
                #                                     -SkuName "Standard_LRS" `
                #                                     -Kind "StorageV2"
                #     }
                # catch
                #     {
                #         Write-Error "An error occurred while creating the storage account for OS diagnostics: $_"
                #         returnWorkspace 1
                #     }

                # create vm instances
                try
                    {
                        # Clean up any old jobs before starting deployment to better track jobs related to the active run
                        Write-Verbose -Message "Cleaning up any existing background jobs..."
                        Get-Job | Remove-Job -Force
                        Write-Verbose -Message "All existing jobs have been removed."

                        # Calculate total VMs for progress tracking
                        $totalDNodes = ($mNodeObject | ForEach-Object { $_.dNodeCount } | Measure-Object -Sum).Sum
                        $totalVMs = $CNodeCount + $totalDNodes

                        # Start main VM creation progress
                        Write-Progress `
                            -Status "Initializing" `
                            -CurrentOperation "Starting VM deployment process..." `
                            -PercentComplete 0 `
                            -Activity "VM Deployment" `
                            -Id 1

                        $DeployedVMs = New-Object 'System.Collections.Generic.List[System.Object]'

                        # CNode creation with sub-progress
                        Write-Progress `
                            -Status "Creating CNodes" `
                            -CurrentOperation "Preparing to create $CNodeCount CNode VMs..." `
                            -PercentComplete 5 `
                            -Activity "VM Deployment" `
                            -Id 1

                        for ($cNode = 1; $cNode -le $CNodeCount; $cNode++)
                            {
                                # Calculate CNode SKU for display
                                $currentCNodeSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix

                                # Update sub-progress for CNode creation
                                Write-Progress `
                                    -Status "Creating CNode $cNode of $CNodeCount ($currentCNodeSku)" `
                                    -CurrentOperation "Configuring CNode $cNode with SKU $currentCNodeSku..." `
                                    -PercentComplete $(($cNode / $CNodeCount) * 100) `
                                    -Activity "CNode Creation" `
                                    -ParentId 1 `
                                    -Id 2

                                # create the cnode management NIC
                                $cNodeMGMTNIC = New-AzNetworkInterface `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -Location $Region `
                                                    -Name $("{0}-cnode-mgmt-nic-{1}" -f $ResourceNamePrefix, $cNode) `
                                                    -SubnetId $mGMTSubnetID

                                Write-Verbose -Message "✓ CNode $cNode management NIC '$($cNodeMGMTNIC.Name)' successfully created with IP '$($cNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)'"

                                # $cNodeStorageNIC = New-AzNetworkInterface `
                                #                     -ResourceGroupName $ResourceGroupName `
                                #                     -Location $Region `
                                #                     -Name $("{0}-cnode-storage-nic-{1}" -f $ResourceNamePrefix, $cNode) `
                                #                     -SubnetId $storageSubnetID `
                                #                     -EnableAcceleratedNetworking:$true

                                # create the cnode vm configuration
                                $cNodeConfig = New-AzVMConfig `
                                                -Zone $Zone `
                                                -VMName $("{0}-cnode-{1}" -f $ResourceNamePrefix, $cNode) `
                                                -VMSize $("{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix)

                                # set operating system details
                                $cNodeConfig = Set-AzVMOperatingSystem `
                                                -VM $cNodeConfig `
                                                -Linux `
                                                -ComputerName $("{0}-cnode-{1}" -f $ResourceNamePrefix, $cNode) `
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

                                # # set the cnode vm diagnostics
                                # $cNodeConfig = Set-AzVMBootDiagnostic `
                                #                 -VM $cNodeConfig `
                                #                 -ResourceGroupName $ResourceGroupName `
                                #                 -StorageAccountName $bootDiagStorageAccount.StorageAccountName `
                                #                 -Enable:$true

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

                                # # Add the storage NIC to the cnode vm configuration
                                # $cNodeConfig = Add-AzVMNetworkInterface `
                                #                 -VM $cNodeConfig `
                                #                 -Id $cNodeStorageNIC.Id `
                                #                 -Primary:$false `
                                #                 -DeleteOption "Delete"

                                New-AzVM `
                                    -ResourceGroupName $ResourceGroupName `
                                    -Location $Region `
                                    -VM $cNodeConfig `
                                    -AsJob | Out-Null
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

                                # Update main progress for MNode group
                                $processedCNodes = $CNodeCount
                                $processedDNodes = $dNodeStartCount
                                $totalProcessed = $processedCNodes + $processedDNodes
                                $mainPercentComplete = [Math]::Min([Math]::Round(($totalProcessed / $totalVMs) * 100), 90)
                                Write-Progress `
                                    -Status "Processing MNode Group $currentMNode of $($mNodeObject.Count) - $currentMNodePhysicalSize TiB ($currentMNodeSku)" `
                                    -CurrentOperation "Creating $($mNode.dNodeCount) DNodes for $currentMNodePhysicalSize TiB MNode..." `
                                    -PercentComplete $mainPercentComplete `
                                    -Activity "VM Deployment" `
                                    -Id 1
                                for ($dNode = 1; $dNode -le $mNode.dNodeCount; $dNode++)
                                    {
                                        # Update sub-progress for DNode creation
                                        Write-Progress `
                                            -Status "Creating DNode $dNode of $($mNode.dNodeCount) - $currentMNodePhysicalSize TiB ($currentMNodeSku)" `
                                            -CurrentOperation "Configuring DNode $($dNode + $dNodeStartCount) with SKU $currentMNodeSku..." `
                                            -PercentComplete $(($dNode / $mNode.dNodeCount) * 100) `
                                            -Activity "MNode Group $currentMNode DNode Creation" `
                                            -ParentId 1 `
                                            -Id 3

                                        # set dnode number to use for naming
                                        $dNodeNumber = $dNode + $dNodeStartCount

                                        # create the dnode management
                                        $dNodeMGMTNIC = New-AzNetworkInterface `
                                                            -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -Name $("{0}-dnode-{1}-mgmt-nic" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -SubnetId $mGMTSubnetID

                                        Write-Verbose -Message "✓ DNode $dNodeNumber management NIC '$($dNodeMGMTNIC.Name)' successfully created with IP '$($dNodeMGMTNIC.IpConfigurations[0].PrivateIpAddress)'"

                                        # $cNodeStorageNIC = New-AzNetworkInterface `
                                        #                     -ResourceGroupName $ResourceGroupName `
                                        #                     -Location $Region `
                                        #                     -Name $("{0}-dnode-storage-nic-{1}" -f $ResourceNamePrefix, $dNodeNumber) `
                                        #                     -SubnetId $storageSubnetID `
                                        #                     -EnableAcceleratedNetworking:$true

                                        # create the dnode vm configuration
                                        $dNodeConfig = New-AzVMConfig `
                                                        -Zone $Zone `
                                                        -VMName $("{0}-dnode-{1}" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -VMSize $("{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix)

                                        # set operating system details
                                        $dNodeConfig = Set-AzVMOperatingSystem `
                                                        -VM $dNodeConfig `
                                                        -Linux `
                                                        -ComputerName $("{0}-dnode-{1}" -f $ResourceNamePrefix, $dNodeNumber) `
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

                                        # # set the cnode vm diagnostics
                                        # $cNodeConfig = Set-AzVMBootDiagnostic `
                                        #                 -VM $cNodeConfig `
                                        #                 -ResourceGroupName $ResourceGroupName `
                                        #                 -StorageAccountName $bootDiagStorageAccount.StorageAccountName `
                                        #                 -Enable:$true

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

                                        # # Add the storage NIC to the dnode vm configuration
                                        # $dNodeConfig = Add-AzVMNetworkInterface `
                                        #                 -VM $dNodeConfig `
                                        #                 -Id $dNodeStorageNIC.Id `
                                        #                 -Primary:$false `
                                        #                 -DeleteOption "Delete"

                                        # Update sub-progress for VM creation
                                        Write-Progress `
                                            -Status "Creating DNode $dNode VM ($currentMNodeSku)..." `
                                            -CurrentOperation "Starting VM creation job for DNode $dNodeNumber with SKU $currentMNodeSku..." `
                                            -PercentComplete $(($dNode / $mNode.dNodeCount) * 100) `
                                            -Activity "MNode Group $currentMNode DNode Creation" `
                                            -ParentId 1 `
                                            -Id 3

                                        New-AzVM `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Location $Region `
                                            -VM $dNodeConfig `
                                            -AsJob | Out-Null
                                    }

                                # Clean up this MNode group's sub-progress bar as it's complete
                                Write-Progress -Activity "MNode Group $currentMNode DNode Creation" -Id 3 -Completed

                                $dNodeStartCount += $mNode.dNodeCount
                            }


                        # Validate all network interfaces were created successfully
                        Write-Verbose -Message "✓ All network interfaces created successfully: $((Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }).Count) total NICs"

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
                            -CurrentOperation "Waiting for $($allVMJobs.Count) VMs to deploy..." `
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
                            -Status "VM Deployment: $initialCompletionPercent%" `
                            -CurrentOperation "Monitoring $($runningJobs.Count) running VMs..." `
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
                                $completionPercent = [Math]::Round(($completedJobs.Count / $allVMJobs.Count) * 100)

                                # Update sub-progress for VM deployment
                                Write-Progress `
                                    -Status "VM Deployment: $completionPercent%" `
                                    -CurrentOperation "Waiting for $($runningJobs.Count) remaining VMs to deploy..." `
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
                        Write-Progress -Activity "VM Deployment Monitoring" -Id 4 -Completed

                    }
                catch
                    {
                        Write-Warning -Message "Error occurred while creating VMs: $_"
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
                $allResources = Get-AzResource -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                # Create deployment report
                $deploymentReport = @()

                # Build CNode deployment report
                for ($cNode = 1; $cNode -le $CNodeCount; $cNode++) {
                    $expectedVMName = "$ResourceNamePrefix-cnode-$cNode"
                    $expectedNICName = "$ResourceNamePrefix-cnode-mgmt-nic-$cNode"

                    $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                    $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                    # Calculate CNode SKU for reporting
                    $reportCNodeSku = "{0}{1}{2}" -f $cNodeObject.vmSkuPrefix, $cNodeObject.vCPU, $cNodeObject.vmSkuSuffix

                    $deploymentReport += [PSCustomObject]@{
                        ResourceType = "CNode"
                        GroupNumber = "CNode Group"
                        NodeNumber = $cNode
                        VMName = $expectedVMName
                        ExpectedSKU = $reportCNodeSku
                        DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                        VMStatus = if ($vm) { "✓ Deployed" } else { "✗ Failed" }
                        NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                    }
                }

                # Build DNode deployment report
                $dNodeStartCount = 0
                $currentMNode = 0
                foreach ($mNode in $mNodeObject) {
                    $currentMNode++
                    $currentMNodePhysicalSize = $mNode.PhysicalSize
                    $reportMNodeSku = "{0}{1}{2}" -f $mNode.vmSkuPrefix, $mNode.vCPU, $mNode.vmSkuSuffix

                    for ($dNode = 1; $dNode -le $mNode.dNodeCount; $dNode++) {
                        $dNodeNumber = $dNode + $dNodeStartCount
                        $expectedVMName = "$ResourceNamePrefix-dnode-$dNodeNumber"
                        $expectedNICName = "$ResourceNamePrefix-dnode-$dNodeNumber-mgmt-nic"

                        $vm = $deployedVMs | Where-Object { $_.Name -eq $expectedVMName }
                        $nic = $deployedNICs | Where-Object { $_.Name -eq $expectedNICName }

                        $deploymentReport += [PSCustomObject]@{
                            ResourceType = "DNode"
                            GroupNumber = "MNode $currentMNode ($currentMNodePhysicalSize TiB)"
                            NodeNumber = $dNodeNumber
                            VMName = $expectedVMName
                            ExpectedSKU = $reportMNodeSku
                            DeployedSKU = if ($vm) { $vm.HardwareProfile.VmSize } else { "Not Found" }
                            VMStatus = if ($vm) { "✓ Deployed" } else { "✗ Failed" }
                            NICStatus = if ($nic) { "✓ Created" } else { "✗ Failed" }
                        }
                    }
                    $dNodeStartCount += $mNode.dNodeCount
                }

                # Display the deployment report table
                Write-Host "`n=== VM Deployment Report ===" -ForegroundColor Cyan

                # CNode Report
                $cNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "CNode" }
                if ($cNodeReport) {
                    $cNodeExpectedSku = $cNodeReport[0].ExpectedSKU
                    Write-Host "`nCNode Deployment Status (Expected SKU: $cNodeExpectedSku):" -ForegroundColor Yellow
                    $cNodeReport | Format-Table -Property @(
                        @{Label="Node"; Expression={"CNode $($_.NodeNumber)"}; Width=12},
                        @{Label="VM Name"; Expression={$_.VMName}; Width=25},
                        @{Label="Deployed SKU"; Expression={$_.DeployedSKU}; Width=18},
                        @{Label="VM Status"; Expression={$_.VMStatus}; Width=15},
                        @{Label="NIC Status"; Expression={$_.NICStatus}; Width=15}
                    ) -AutoSize
                }

                # DNode Report by MNode Group
                $mNodeGroups = $deploymentReport | Where-Object { $_.ResourceType -eq "DNode" } | Group-Object GroupNumber
                foreach ($group in $mNodeGroups) {
                    $mNodeExpectedSku = $group.Group[0].ExpectedSKU
                    Write-Host "`n$($group.Name) DNode Deployment Status (Expected SKU: $mNodeExpectedSku):" -ForegroundColor Yellow
                    $group.Group | Format-Table -Property @(
                        @{Label="Node"; Expression={"DNode $($_.NodeNumber)"}; Width=12},
                        @{Label="VM Name"; Expression={$_.VMName}; Width=25},
                        @{Label="Deployed SKU"; Expression={$_.DeployedSKU}; Width=18},
                        @{Label="VM Status"; Expression={$_.VMStatus}; Width=15},
                        @{Label="NIC Status"; Expression={$_.NICStatus}; Width=15}
                    ) -AutoSize
                }

                # Silk Component Summary
                Write-Host "`n=== Silk Component Summary ===" -ForegroundColor Cyan

                # Calculate CNode statistics
                $cNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "CNode" }
                $successfulCNodes = ($cNodeReport | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                $cNodeSummaryLabel = if ($cNodeReport) { $cNodeReport[0].ExpectedSKU } else { "Unknown" }

                # Calculate DNode statistics by MNode group
                $dNodeReport = $deploymentReport | Where-Object { $_.ResourceType -eq "DNode" }
                $mNodeGroups = $dNodeReport | Group-Object GroupNumber

                # Create summary table
                $silkSummary = @()

                # Add CNode summary
                $silkSummary += [PSCustomObject]@{
                    Component = "CNode"
                    DeployedCount = $successfulCNodes
                    ExpectedCount = $CNodeCount
                    SKU = $cNodeSummaryLabel
                    Status = if ($successfulCNodes -eq $CNodeCount) { "✓ Complete" } else { "⚠ Partial" }
                }

                # Add MNode/DNode summary for each group
                foreach ($group in $mNodeGroups) {
                    $groupSuccessful = ($group.Group | Where-Object { $_.VMStatus -eq "✓ Deployed" }).Count
                    $groupExpected = $group.Group.Count
                    $groupSku = $group.Group[0].ExpectedSKU
                    $groupName = $group.Name.Replace("MNode ", "M").Replace(" TiB)", "TB)")

                    $silkSummary += [PSCustomObject]@{
                        Component = $groupName
                        DeployedCount = $groupSuccessful
                        ExpectedCount = $groupExpected
                        SKU = $groupSku
                        Status = if ($groupSuccessful -eq $groupExpected) { "✓ Complete" } else { "⚠ Partial" }
                    }
                }

                # Display the summary table
                $silkSummary | Format-Table -Property @(
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
                if ($deployedVNet) { Write-Host "✓ $($deployedVNet.Name)" -ForegroundColor Green } else { Write-Host "✗ Not Found" -ForegroundColor Red }

                Write-Host "Network Security Group: " -NoNewline
                if ($deployedNSG) { Write-Host "✓ $($deployedNSG.Name)" -ForegroundColor Green } else { Write-Host "✗ Not Found" -ForegroundColor Red }

                Write-Host "Expected VMs: $totalExpectedVMs"
                Write-Host "Successfully Deployed VMs: " -NoNewline
                if ($successfulVMs -eq $totalExpectedVMs) {
                    Write-Host "$successfulVMs" -ForegroundColor Green
                } else {
                    Write-Host "$successfulVMs" -ForegroundColor Yellow
                }

                if ($failedVMs -gt 0) {
                    Write-Host "Failed VM Deployments: " -NoNewline
                    Write-Host "$failedVMs" -ForegroundColor Red
                }

                Write-Host "Total Network Interfaces: $($deployedNICs.Count)"
                Write-Host "Total Resources Created: $($allResources.Count)"

                # Overall Status
                Write-Host "`n=== Overall Deployment Status ===" -ForegroundColor Cyan
                if ($successfulVMs -eq $totalExpectedVMs -and $deployedVNet -and $deployedNSG) {
                    Write-Host "✓ DEPLOYMENT SUCCESSFUL - All resources deployed correctly!" -ForegroundColor Green
                } else {
                    Write-Host "⚠ DEPLOYMENT ISSUES DETECTED - Review the report above for details" -ForegroundColor Yellow
                }

                Write-Progress -Id 1 -Completed

                Start-Sleep -Seconds 2
                if (!$DisableCleanup)
                    {
                        Write-Verbose -Message "Deployment completed. Resources have been created in the resource group: $ResourceGroupName."
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
                                    -ParentId 1 `
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
                                                -Status "Removing VM $currentVMCount of $totalVMs" `
                                                -CurrentOperation "Removing virtual machine: $($_.Name)..." `
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
                                    -CurrentOperation "Waiting for all $totalVMs virtual machines to be removed..." `
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
                                    -CurrentOperation "All $($vmJobs.Count) VM removal jobs submitted, monitoring completion..." `
                                    -PercentComplete 0 `
                                    -Activity "VM Cleanup" `
                                    -ParentId 5 `
                                    -Id 6

                                do {
                                    Start-Sleep -Seconds 2
                                    $currentVMJobs = Get-Job
                                    $completedVMJobs = $currentVMJobs | Where-Object { $_.State -ne 'Running' }

                                    # VM sub-progress: Calculate actual completion percentage
                                    $vmCompletionPercent = [Math]::Round(($completedVMJobs.Count / $vmJobs.Count) * 100)

                                    # Update main progress during VM cleanup (10% to 50% - VMs represent 50% of total)
                                    $mainProgressPercent = 10 + [Math]::Round(($completedVMJobs.Count / $vmJobs.Count) * 40)
                                    Write-Progress `
                                        -Status "Cleaning Up Virtual Machines - $vmCompletionPercent%" `
                                        -CurrentOperation "VM cleanup in progress: $(($vmJobs.Count - $completedVMJobs.Count)) VMs remaining..." `
                                        -PercentComplete $mainProgressPercent `
                                        -Activity "Resource Cleanup" `
                                        -ParentId 1 `
                                        -Id 5

                                    Write-Progress `
                                        -Status "VM Removal Progress: $vmCompletionPercent%" `
                                        -CurrentOperation "Waiting for $(($vmJobs.Count - $completedVMJobs.Count)) remaining VM removal jobs..." `
                                        -PercentComplete $vmCompletionPercent `
                                        -Activity "VM Cleanup" `
                                        -ParentId 5 `
                                        -Id 6
                                } while ($currentVMJobs.State -contains 'Running')

                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "All virtual machines have been removed."

                                # Complete VM cleanup sub-progress
                                Write-Progress -Activity "VM Cleanup" -Id 6 -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        if (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -Match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (NICs = next 15% after VMs)
                                Write-Progress -Id 5 -ParentId 1 -Activity "Cleaning up test resources..." -Status "Removing network interfaces..." -PercentComplete 55

                                # Start NIC cleanup sub-progress
                                Write-Progress -Id 7 -ParentId 5 -Activity "Network Interface Cleanup" -Status "Identifying network interfaces to remove..." -PercentComplete 0

                                # Get all NICs to remove
                                $nicsToRemove = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }
                                $totalNICs = $nicsToRemove.Count

                                Write-Progress -Id 7 -ParentId 5 -Activity "Network Interface Cleanup" -Status "Found $totalNICs network interfaces to remove" -PercentComplete 10

                                # Remove all network interfaces in the resource group
                                $nicCount = 0
                                $nicsToRemove | ForEach-Object {
                                    $nicCount++
                                    $nicProgress = [math]::Round((($nicCount / $totalNICs) * 60) + 10)
                                    Write-Progress -Id 7 -ParentId 5 -Activity "Network Interface Cleanup" -Status "Removing NIC: $($_.Name) ($nicCount of $totalNICs)" -PercentComplete $nicProgress
                                    Write-Host $("Removing network interface: {0} in resource group: {1}" -f $_.Name, $ResourceGroupName);
                                    Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $_.Name -Force:$true -AsJob | Out-Null
                                }

                                # Wait for all NIC removal jobs to complete before proceeding
                                Write-Progress -Id 7 -ParentId 5 -Activity "Network Interface Cleanup" -Status "Waiting for all NIC removal jobs to complete..." -PercentComplete 80
                                Write-Verbose -Message "Waiting for all network interfaces to be removed..."
                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "All network interfaces have been removed."

                                Write-Progress -Id 7 -ParentId 5 -Activity "Network Interface Cleanup" -Status "Network interface cleanup completed" -PercentComplete 100
                                Start-Sleep -Milliseconds 500
                                Write-Progress -Id 7 -Activity "Network Interface Cleanup" -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # clean up deployed test Storage account
                        if (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $bootDiagStorageAccount.StorageAccountName })
                            {
                                # Update main cleanup progress (Storage = next 10% after NICs)
                                Write-Progress -Id 5 -ParentId 1 -Activity "Cleaning up test resources..." -Status "Removing storage account..." -PercentComplete 70

                                # Start Storage Account cleanup sub-progress
                                Write-Progress -Id 8 -ParentId 5 -Activity "Storage Account Cleanup" -Status "Removing boot diagnostics storage account..." -PercentComplete 0

                                Write-Verbose -Message $("Removing boot diagnostics storage account: {0}" -f $bootDiagStorageAccount.StorageAccountName)

                                Write-Progress -Id 8 -ParentId 5 -Activity "Storage Account Cleanup" -Status "Deleting storage account: $($bootDiagStorageAccount.StorageAccountName)" -PercentComplete 50

                                # Remove the boot diagnostics storage account
                                $bootDiagStorageAccount | Remove-AzStorageAccount -Force:$true

                                Write-Progress -Id 8 -ParentId 5 -Activity "Storage Account Cleanup" -Status "Storage account cleanup completed" -PercentComplete 100
                                Start-Sleep -Milliseconds 500
                                Write-Progress -Id 8 -Activity "Storage Account Cleanup" -Completed
                            }


                        # Start VNet removal job
                        if (Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (VNet = next 15% after Storage)
                                Write-Progress -Id 5 -ParentId 1 -Activity "Cleaning up test resources..." -Status "Removing virtual network..." -PercentComplete 85

                                # Start VNet cleanup sub-progress
                                Write-Progress -Id 9 -ParentId 5 -Activity "Virtual Network Cleanup" -Status "Identifying virtual network to remove..." -PercentComplete 0

                                $foundVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }

                                Write-Progress -Id 9 -ParentId 5 -Activity "Virtual Network Cleanup" -Status "Removing virtual network: $($foundVNet.Name)" -PercentComplete 25
                                Write-Verbose -Message $("Starting removal of virtual network: {0}" -f $foundVNet.Name)

                                Write-Progress -Id 9 -ParentId 5 -Activity "Virtual Network Cleanup" -Status "Executing VNet removal..." -PercentComplete 50
                                $foundVNet | Remove-AzVirtualNetwork -Force:$true -AsJob | Out-Null

                                Write-Progress -Id 9 -ParentId 5 -Activity "Virtual Network Cleanup" -Status "Waiting for VNet removal to complete..." -PercentComplete 75
                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "Virtual Network resource cleanup completed."

                                Write-Progress -Id 9 -ParentId 5 -Activity "Virtual Network Cleanup" -Status "Virtual network cleanup completed" -PercentComplete 100
                                Start-Sleep -Milliseconds 500
                                Write-Progress -Id 9 -Activity "Virtual Network Cleanup" -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Start NSG removal job
                        if (Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                # Update main cleanup progress (NSG = final 5% before completion)
                                Write-Progress -Id 5 -ParentId 1 -Activity "Cleaning up test resources..." -Status "Removing network security group..." -PercentComplete 95

                                # Start NSG cleanup sub-progress
                                Write-Progress -Id 10 -ParentId 5 -Activity "Network Security Group Cleanup" -Status "Identifying network security group to remove..." -PercentComplete 0

                                $foundNSG = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }

                                Write-Progress -Id 10 -ParentId 5 -Activity "Network Security Group Cleanup" -Status "Removing NSG: $($foundNSG.Name)" -PercentComplete 25
                                Write-Verbose -Message $("Starting removal of network security group: {0}" -f $foundNSG.Name)

                                Write-Progress -Id 10 -ParentId 5 -Activity "Network Security Group Cleanup" -Status "Executing NSG removal..." -PercentComplete 50
                                $foundNSG | Remove-AzNetworkSecurityGroup -Force:$true -AsJob | Out-Null

                                Write-Progress -Id 10 -ParentId 5 -Activity "Network Security Group Cleanup" -Status "Waiting for NSG removal to complete..." -PercentComplete 75
                                Get-Job | Wait-Job | Out-Null
                                Write-Verbose -Message "Network Security Group resource cleanup completed."

                                Write-Progress -Id 10 -ParentId 5 -Activity "Network Security Group Cleanup" -Status "Network security group cleanup completed" -PercentComplete 100
                                Start-Sleep -Milliseconds 500
                                Write-Progress -Id 10 -Activity "Network Security Group Cleanup" -Completed

                                # clean up jobs
                                Get-Job | Remove-Job -Force | Out-Null
                            }

                        # Final cleanup completion
                        Write-Progress -Id 5 -Activity "Cleaning up test resources..." -Status "All cleanup operations completed" -PercentComplete 100
                        Start-Sleep -Milliseconds 500
                        Write-Progress -Id 5 -Activity "Cleaning up test resources..." -Completed
                    }
            }
    }

Export-ModuleMember -Function Test-SilkResourceDeployment

