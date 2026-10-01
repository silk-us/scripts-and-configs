<#
    .SYNOPSIS
    Exports an Azure NetApp Files provisioning and cost report.

    .DESCRIPTION
    Provisioned state only - capacity and performance ceilings, no historical metrics.
    Costs come out on two bases side by side: list price from the Azure Retail Prices API
    and actual billed spend from Cost Management. The gap between them tells you whether
    the customer is on list or on a reserved/negotiated rate.

    .EXAMPLE
    Export-SilkTCOAzureANF

    .EXAMPLE
    Export-SilkTCOAzureANF -resourceGroupNames @('netapp-prod-rg') -includeSnapshots
#>

Function Export-SilkTCOAzureANF {
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
        [switch] $includeSnapshots,
        [Parameter()]
        [switch] $includeBackups,
        [Parameter()]
        [switch] $skipActualCost,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $listParams = @{}
    if ($resourceGroupNames) { $listParams['resourceGroupNames'] = $resourceGroupNames }
    if ($includeSnapshots) { $listParams['includeSnapshots'] = $true }
    if ($includeBackups) { $listParams['includeBackups'] = $true }

    $anflist = New-SilkTCOANFList @listParams

    if (-not $anflist) {
        Write-Warning "No Azure NetApp Files capacity pools found for the given scope."
        return
    }

    $costParams = @{
        anflist    = $anflist
        days       = $days
        offsetDays = $offsetDays
        costMetric = $costMetric
    }
    if ($skipActualCost) { $costParams['skipActualCost'] = $true }

    $costs = New-SilkTCOANFCostArray @costParams

    $report = Merge-SilkTCOANFData -anflist $anflist -costs $costs

    $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'Azure-ANF' -PassThru }

    # stranded capacity is the headline for this one - anf charges for the pool whether or
    # not you carved volumes out of it, so call it out before the csv drops
    $pools = @($report | Where-Object { $_.RecordType -eq 'Pool' })
    if ($pools) {
        $totalProv = ($pools | Measure-Object -Property ProvisionedGiB -Sum).Sum
        $totalStranded = ($pools | Measure-Object -Property StrandedGiB -Sum).Sum
        if ($totalStranded -gt 0 -and $totalProv -gt 0) {
            $pct = [Math]::Round(($totalStranded / $totalProv) * 100, 1)
            Write-Warning "$([Math]::Round($totalStranded / 1024, 2)) TiB of $([Math]::Round($totalProv / 1024, 2)) TiB pool capacity ($pct%) is provisioned but not allocated to any volume - billed regardless."
        }
    }

    $report | Export-Csv -Path ".\SilkTCO_ANF_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
}
