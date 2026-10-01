<#
    .SYNOPSIS
    Builds both cost bases for Azure NetApp Files capacity pools.

    .DESCRIPTION
    Two independent numbers, deliberately kept in separate columns:

      ProvisionedCost*USD - Azure Retail Prices API rate x pool size. No auth, no
                            billing lag. This is the apples to apples number.
      ActualCost*USD      - the Cost Details report for the pool resource, which is what
                            ANF bills against (not the account or the volumes).

    Each comes out twice: PeriodUSD covers the -days window (so -days 1 is one day's
    cost, matching every other collector in this module) and MonthlyUSD is the same
    thing scaled to 30 days. ActualCostPeriodUSD is the only measured figure on the row.

    Either source can fail on its own without killing the other. A big gap between the two
    usually means reserved capacity, an EA/MCA negotiated rate, or cool access tiering -
    all of which matter, because a customer 40% under list needs comparing at their rate.
#>

function New-SilkTCOANFCostArray {
    param(
        [Parameter(Mandatory)]
        [array] $anflist,
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter()]
        [switch] $skipActualCost,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $costReport = @()
    $retailCache = @{}

    # ---------------------------------------------------------------
    # list price, straight off the public retail api. no module or auth needed
    # ---------------------------------------------------------------
    function Get-AnfRetailRate {
        param(
            [string] $armRegion,
            [string] $serviceLevel
        )

        $cacheKey = "$armRegion-$serviceLevel"
        if ($retailCache.ContainsKey($cacheKey)) {
            return $retailCache[$cacheKey]
        }

        try {
            $filter = "serviceName eq 'Azure NetApp Files' and armRegionName eq '$armRegion'"
            $uri = "https://prices.azure.com/api/retail/prices?`$filter=$([uri]::EscapeDataString($filter))"

            $items = @()
            $page = 0
            while ($uri -and $page -lt 10) {
                $resp = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction Stop
                if ($resp.Items) { $items += $resp.Items }
                $uri = $resp.NextPageLink
                $page++
            }

            # want the plain capacity meter for this tier, not snapshot/backup/replication ones
            $meter = $items | Where-Object {
                $_.meterName -match "^$serviceLevel\s+Capacity$" -and $_.type -eq 'Consumption'
            } | Select-Object -First 1

            # deliberately NO fuzzy fallback here. a loose match happily grabs
            # '<tier> Storage with Cool Access Capacity' or '<tier> Double Encrypted Capacity',
            # and cool access is ~60% cheaper - you'd silently underprice the whole pool.
            # no exact meter = report nothing and say so.

            if ($meter) {
                # anf meters come through hourly (1 GiB/Hour), so scale to a 730h month
                $gibMonth = if ($meter.unitOfMeasure -match 'Hour') {
                    [decimal]$meter.retailPrice * 730
                } else {
                    [decimal]$meter.retailPrice
                }

                $result = New-Object psobject
                $result | Add-Member -MemberType NoteProperty -Name RateGiBMonth -Value ([Math]::Round($gibMonth, 6))
                $result | Add-Member -MemberType NoteProperty -Name MeterName -Value $meter.meterName
                $result | Add-Member -MemberType NoteProperty -Name Currency -Value $meter.currencyCode

                $retailCache[$cacheKey] = $result
                return $result
            }

            Write-Warning "No ANF retail meter matched for $serviceLevel in $armRegion."
        } catch {
            Write-Warning "Azure Retail Prices lookup failed for $armRegion/$serviceLevel : $($_.Exception.Message)"
        }

        return $null
    }

    # ---------------------------------------------------------------
    # actual billed spend, off the shared cost details report
    # ---------------------------------------------------------------
    $actualByResource = @{}

    if (-not $skipActualCost) {
        $cd = Get-SilkTCOAzureCostDetails -days $days -offsetDays $offsetDays -metric $costMetric
        if ($cd) {
            foreach ($r in $cd.Rows) {
                if (-not $r.ResourceId.Contains('/providers/microsoft.netapp/')) { continue }
                if (-not $actualByResource.ContainsKey($r.ResourceId)) { $actualByResource[$r.ResourceId] = 0.0 }
                $actualByResource[$r.ResourceId] += $r.Cost
            }
            Write-Verbose "Matched $($actualByResource.Keys.Count) NetApp resource(s) in cost data." -Verbose
        }
    }

    # ---------------------------------------------------------------
    # stitch both onto each pool
    # ---------------------------------------------------------------
    foreach ($pool in $anflist) {
        if ($pool.IsBackupVault) { continue }

        $notes = @()

        $retail = Get-AnfRetailRate -armRegion $pool.Region -serviceLevel $pool.ServiceLevel
        $listRate = $null
        $provisionedMonthly = $null
        $provisionedPeriod = $null
        if ($retail) {
            $listRate = $retail.RateGiBMonth
            # azure bills capacity by the hour and a day is 24 of them. a 30th of a 730 hour
            # month is 24.3h, which put list 1.4% above what actually gets billed
            $provisionedPeriod = [Math]::Round(($listRate / 730) * 24 * $pool.ProvisionedGiB * $days, 4)
            $provisionedMonthly = [Math]::Round(($provisionedPeriod / $days) * 30, 2)
        } else {
            $notes += 'retail rate unavailable'
        }

        $actualPeriod = $null
        $actualMonthly = $null
        if ($pool.ResourceId) {
            $key = ([string]$pool.ResourceId).ToLower()
            if ($actualByResource.ContainsKey($key)) {
                # what actually got billed across the window. this one is measured, not
                # derived - everything else on the row comes off a rate card
                $actualPeriod = [Math]::Round($actualByResource[$key], 4)
                # window total -> monthly equivalent
                $actualMonthly = [Math]::Round(($actualByResource[$key] / $days) * 30, 2)
            }
        }
        if ($null -eq $actualMonthly) {
            $notes += 'no billed cost matched'
        }

        # compare the same window both ways, so on-list billing reads as 0%
        $variance = $null
        if ($provisionedPeriod -and $null -ne $actualPeriod -and $provisionedPeriod -gt 0) {
            $variance = [Math]::Round((($actualPeriod - $provisionedPeriod) / $provisionedPeriod) * 100, 2)
            if ($variance -lt -10) {
                $notes += 'billed well under list - check reserved capacity or negotiated rate'
            }
        }

        $c = New-Object psobject
        $c | Add-Member -MemberType NoteProperty -Name ResourceId -Value $pool.ResourceId
        $c | Add-Member -MemberType NoteProperty -Name PoolName -Value $pool.PoolName
        $c | Add-Member -MemberType NoteProperty -Name Days -Value $days
        $c | Add-Member -MemberType NoteProperty -Name ListRateGiBMonthUSD -Value $listRate
        $c | Add-Member -MemberType NoteProperty -Name ProvisionedCostPeriodUSD -Value $provisionedPeriod
        $c | Add-Member -MemberType NoteProperty -Name ProvisionedCostMonthlyUSD -Value $provisionedMonthly
        $c | Add-Member -MemberType NoteProperty -Name ActualCostPeriodUSD -Value $actualPeriod
        $c | Add-Member -MemberType NoteProperty -Name ActualCostMonthlyUSD -Value $actualMonthly
        $c | Add-Member -MemberType NoteProperty -Name CostVariancePct -Value $variance
        $c | Add-Member -MemberType NoteProperty -Name CostNotes -Value $(if ($notes) { $notes -join '; ' } else { $null })
        $costReport += $c
    }

    return $costReport
}
