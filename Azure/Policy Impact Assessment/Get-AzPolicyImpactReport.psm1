<#
.SYNOPSIS
    Generates a comprehensive Azure Policy impact assessment report for specified resources and scopes.

.DESCRIPTION
    This module collects all Azure Policy assignments that could impact deployment or configuration
    at multiple scopes including subscription, resource groups, VNets, NSGs, UMIs, and custom roles.

    The report includes:
    - Policy assignments at all hierarchy levels (Management Group, Subscription, Resource Group)
    - Policy definitions with detailed rules and effects
    - Policy exemptions
    - Scope analysis showing which policies apply where
    - Export options to JSON, CSV, and HTML formats

.PARAMETER SubscriptionId
    The Azure Subscription ID to analyze. If not provided, uses the current context subscription.

.PARAMETER SubscriptionName
    The Azure Subscription Name to analyze (alternative to SubscriptionId).

.PARAMETER ResourceGroupName
    The Silk Resource Group name - the primary target resource group where Silk resources will be deployed.

.PARAMETER VNetNames
    Array of Virtual Network names. If multiple VNets with the same name exist, you'll be prompted to select.

.PARAMETER VNetResourceGroup
    Resource group where VNet will be deployed (even if it doesn't exist yet). Use this to assess policies without existing resources.

.PARAMETER NSGNames
    Array of Network Security Group names. If multiple NSGs with the same name exist, you'll be prompted to select.

.PARAMETER NSGResourceGroup
    Resource group where NSGs will be deployed (even if they don't exist yet). Use this to assess policies without existing resources.

.PARAMETER UMINames
    Array of User-Assigned Managed Identity names. If multiple UMIs with the same name exist, you'll be prompted to select.

.PARAMETER UMIResourceGroup
    Resource group where UMI will be deployed (even if it doesn't exist yet). Use this to assess policies without existing resources.

.PARAMETER VNetResourceIds
    (Advanced) Array of Virtual Network full resource IDs. Use this if you have the full resource IDs.

.PARAMETER NSGResourceIds
    (Advanced) Array of Network Security Group full resource IDs. Use this if you have the full resource IDs.

.PARAMETER UMIResourceIds
    (Advanced) Array of User-Assigned Managed Identity full resource IDs. Use this if you have the full resource IDs.

.PARAMETER Interactive
    Enable interactive mode to select resources from a menu if not specified.

.PARAMETER IncludeRoleAssignments
    Include role assignments at subscription and Silk Resource Group level in the report.

.PARAMETER OutputFormat
    Format for the output report. Valid values: JSON, CSV, HTML, All (default: All)

.PARAMETER OutputPath
    Directory path where reports will be saved. Default is current directory.

.PARAMETER ReportName
    Base name for the output report files. Timestamp will be appended automatically.

#>

function Get-AzPolicyImpactReport
    {
        [CmdletBinding  (
                            DefaultParameterSetName = 'ByName',
                            HelpURI = "https://github.com/silk-us/scripts-and-configs/tree/main/Azure/Policy%20Impact%20Assessment"
                        )]

        param
            (
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Azure Subscription ID'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Azure Subscription ID'
                            )]
                [string]
                $SubscriptionId,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Azure Subscription Name'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Azure Subscription Name'
                            )]
                [string]
                $SubscriptionName,

                [Parameter  (
                                Mandatory = $true,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Silk Resource Group name where resources will be deployed'
                            )]
                [Parameter  (
                                Mandatory = $true,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Silk Resource Group name where resources will be deployed'
                            )]
                [string]
                $ResourceGroupName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Array of Virtual Network names'
                            )]
                [string[]]
                $VNetName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Resource group where VNet will be deployed'
                            )]
                [string]
                $VNetResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Array of Network Security Group names'
                            )]
                [string[]]
                $NSGName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Resource group where NSGs will be deployed'
                            )]
                [string]
                $NSGResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Array of User-Assigned Managed Identity names'
                            )]
                [string[]]
                $UMIName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Resource group where UMI will be deployed'
                            )]
                [string]
                $UMIResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Array of Virtual Network resource IDs'
                            )]
                [string[]]
                $VNetResourceIds,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Array of Network Security Group resource IDs'
                            )]
                [string[]]
                $NSGResourceIds,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Array of User-Assigned Managed Identity resource IDs'
                            )]
                [string[]]
                $UMIResourceIds,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Enable interactive mode for resource selection'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Enable interactive mode for resource selection'
                            )]
                [switch]
                $Interactive,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Include role assignments in the report'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Include role assignments in the report'
                            )]
                [switch]
                $IncludeRoleAssignments,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Output format: JSON, CSV, HTML, or All'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Output format: JSON, CSV, HTML, or All'
                            )]
                [ValidateSet('JSON', 'CSV', 'HTML', 'All')]
                [string]
                $OutputFormat = 'All',

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Directory path for output files'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Directory path for output files'
                            )]
                [string]
                $OutputPath = '.',

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ByName',
                                HelpMessage = 'Base name for the output report files'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'ById',
                                HelpMessage = 'Base name for the output report files'
                            )]
                [string]
                $ReportName = 'AzurePolicyImpactReport'
            )

        begin
            {
                Write-Host $("{0}{1}" -f [Environment]::NewLine, $("========================================")) -ForegroundColor Cyan
                Write-Host $("Azure Policy Impact Assessment Report") -ForegroundColor Cyan
                Write-Host $("{0}{1}" -f $("========================================"), [Environment]::NewLine) -ForegroundColor Cyan

                # Validate Azure context
                try
                    {
                        $context = Get-AzContext
                        if (-not $context)
                            {
                                throw $("Not connected to Azure. Please run Connect-AzAccount first.")
                            }

                        # Handle subscription selection
                        if ($SubscriptionName)
                            {
                                $sub = Get-AzSubscription | Where-Object {$_.Name -eq $SubscriptionName}
                                if (-not $sub)
                                    {
                                        throw $("Subscription '{0}' not found" -f $SubscriptionName)
                                    }
                                Set-AzContext -SubscriptionId $sub.Id | Out-Null
                                $context = Get-AzContext
                            } `
                        elseif ($SubscriptionId)
                            {
                                Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
                                $context = Get-AzContext
                            }

                        Write-Host $("Connected to Azure") -ForegroundColor Green
                        Write-Host $("  Subscription: {0}" -f $context.Subscription.Name) -ForegroundColor Gray
                        Write-Host $("  Account: {0}{1}" -f $context.Account.Id, [Environment]::NewLine) -ForegroundColor Gray
                    } `
                catch
                    {
                        Write-Error $("Failed to establish Azure context: {0}" -f $_)
                        return
                    }

                # Validate resource group exists
                try
                    {
                        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
                        Write-Host $("Silk Resource Group (Target): {0}" -f $ResourceGroupName) -ForegroundColor Green
                        Write-Host $("  Location: {0}" -f $rg.Location) -ForegroundColor Gray
                        Write-Host $("  ResourceId: {0}{1}" -f $rg.ResourceId, [Environment]::NewLine) -ForegroundColor Gray
                    } `
                catch
                    {
                        Write-Error $("Resource Group '{0}' not found: {1}" -f $ResourceGroupName, $_)
                        return
                    }


                # Analyze current user's permissions to identify potential blind spots
                Write-Host $("Analyzing your permissions...") -ForegroundColor Yellow
                $userPermissions =  @{
                                        UserIdentity = $context.Account.Id
                                        Roles = @()
                                        HasManagementGroupAccess = $false
                                        HasSubscriptionReaderOrHigher = $false
                                        HasResourceGroupAccess = $false
                                        ManagementGroupScopes = @()
                                        SubscriptionScopes = @()
                                        ResourceGroupScopes = @()
                                        PotentialBlindSpots = @()
                                    }

                try
                    {
                        # Get user's role assignments
                        $userRoles = Get-AzRoleAssignment -SignInName $context.Account.Id -ErrorAction SilentlyContinue
                        if (-not $userRoles)
                            {
                                # Try with ObjectId if SignInName doesn't work (service principals)
                                $userRoles = Get-AzRoleAssignment -ObjectId $context.Account.Id -ErrorAction SilentlyContinue
                            }

                        if ($userRoles)
                            {
                                foreach ($role in $userRoles)
                                    {
                                        $userPermissions.Roles += [PSCustomObject]  @{
                                                                                        Role = $role.RoleDefinitionName
                                                                                        Scope = $role.Scope
                                                                                        ScopeType = if ($role.Scope -like $("*/managementGroups/*")) {$("ManagementGroup")} `
                                                                                                    elseif ($role.Scope -like $("*/subscriptions/*/resourceGroups/*")) {$("ResourceGroup")} `
                                                                                                    elseif ($role.Scope -like $("*/subscriptions/*")) {$("Subscription")} `
                                                                                                    else {$("Other")}
                                                                                    }

                                        # Track scope access
                                        if ($role.Scope -like $("*/managementGroups/*"))
                                            {
                                                $userPermissions.HasManagementGroupAccess = $true
                                                $userPermissions.ManagementGroupScopes += $role.Scope
                                            } `
                                        elseif ($role.Scope -like $("*/subscriptions/*") -and $role.Scope -notlike $("*/resourceGroups/*"))
                                            {
                                                if ($role.RoleDefinitionName -match $("(Reader|Contributor|Owner)"))
                                                    {
                                                        $userPermissions.HasSubscriptionReaderOrHigher = $true
                                                    }
                                                $userPermissions.SubscriptionScopes += $role.Scope
                                            } `
                                        elseif ($role.Scope -like $("*/resourceGroups/*"))
                                            {
                                                $userPermissions.HasResourceGroupAccess = $true
                                                $userPermissions.ResourceGroupScopes += $role.Scope
                                            }
                                    }

                                # Identify potential blind spots
                                if (-not $userPermissions.HasManagementGroupAccess)
                                    {
                                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                        Area = $("Management Group Policies")
                                                                                                        Severity = $("High")
                                                                                                        Description = $("No Management Group-level access detected. Policies assigned at Management Group scope may be invisible or details unavailable.")
                                                                                                        Impact = $("Management Group policies can apply to all subscriptions and resources below them. Without MG access, you cannot see policy definitions from parent Management Groups.")
                                                                                                        Recommendation = $("Request Reader role at Management Group level for complete policy visibility.")
                                                                                                    }
                                    }

                                if (-not $userPermissions.HasSubscriptionReaderOrHigher)
                                    {
                                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                        Area = $("Subscription-Level Policies")
                                                                                                        Severity = $("Medium")
                                                                                                        Description = $("Limited subscription access detected. Some subscription-scoped policies may not be visible.")
                                                                                                        Impact = $("Subscription policies apply to all resource groups. Limited access may result in incomplete policy inventory.")
                                                                                                        Recommendation = $("Request Reader role at Subscription level for full subscription policy visibility.")
                                                                                                    }
                                    }

                                if ($userRoles.Count -eq 0)
                                    {
                                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                        Area = $("All Scopes")
                                                                                                        Severity = $("Critical")
                                                                                                        Description = $("No role assignments found for current user. This report may be severely incomplete.")
                                                                                                        Impact = $("Without explicit role assignments, policy data collection will fail at most scopes.")
                                                                                                        Recommendation = $("Request appropriate Reader permissions at Subscription or Management Group level.")
                                                                                                    }
                                    }

                                Write-Host $("  ✓ Found {0} role assignment(s)" -f $userRoles.Count) -ForegroundColor Gray
                                Write-Host $("  MG Access: {0}" -f $userPermissions.HasManagementGroupAccess) -ForegroundColor Gray
                                Write-Host $("  Subscription Reader: {0}" -f $userPermissions.HasSubscriptionReaderOrHigher) -ForegroundColor Gray
                                if ($userPermissions.PotentialBlindSpots.Count -gt 0)
                                    {
                                        Write-Host $("  ⚠ Potential Blind Spots: {0}" -f $userPermissions.PotentialBlindSpots.Count) -ForegroundColor Yellow
                                    }
                            } `
                        else
                            {
                                Write-Warning $("Could not retrieve role assignments for current user")
                                $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                Area = $("Permission Analysis")
                                                                                                Severity = $("High")
                                                                                                Description = $("Unable to retrieve user's role assignments. Cannot determine access level or potential blind spots.")
                                                                                                Impact = $("Report completeness cannot be assessed.")
                                                                                                Recommendation = $("Verify you have permissions to read role assignments, or contact your Azure administrator.")
                                                                                            }
                            }
                    } `
                catch
                    {
                        Write-Warning $("Failed to analyze user permissions: {0}" -f $_)
                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                        Area = $("Permission Analysis")
                                                                                        Severity = $("High")
                                                                                        Description = $("Error analyzing user permissions: {0}" -f $_.Exception.Message)
                                                                                        Impact = $("Cannot determine what policies may be invisible to current user.")
                                                                                        Recommendation = $("Review Azure RBAC permissions and re-run report.")
                                                                                    }
                    }
                Write-Host $("")

                # Initialize report data structure
                $reportData =  @{
                                    Metadata =  @{
                                                    GeneratedDate = Get-Date -Format $("yyyy-MM-dd HH:mm:ss")
                                                    SubscriptionId = $context.Subscription.Id
                                                    SubscriptionName = $context.Subscription.Name
                                                    SilkResourceGroupName = $ResourceGroupName
                                                    SilkResourceGroupId = $rg.ResourceId
                                                    GeneratedBy = $context.Account.Id
                                                }
                                    PermissionContext = $userPermissions
                                    PolicyAssignments = @()
                                    PolicyExemptions = @()
                                    ScopeAnalysis = @()
                                    RoleAssignments = @()
                                    ResourcesAnalyzed = @{
                                                            VNets = @()
                                                            NSGs = @()
                                                            UMIs = @()
                                                        }
                                    AccessIssues = @()
                                    Warnings = @()
                                }


                # Resolve resource names to IDs
                if ($PSCmdlet.ParameterSetName -eq $('ByName'))
                    {
                        Write-Host $("Resolving resource names to IDs...") -ForegroundColor Yellow

                        # Resolve VNets
                        if ($VNetName)
                            {
                                $VNetResourceIds = @()
                                foreach ($vnetName in $VNetName)
                                    {
                                        Write-Verbose $("Searching for VNet: {0}" -f $vnetName)
                                        $vnets = Get-AzVirtualNetwork | Where-Object {$_.Name -eq $vnetName}

                                        if ($vnets.Count -eq 0)
                                            {
                                                Write-Warning $("VNet '{0}' not found" -f $vnetName)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $VNetResourceGroup)
                                                    {
                                                        $VNetResourceGroup = Read-Host $("  Enter resource group where VNet '{0}' will be deployed (or press Enter to skip)" -f $vnetName)
                                                    }
                                                if ($VNetResourceGroup)
                                                    {
                                                        # Validate RG exists
                                                        $rgExists = Get-AzResourceGroup -Name $VNetResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.VNets += [PSCustomObject]  @{
                                                                                                                            Name = $vnetName
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $VNetResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  ℹ Will analyze policies for VNet deployment in RG: {0}" -f $VNetResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $VNetResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($vnets.Count -eq 1)
                                            {
                                                $VNetResourceIds += $vnets[0].Id
                                                Write-Host $("  ✓ Found VNet: {0} (RG: {1})" -f $vnetName, $vnets[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple VNets with same name - prompt user to select
                                                Write-Host $("  Multiple VNets named '{0}' found:" -f $vnetName) -ForegroundColor Yellow
                                                for ($i = 0; $i -lt $vnets.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $vnets[$i].ResourceGroupName, $vnets[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select VNet (1-{0})" -f $vnets.Count)
                                                $selectedIndex = [int]$selection - 1
                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $vnets.Count)
                                                    {
                                                        $VNetResourceIds += $vnets[$selectedIndex].Id
                                                        Write-Host $("  ✓ Selected: {0} (RG: {1})" -f $vnetName, $vnets[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                    } `
                                                else
                                                    {
                                                        Write-Warning $("Invalid selection for VNet '{0}'" -f $vnetName)
                                                    }
                                            }
                                    }
                            } `
                        elseif ($VNetResourceGroup)
                            {
                                # No VNet names provided, but RG specified for pre-deployment analysis
                                $rgExists = Get-AzResourceGroup -Name $VNetResourceGroup -ErrorAction SilentlyContinue
                                if ($rgExists)
                                    {
                                        $reportData.ResourcesAnalyzed.VNets += [PSCustomObject]  @{
                                                                                                    Name = $("N/A (Pre-deployment)")
                                                                                                    ResourceId = $("N/A (Pre-deployment)")
                                                                                                    ResourceGroupName = $VNetResourceGroup
                                                                                                    Location = $rgExists.Location
                                                                                                    Status = $("Planned Deployment")
                                                                                                }
                                        Write-Host $("  ℹ Analyzing policies for VNet deployment in RG: {0}" -f $VNetResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("VNet Resource Group '{0}' not found" -f $VNetResourceGroup)
                                    }
                            }

                        # Resolve NSGs
                        if ($NSGName)
                            {
                                $NSGResourceIds = @()
                                foreach ($nsgName in $NSGName)
                                    {
                                        Write-Verbose $("Searching for NSG: {0}" -f $nsgName)
                                        $nsgs = Get-AzNetworkSecurityGroup | Where-Object {$_.Name -eq $nsgName}

                                        if ($nsgs.Count -eq 0)
                                            {
                                                Write-Warning $("NSG '{0}' not found" -f $nsgName)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $NSGResourceGroup)
                                                    {
                                                        $NSGResourceGroup = Read-Host $("  Enter resource group where NSG '{0}' will be deployed (or press Enter to skip)" -f $nsgName)
                                                    }
                                                if ($NSGResourceGroup)
                                                    {
                                                        $rgExists = Get-AzResourceGroup -Name $NSGResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.NSGs += [PSCustomObject]  @{
                                                                                                                            Name = $nsgName
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $NSGResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  ℹ Will analyze policies for NSG deployment in RG: {0}" -f $NSGResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $NSGResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($nsgs.Count -eq 1)
                                            {
                                                $NSGResourceIds += $nsgs[0].Id
                                                Write-Host $("  ✓ Found NSG: {0} (RG: {1})" -f $nsgName, $nsgs[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple NSGs with same name - prompt user to select
                                                Write-Host $("  Multiple NSGs named '{0}' found:" -f $nsgName) -ForegroundColor Yellow
                                                for ($i = 0; $i -lt $nsgs.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $nsgs[$i].ResourceGroupName, $nsgs[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select NSG (1-{0})" -f $nsgs.Count)
                                                $selectedIndex = [int]$selection - 1
                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $nsgs.Count)
                                                    {
                                                        $NSGResourceIds += $nsgs[$selectedIndex].Id
                                                        Write-Host $("  ✓ Selected: {0} (RG: {1})" -f $nsgName, $nsgs[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                    } `
                                                else
                                                    {
                                                        Write-Warning $("Invalid selection for NSG '{0}'" -f $nsgName)
                                                    }
                                            }
                                    }
                            } `
                        elseif ($NSGResourceGroup)
                            {
                                # No NSG names provided, but RG specified for pre-deployment analysis
                                $rgExists = Get-AzResourceGroup -Name $NSGResourceGroup -ErrorAction SilentlyContinue
                                if ($rgExists)
                                    {
                                        $reportData.ResourcesAnalyzed.NSGs += [PSCustomObject]  @{
                                                                                                    Name = $("N/A (Pre-deployment)")
                                                                                                    ResourceId = $("N/A (Pre-deployment)")
                                                                                                    ResourceGroupName = $NSGResourceGroup
                                                                                                    Location = $rgExists.Location
                                                                                                    Status = $("Planned Deployment")
                                                                                                }
                                        Write-Host $("  ℹ Analyzing policies for NSG deployment in RG: {0}" -f $NSGResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("NSG Resource Group '{0}' not found" -f $NSGResourceGroup)
                                    }
                            }

                        # Resolve UMIs
                        if ($UMIName)
                            {
                                $UMIResourceIds = @()
                                foreach ($umiName in $UMIName)
                                    {
                                        Write-Verbose $("Searching for UMI: {0}" -f $umiName)
                                        $umis = Get-AzUserAssignedIdentity | Where-Object {$_.Name -eq $umiName}

                                        if ($umis.Count -eq 0)
                                            {
                                                Write-Warning $("UMI '{0}' not found" -f $umiName)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $UMIResourceGroup)
                                                    {
                                                        $UMIResourceGroup = Read-Host $("  Enter resource group where UMI '{0}' will be deployed (or press Enter to skip)" -f $umiName)
                                                    }
                                                if ($UMIResourceGroup)
                                                    {
                                                        $rgExists = Get-AzResourceGroup -Name $UMIResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.UMIs += [PSCustomObject]  @{
                                                                                                                            Name = $umiName
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $UMIResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            PrincipalId = $("N/A (Pre-deployment)")
                                                                                                                            ClientId = $("N/A (Pre-deployment)")
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  ℹ Will analyze policies for UMI deployment in RG: {0}" -f $UMIResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $UMIResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($umis.Count -eq 1)
                                            {
                                                $UMIResourceIds += $umis[0].Id
                                                Write-Host $("  ✓ Found UMI: {0} (RG: {1})" -f $umiName, $umis[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple UMIs with same name - prompt user to select
                                                Write-Host $("  Multiple UMIs named '{0}' found:" -f $umiName) -ForegroundColor Yellow
                                                for ($i = 0; $i -lt $umis.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $umis[$i].ResourceGroupName, $umis[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select UMI (1-{0})" -f $umis.Count)
                                                $selectedIndex = [int]$selection - 1
                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $umis.Count)
                                                    {
                                                        $UMIResourceIds += $umis[$selectedIndex].Id
                                                        Write-Host $("  ✓ Selected: {0} (RG: {1})" -f $umiName, $umis[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                    } `
                                                else
                                                    {
                                                        Write-Warning $("Invalid selection for UMI '{0}'" -f $umiName)
                                                    }
                                            }
                                    }
                            } `
                        elseif ($UMIResourceGroup)
                            {
                                # No UMI names provided, but RG specified for pre-deployment analysis
                                $rgExists = Get-AzResourceGroup -Name $UMIResourceGroup -ErrorAction SilentlyContinue
                                if ($rgExists)
                                    {
                                        $reportData.ResourcesAnalyzed.UMIs += [PSCustomObject]  @{
                                                                                                    Name = $("N/A (Pre-deployment)")
                                                                                                    ResourceId = $("N/A (Pre-deployment)")
                                                                                                    ResourceGroupName = $UMIResourceGroup
                                                                                                    Location = $rgExists.Location
                                                                                                    PrincipalId = $("N/A (Pre-deployment)")
                                                                                                    ClientId = $("N/A (Pre-deployment)")
                                                                                                    Status = $("Planned Deployment")
                                                                                                }
                                        Write-Host $("  ℹ Analyzing policies for UMI deployment in RG: {0}" -f $UMIResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("UMI Resource Group '{0}' not found" -f $UMIResourceGroup)
                                    }
                            }

                        Write-Host $("")
                    }

                # Interactive mode - removed duplicate section that was previously here
            }

        process
            {
                Write-Host $("Collecting Policy Assignments...") -ForegroundColor Yellow

                # Get all policy assignments
                $allPolicyAssignments = Get-AzPolicyAssignment
                Write-Host $("  Found {0} policy assignment(s){1}" -f $allPolicyAssignments.Count, [Environment]::NewLine) -ForegroundColor Gray

                foreach ($assignment in $allPolicyAssignments)
                    {
                        Write-Verbose $("Processing policy: {0}" -f $assignment.Name)

                        # Get policy definition details
                        try
                            {
                                # Use the established subscription context for policy definition retrieval
                                $definition = Get-AzPolicyDefinition -Id $assignment.PolicyDefinitionId -SubscriptionId $context.Subscription.Id -ErrorAction Stop

                                # Determine scope type
                                $scopeType = if ($assignment.Scope -like $("*/managementGroups/*")) {$("ManagementGroup")} `
                                            elseif ($assignment.Scope -like $("*/resourceGroups/*")) {$("ResourceGroup")} `
                                            else {$("Subscription")}

                                # Check if this policy impacts our target resource group
                                $impactsTargetRG = $false
                                if ($scopeType -eq $("ManagementGroup"))
                                    {
                                        $impactsTargetRG = $true  # Management group policies apply to all subscriptions below
                                    } `
                                elseif ($scopeType -eq $("Subscription") -and $assignment.Scope -like $("*{0}*" -f $context.Subscription.Id))
                                    {
                                        $impactsTargetRG = $true  # Subscription policies apply to all RGs in that subscription
                                    } `
                                elseif ($scopeType -eq $("ResourceGroup") -and $assignment.Scope -like $("*{0}*" -f $ResourceGroupName))
                                    {
                                        $impactsTargetRG = $true  # Direct RG assignment
                                    }

                                # Extract policy effect (handling both simple effects and parameterized effects)
                                $policyEffect = $("Unknown")
                                if ($definition.PolicyRule.then.effect)
                                    {
                                        $policyEffect = $definition.PolicyRule.then.effect
                                    } `
                                elseif ($definition.PolicyRule.then.details.type)
                                    {
                                        $policyEffect = $definition.PolicyRule.then.details.type
                                    }

                                $policyData = [PSCustomObject] @{
                                                                    AssignmentName = $assignment.Name
                                                                    AssignmentDisplayName = $assignment.DisplayName
                                                                    AssignmentId = $assignment.Id
                                                                    PolicyDefinitionId = $assignment.PolicyDefinitionId
                                                                    PolicyDefinitionName = $definition.Name
                                                                    PolicyDisplayName = $definition.DisplayName
                                                                    PolicyDescription = $definition.Description
                                                                    Scope = $assignment.Scope
                                                                    ScopeType = $scopeType
                                                                    ImpactsTargetResourceGroup = $impactsTargetRG
                                                                    EnforcementMode = $assignment.EnforcementMode
                                                                    PolicyType = $definition.PolicyType
                                                                    Mode = $definition.Mode
                                                                    Effect = $policyEffect
                                                                    NotScopes = ($assignment.NotScope -join $("; "))
                                                                    Parameters = ($assignment.Parameter | ConvertTo-Json -Compress -Depth 3)
                                                                }

                                $reportData.PolicyAssignments += $policyData
                            } `
                        catch
                            {
                                $errorMessage = $_.Exception.Message
                                $isPermissionError = $errorMessage -match $("(Authorization|Forbidden|403|permissions|authorized)")

                                $issueType = if ($isPermissionError) {$("Permission Denied")} else {$("Access Error")}

                                Write-Warning $("Failed to get definition for policy {0}: {1}" -f $assignment.Name, $errorMessage)

                                $reportData.AccessIssues += [PSCustomObject]    @{
                                                                                    ResourceType = $("Policy Definition")
                                                                                    ResourceName = $assignment.Name
                                                                                    ResourceId = $assignment.PolicyDefinitionId
                                                                                    Scope = $assignment.Scope
                                                                                    IssueType = $issueType
                                                                                    ErrorMessage = $errorMessage
                                                                                    Impact = $("Policy details unavailable - may affect deployment planning")
                                                                                }
                            }
                    }

                Write-Host $("Checking for Policy Exemptions...") -ForegroundColor Yellow

                # Get policy exemptions
                try
                    {
                        $exemptions = Get-AzPolicyExemption -ErrorAction SilentlyContinue
                        if ($exemptions)
                            {
                                Write-Host $("  Found {0} exemption(s){1}" -f $exemptions.Count, [Environment]::NewLine) -ForegroundColor Gray

                                foreach ($exemption in $exemptions)
                                    {
                                        $exemptionData = [PSCustomObject]  @{
                                                                                ExemptionName = $exemption.Name
                                                                                DisplayName = $exemption.DisplayName
                                                                                ExemptionCategory = $exemption.ExemptionCategory
                                                                                PolicyAssignmentId = $exemption.PolicyAssignmentId
                                                                                Scope = $exemption.Scope
                                                                                Description = $exemption.Description
                                                                                ExpiresOn = $exemption.ExpiresOn
                                                                            }
                                        $reportData.PolicyExemptions += $exemptionData
                                    }
                            } `
                        else
                            {
                                Write-Host $("  No policy exemptions found{0}" -f [Environment]::NewLine) -ForegroundColor Gray
                            }
                    } `
                catch
                    {
                        $errorMessage = $_.Exception.Message
                        $isPermissionError = $errorMessage -match $("(Authorization|Forbidden|403|permissions|authorized)")

                        $issueType = if ($isPermissionError) {$("Permission Denied")} else {$("Access Error")}

                        Write-Warning $("Could not retrieve policy exemptions: {0}" -f $errorMessage)

                        $reportData.AccessIssues += [PSCustomObject]    @{
                                                                            ResourceType = $("Policy Exemptions")
                                                                            ResourceName = $("All Exemptions")
                                                                            ResourceId = $("N/A")
                                                                            Scope = $("Subscription")
                                                                            IssueType = $issueType
                                                                            ErrorMessage = $errorMessage
                                                                            Impact = $("Unable to identify exempted policies - report may show policies that don't apply")
                                                                        }
                    }

                # Analyze VNets
                if ($VNetResourceIds)
                    {
                        Write-Host $("Analyzing Virtual Networks...") -ForegroundColor Yellow
                        foreach ($vnetId in $VNetResourceIds)
                            {
                                try
                                    {
                                        $vnet = Get-AzResource -ResourceId $vnetId -ErrorAction Stop
                                        $reportData.ResourcesAnalyzed.VNets += [PSCustomObject]  @{
                                                                                                    Name = $vnet.Name
                                                                                                    ResourceId = $vnet.ResourceId
                                                                                                    ResourceGroupName = $vnet.ResourceGroupName
                                                                                                    Location = $vnet.Location
                                                                                                }
                                        Write-Host $("  Added: {0}" -f $vnet.Name) -ForegroundColor Gray
                                    } `
                                catch
                                    {
                                        Write-Warning $("Could not find VNet: {0}" -f $vnetId)
                                    }
                            }
                        Write-Host $("")
                    }

                # Analyze NSGs
                if ($NSGResourceIds)
                    {
                        Write-Host $("Analyzing Network Security Groups...") -ForegroundColor Yellow
                        foreach ($nsgId in $NSGResourceIds)
                            {
                                try
                                    {
                                        $nsg = Get-AzResource -ResourceId $nsgId -ErrorAction Stop
                                        $reportData.ResourcesAnalyzed.NSGs += [PSCustomObject]  @{
                                                                                                    Name = $nsg.Name
                                                                                                    ResourceId = $nsg.ResourceId
                                                                                                    ResourceGroupName = $nsg.ResourceGroupName
                                                                                                    Location = $nsg.Location
                                                                                                }
                                        Write-Host $("  Added: {0}" -f $nsg.Name) -ForegroundColor Gray
                                    } `
                                catch
                                    {
                                        Write-Warning $("Could not find NSG: {0}" -f $nsgId)
                                    }
                            }
                        Write-Host $("")
                    }

                # Analyze UMIs
                if ($UMIResourceIds)
                    {
                        Write-Host $("Analyzing User-Assigned Managed Identities...") -ForegroundColor Yellow
                        foreach ($umiId in $UMIResourceIds)
                            {
                                try
                                    {
                                        $umi = Get-AzResource -ResourceId $umiId -ErrorAction Stop

                                        $umiData = [PSCustomObject]  @{
                                                                        Name = $umi.Name
                                                                        ResourceId = $umi.ResourceId
                                                                        ResourceGroupName = $umi.ResourceGroupName
                                                                        Location = $umi.Location
                                                                        PrincipalId = $null
                                                                        ClientId = $null
                                                                    }

                                        # Try to get UMI details
                                        try
                                            {
                                                $umiDetails = Get-AzUserAssignedIdentity -ResourceGroupName $umi.ResourceGroupName -Name $umi.Name -ErrorAction SilentlyContinue
                                                if ($umiDetails)
                                                    {
                                                        $umiData.PrincipalId = $umiDetails.PrincipalId
                                                        $umiData.ClientId = $umiDetails.ClientId
                                                    }
                                            } `
                                        catch
                                            {
                                                Write-Verbose $("Could not get UMI details for {0}" -f $umi.Name)
                                            }

                                        $reportData.ResourcesAnalyzed.UMIs += $umiData
                                        Write-Host $("  Added: {0}" -f $umi.Name) -ForegroundColor Gray
                                    } `
                                catch
                                    {
                                        Write-Warning $("Could not find UMI: {0}" -f $umiId)
                                    }
                            }
                        Write-Host $("")
                    }

                # Get role assignments if requested
                if ($IncludeRoleAssignments)
                    {
                        Write-Host $("Collecting Role Assignments...") -ForegroundColor Yellow

                        # Get role assignments at subscription level
                        $subRoles = Get-AzRoleAssignment -Scope $("/subscriptions/{0}" -f $context.Subscription.Id) -ErrorAction SilentlyContinue

                        # Get role assignments at resource group level
                        $rgRoles = Get-AzRoleAssignment -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

                        $allRoles = @($subRoles) + @($rgRoles) | Select-Object -Unique -Property RoleAssignmentId, *

                        Write-Host $("  Found {0} role assignment(s){1}" -f $allRoles.Count, [Environment]::NewLine) -ForegroundColor Gray

                        foreach ($role in $allRoles)
                            {
                                $roleData = [PSCustomObject]  @{
                                                                DisplayName = $role.DisplayName
                                                                SignInName = $role.SignInName
                                                                RoleDefinitionName = $role.RoleDefinitionName
                                                                RoleDefinitionId = $role.RoleDefinitionId
                                                                ObjectType = $role.ObjectType
                                                                Scope = $role.Scope
                                                                CanDelegate = $role.CanDelegate
                                                            }
                                $reportData.RoleAssignments += $roleData
                            }
                    }

                # Create scope analysis summary
                $scopeSummary = @{
                                    TotalPolicies = $reportData.PolicyAssignments.Count
                                    ManagementGroupPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("ManagementGroup")}).Count
                                    SubscriptionPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("Subscription")}).Count
                                    ResourceGroupPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("ResourceGroup")}).Count
                                    PoliciesImpactingTargetRG = ($reportData.PolicyAssignments | Where-Object {$_.ImpactsTargetResourceGroup}).Count
                                    TotalExemptions = $reportData.PolicyExemptions.Count
                                    EnforcedPolicies = ($reportData.PolicyAssignments | Where-Object {$_.EnforcementMode -eq $("Default")}).Count
                                    AuditOnlyPolicies = ($reportData.PolicyAssignments | Where-Object {$_.EnforcementMode -eq $("DoNotEnforce")}).Count
                                    AccessIssuesCount = $reportData.AccessIssues.Count
                                    PermissionDeniedCount = ($reportData.AccessIssues | Where-Object {$_.IssueType -eq $("Permission Denied")}).Count
                                }

                $reportData.ScopeAnalysis = [PSCustomObject]$scopeSummary

                Write-Host $("{0}========================================" -f [Environment]::NewLine) -ForegroundColor Green
                Write-Host $("Policy Analysis Summary") -ForegroundColor Green
                Write-Host $("========================================") -ForegroundColor Green
                Write-Host $("Total Policies: {0}" -f $scopeSummary.TotalPolicies) -ForegroundColor White
                Write-Host $("  Management Group: {0}" -f $scopeSummary.ManagementGroupPolicies) -ForegroundColor Gray
                Write-Host $("  Subscription: {0}" -f $scopeSummary.SubscriptionPolicies) -ForegroundColor Gray
                Write-Host $("  Resource Group: {0}" -f $scopeSummary.ResourceGroupPolicies) -ForegroundColor Gray
                Write-Host $("Policies Impacting Target RG: {0}" -f $scopeSummary.PoliciesImpactingTargetRG) -ForegroundColor Yellow
                Write-Host $("Policy Exemptions: {0}" -f $scopeSummary.TotalExemptions) -ForegroundColor Cyan
                Write-Host $("Enforced: {0} | Audit Only: {1}" -f $scopeSummary.EnforcedPolicies, $scopeSummary.AuditOnlyPolicies) -ForegroundColor White

                # Display permission context
                Write-Host $("{0}--- Permission Context ---" -f [Environment]::NewLine) -ForegroundColor Cyan
                Write-Host $("Your Role Assignments: {0}" -f $reportData.PermissionContext.Roles.Count) -ForegroundColor White
                Write-Host $("  Management Group Access: {0}" -f $reportData.PermissionContext.HasManagementGroupAccess) -ForegroundColor $(if ($reportData.PermissionContext.HasManagementGroupAccess) {$("Green")} else {$("Yellow")})
                Write-Host $("  Subscription Reader+: {0}" -f $reportData.PermissionContext.HasSubscriptionReaderOrHigher) -ForegroundColor $(if ($reportData.PermissionContext.HasSubscriptionReaderOrHigher) {$("Green")} else {$("Yellow")})

                if ($reportData.PermissionContext.PotentialBlindSpots.Count -gt 0)
                    {
                        Write-Host $("{0}⚠️  Potential Blind Spots: {1}" -f [Environment]::NewLine, $reportData.PermissionContext.PotentialBlindSpots.Count) -ForegroundColor Yellow
                        foreach ($blindSpot in $reportData.PermissionContext.PotentialBlindSpots)
                            {
                                $severityColor = switch ($blindSpot.Severity)
                                    {
                                        $("Critical") {$("Red")}
                                        $("High") {$("Red")}
                                        $("Medium") {$("Yellow")}
                                        default {$("Gray")}
                                    }
                                Write-Host $("  [{0}] {1}" -f $blindSpot.Severity, $blindSpot.Area) -ForegroundColor $severityColor
                            }
                        Write-Host $("  ⓘ  See report for detailed blind spot analysis") -ForegroundColor Cyan
                    } `
                else
                    {
                        Write-Host $("  ✓ No obvious permission gaps detected") -ForegroundColor Green
                    }

                if ($reportData.AccessIssues.Count -gt 0)
                    {
                        $accessIssueColor = if ($scopeSummary.PermissionDeniedCount -gt 0) {$("Red")} else {$("Yellow")}
                        $permissionDeniedColor = if ($scopeSummary.PermissionDeniedCount -gt 0) {$("Red")} else {$("Green")}
                        Write-Host $("{0}⚠️  Access Issues Detected: {1}" -f [Environment]::NewLine, $reportData.AccessIssues.Count) -ForegroundColor $accessIssueColor
                        Write-Host $("  Permission Denied: {0}" -f $scopeSummary.PermissionDeniedCount) -ForegroundColor $permissionDeniedColor
                        Write-Host $("  Other Errors: {0}" -f ($reportData.AccessIssues.Count - $scopeSummary.PermissionDeniedCount)) -ForegroundColor Yellow
                        Write-Host $("  ⓘ  Some policy details may be incomplete - see report for details") -ForegroundColor Cyan
                    }

                Write-Host $("")
            }

        end
            {
                # Export reports
                $timestamp = Get-Date -Format $("yyyyMMdd-HHmmss")
                $baseFileName = $("{0}-{1}" -f $ReportName, $timestamp)

                Write-Host $("Exporting Reports...") -ForegroundColor Yellow

                if ($OutputFormat -eq $('JSON') -or $OutputFormat -eq $('All'))
                    {
                        $jsonPath = Join-Path $OutputPath $("{0}.json" -f $baseFileName)
                        $reportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
                        Write-Host $("  JSON report saved: {0}" -f $jsonPath) -ForegroundColor Green
                    }

                if ($OutputFormat -eq $('CSV') -or $OutputFormat -eq $('All'))
                    {
                        $csvPath = Join-Path $OutputPath $("{0}-Policies.csv" -f $baseFileName)
                        $reportData.PolicyAssignments | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                        Write-Host $("  CSV report saved: {0}" -f $csvPath) -ForegroundColor Green

                        if ($reportData.PolicyExemptions.Count -gt 0)
                            {
                                $exemptionCsvPath = Join-Path $OutputPath $("{0}-Exemptions.csv" -f $baseFileName)
                                $reportData.PolicyExemptions | Export-Csv -Path $exemptionCsvPath -NoTypeInformation -Encoding UTF8
                                Write-Host $("  Exemptions CSV saved: {0}" -f $exemptionCsvPath) -ForegroundColor Green
                            }

                        if ($IncludeRoleAssignments -and $reportData.RoleAssignments.Count -gt 0)
                            {
                                $rolesCsvPath = Join-Path $OutputPath $("{0}-RoleAssignments.csv" -f $baseFileName)
                                $reportData.RoleAssignments | Export-Csv -Path $rolesCsvPath -NoTypeInformation -Encoding UTF8
                                Write-Host $("  Role Assignments CSV saved: {0}" -f $rolesCsvPath) -ForegroundColor Green
                            }

                        if ($reportData.AccessIssues.Count -gt 0)
                            {
                                $accessIssuesCsvPath = Join-Path $OutputPath $("{0}-AccessIssues.csv" -f $baseFileName)
                                $reportData.AccessIssues | Export-Csv -Path $accessIssuesCsvPath -NoTypeInformation -Encoding UTF8
                                Write-Host $("  Access Issues CSV saved: {0}" -f $accessIssuesCsvPath) -ForegroundColor Yellow
                            }
                    }

                if ($OutputFormat -eq $('HTML') -or $OutputFormat -eq $('All'))
                    {
                        $htmlPath = Join-Path $OutputPath $("{0}.html" -f $baseFileName)
                        $html = Generate-HTMLReport -ReportData $reportData
                        $html | Out-File -FilePath $htmlPath -Encoding UTF8
                        Write-Host $("  HTML report saved: {0}" -f $htmlPath) -ForegroundColor Green
                    }

                Write-Host $("{0}Report generation complete!" -f [Environment]::NewLine) -ForegroundColor Green
                Write-Host $("========================================{0}" -f [Environment]::NewLine) -ForegroundColor Cyan

                return $reportData
            }
    }   # End of Get-AzPolicyImpactReport function

function Generate-HTMLReport
    {
        param($ReportData)

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$("Azure Policy Impact Assessment Report")</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #106ebe; margin-top: 30px; border-bottom: 2px solid #e0e0e0; padding-bottom: 5px; }
        .metadata { background-color: #e7f3ff; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .summary { background-color: #fff; padding: 15px; border-radius: 5px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .summary-box { background-color: #f9f9f9; padding: 10px; border-left: 4px solid #0078d4; }
        .summary-box .label { font-size: 12px; color: #666; }
        .summary-box .value { font-size: 24px; font-weight: bold; color: #0078d4; }
        table { width: 100%; border-collapse: collapse; background-color: white; box-shadow: 0 2px 4px rgba(0,0,0,0.1); margin-bottom: 20px; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background-color: #f5f5f5; }
        .scope-mgmt { color: #d13438; font-weight: bold; }
        .scope-sub { color: #ff8c00; font-weight: bold; }
        .scope-rg { color: #107c10; font-weight: bold; }
        .enforced { color: #d13438; font-weight: bold; }
        .audit-only { color: #ff8c00; }
        .impact-yes { background-color: #fff4ce; }
        .impact-no { background-color: #f0f0f0; }
    </style>
</head>
<body>
    <h1>$("Azure Policy Impact Assessment Report")</h1>

    <div class="metadata">
        <strong>Generated:</strong> $($ReportData.Metadata.GeneratedDate)<br>
        <strong>Subscription:</strong> $($ReportData.Metadata.SubscriptionName) ($($ReportData.Metadata.SubscriptionId))<br>
        <strong>Silk Resource Group (Target):</strong> $($ReportData.Metadata.SilkResourceGroupName)<br>
        <strong>Generated By:</strong> $($ReportData.Metadata.GeneratedBy)
    </div>

    <div style="background-color: #e7f3ff; border-left: 5px solid #0078d4; padding: 15px; margin-bottom: 20px; border-radius: 5px;">
        <h2 style="margin-top: 0; color: #0078d4;">📋 Permission Context & Visibility</h2>
        <p><strong>Your Identity:</strong> $($ReportData.PermissionContext.UserIdentity)</p>
        <p><strong>Role Assignments Found:</strong> $($ReportData.PermissionContext.Roles.Count)</p>
        <ul>
            <li><strong>Management Group Access:</strong> $(if ($ReportData.PermissionContext.HasManagementGroupAccess) { "✓ Yes" } else { "✗ No" })</li>
            <li><strong>Subscription Reader or Higher:</strong> $(if ($ReportData.PermissionContext.HasSubscriptionReaderOrHigher) { "✓ Yes" } else { "✗ No" })</li>
        </ul>

        $(if ($ReportData.PermissionContext.PotentialBlindSpots.Count -gt 0) {
            "<h3 style='color: #d13438;'>⚠️ Potential Blind Spots ($($ReportData.PermissionContext.PotentialBlindSpots.Count))</h3>"
            "<p><em>Based on your current permissions, the following areas may have limited visibility:</em></p>"
            "<table style='margin-top: 10px;'>"
            "<tr><th>Area</th><th>Severity</th><th>Description</th><th>Impact</th><th>Recommendation</th></tr>"
            foreach ($blindSpot in $ReportData.PermissionContext.PotentialBlindSpots) {
                $severityColor = switch ($blindSpot.Severity) {
                    "Critical" { "#d13438" }
                    "High" { "#d13438" }
                    "Medium" { "#ff8c00" }
                    default { "#666" }
                }
                "<tr>"
                "<td><strong>$($blindSpot.Area)</strong></td>"
                "<td><strong style='color: $severityColor;'>$($blindSpot.Severity)</strong></td>"
                "<td>$($blindSpot.Description)</td>"
                "<td>$($blindSpot.Impact)</td>"
                "<td><em>$($blindSpot.Recommendation)</em></td>"
                "</tr>"
            }
            "</table>"
        } else {
            "<p style='color: #107c10;'><strong>✓ No obvious permission gaps detected.</strong> Your access appears sufficient for comprehensive policy analysis.</p>"
        })
    </div>

    <div class="summary">
        <h2>Summary</h2>
        <div class="summary-grid">
            <div class="summary-box">
                <div class="label">Total Policies</div>
                <div class="value">$($ReportData.ScopeAnalysis.TotalPolicies)</div>
            </div>
            <div class="summary-box">
                <div class="label">Management Group</div>
                <div class="value">$($ReportData.ScopeAnalysis.ManagementGroupPolicies)</div>
            </div>
            <div class="summary-box">
                <div class="label">Subscription</div>
                <div class="value">$($ReportData.ScopeAnalysis.SubscriptionPolicies)</div>
            </div>
            <div class="summary-box">
                <div class="label">Resource Group</div>
                <div class="value">$($ReportData.ScopeAnalysis.ResourceGroupPolicies)</div>
            </div>
            <div class="summary-box">
                <div class="label">Impacting Target RG</div>
                <div class="value">$($ReportData.ScopeAnalysis.PoliciesImpactingTargetRG)</div>
            </div>
            <div class="summary-box">
                <div class="label">Exemptions</div>
                <div class="value">$($ReportData.ScopeAnalysis.TotalExemptions)</div>
            </div>
        </div>
    </div>

    <h2>Policy Assignments</h2>
    <table>
        <tr>
            <th>Assignment Name</th>
            <th>Display Name</th>
            <th>Scope Type</th>
            <th>Enforcement</th>
            <th>Policy Type</th>
            <th>Mode</th>
            <th>Impacts Target RG</th>
        </tr>
"@

    foreach ($policy in $ReportData.PolicyAssignments)
        {
            $scopeClass = switch ($policy.ScopeType)
                {
                    $("ManagementGroup") {$("scope-mgmt")}
                    $("Subscription") {$("scope-sub")}
                    $("ResourceGroup") {$("scope-rg")}
                }

            $enforcementClass = if ($policy.EnforcementMode -eq $("Default")) {$("enforced")} else {$("audit-only")}
            $impactClass = if ($policy.ImpactsTargetResourceGroup) {$("impact-yes")} else {$("impact-no")}
            $impactText = if ($policy.ImpactsTargetResourceGroup) {$("YES")} else {$("No")}

            $html += @"
        <tr>
            <td>$($policy.AssignmentName)</td>
            <td>$($policy.AssignmentDisplayName)</td>
            <td class="$scopeClass">$($policy.ScopeType)</td>
            <td class="$enforcementClass">$($policy.EnforcementMode)</td>
            <td>$($policy.PolicyType)</td>
            <td>$($policy.Mode)</td>
            <td class="$impactClass">$impactText</td>
        </tr>
"@
        }

    $html += $("</table>")

    if ($ReportData.PolicyExemptions.Count -gt 0)
        {
            $html += @"
    <h2>$("Policy Exemptions")</h2>
    <table>
        <tr>
            <th>$("Exemption Name")</th>
            <th>$("Category")</th>
            <th>$("Policy Assignment")</th>
            <th>$("Scope")</th>
            <th>$("Expires On")</th>
        </tr>
"@
            foreach ($exemption in $ReportData.PolicyExemptions)
                {
                    $expiresText = if ($exemption.ExpiresOn) {$exemption.ExpiresOn} else {$("No Expiration")}
                    $html += @"
        <tr>
            <td>$($exemption.ExemptionName)</td>
            <td>$($exemption.ExemptionCategory)</td>
            <td>$($exemption.PolicyAssignmentId.Split('/')[-1])</td>
            <td>$($exemption.Scope)</td>
            <td>$expiresText</td>
        </tr>
"@
                }
            $html += $("</table>")
        }

    if ($ReportData.ResourcesAnalyzed.VNets.Count -gt 0)
        {
            $html += $("<h2>Virtual Networks Analyzed</h2><table><tr><th>Name</th><th>Resource Group</th><th>Location</th></tr>")
            foreach ($vnet in $ReportData.ResourcesAnalyzed.VNets)
                {
                    $html += $("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f $vnet.Name, $vnet.ResourceGroupName, $vnet.Location)
                }
            $html += $("</table>")
        }

    if ($ReportData.ResourcesAnalyzed.NSGs.Count -gt 0)
        {
            $html += $("<h2>Network Security Groups Analyzed</h2><table><tr><th>Name</th><th>Resource Group</th><th>Location</th></tr>")
            foreach ($nsg in $ReportData.ResourcesAnalyzed.NSGs)
                {
                    $html += $("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f $nsg.Name, $nsg.ResourceGroupName, $nsg.Location)
                }
            $html += $("</table>")
        }

    if ($ReportData.ResourcesAnalyzed.UMIs.Count -gt 0)
        {
            $html += $("<h2>User-Assigned Managed Identities Analyzed</h2><table><tr><th>Name</th><th>Resource Group</th><th>Principal ID</th></tr>")
            foreach ($umi in $ReportData.ResourcesAnalyzed.UMIs)
                {
                    $html += $("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f $umi.Name, $umi.ResourceGroupName, $umi.PrincipalId)
                }
            $html += $("</table>")
        }

    if ($ReportData.RoleAssignments.Count -gt 0)
        {
            $html += $("<h2>Role Assignments</h2><table><tr><th>Display Name</th><th>Role</th><th>Object Type</th><th>Scope</th></tr>")
            foreach ($role in $ReportData.RoleAssignments)
                {
                    $html += $("<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>" -f $role.DisplayName, $role.RoleDefinitionName, $role.ObjectType, $role.Scope)
                }
            $html += $("</table>")
        }

    # Add Access Issues section if any issues were encountered
    if ($ReportData.AccessIssues.Count -gt 0)
        {
            $permissionCount = ($ReportData.AccessIssues | Where-Object {$_.IssueType -eq $("Permission Denied")}).Count
            $otherCount = $ReportData.AccessIssues.Count - $permissionCount

            $html += @"
    <div style="background-color: #fff4ce; border-left: 5px solid #ff8c00; padding: 15px; margin-top: 30px; border-radius: 5px;">
        <h2 style="color: #d13438; margin-top: 0;">$("⚠️ Access Issues Detected")</h2>
        <p><strong>$("Warning:")</strong> $("This report encountered {0} access issue(s) during data collection. Some policy information may be incomplete." -f $ReportData.AccessIssues.Count)</p>
        <ul>
            <li><strong>$("Permission Denied:")</strong> $permissionCount</li>
            <li><strong>$("Other Access Errors:")</strong> $otherCount</li>
        </ul>
        <p><em>$("ⓘ Impact: The report may not reflect all policies that could affect your deployment. Consider running this report with an account that has Reader access at Management Group level for complete visibility.")</em></p>
    </div>

    <h2 style="color: #d13438;">$("Access Issues Details")</h2>
    <table>
        <tr>
            <th>$("Resource Type")</th>
            <th>$("Resource Name")</th>
            <th>$("Scope")</th>
            <th>$("Issue Type")</th>
            <th>$("Error Message")</th>
            <th>$("Impact")</th>
        </tr>
"@
            foreach ($issue in $ReportData.AccessIssues)
                {
                    $issueColor = if ($issue.IssueType -eq $("Permission Denied")) {$("background-color: #fde7e9;")} else {$("background-color: #fff4ce;")}
                    $html += @"
        <tr style="$issueColor">
            <td>$($issue.ResourceType)</td>
            <td>$($issue.ResourceName)</td>
            <td>$($issue.Scope)</td>
            <td><strong>$($issue.IssueType)</strong></td>
            <td><small>$($issue.ErrorMessage)</small></td>
            <td>$($issue.Impact)</td>
        </tr>
"@
                }
            $html += $("</table>")
        }

    $html += $("</body></html>")

    return $html
    }   # End of Generate-HTMLReport function

Export-ModuleMember -Function Get-AzPolicyImpactReport

