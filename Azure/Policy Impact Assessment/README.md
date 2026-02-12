# Azure Policy Impact Assessment

## Overview

This PowerShell module generates comprehensive Azure Policy impact assessment reports for specified resources and scopes. It's designed to help you understand which Azure Policies could impact deployment or configuration of resources across multiple scopes including subscriptions, resource groups, VNets, NSGs, and User-Assigned Managed Identities.

## Purpose

When deploying Azure resources like Silk Data Platform clusters, it's critical to understand:
- Which policies will be evaluated during deployment
- Whether policies will block or audit resource creation/configuration
- Which scopes (Management Group, Subscription, Resource Group) policies are applied at
- Any exemptions that may apply to your resources
- Role assignments that govern permissions

This tool collects all that information in an easy-to-review format that can be shared with customers or used for pre-deployment validation.

## Features

✅ **Comprehensive Policy Collection**
- Policies at Management Group, Subscription, and Resource Group levels
- Policy definitions with effects and rules
- Policy exemptions
- Scope hierarchy analysis

✅ **Multi-Resource Analysis**
- Target Resource Group
- Virtual Networks (can be in different RGs)
- Network Security Groups (can be in different RGs)
- User-Assigned Managed Identities (can be in different RGs)

✅ **Multiple Export Formats**
- JSON (for programmatic processing)
- CSV (for spreadsheet analysis)
- HTML (for easy viewing and sharing)

✅ **Optional Role Assignments**
- Include RBAC role assignments at analyzed scopes

## Prerequisites

- **Azure PowerShell Modules:**
  ```powershell
  Install-Module -Name Az.Accounts, Az.Resources -Repository PSGallery -Scope CurrentUser
  ```

- **Azure Authentication:**
  - Must be authenticated to Azure (`Connect-AzAccount`)

- **Required Permissions:**
  - **Minimum:** `Reader` role at Subscription level
  - **Recommended:** `Reader` role at Management Group level (for complete policy visibility)
  - **For Role Assignments:** Appropriate permissions to read role assignments

> **⚠️ Permission Considerations:**
> If you don't have Reader access at Management Group level, the report will still run but:
> - Management Group-scoped policies may not be visible
> - Policy definitions from parent scopes may be inaccessible
> - The report will include an **Access Issues** section documenting what couldn't be retrieved
> - This ensures transparency even when permissions are limited

> **💡 Best Practice:** For complete policy visibility across all scopes, request `Reader` role assignment at the root Management Group level or at least at the Management Group that contains your subscription.

## Installation

### Option 1: Download from Repository

1. Download the module file to your local machine or Azure Cloud Shell
2. Import the module:
   ```powershell
   Import-Module .\Get-AzPolicyImpactReport.psm1
   ```

### Option 2: Azure Cloud Shell

1. Upload `Get-AzPolicyImpactReport.psm1` to your Cloud Shell storage
2. Import the module:
   ```powershell
   Import-Module ./Get-AzPolicyImpactReport.psm1
   ```

## Usage Examples

### Example 1: Basic - Just Resource Group

Simplest usage - analyze policies for your Silk deployment resource group:

```powershell
Get-AzPolicyImpactReport -ResourceGroupName 'my-silk-cluster-rg'
```

### Example 2: With External Resources (Using Friendly Names)

**RECOMMENDED** - Just provide resource names, the module finds them:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetNames 'shared-vnet' `
    -NSGNames 'silk-flex-nsg' `
    -UMINames 'silk-umi'
```

💡 If duplicate names exist, you'll be prompted to select which one.

### Example 3: Multiple NSGs (Typical Silk Deployment)

For Silk Flex + Cluster deployments with separate NSGs:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'silk-cluster-rg' `
    -VNetNames 'shared-vnet' `
    -NSGNames @('silk-flex-nsg', 'silk-cluster-nsg') `
    -UMINames 'silk-umi' `
    -IncludeRoleAssignments
```

### Example 4: Pre-Deployment Assessment

**Analyze policies BEFORE creating resources!** Perfect for planning:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'silk-cluster-rg' `
    -VNetResourceGroup 'network-rg' `
    -NSGResourceGroup 'network-rg' `
    -UMIResourceGroup 'identity-rg' `
    -OutputFormat All
```

Use this when:
- Planning Silk deployments
- Understanding policy requirements before resource creation
- Validating resource group configurations
- Pre-deployment compliance checks

### Example 5: Interactive Mode

Let the module show you available resources and select from menus:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -Interactive `
    -IncludeRoleAssignments
```

### Example 6: By Subscription Name

Use subscription name instead of ID:

```powershell
Get-AzPolicyImpactReport `
    -SubscriptionName 'Sales-Azure' `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetNames 'shared-vnet'
```

### Example 7: Custom Output Location

Specify where reports are saved:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetNames 'shared-vnet' `
    -OutputPath 'C:\Reports' `
    -ReportName 'SilkPolicyAnalysis'
```

### Example 8: HTML Only (For Quick Review)

Generate just the HTML report:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetNames 'shared-vnet' `
    -OutputFormat HTML
```

### Example 9: Complete Analysis

Full-featured report with everything enabled:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetNames 'shared-vnet' `
    -NSGNames @('silk-flex-nsg', 'silk-cluster-nsg') `
    -UMINames 'silk-umi' `
    -IncludeRoleAssignments `
    -OutputFormat All `
    -OutputPath '.' `
    -ReportName 'SilkDeploymentPolicyReport'
```

### Advanced: Using Full Resource IDs

If you have full resource IDs (or resources in different subscriptions):

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'my-silk-cluster-rg' `
    -VNetResourceIds '/subscriptions/.../virtualNetworks/my-vnet' `
    -NSGResourceIds '/subscriptions/.../networkSecurityGroups/my-nsg' `
    -UMIResourceIds '/subscriptions/.../userAssignedIdentities/my-umi'
```

---

## Output Files

The module generates the following files based on `OutputFormat`:

- **JSON**: `{ReportName}-{Timestamp}.json` - Complete report data in JSON format
- **CSV**:
  - `{ReportName}-{Timestamp}-Policies.csv` - Policy assignments
  - `{ReportName}-{Timestamp}-Exemptions.csv` - Policy exemptions (if any)
  - `{ReportName}-{Timestamp}-RoleAssignments.csv` - Role assignments (if requested)
  - `{ReportName}-{Timestamp}-AccessIssues.csv` - **Access/permission issues (if any)** ⚠️
- **HTML**: `{ReportName}-{Timestamp}.html` - Formatted HTML report with styling

## Understanding the Report

### Report Sections

1. **Metadata**: Report generation details, subscription info, target resources
2. **Permission Context**: **NEW!** Your access level analysis and potential blind spots
   - Your role assignments at various scopes
   - Whether you have Management Group access
   - Whether you have Subscription Reader or higher
   - **Potential Blind Spots**: Areas where you may not have visibility
   - Impact assessment of missing permissions
   - Recommendations for complete visibility
3. **Summary**: Aggregate counts of policies by scope and enforcement mode
4. **Policy Assignments**: Detailed list of all applicable policies
5. **Policy Exemptions**: Any exemptions that may apply (if found)
6. **Resources Analyzed**: VNets, NSGs, UMIs that were analyzed
7. **Role Assignments**: RBAC roles (if `-IncludeRoleAssignments` was used)
8. **Access Issues**: Policies/scopes that couldn't be read due to permissions ⚠️

### Permission Context & Blind Spots

**NEW FEATURE:** The report now automatically analyzes your permissions and identifies potential blind spots!

When you run the report, it will:
- Check your role assignments at Management Group, Subscription, and Resource Group scopes
- Identify whether you have sufficient permissions for complete policy visibility
- List specific areas where your access may be limited
- Provide recommendations for obtaining complete visibility

**Example Output:**
```
Analyzing your permissions...
  ✓ Found 3 role assignment(s)
  MG Access: False
  Subscription Reader: True
  ⚠ Potential Blind Spots: 1

--- Permission Context ---
Your Role Assignments: 3
  Management Group Access: False
  Subscription Reader+: True

⚠️  Potential Blind Spots: 1
  [High] Management Group Policies
  ⓘ  See report for detailed blind spot analysis

⚠️  Access Issues Detected: 3
  Permission Denied: 0
  Other Errors: 3
  ⓘ  Some policy details may be incomplete - see report for details
```

**Blind Spot Severity Levels:**
- **Critical**: No role assignments found - report will be severely incomplete
- **High**: Missing Management Group access - MG policies may be invisible
- **Medium**: Limited subscription access - some policies may not be visible

Each blind spot includes specific recommendations for what permissions to request for complete visibility.

### Access Issues Tracking

The report automatically tracks any errors encountered while collecting policy data:

- **Permission Denied**: Missing Reader access at specific scopes (e.g., Management Groups) - displays in **red**
- **Other Access Errors**: Parameter resolution errors, API timeouts, or transient errors - displays in **yellow**

**Color Coding:**
- 🟢 **Green**: "Permission Denied: 0" indicates no permission issues (good!)  
- 🟡 **Yellow**: Access issues header when only "Other Errors" exist (warnings)
- 🔴 **Red**: Access issues header when "Permission Denied" > 0 (critical errors)

**Exports:** Access issues are included in JSON, exported to a separate CSV, and highlighted in the HTML report with a warning banner.

**Action:** If access issues are detected, request appropriate Reader permissions at the identified scopes and re-run the report.

---

## Understanding the Report

### Policy Assignment Fields

- **AssignmentName**: Internal name of the policy assignment
- **DisplayName**: Human-readable name
- **ScopeType**: Level where policy is assigned (ManagementGroup, Subscription, ResourceGroup)
- **ImpactsTargetResourceGroup**: Whether this policy applies to your target RG
- **EnforcementMode**:
  - `Default` - Policy is enforced (can block deployments)
  - `DoNotEnforce` - Policy only audits (won't block)
- **PolicyType**: `BuiltIn` or `Custom`
- **Mode**: Policy evaluation mode (`All`, `Indexed`, etc.)
- **Effect**: Policy effect (Deny, Audit, DeployIfNotExists, etc.)

### Scope Hierarchy

Policies inherit down the scope hierarchy:
1. **Management Group** → Applies to all subscriptions and resources below
2. **Subscription** → Applies to all resource groups and resources in that subscription
3. **Resource Group** → Applies only to resources in that resource group

### Policy Effects

Common policy effects and their impact:

| Effect | Impact on Deployment |
|--------|---------------------|
| `Deny` | **BLOCKS** resource creation/modification if non-compliant |
| `Audit` | Logs non-compliance but **ALLOWS** deployment |
| `AuditIfNotExists` | Audits if condition not met, **ALLOWS** deployment |
| `DeployIfNotExists` | **CREATES** additional resources if not present |
| `Modify` | **CHANGES** resource properties during deployment |
| `Disabled` | No effect |

## Common Scenarios

### Scenario 1: Pre-Deployment Validation

Before deploying a Silk cluster, check what policies will apply:

```powershell
Get-AzPolicyImpactReport -ResourceGroupName 'silk-new-cluster-rg' -OutputFormat HTML
```

Review the HTML report to identify:
- Any `Deny` policies that might block deployment
- Required tags or naming conventions
- Network restrictions

### Scenario 2: Cross-Resource Group Deployment

When using shared networking resources:

```powershell
# Get resource IDs first
$vnet = Get-AzVirtualNetwork -Name 'shared-vnet' -ResourceGroupName 'network-rg'
$nsg = Get-AzNetworkSecurityGroup -Name 'silk-nsg' -ResourceGroupName 'network-rg'
$umi = Get-AzUserAssignedIdentity -Name 'silk-umi' -ResourceGroupName 'identity-rg'

# Run analysis
Get-AzPolicyImpactReport `
    -ResourceGroupName 'silk-cluster-rg' `
    -VNetResourceIds $vnet.Id `
    -NSGResourceIds $nsg.Id `
    -UMIResourceIds $umi.Id `
    -OutputFormat All
```

### Scenario 3: Customer Policy Review

Generate a report for customer review:

```powershell
Get-AzPolicyImpactReport `
    -ResourceGroupName 'customer-cluster-rg' `
    -IncludeRoleAssignments `
    -OutputFormat HTML `
    -OutputPath 'C:\CustomerReports' `
    -ReportName 'CustomerName-PolicyReview'
```

Send the HTML file to the customer for review and approval.

## Troubleshooting

### "Not connected to Azure"

```powershell
Connect-AzAccount
```

### "Resource Group not found"

Verify the resource group name is correct and you have access:
```powershell
Get-AzResourceGroup -Name 'your-rg-name'
```

### "Could not find VNet/NSG/UMI"

If you're using the ByName parameter set, ensure the resource names are exact:
```powershell
# Verify resource names exist
Get-AzVirtualNetwork | Where-Object {$_.Name -like '*silk*'}
Get-AzNetworkSecurityGroup | Where-Object {$_.Name -like '*silk*'}
Get-AzUserAssignedIdentity | Where-Object {$_.Name -like '*silk*'}
```

If using resource IDs, ensure you're using the full resource ID format:
```powershell
# Correct
-VNetResourceIds '/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/vnet-name'

# Incorrect
-VNetResourceIds 'vnet-name'
```

### Management Group Policy Access Issues

If you see warnings like "Parameter set cannot be resolved" for policies, this indicates:
- Policies are assigned at Management Group level
- You don't have Management Group Reader permissions  
- The function correctly identifies these as "Other Errors" (not critical)
- Request Management Group Reader role for complete visibility

### Permissions Errors

Ensure you have at least `Reader` role on the subscription. For role assignments, you need `Reader` or `User Access Administrator` role.

## Best Practices

1. **Run Early**: Execute policy analysis before starting deployment planning
2. **Include All Resources**: Specify all VNets, NSGs, and UMIs that will be used
3. **Review HTML Reports**: HTML format is easiest for human review
4. **Use JSON for Automation**: JSON format is best for programmatic processing
5. **Document Exemptions**: If policy exemptions are needed, document why in the exemption description
6. **Regular Updates**: Re-run analysis if subscription policies change

## Advanced Usage

### Filtering Results with PowerShell

You can filter the returned data object:

```powershell
# Get the report data
$report = Get-AzPolicyImpactReport -ResourceGroupName 'my-rg' -OutputFormat JSON

# Show only enforced deny policies
$report.PolicyAssignments |
    Where-Object { $_.EnforcementMode -eq 'Default' -and $_.Effect -like '*deny*' } |
    Select-Object AssignmentDisplayName, ScopeType, Effect

# Show policies impacting target RG
$report.PolicyAssignments |
    Where-Object { $_.ImpactsTargetResourceGroup } |
    Format-Table AssignmentDisplayName, ScopeType, EnforcementMode
```

### Comparing Multiple Subscriptions

```powershell
# Get policies from multiple subscriptions
$subs = @('sub1-id', 'sub2-id', 'sub3-id')
$reports = @{}

foreach ($sub in $subs) {
    Set-AzContext -SubscriptionId $sub
    $reports[$sub] = Get-AzPolicyImpactReport -ResourceGroupName 'test-rg' -OutputFormat JSON
}

# Compare policy counts
$reports.Keys | ForEach-Object {
    [PSCustomObject]@{
        Subscription = $_
        TotalPolicies = $reports[$_].ScopeAnalysis.TotalPolicies
        EnforcedPolicies = $reports[$_].ScopeAnalysis.EnforcedPolicies
    }
} | Format-Table
```

## Support

Relevant Support Material:
[Azure Policy documentation](https://learn.microsoft.com/en-us/azure/governance/policy/)

## Version History

- **1.0.0** - Initial release
  - Policy assignment collection
  - Policy exemption detection
  - Multi-resource analysis
  - JSON/CSV/HTML export
  - Role assignment collection

## License

Copyright © 2026 Silk Technologies Inc. All rights reserved.
