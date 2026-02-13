<#
.SYNOPSIS
    Generates a comprehensive Azure Policy impact assessment report for specified resources and scopes.

.DESCRIPTION
    This module collects all Azure Policy assignments that could impact deployment or configuration
    at multiple scopes including subscription, resource groups, VNets, NSGs, UMIs, and custom roles.

    The report includes:
    - Policy assignments at all hierarchy levels (Management Group, Subscription, Resource Group, and Resource)
    - Policy definitions with detailed rules and effects
    - Policy exemptions
    - Scope analysis showing which policies apply where
    - Export to JSON format with complete policy rule details for deployment assessment

.PARAMETER SubscriptionId
    The Azure Subscription ID to analyze. If not provided and FlexResourceGroupName is specified, subscription will be auto-discovered from the resource group. Otherwise, you will be prompted to select a subscription (press Enter to use current context as default).

.PARAMETER SubscriptionName
    The Azure Subscription Name to analyze (alternative to SubscriptionId). If not provided and FlexResourceGroupName is specified, subscription will be auto-discovered from the resource group. Otherwise, you will be prompted to select a subscription (press Enter to use current context as default).

.PARAMETER FlexResourceGroupName
    The Silk Resource Group name - the primary target resource group where Silk Flex resources will be deployed.

.PARAMETER VNetName
    Array of Virtual Network names. If multiple VNets with the same name exist, you'll be prompted to select.

.PARAMETER VNetResourceGroup
    Resource group where VNet will be deployed (even if it doesn't exist yet). Use this to assess policies without existing resources.

.PARAMETER NSGName
    Array of Network Security Group names. If multiple NSGs with the same name exist, you'll be prompted to select.

.PARAMETER NSGResourceGroup
    Resource group where NSGs will be deployed (even if they don't exist yet). Use this to assess policies without existing resources.

.PARAMETER UMIName
    Array of User-Assigned Managed Identity names. If multiple UMIs with the same name exist, you'll be prompted to select.

.PARAMETER UMIResourceGroup
    Resource group where UMI will be deployed (even if it doesn't exist yet). Use this to assess policies without existing resources.

.PARAMETER OutputPath
    Directory path where report will be saved. Default is current directory.

#>

function Get-AzPolicyImpactReport
    {
        [CmdletBinding  (
                            DefaultParameterSetName = $('Default'),
                            PositionalBinding = $false,
                            HelpURI = $("https://github.com/silk-us/scripts-and-configs/tree/main/Azure/Policy%20Impact%20Assessment")
                        )]

        param
            (
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'Default',
                                HelpMessage = 'Azure Subscription ID'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Azure Subscription ID'
                            )]
                [string]
                $SubscriptionId,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'Default',
                                HelpMessage = 'Azure Subscription Name'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Azure Subscription Name'
                            )]
                [string]
                $SubscriptionName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'Default',
                                HelpMessage = 'Silk Resource Group name where resources will be deployed'
                            )]
                [Parameter  (
                                Mandatory = $true,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Silk Resource Group name where resources will be deployed'
                            )]
                [string]
                $FlexResourceGroupName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Array of Virtual Network names'
                            )]
                [string[]]
                $VNetName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Resource group where VNet will be deployed'
                            )]
                [string]
                $VNetResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Array of Network Security Group names'
                            )]
                [string[]]
                $NSGName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Resource group where NSGs will be deployed'
                            )]
                [string]
                $NSGResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Array of User-Assigned Managed Identity names'
                            )]
                [string[]]
                $UMIName,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Resource group where UMI will be deployed'
                            )]
                [string]
                $UMIResourceGroup,

                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'Default',
                                HelpMessage = 'Directory path for output files'
                            )]
                [Parameter  (
                                Mandatory = $false,
                                ParameterSetName = 'WithResources',
                                HelpMessage = 'Directory path for output files'
                            )]
                [string]
                $OutputPath = '.'
            )

        begin
            {
                Write-Host $("{0}{1}" -f [Environment]::NewLine, $("========================================")) -ForegroundColor Cyan
                Write-Host $("Azure Policy Impact Assessment Report") -ForegroundColor Cyan
                Write-Host $("{0}{1}" -f $("========================================"), [Environment]::NewLine) -ForegroundColor Cyan

                # Validate Azure context
                try
                    {
                        $azContext = Get-AzContext
                        if (-not $azContext)
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
                                $azContext = Get-AzContext
                            } `
                        elseif ($SubscriptionId)
                            {
                                Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
                                $azContext = Get-AzContext
                            } `
                        elseif ($FlexResourceGroupName)
                            {
                                # Auto-discover subscription from resource group name
                                Write-Host $("Searching for resource group '{0}' across all subscriptions..." -f $FlexResourceGroupName) -ForegroundColor Yellow
                                $allSubs = Get-AzSubscription
                                $foundRGs =    @()

                                foreach ($sub in $allSubs)
                                    {
                                        Set-AzContext -SubscriptionId $sub.Id | Out-Null
                                        $rg = Get-AzResourceGroup -Name $FlexResourceGroupName -ErrorAction SilentlyContinue
                                        if ($rg)
                                            {
                                                $foundRGs += [PSCustomObject]@{
                                                    Subscription = $sub
                                                    ResourceGroup = $rg
                                                }
                                            }
                                    }

                                if ($foundRGs.Count -eq 0)
                                    {
                                        throw $("Resource group '{0}' not found in any accessible subscription" -f $FlexResourceGroupName)
                                    } `
                                elseif ($foundRGs.Count -eq 1)
                                    {
                                        Set-AzContext -SubscriptionId $foundRGs[0].Subscription.Id | Out-Null
                                        $azContext = Get-AzContext
                                        Write-Host $("  [OK] Found in subscription: {0}" -f $foundRGs[0].Subscription.Name) -ForegroundColor Green
                                    } `
                                else
                                    {
                                        # Multiple found - prompt user
                                        Write-Host $("  Resource group '{0}' found in multiple subscriptions:" -f $FlexResourceGroupName) -ForegroundColor Yellow
                                        Write-Host $("  Please select which subscription contains the '{0}' resource group to analyze:" -f $FlexResourceGroupName) -ForegroundColor Cyan
                                        for ($i = 0; $i -lt $foundRGs.Count; $i++)
                                            {
                                                Write-Host $("    [{0}] {1} (ID: {2})" -f ($i+1), $foundRGs[$i].Subscription.Name, $foundRGs[$i].Subscription.Id)
                                            }
                                        $selection = Read-Host $("  Select subscription for resource group '{0}' (1-{1})" -f $FlexResourceGroupName, $foundRGs.Count)
                                        $selectedIndex = [int]$selection - 1
                                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $foundRGs.Count)
                                            {
                                                Set-AzContext -SubscriptionId $foundRGs[$selectedIndex].Subscription.Id | Out-Null
                                                $azContext = Get-AzContext
                                                Write-Host $("  [OK] Selected: {0}" -f $foundRGs[$selectedIndex].Subscription.Name) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                throw $("Invalid selection")
                                            }
                                    }
                            } `
                        else
                            {
                                # No subscription or RG specified - prompt for subscription
                                $allSubs = Get-AzSubscription
                                if ($allSubs.Count -eq 0)
                                    {
                                        throw $("No Azure subscriptions found")
                                    } `
                                elseif ($allSubs.Count -eq 1)
                                    {
                                        Set-AzContext -SubscriptionId $allSubs[0].Id | Out-Null
                                        $azContext = Get-AzContext
                                    } `
                                else
                                    {
                                        Write-Host $("Select subscription to analyze (or press Enter to use current context):") -ForegroundColor Cyan
                                        for ($i = 0; $i -lt $allSubs.Count; $i++)
                                            {
                                                Write-Host $("  [{0}] {1} (ID: {2})" -f ($i+1), $allSubs[$i].Name, $allSubs[$i].Id)
                                            }
                                        Write-Host $("  Current context: {0}" -f $azContext.Subscription.Name) -ForegroundColor Gray
                                        $selection = Read-Host $("Select subscription (1-{0}) or press Enter for current" -f $allSubs.Count)

                                        if ($selection -and $selection -match $('^\\d+$'))
                                            {
                                                $selectedIndex = [int]$selection - 1
                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $allSubs.Count)
                                                    {
                                                        Set-AzContext -SubscriptionId $allSubs[$selectedIndex].Id | Out-Null
                                                        $azContext = Get-AzContext
                                                        Write-Host $("  [OK] Selected: {0}" -f $azContext.Subscription.Name) -ForegroundColor Green
                                                    } `
                                                else
                                                    {
                                                        throw $("Invalid selection")
                                                    }
                                            } `
                                        else
                                            {
                                                Write-Host $("  [OK] Using current context: {0}" -f $azContext.Subscription.Name) -ForegroundColor Green
                                            }

                                        Write-Host $("  [INFO] Performing subscription-level analysis") -ForegroundColor Gray
                                    }
                            }

                        Write-Host $("{0}Connected to Azure" -f [Environment]::NewLine) -ForegroundColor Green
                        Write-Host $("  Subscription: {0}" -f $azContext.Subscription.Name) -ForegroundColor Gray
                        Write-Host $("  Account: {0}{1}" -f $azContext.Account.Id, [Environment]::NewLine) -ForegroundColor Gray
                    } `
                catch
                    {
                        Write-Error $("Failed to establish Azure context: {0}" -f $_)
                        return
                    }

                # Validate resource group exists (if specified)
                if ($FlexResourceGroupName)
                    {
                        try
                            {
                                $rg = Get-AzResourceGroup -Name $FlexResourceGroupName -ErrorAction Stop
                                Write-Host $("Silk Resource Group (Target): {0}" -f $FlexResourceGroupName) -ForegroundColor Green
                                Write-Host $("  Location: {0}" -f $rg.Location) -ForegroundColor Gray
                                Write-Host $("  ResourceId: {0}{1}" -f $rg.ResourceId, [Environment]::NewLine) -ForegroundColor Gray
                            } `
                        catch
                            {
                                Write-Error $("Resource Group '{0}' not found: {1}" -f $FlexResourceGroupName, $_)
                                return
                            }
                    } `
                else
                    {
                        Write-Host $("No target resource group specified - performing subscription-level analysis only{0}" -f [Environment]::NewLine) -ForegroundColor Gray
                        $rg = $null
                    }


                # Analyze current user's permissions to identify potential blind spots
                Write-Host $("Analyzing your permissions...") -ForegroundColor Yellow
                $userPermissions = @{
                                        UserIdentity = $azContext.Account.Id
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
                        $userRoles = Get-AzRoleAssignment -SignInName $azContext.Account.Id -ErrorAction SilentlyContinue
                        if (-not $userRoles)
                            {
                                # Try with ObjectId if SignInName doesn't work (service principals)
                                $userRoles = Get-AzRoleAssignment -ObjectId $azContext.Account.Id -ErrorAction SilentlyContinue
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
                                                                                                        Severity = $("Major Gap")
                                                                                                        Description = $("No Management Group-level access detected. Policies assigned at Management Group scope may be invisible or details unavailable.")
                                                                                                        Impact = $("Management Group policies can apply to all subscriptions and resources below them. Without MG access, you cannot see policy definitions from parent Management Groups.")
                                                                                                        Recommendation = $("Request Reader role at Management Group level for complete policy visibility.")
                                                                                                    }
                                    }

                                if (-not $userPermissions.HasSubscriptionReaderOrHigher)
                                    {
                                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                        Area = $("Subscription-Level Policies")
                                                                                                        Severity = $("Moderate Gap")
                                                                                                        Description = $("Limited subscription access detected. Some subscription-scoped policies may not be visible.")
                                                                                                        Impact = $("Subscription policies apply to all resource groups. Limited access may result in incomplete policy inventory.")
                                                                                                        Recommendation = $("Request Reader role at Subscription level for full subscription policy visibility.")
                                                                                                    }
                                    }

                                if ($userRoles.Count -eq 0)
                                    {
                                        $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                        Area = $("All Scopes")
                                                                                                        Severity = $("Analysis Blocked")
                                                                                                        Description = $("No role assignments found for current user. This report may be severely incomplete.")
                                                                                                        Impact = $("Without explicit role assignments, policy data collection will fail at most scopes.")
                                                                                                        Recommendation = $("Request appropriate Reader permissions at Subscription or Management Group level.")
                                                                                                    }
                                    }

                                Write-Host $("  [OK] Found {0} role assignment(s)" -f $userRoles.Count) -ForegroundColor Gray
                                Write-Host $("  MG Access: {0}" -f $userPermissions.HasManagementGroupAccess) -ForegroundColor Gray
                                Write-Host $("  Subscription Reader: {0}" -f $userPermissions.HasSubscriptionReaderOrHigher) -ForegroundColor Gray
                                if ($userPermissions.PotentialBlindSpots.Count -gt 0)
                                    {
                                        Write-Host $("  [WARNING] Potential Blind Spots: {0}" -f $userPermissions.PotentialBlindSpots.Count) -ForegroundColor Yellow
                                    }
                            } `
                        else
                            {
                                Write-Warning $("Could not retrieve role assignments for current user")
                                $userPermissions.PotentialBlindSpots += [PSCustomObject]   @{
                                                                                                Area = $("Permission Analysis")
                                                                                                Severity = $("Data Missing")
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
                                                                                        Severity = $("Analysis Error")
                                                                                        Description = $("Error analyzing user permissions: {0}" -f $_.Exception.Message)
                                                                                        Impact = $("Cannot determine what policies may be invisible to current user.")
                                                                                        Recommendation = $("Review Azure RBAC permissions and re-run report.")
                                                                                    }
                    }
                Write-Host $("")

                # Initialize report data structure
                $reportData = @{
                                    Metadata = @{
                                                    GeneratedDate = Get-Date -Format $("yyyy-MM-dd HH:mm:ss")
                                                    SubscriptionId = $azContext.Subscription.Id
                                                    SubscriptionName = $azContext.Subscription.Name
                                                    SilkResourceGroupName = if ($FlexResourceGroupName) {$FlexResourceGroupName} else {$null}
                                                    SilkResourceGroupId = if ($rg) {$rg.ResourceId} else {$null}
                                                    GeneratedBy = $azContext.Account.Id
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
                Write-Host $("Resolving resource names to IDs...") -ForegroundColor Yellow

                # Resolve VNets
                if ($VNetName)
                            {
                                $vnetResourceIds = @()
                                foreach ($vnet in $VNetName)
                                    {
                                        Write-Verbose $("Searching for VNet: {0}" -f $vnet)
                                        $vnets = Get-AzVirtualNetwork | Where-Object {$_.Name -eq $vnet}

                                        if ($vnets.Count -eq 0)
                                            {
                                                Write-Warning $("VNet '{0}' not found" -f $vnet)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $VNetResourceGroup)
                                                    {
                                                        $allRGs = Get-AzResourceGroup | Sort-Object ResourceGroupName
                                                        Write-Host $("  Select resource group where VNet '{0}' will be deployed:" -f $vnet) -ForegroundColor Cyan
                                                        for ($i = 0; $i -lt $allRGs.Count; $i++)
                                                            {
                                                                Write-Host $("    [{0}] {1} ({2})" -f ($i+1), $allRGs[$i].ResourceGroupName, $allRGs[$i].Location)
                                                            }
                                                        $selection = Read-Host $("  Select resource group for VNet '{0}' (1-{1}) or press Enter to skip" -f $vnet, $allRGs.Count)
                                                        if ($selection -and $selection -match $('^\\d+$'))
                                                            {
                                                                $selectedIndex = [int]$selection - 1
                                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $allRGs.Count)
                                                                    {
                                                                        $VNetResourceGroup = $allRGs[$selectedIndex].ResourceGroupName
                                                                    }
                                                            }
                                                    }
                                                if ($VNetResourceGroup)
                                                    {
                                                        # Validate RG exists
                                                        $rgExists = Get-AzResourceGroup -Name $VNetResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.VNets += [PSCustomObject]  @{
                                                                                                                            Name = $vnet
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $VNetResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  [INFO] Will analyze policies for VNet deployment in RG: {0}" -f $VNetResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $VNetResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($vnets.Count -eq 1)
                                            {
                                                $vnetResourceIds += $vnets[0].Id
                                                Write-Host $("  [OK] Found VNet: {0} (RG: {1})" -f $vnets[0].Name, $vnets[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple VNets with same name - prompt user to select
                                                Write-Host $("  Multiple VNets named '{0}' found:" -f $vnet) -ForegroundColor Yellow
                                                Write-Host $("  Please select the resource group that contains the '{0}' VNet:" -f $vnet) -ForegroundColor Cyan
                                                for ($i = 0; $i -lt $vnets.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $vnets[$i].ResourceGroupName, $vnets[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select resource group that contains '{0}' (1-{1}) or press Enter to skip" -f $vnet, $vnets.Count)
                                                if ($selection -and $selection -match $('^\\d+$'))
                                                    {
                                                        $selectedIndex = [int]$selection - 1
                                                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $vnets.Count)
                                                            {
                                                                $vnetResourceIds += $vnets[$selectedIndex].Id
                                                                Write-Host $("  [OK] Selected: {0} (RG: {1})" -f $vnets[$selectedIndex].Name, $vnets[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Invalid selection for VNet '{0}'" -f $vnet)
                                                            }
                                                    } `
                                                else
                                                    {
                                                        Write-Host $("  [INFO] Skipped VNet '{0}'" -f $vnet) -ForegroundColor Gray
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
                                        Write-Host $("  [INFO] Analyzing policies for VNet deployment in RG: {0}" -f $VNetResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("VNet Resource Group '{0}' not found" -f $VNetResourceGroup)
                                    }
                            }

                        # Resolve NSGs
                        if ($NSGName)
                            {
                                $nsgResourceIds = @()
                                foreach ($nsg in $NSGName)
                                    {
                                        Write-Verbose $("Searching for NSG: {0}" -f $nsg)
                                        $nsgs = Get-AzNetworkSecurityGroup | Where-Object {$_.Name -eq $nsg}

                                        if ($nsgs.Count -eq 0)
                                            {
                                                Write-Warning $("NSG '{0}' not found" -f $nsg)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $NSGResourceGroup)
                                                    {
                                                        $allRGs = Get-AzResourceGroup | Sort-Object ResourceGroupName
                                                        Write-Host $("  Select resource group where NSG '{0}' will be deployed:" -f $nsg) -ForegroundColor Cyan
                                                        for ($i = 0; $i -lt $allRGs.Count; $i++)
                                                            {
                                                                Write-Host $("    [{0}] {1} ({2})" -f ($i+1), $allRGs[$i].ResourceGroupName, $allRGs[$i].Location)
                                                            }
                                                        $selection = Read-Host $("  Select resource group for NSG '{0}' (1-{1}) or press Enter to skip" -f $nsg, $allRGs.Count)
                                                        if ($selection -and $selection -match $('^\\d+$'))
                                                            {
                                                                $selectedIndex = [int]$selection - 1
                                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $allRGs.Count)
                                                                    {
                                                                        $NSGResourceGroup = $allRGs[$selectedIndex].ResourceGroupName
                                                                    }
                                                            }
                                                    }
                                                if ($NSGResourceGroup)
                                                    {
                                                        $rgExists = Get-AzResourceGroup -Name $NSGResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.NSGs += [PSCustomObject]  @{
                                                                                                                            Name = $nsg
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $NSGResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  [INFO] Will analyze policies for NSG deployment in RG: {0}" -f $NSGResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $NSGResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($nsgs.Count -eq 1)
                                            {
                                                $nsgResourceIds += $nsgs[0].Id
                                                Write-Host $("  [OK] Found NSG: {0} (RG: {1})" -f $nsgs[0].Name, $nsgs[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple NSGs with same name - prompt user to select
                                                Write-Host $("  Multiple NSGs named '{0}' found:" -f $nsg) -ForegroundColor Yellow
                                                Write-Host $("  Please select the resource group that contains the '{0}' NSG:" -f $nsg) -ForegroundColor Cyan
                                                for ($i = 0; $i -lt $nsgs.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $nsgs[$i].ResourceGroupName, $nsgs[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select resource group that contains '{0}' (1-{1}) or press Enter to skip" -f $nsg, $nsgs.Count)
                                                if ($selection -and $selection -match $('^\\d+$'))
                                                    {
                                                        $selectedIndex = [int]$selection - 1
                                                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $nsgs.Count)
                                                            {
                                                                $nsgResourceIds += $nsgs[$selectedIndex].Id
                                                                Write-Host $("  [OK] Selected: {0} (RG: {1})" -f $nsgs[$selectedIndex].Name, $nsgs[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Invalid selection for NSG '{0}'" -f $nsg)
                                                            }
                                                    } `
                                                else
                                                    {
                                                        Write-Host $("  [INFO] Skipped NSG '{0}'" -f $nsg) -ForegroundColor Gray
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
                                        Write-Host $("  [INFO] Analyzing policies for NSG deployment in RG: {0}" -f $NSGResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("NSG Resource Group '{0}' not found" -f $NSGResourceGroup)
                                    }
                            }

                        # Resolve UMIs
                        if ($UMIName)
                            {
                                $umiResourceIds = @()
                                foreach ($umi in $UMIName)
                                    {
                                        Write-Verbose $("Searching for UMI: {0}" -f $umi)
                                        $umis = Get-AzUserAssignedIdentity | Where-Object {$_.Name -eq $umi}

                                        if ($umis.Count -eq 0)
                                            {
                                                Write-Warning $("UMI '{0}' not found" -f $umi)
                                                # Prompt for resource group where it will be deployed
                                                if (-not $UMIResourceGroup)
                                                    {
                                                        $allRGs = Get-AzResourceGroup | Sort-Object ResourceGroupName
                                                        Write-Host $("  Select resource group where UMI '{0}' will be deployed:" -f $umi) -ForegroundColor Cyan
                                                        for ($i = 0; $i -lt $allRGs.Count; $i++)
                                                            {
                                                                Write-Host $("    [{0}] {1} ({2})" -f ($i+1), $allRGs[$i].ResourceGroupName, $allRGs[$i].Location)
                                                            }
                                                        $selection = Read-Host $("  Select resource group for UMI '{0}' (1-{1}) or press Enter to skip" -f $umi, $allRGs.Count)
                                                        if ($selection -and $selection -match $('^\\d+$'))
                                                            {
                                                                $selectedIndex = [int]$selection - 1
                                                                if ($selectedIndex -ge 0 -and $selectedIndex -lt $allRGs.Count)
                                                                    {
                                                                        $UMIResourceGroup = $allRGs[$selectedIndex].ResourceGroupName
                                                                    }
                                                            }
                                                    }
                                                if ($UMIResourceGroup)
                                                    {
                                                        $rgExists = Get-AzResourceGroup -Name $UMIResourceGroup -ErrorAction SilentlyContinue
                                                        if ($rgExists)
                                                            {
                                                                $reportData.ResourcesAnalyzed.UMIs += [PSCustomObject]  @{
                                                                                                                            Name = $umi
                                                                                                                            ResourceId = $("N/A (Pre-deployment)")
                                                                                                                            ResourceGroupName = $UMIResourceGroup
                                                                                                                            Location = $rgExists.Location
                                                                                                                            PrincipalId = $("N/A (Pre-deployment)")
                                                                                                                            ClientId = $("N/A (Pre-deployment)")
                                                                                                                            Status = $("Planned")
                                                                                                                        }
                                                                Write-Host $("  [INFO] Will analyze policies for UMI deployment in RG: {0}" -f $UMIResourceGroup) -ForegroundColor Cyan
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Resource Group '{0}' not found" -f $UMIResourceGroup)
                                                            }
                                                    }
                                            } `
                                        elseif ($umis.Count -eq 1)
                                            {
                                                $umiResourceIds += $umis[0].Id
                                                Write-Host $("  [OK] Found UMI: {0} (RG: {1})" -f $umis[0].Name, $umis[0].ResourceGroupName) -ForegroundColor Green
                                            } `
                                        else
                                            {
                                                # Multiple UMIs with same name - prompt user to select
                                                Write-Host $("  Multiple UMIs named '{0}' found:" -f $umi) -ForegroundColor Yellow
                                                Write-Host $("  Please select the resource group that contains the '{0}' UMI:" -f $umi) -ForegroundColor Cyan
                                                for ($i = 0; $i -lt $umis.Count; $i++)
                                                    {
                                                        Write-Host $("    [{0}] Resource Group: {1}, Location: {2}" -f ($i+1), $umis[$i].ResourceGroupName, $umis[$i].Location)
                                                    }
                                                $selection = Read-Host $("  Select resource group that contains '{0}' (1-{1}) or press Enter to skip" -f $umi, $umis.Count)
                                                if ($selection -and $selection -match $('^\\d+$'))
                                                    {
                                                        $selectedIndex = [int]$selection - 1
                                                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $umis.Count)
                                                            {
                                                                $umiResourceIds += $umis[$selectedIndex].Id
                                                                Write-Host $("  [OK] Selected: {0} (RG: {1})" -f $umis[$selectedIndex].Name, $umis[$selectedIndex].ResourceGroupName) -ForegroundColor Green
                                                            } `
                                                        else
                                                            {
                                                                Write-Warning $("Invalid selection for UMI '{0}'" -f $umi)
                                                            }
                                                    } `
                                                else
                                                    {
                                                        Write-Host $("  [INFO] Skipped UMI '{0}'" -f $umi) -ForegroundColor Gray
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
                                        Write-Host $("  [INFO] Analyzing policies for UMI deployment in RG: {0}" -f $UMIResourceGroup) -ForegroundColor Cyan
                                    } `
                                else
                                    {
                                        Write-Warning $("UMI Resource Group '{0}' not found" -f $UMIResourceGroup)
                                    }
                            }

                Write-Host $("")
            }

        process
            {
                Write-Host $("Collecting Policy Assignments...") -ForegroundColor Yellow

                # Get all policy assignments at subscription and management group level
                $allPolicyAssignments = Get-AzPolicyAssignment
                Write-Host $("  Found {0} policy assignment(s) at MG/Subscription scopes" -f $allPolicyAssignments.Count) -ForegroundColor Gray

                # Collect Resource Group-level policy assignments
                $resourceGroupLevelAssignments = @()
                $resourceGroupScopes = @()
                $uniqueResourceGroups = @{}
                
                # Add parameter-specified resource groups
                if ($FlexResourceGroupName)
                    {
                        $uniqueResourceGroups[$FlexResourceGroupName] = $true
                    }
                if ($VNetResourceGroup)
                    {
                        $uniqueResourceGroups[$VNetResourceGroup] = $true
                    }
                if ($NSGResourceGroup)
                    {
                        $uniqueResourceGroups[$NSGResourceGroup] = $true
                    }
                if ($UMIResourceGroup)
                    {
                        $uniqueResourceGroups[$UMIResourceGroup] = $true
                    }
                
                # Add resource groups from discovered resource IDs
                foreach ($resourceId in $vnetResourceIds)
                    {
                        # Extract RG name from resource ID: /subscriptions/{sub}/resourceGroups/{rg}/providers/...
                        if ($resourceId -match '/resourceGroups/([^/]+)/')
                            {
                                $uniqueResourceGroups[$Matches[1]] = $true
                            }
                    }
                foreach ($resourceId in $nsgResourceIds)
                    {
                        if ($resourceId -match '/resourceGroups/([^/]+)/')
                            {
                                $uniqueResourceGroups[$Matches[1]] = $true
                            }
                    }
                foreach ($resourceId in $umiResourceIds)
                    {
                        if ($resourceId -match '/resourceGroups/([^/]+)/')
                            {
                                $uniqueResourceGroups[$Matches[1]] = $true
                            }
                    }
                
                # Build resource group scopes from unique RG names
                foreach ($rgName in $uniqueResourceGroups.Keys)
                    {
                        $rgResourceId = "/subscriptions/$($azContext.Subscription.Id)/resourceGroups/$rgName"
                        $resourceGroupScopes += $rgResourceId
                    }

                if ($resourceGroupScopes.Count -gt 0)
                    {
                        Write-Host $("  Checking for Resource Group-level policy assignments...") -ForegroundColor Gray
                        foreach ($rgScope in $resourceGroupScopes)
                            {
                                try
                                    {
                                        $rgPolicies = Get-AzPolicyAssignment -Scope $rgScope -ErrorAction SilentlyContinue
                                        if ($rgPolicies)
                                            {
                                                $resourceGroupLevelAssignments += $rgPolicies
                                                Write-Verbose $("    Found {0} policy assignment(s) on RG: {1}" -f $rgPolicies.Count, $rgScope)
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose $("    Could not retrieve policies for RG: {0}" -f $rgScope)
                                    }
                            }
                        
                        if ($resourceGroupLevelAssignments.Count -gt 0)
                            {
                                Write-Host $("  Found {0} Resource Group-level policy assignment(s)" -f $resourceGroupLevelAssignments.Count) -ForegroundColor Gray
                                $allPolicyAssignments += $resourceGroupLevelAssignments
                            } `
                        else
                            {
                                Write-Host $("  No Resource Group-level policy assignments found") -ForegroundColor Gray
                            }
                    }

                # Collect resource-level policy assignments if we have specific resources
                $resourceLevelAssignments = @()
                if ($vnetResourceIds.Count -gt 0 -or $nsgResourceIds.Count -gt 0 -or $umiResourceIds.Count -gt 0)
                    {
                        Write-Host $("  Checking for resource-level policy assignments...") -ForegroundColor Gray
                        
                        foreach ($resourceId in $vnetResourceIds)
                            {
                                try
                                    {
                                        $resourcePolicies = Get-AzPolicyAssignment -Scope $resourceId -ErrorAction SilentlyContinue
                                        if ($resourcePolicies)
                                            {
                                                $resourceLevelAssignments += $resourcePolicies
                                                Write-Verbose $("    Found {0} policy assignment(s) on VNet: {1}" -f $resourcePolicies.Count, $resourceId)
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose $("    Could not retrieve policies for VNet: {0}" -f $resourceId)
                                    }
                            }
                        
                        foreach ($resourceId in $nsgResourceIds)
                            {
                                try
                                    {
                                        $resourcePolicies = Get-AzPolicyAssignment -Scope $resourceId -ErrorAction SilentlyContinue
                                        if ($resourcePolicies)
                                            {
                                                $resourceLevelAssignments += $resourcePolicies
                                                Write-Verbose $("    Found {0} policy assignment(s) on NSG: {1}" -f $resourcePolicies.Count, $resourceId)
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose $("    Could not retrieve policies for NSG: {0}" -f $resourceId)
                                    }
                            }
                        
                        foreach ($resourceId in $umiResourceIds)
                            {
                                try
                                    {
                                        $resourcePolicies = Get-AzPolicyAssignment -Scope $resourceId -ErrorAction SilentlyContinue
                                        if ($resourcePolicies)
                                            {
                                                $resourceLevelAssignments += $resourcePolicies
                                                Write-Verbose $("    Found {0} policy assignment(s) on UMI: {1}" -f $resourcePolicies.Count, $resourceId)
                                            }
                                    } `
                                catch
                                    {
                                        Write-Verbose $("    Could not retrieve policies for UMI: {0}" -f $resourceId)
                                    }
                            }
                        
                        if ($resourceLevelAssignments.Count -gt 0)
                            {
                                Write-Host $("  Found {0} additional resource-level policy assignment(s)" -f $resourceLevelAssignments.Count) -ForegroundColor Gray
                                $allPolicyAssignments += $resourceLevelAssignments
                            } `
                        else
                            {
                                Write-Host $("  No resource-level policy assignments found") -ForegroundColor Gray
                            }
                    }
                
                Write-Host $("  Total policy assignments to analyze: {0}{1}" -f $allPolicyAssignments.Count, [Environment]::NewLine) -ForegroundColor Gray

                foreach ($assignment in $allPolicyAssignments)
                    {
                        Write-Verbose $("Processing policy: {0}" -f $assignment.Name)

                        # Get policy definition details
                        try
                            {
                                # Determine scope type first to decide how to retrieve the policy definition
                                $scopeType = if ($assignment.Scope -like $("*/managementGroups/*")) {$("ManagementGroup")} `
                                            elseif ($assignment.Scope -like $("*/resourceGroups/*") -and $assignment.Scope -notlike $("*/providers/*")) {$("ResourceGroup")} `
                                            elseif ($assignment.Scope -like $("*/providers/*")) {$("Resource")} `
                                            else {$("Subscription")}

                                # Check if this is a policy set (initiative) or single policy
                                $isInitiative = $assignment.PolicyDefinitionId -like $("*/policySetDefinitions/*")

                                # Retrieve policy or policy set definition based on type and scope
                                if ($isInitiative)
                                    {
                                        # Policy Set Definition (Initiative)
                                        if ($scopeType -eq $("ManagementGroup") -or $assignment.PolicyDefinitionId -like $("*/providers/Microsoft.Authorization/policySetDefinitions/*"))
                                            {
                                                $definition = Get-AzPolicySetDefinition -Id $assignment.PolicyDefinitionId -ErrorAction Stop
                                            } `
                                        else
                                            {
                                                $definition = Get-AzPolicySetDefinition -Id $assignment.PolicyDefinitionId -SubscriptionId $azContext.Subscription.Id -ErrorAction Stop
                                            }
                                    } `
                                else
                                    {
                                        # Single Policy Definition
                                        if ($scopeType -eq $("ManagementGroup") -or $assignment.PolicyDefinitionId -like $("*/providers/Microsoft.Authorization/policyDefinitions/*"))
                                            {
                                                $definition = Get-AzPolicyDefinition -Id $assignment.PolicyDefinitionId -ErrorAction Stop
                                            } `
                                        else
                                            {
                                                $definition = Get-AzPolicyDefinition -Id $assignment.PolicyDefinitionId -SubscriptionId $azContext.Subscription.Id -ErrorAction Stop
                                            }
                                    }

                                # Check if this policy impacts our target resource group
                                $impactsTargetRG = $false
                                if ($scopeType -eq $("ManagementGroup"))
                                    {
                                        $impactsTargetRG = $true  # Management group policies apply to all subscriptions below
                                    } `
                                elseif ($scopeType -eq $("Subscription") -and $assignment.Scope -like $("*{0}*" -f $azContext.Subscription.Id))
                                    {
                                        $impactsTargetRG = $true  # Subscription policies apply to all RGs in that subscription
                                    } `
                                elseif ($scopeType -eq $("ResourceGroup") -and $assignment.Scope -like $("*{0}*" -f $FlexResourceGroupName))
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
                                                                    PolicyRule = $definition.PolicyRule
                                                                    PolicyMetadata = $definition.Metadata
                                                                    PolicyCategory = $definition.Metadata.category
                                                                    PolicyVersion = $definition.Metadata.version
                                                                    DefinitionParameters = $definition.Parameter
                                                                    Scope = $assignment.Scope
                                                                    ScopeType = $scopeType
                                                                    ImpactsTargetResourceGroup = $impactsTargetRG
                                                                    EnforcementMode = $assignment.EnforcementMode
                                                                    PolicyType = $definition.PolicyType
                                                                    Mode = $definition.Mode
                                                                    Effect = $policyEffect
                                                                    NotScopes = ($assignment.NotScope -join $("; "))
                                                                    AssignmentParameters = ($assignment.Parameter | ConvertTo-Json -Compress -Depth 3)
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
                                                                                    ResourceName = $assignment.name
                                                                                    ResourceId = $assignment.properties.policyDefinitionId
                                                                                    Scope = $assignment.properties.scope
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
                if ($vnetResourceIds)
                    {
                        Write-Host $("Analyzing Virtual Networks...") -ForegroundColor Yellow
                        foreach ($vnetId in $vnetResourceIds)
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
                if ($nsgResourceIds)
                    {
                        Write-Host $("Analyzing Network Security Groups...") -ForegroundColor Yellow
                        foreach ($nsgId in $nsgResourceIds)
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
                if ($umiResourceIds)
                    {
                        Write-Host $("Analyzing User-Assigned Managed Identities...") -ForegroundColor Yellow
                        foreach ($umiId in $umiResourceIds)
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

                # Create scope analysis summary
                $scopeSummary = @{
                                    TotalPolicies = $reportData.PolicyAssignments.Count
                                    ManagementGroupPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("ManagementGroup")}).Count
                                    SubscriptionPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("Subscription")}).Count
                                    ResourceGroupPolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("ResourceGroup")}).Count
                                    ResourcePolicies = ($reportData.PolicyAssignments | Where-Object {$_.ScopeType -eq $("Resource")}).Count
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
                Write-Host $("  Resource: {0}" -f $scopeSummary.ResourcePolicies) -ForegroundColor Gray
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
                        Write-Host $("{0}[WARNING] Potential Blind Spots: {1}" -f [Environment]::NewLine, $reportData.PermissionContext.PotentialBlindSpots.Count) -ForegroundColor Yellow
                        foreach ($blindSpot in $reportData.PermissionContext.PotentialBlindSpots)
                            {
                                $severityColor = switch ($blindSpot.Severity)
                                    {
                                        $("Analysis Blocked") {$("Red")}
                                        $("Major Gap") {$("Red")}
                                        $("Moderate Gap") {$("Yellow")}
                                        $("Data Missing") {$("Yellow")}
                                        $("Analysis Error") {$("Yellow")}
                                        default {$("Gray")}
                                    }
                                Write-Host $("  [{0}] {1}: {2}" -f $blindSpot.Severity, $blindSpot.Area, $blindSpot.Description) -ForegroundColor $severityColor
                                Write-Host $("      Impact: {0}" -f $blindSpot.Impact) -ForegroundColor Gray
                                Write-Host $("      Action: {0}" -f $blindSpot.Recommendation) -ForegroundColor Cyan
                            }
                        Write-Host $("  [INFO] See report for detailed blind spot analysis") -ForegroundColor Cyan
                    } `
                else
                    {
                        Write-Host $("  [OK] No obvious permission gaps detected") -ForegroundColor Green
                    }

                if ($reportData.AccessIssues.Count -gt 0)
                    {
                        $accessIssueColor = if ($scopeSummary.PermissionDeniedCount -gt 0) {$("Red")} else {$("Yellow")}
                        $permissionDeniedColor = if ($scopeSummary.PermissionDeniedCount -gt 0) {$("Red")} else {$("Green")}
                        Write-Host $("{0}[WARNING] Access Issues Detected: {1}" -f [Environment]::NewLine, $reportData.AccessIssues.Count) -ForegroundColor $accessIssueColor
                        Write-Host $("  Permission Denied: {0}" -f $scopeSummary.PermissionDeniedCount) -ForegroundColor $permissionDeniedColor
                        Write-Host $("  Other Errors: {0}" -f ($reportData.AccessIssues.Count - $scopeSummary.PermissionDeniedCount)) -ForegroundColor Yellow
                        Write-Host $("  [INFO] Some policy details may be incomplete - see report for details") -ForegroundColor Cyan
                    }

                Write-Host $("")
            }

        end
            {
                # Export reports
                $timestamp = Get-Date -Format $("yyyyMMdd-HHmmss")
                $baseFileName = $("AzurePolicyImpactReport-{0}" -f $timestamp)

                Write-Host $("Exporting JSON Report...") -ForegroundColor Yellow

                $jsonPath = Join-Path $OutputPath $("{0}.json" -f $baseFileName)
                $reportData | ConvertTo-Json -Depth 20 | Out-File -FilePath $jsonPath -Encoding UTF8
                Write-Host $("  JSON report saved: {0}" -f $jsonPath) -ForegroundColor Green

                Write-Host $("{0}Report generation complete!" -f [Environment]::NewLine) -ForegroundColor Green
                Write-Host $("========================================{0}" -f [Environment]::NewLine) -ForegroundColor Cyan

                return $reportData
            }
    }   # End of Get-AzPolicyImpactReport function

Export-ModuleMember -Function Get-AzPolicyImpactReport

