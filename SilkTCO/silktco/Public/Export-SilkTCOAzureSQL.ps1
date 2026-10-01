<#
    .SYNOPSIS
    Exports an Azure managed SQL (PaaS) inventory and cost report.

    .DESCRIPTION
    The Azure counterpart to Export-SilkTCOAWSRDS. Covers the whole managed SQL family:
    Azure SQL Database, elastic pools, SQL Managed Instance and its databases, and the
    PostgreSQL and MySQL flexible servers.

    Costs are billed spend from the Cost Details report over whole UTC days, split into
    compute, license, storage and backup. -days 1 is exactly one day. There is no
    rate-card estimate - see New-SilkTCOAzureSQLCostArray for why.

    Performance metrics are collected by default. They cost one Azure Monitor call per
    metric per resource, so on a big estate add -excludeMetrics for a quick costs-only run.

    .EXAMPLE
    Export-SilkTCOAzureSQL

    Inventory, performance and cost.

    .EXAMPLE
    Export-SilkTCOAzureSQL -resourceGroupNames @('sql-prod-rg') -days 7 -excludeMetrics

    Costs only. One Cost Details report plus discovery.
#>

Function Export-SilkTCOAzureSQL {
    param(
        [Parameter()]
        [array] $resourceGroupNames,
        [Parameter()]
        [ValidateRange(1, 365)]
        [int] $days = 1,
        [Parameter()]
        [ValidateRange(0, 365)]
        [int] $offsetDays = 1,
        [Parameter()]
        [switch] $includeSystemDatabases,
        [Parameter()]
        [switch] $excludeMetrics,
        [Parameter()]
        [switch] $skipCost,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $listParams = @{}
    if ($resourceGroupNames) { $listParams['resourceGroupNames'] = $resourceGroupNames }
    if ($includeSystemDatabases) { $listParams['includeSystemDatabases'] = $true }

    $sqllist = New-SilkTCOAzureSQLList @listParams

    if (-not $sqllist) {
        Write-Warning "No Azure managed SQL resources found for the given scope."
        return
    }

    # metrics on by default. -excludeMetrics skips the azure monitor calls for a quick
    # costs-only run
    $metrics = $null
    if (-not $excludeMetrics) {
        try {
            $metrics = New-SilkTCOAzureSQLMetrics -sqllist $sqllist -days $days -offsetDays $offsetDays -Verbose
        } catch {
            Write-Warning "Metric collection failed, continuing with inventory and cost only: $($_.Exception.Message)"
        }
    }

    $costs = $null
    if (-not $skipCost) {
        $costs = New-SilkTCOAzureSQLCostArray -sqllist $sqllist -days $days -offsetDays $offsetDays -costMetric $costMetric
    }

    $report = Merge-SilkTCOAzureSQLData -sqllist $sqllist -metrics $metrics -costs $costs

    $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'Azure-SQL' -PassThru }

    # quick shape of what was found, plus the licensing lever if anyone is paying for it
    $byType = $report | Group-Object RecordType | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Verbose "--- Collected $($report.Count) row(s): $($byType -join ', ') ---" -Verbose

    # this is a cost report, so say what the cost was
    $periodTotal = ($report | Measure-Object -Property TotalCostPeriodUSD -Sum).Sum
    if ($periodTotal -gt 0) {
        $monthlyTotal = [Math]::Round(($periodTotal / $days) * 30, 2)
        Write-Verbose "--- Total SQL spend: `$$([Math]::Round($periodTotal, 2)) over $days day(s), about `$$monthlyTotal/month ---" -Verbose
    }

    $orphans = @($report | Where-Object { $_.RecordType -eq 'UnmatchedCost' })
    if ($orphans) {
        $orphanTotal = [Math]::Round((($orphans | Measure-Object -Property TotalCostPeriodUSD -Sum).Sum), 2)
        Write-Warning "$($orphans.Count) billed SQL resource(s) were not returned by discovery, totalling `$$orphanTotal. They're in the CSV as RecordType 'UnmatchedCost' - widen the scope or check for deleted/retired resources."
    }

    # sql licensing bills on its own meter, so when cost data is present we can put a
    # number on what azure hybrid benefit would actually save rather than just flagging it
    $licenseSpend = ($report | Measure-Object -Property LicenseCostPeriodUSD -Sum).Sum
    if ($licenseSpend -gt 0) {
        $licMonthly = [Math]::Round(($licenseSpend / $days) * 30, 2)
        Write-Warning "SQL licensing is billing separately: `$$([Math]::Round($licenseSpend, 2)) over $days day(s), about `$$licMonthly/month. Azure Hybrid Benefit removes that line entirely if the customer holds Software Assurance."
    } else {
        $payingLicense = @($report | Where-Object { $_.LicenseType -eq 'LicenseIncluded' })
        if ($payingLicense) {
            Write-Warning "$($payingLicense.Count) resource(s) report LicenseType = LicenseIncluded. Azure Hybrid Benefit would cut the licensing line if the customer holds Software Assurance."
        }
    }

    $report | Export-Csv -Path ".\SilkTCO_AzureSQL_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
}
