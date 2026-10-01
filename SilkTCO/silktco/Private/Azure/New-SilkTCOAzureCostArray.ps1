<#
    .SYNOPSIS
    Per resource Azure cost for the VM report.

    .DESCRIPTION
    Reads the shared Cost Details report and rolls it up to one line per resource per
    meter category - one line for the VM, one per disk - which is the shape the merge
    matches on. The window is whole UTC days, so -days 1 is exactly one day of cost.

    .EXAMPLE
    New-SilkTCOAzureCostArray -days 1

    .EXAMPLE
    New-SilkTCOAzureCostArray -ResourceGroupName MyResourceGroup -days 7
#>

function New-SilkTCOAzureCostArray {
    param(
        [Parameter()]
        [array] $ResourceGroupName,
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $cd = Get-SilkTCOAzureCostDetails -days $days -offsetDays $offsetDays -metric $costMetric
    if (-not $cd) { return }

    $rgPaths = @($ResourceGroupName | Where-Object { $_ } | ForEach-Object { "/resourcegroups/$("$_".ToLower())/" })

    # one bucket per resource per meter category
    $agg = @{}
    foreach ($r in $cd.Rows) {
        if ($rgPaths) {
            $inScope = $false
            foreach ($p in $rgPaths) { if ($r.ResourceId.Contains($p)) { $inScope = $true; break } }
            if (-not $inScope) { continue }
        }

        $key = "$($r.ResourceId)|$($r.MeterCategory)"
        if (-not $agg.ContainsKey($key)) {
            $agg[$key] = @{ ResourceId = $r.ResourceId; MeterCategory = $r.MeterCategory; Cost = 0.0; Subs = @{} }
        }
        $agg[$key].Cost += $r.Cost
        if ($r.MeterSubCategory) { $agg[$key].Subs[$r.MeterSubCategory] = $true }
    }

    $report = foreach ($a in $agg.Values) {
        if ($a.Cost -le 0) { continue }
        $rid = $a.ResourceId

        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name ResourceName -Value $rid.Substring($rid.LastIndexOf('/') + 1)
        $o | Add-Member -MemberType NoteProperty -Name ResourceType -Value (Get-SilkTCOResourceType -resourceId $rid)
        $o | Add-Member -MemberType NoteProperty -Name MeterCategory -Value $a.MeterCategory
        $o | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value (($a.Subs.Keys | Sort-Object) -join '; ')
        $o | Add-Member -MemberType NoteProperty -Name Cost -Value ([Math]::Round($a.Cost, 4))
        $o | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
        $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $rid
        $o
    }

    if (-not $report) {
        Write-Warning "No Azure resource cost found for $($cd.StartDate) .. $($cd.EndDate)."
        return
    }

    Write-Verbose "Cost lines for $(@($report).Count) resource/category pairs, $($cd.StartDate) .. $($cd.EndDate)." -Verbose
    return ($report | Sort-Object -Property Cost -Descending)
}
