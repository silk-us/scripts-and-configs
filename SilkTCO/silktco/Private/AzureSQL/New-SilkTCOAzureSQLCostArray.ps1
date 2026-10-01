<#
    .SYNOPSIS
    Reads actual billed cost for Azure managed SQL resources.

    .DESCRIPTION
    Billed spend from the shared Cost Details report - deliberately no rate-card estimate.
    The Retail Prices API carries hundreds of SQL meters per region and consumption and
    reservation rows look identical on the fields you'd match on, so a guessed rate can be
    orders of magnitude out.

    Costs come out per resource, split into compute / license / storage / backup so the
    licensing and retention story is visible rather than buried in one total. Anything
    billed that discovery didn't return is still emitted, so no SQL spend goes missing.
#>

function New-SilkTCOAzureSQLCostArray {
    param(
        [Parameter(Mandatory)]
        [array] $sqllist,
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

    $byResource = @{}

    foreach ($r in $cd.Rows) {
        $rid = $r.ResourceId
        if (-not ($rid.Contains('/providers/microsoft.sql/') -or
                  $rid.Contains('/providers/microsoft.dbforpostgresql/') -or
                  $rid.Contains('/providers/microsoft.dbformysql/'))) { continue }

        if (-not $byResource.ContainsKey($rid)) {
            $byResource[$rid] = @{ Compute = 0.0; License = 0.0; Storage = 0.0; Backup = 0.0; Other = 0.0; Unclassified = @() }
        }

        $sub = $r.MeterSubCategory
        $cat = $r.MeterCategory

        # matched against the real subcategory strings azure returns, eg
        #   'SQL Managed Instance General Purpose - Compute Gen5'
        #   'SQL Managed Instance General Purpose - SQL License'
        #   'SQL Managed Instance General Purpose - Storage'
        #   'SQL Database Single Basic'
        # order is load bearing. license first, backup before storage ('LTR Backup
        # Storage'), storage before compute or 'General Purpose - Storage' gets caught by
        # the tier name. meter name alone wont do - license and compute are both 'vCore'.
        $bucket = switch -Regex ("$sub|$cat") {
            'License'                                             { 'License'; break }
            'Backup|LTR|Long Term Retention|Point.?In.?Time|PITR' { 'Backup'; break }
            'Storage|Data Stored'                                 { 'Storage'; break }
            'Compute|vCore|DTU|Single|Elastic Pool|Hyperscale|Serverless|General Purpose|Business Critical|Basic|Standard|Premium' { 'Compute'; break }
            default                                               { 'Other' }
        }

        # leave a trail so an Other bucket is diagnosable instead of just opaque
        if ($bucket -eq 'Other' -and $sub -and $byResource[$rid].Unclassified -notcontains $sub) {
            $byResource[$rid].Unclassified += $sub
        }

        $byResource[$rid][$bucket] += $r.Cost
    }

    Write-Verbose "Matched $($byResource.Keys.Count) SQL resource(s) in cost data for $($cd.StartDate) .. $($cd.EndDate)." -Verbose

    $costReport = @()
    $claimed = @{}

    foreach ($res in $sqllist) {
        $notes = @()
        $compute = $null; $license = $null; $storage = $null; $backup = $null; $other = $null; $total = $null

        if ($res.ResourceId) {
            $key = ([string]$res.ResourceId).ToLower()
            if ($byResource.ContainsKey($key)) {
                $claimed[$key] = $true
                $b = $byResource[$key]
                $compute = [Math]::Round($b.Compute, 4)
                $license = [Math]::Round($b.License, 4)
                $storage = [Math]::Round($b.Storage, 4)
                $backup  = [Math]::Round($b.Backup, 4)
                $other   = [Math]::Round($b.Other, 4)
                $total   = [Math]::Round(($b.Compute + $b.License + $b.Storage + $b.Backup + $b.Other), 4)

                if ($b.Unclassified.Count) {
                    $notes += "unbucketed meter(s): $($b.Unclassified -join ', ')"
                }
            }
        }

        if ($null -eq $total) {
            # these two genuinely dont bill on their own, so an empty cost is correct
            if ($res.RecordType -eq 'ManagedDatabase') {
                $notes += 'no separate cost - billed at the managed instance'
            } elseif ($res.RecordType -eq 'SqlDatabase' -and $res.ElasticPoolName) {
                $notes += "no separate cost - billed at elastic pool '$($res.ElasticPoolName)'"
            } else {
                $notes += 'no billed cost matched'
            }
        }

        $monthly = if ($null -ne $total) { [Math]::Round(($total / $days) * 30, 2) } else { $null }

        # azure hybrid benefit is the single biggest lever on sql compute. when the
        # license meter is actually present we can say what it costs, not just that it exists
        if ($license -gt 0) {
            $notes += 'SQL licensing billed separately - Azure Hybrid Benefit would remove this line'
        } elseif ($res.LicenseType -eq 'LicenseIncluded' -and $res.RecordType -in @('ManagedInstance', 'SqlDatabase', 'ElasticPool')) {
            $notes += 'paying for SQL licensing - Azure Hybrid Benefit not applied'
        }

        $c = New-Object psobject
        $c | Add-Member -MemberType NoteProperty -Name ResourceId -Value $res.ResourceId
        $c | Add-Member -MemberType NoteProperty -Name Days -Value $days
        $c | Add-Member -MemberType NoteProperty -Name ComputeCostPeriodUSD -Value $compute
        $c | Add-Member -MemberType NoteProperty -Name LicenseCostPeriodUSD -Value $license
        $c | Add-Member -MemberType NoteProperty -Name StorageCostPeriodUSD -Value $storage
        $c | Add-Member -MemberType NoteProperty -Name BackupCostPeriodUSD -Value $backup
        $c | Add-Member -MemberType NoteProperty -Name OtherCostPeriodUSD -Value $other
        $c | Add-Member -MemberType NoteProperty -Name TotalCostPeriodUSD -Value $total
        $c | Add-Member -MemberType NoteProperty -Name TotalCostMonthlyUSD -Value $monthly
        $c | Add-Member -MemberType NoteProperty -Name CostNotes -Value $(if ($notes) { $notes -join '; ' } else { $null })
        $costReport += $c
    }

    # anything azure billed that discovery never found still has to show up, otherwise the
    # report quietly understates the estate. retired single servers, resources outside the
    # rg filter, things deleted mid-period - they all land here rather than vanishing.
    foreach ($key in $byResource.Keys) {
        if ($claimed.ContainsKey($key)) { continue }

        $b = $byResource[$key]
        $total = [Math]::Round(($b.Compute + $b.License + $b.Storage + $b.Backup + $b.Other), 4)
        if ($total -le 0) { continue }

        $c = New-Object psobject
        $c | Add-Member -MemberType NoteProperty -Name ResourceId -Value $key
        $c | Add-Member -MemberType NoteProperty -Name UnmatchedResourceName -Value $key.Substring($key.LastIndexOf('/') + 1)
        $c | Add-Member -MemberType NoteProperty -Name Days -Value $days
        $c | Add-Member -MemberType NoteProperty -Name ComputeCostPeriodUSD -Value ([Math]::Round($b.Compute, 4))
        $c | Add-Member -MemberType NoteProperty -Name LicenseCostPeriodUSD -Value ([Math]::Round($b.License, 4))
        $c | Add-Member -MemberType NoteProperty -Name StorageCostPeriodUSD -Value ([Math]::Round($b.Storage, 4))
        $c | Add-Member -MemberType NoteProperty -Name BackupCostPeriodUSD -Value ([Math]::Round($b.Backup, 4))
        $c | Add-Member -MemberType NoteProperty -Name OtherCostPeriodUSD -Value ([Math]::Round($b.Other, 4))
        $c | Add-Member -MemberType NoteProperty -Name TotalCostPeriodUSD -Value $total
        $c | Add-Member -MemberType NoteProperty -Name TotalCostMonthlyUSD -Value ([Math]::Round(($total / $days) * 30, 2))
        $c | Add-Member -MemberType NoteProperty -Name CostNotes -Value 'billed SQL resource that discovery did not return - check scope, or it may be deleted/retired'
        $costReport += $c
    }

    return $costReport
}
