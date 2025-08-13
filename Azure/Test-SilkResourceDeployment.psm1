

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
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "s_v3";   PhysicalSize = 19.5};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "s_v3";   PhysicalSize = 39.1};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 32;   vmSkuSuffix = "s_v3";   PhysicalSize = 78.2};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 2;    vmSkuSuffix = "aos_v4"; PhysicalSize = 14.67};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 4;    vmSkuSuffix = "aos_v4"; PhysicalSize = 29.34};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 8;    vmSkuSuffix = "aos_v4"; PhysicalSize = 58.67};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 12;   vmSkuSuffix = "aos_v4"; PhysicalSize = 88.01};
                                        [pscustomobject]@{dNodeCount = 16; vmSkuPrefix = "Standard_L"; vCPU = 16;   vmSkuSuffix = "aos_v4"; PhysicalSize = 117.35}
                                    )

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

                        $mGMTSubnet = New-AzVirtualNetworkSubnetConfig `
                                        -Name $("{0}-mgmt-subnet" -f $ResourceNamePrefix) `
                                        -AddressPrefix $IPRangeCIDR `
                                        -NetworkSecurityGroup $nSG

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
                        $DeployedVMs = New-Object 'System.Collections.Generic.List[System.Object]'

                        for ($cNode = 1; $cNode -le $CNodeCount; $cNode++)
                            {
                                # create the cnode management
                                $cNodeMGMTNIC = New-AzNetworkInterface `
                                                    -ResourceGroupName $ResourceGroupName `
                                                    -Location $Region `
                                                    -Name $("{0}-cnode-mgmt-nic-{1}" -f $ResourceNamePrefix, $cNode) `
                                                    -SubnetId $mGMTSubnetID

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
                                    -AsJob
                            }

                        $dNodeStartCount = 0
                        foreach ($mNode in $mNodeObject)
                            {
                                for ($dNode = 1; $dNode -le $mNode.dNodeCount; $dNode++)
                                    {
                                        # set dnode number to use for naming
                                        $dNodeNumber = $dNode + $dNodeStartCount

                                        # create the dnode management
                                        $dNodeMGMTNIC = New-AzNetworkInterface `
                                                            -ResourceGroupName $ResourceGroupName `
                                                        -Location $Region `
                                                        -Name $("{0}-dnode-{1}-mgmt-nic" -f $ResourceNamePrefix, $dNodeNumber) `
                                                        -SubnetId $mGMTSubnetID

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

                                        New-AzVM `
                                            -ResourceGroupName $ResourceGroupName `
                                            -Location $Region `
                                            -VM $dNodeConfig `
                                            -AsJob 
                                    }
                                $dNodeStartCount += 16
                            }


                        # Wait for all VMs to be created
                        $allVMJobs = Get-Job

                        Write-Progress `
                            -Status "Running" `
                            -CurrentOperation "Waiting for all VMs to be created." `
                            -PercentComplete $(($($allVMJobs | Where-Object { $_.State -ne 'Running' }).Count / $allVMJobs.Count) * 100) `
                            -Activity "Creating VMs" `
                            -Id 1

                        do
                            {
                                Start-Sleep -Seconds 10
                                $currentVMJobs = Get-Job

                                Write-Progress `
                                    -Status $("Progress...{0}%" -f [System.Math]::($(($($currentVMJobs | Where-Object { $_.State -ne 'Running' }).Count / $allVMJobs.Count) * 100),0)) `
                                    -CurrentOperation $("Waiting for {0} VMs to be created." -f $($currentVMJobs | Where-Object { $_.State -ne 'Running' }).Count) `
                                    -PercentComplete $(($($currentVMJobs | Where-Object { $_.State -ne 'Running' }).Count / $allVMJobs.Count) * 100) `
                                    -Activity "Creating VMs" `
                                    -Id 1
                            } `
                        while
                            (
                                $currentVMJobs.State -contains 'Running'
                            )

                        Write-Progress `
                            -Status "Progress 100%" `
                            -CurrentOperation "All VMs have been created." `
                            -PercentComplete 100 `
                            -Activity "Creating VMs" `
                            -Id 1

                        Start-Sleep -Seconds 5

                        Write-Progress -Id 1 -Completed

                        # Collect the deployed VMs
                        $DeployedVMs = Get-AzVM -ResourceGroupName $ResourceGroupName | Where-Object { $_.Name -match $ResourceNamePrefix }

                        $DeployedVMs |
                            ForEach-Object `
                                {
                                    Write-Host "Deployed VM: {0} sku: {1}" -f $_.Name, $_.HardwareProfile.VmSize
                                }

                        Start-Sleep -Seconds 10
                        Read-Host -Prompt "Press Enter to continue..."
                    }
                catch
                    {
                        Write-Host "Error occurred while creating VMs: $_"
                    }
            }
        end
            {
                if ( $RunCleanupOnly -or !$DisableCleanup )
                    {
                        # Clean up resources

                        # clean up deployed test VMs
                        if (Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -Match $ResourceNamePrefix })
                            {
                                # Remove all cnode virtual machines in the resource group
                                Get-AzVM -ResourceGroupName $ResourceGroupName |
                                    Where-Object { $_.Name -match $ResourceNamePrefix } |
                                        ForEach-Object  {
                                                            Write-Host $("Removing virtual machine: {0} in resource group: {1}" -f $_.Name, $ResourceGroupName);
                                                            Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $_.Name -Force:$true -AsJob
                                                        }
                                # Wait for all VM removal jobs to complete
                                Get-Job | Wait-Job
                            }

                        if (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -Match $ResourceNamePrefix })
                            {
                                # Remove all cnode virtual machines in the resource group
                                Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName |
                                    Where-Object { $_.Name -match $ResourceNamePrefix } |
                                        ForEach-Object {
                                                            Write-Host $("Removing network interface: {0} in resource group: {1}" -f $_.Name, $ResourceGroupName);
                                                            Remove-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $_.Name -Force:$true -AsJob
                                                        }
                            }

                    # clean up deployed test Storage account
                        if (Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $bootDiagStorageAccount.StorageAccountName })
                            {
                                Write-Host $("Removing boot diagnostics storage account: {0}" -f $bootDiagStorageAccount.StorageAccountName)
                                # Remove the boot diagnostics storage account
                                $bootDiagStorageAccount | Remove-AzStorageAccount -Force:$true
                            }

                        # clean up virtual network
                        if (Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                $foundVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                                Write-Host $("Removing virtual network: {0}" -f $foundVNet.Name)
                                # Remove the virtual network
                                $foundVNet | Remove-AzVirtualNetwork -Force:$true
                            }

                        # clean up network security group
                        if (Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix })
                            {
                                $foundNSG = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $ResourceNamePrefix }
                                Write-Host $("Removing network security group: {0}" -f $foundNSG.Name)
                                # Remove the network security group
                                $foundNSG | Remove-AzNetworkSecurityGroup -Force:$true
                            }
                    }
            }
    }

Export-ModuleMember -Function Test-SilkResourceDeployment

