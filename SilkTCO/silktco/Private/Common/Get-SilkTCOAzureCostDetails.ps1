<#
    .SYNOPSIS
    Pulls resource level Azure cost from the Cost Details report API.

    .DESCRIPTION
    One report per subscription + date window + metric, cached for the session, so every
    Azure export in the same run reads the same data rather than asking again.

    The window is whole UTC days, both ends inclusive. Cost Management only keeps cost per
    day, so a rolling 24h window touches two days and comes back doubled - which is the
    bug this replaces. -days 1 -offsetDays 1 is all of yesterday, nothing else.

    Rows come back as hashtables on purpose. A busy subscription is tens of thousands of
    rows a day and building a psobject for each one is painfully slow.
#>

function Get-SilkTCOAzureCostDetails {
    param(
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $metric = 'AmortizedCost',
        [Parameter()]
        [int] $timeoutMinutes = 15
    )

    if (-not (Install-SilkTCOModule -Name 'Az.Accounts')) {
        Write-Warning "Az.Accounts unavailable - no cost data will be collected."
        return
    }

    $ctx = Get-AzContext
    if (-not $ctx) {
        Write-Warning "No Azure context - run Connect-AzAccount for cost data."
        return
    }

    $scope = "subscriptions/$($ctx.Subscription.Id)"

    $utcToday  = (Get-Date).ToUniversalTime().Date
    $endDate   = $utcToday.AddDays(-$offsetDays)
    $startDate = $endDate.AddDays(-($days - 1))
    $startStr  = $startDate.ToString('yyyy-MM-dd')
    $endStr    = $endDate.ToString('yyyy-MM-dd')

    # every azure export in the session shares one report per window
    $cacheKey = "$scope|$startStr|$endStr|$metric"
    if (-not $script:SilkTCOCostDetailsCache) { $script:SilkTCOCostDetailsCache = @{} }
    if ($script:SilkTCOCostDetailsCache.ContainsKey($cacheKey)) {
        Write-Verbose "-> reusing cost details already pulled this session ($startStr .. $endStr, $metric)" -Verbose
        return $script:SilkTCOCostDetailsCache[$cacheKey]
    }

    Write-Verbose "Cost window: $startStr .. $endStr ($days day(s), $metric) for $($ctx.Subscription.Name)" -Verbose
    if ($offsetDays -eq 0) {
        Write-Warning "offsetDays 0 includes today, which is always partial - today's cost will read low."
    }

    $tok = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com/').Token
    if ($tok -is [securestring]) { $tok = [System.Net.NetworkCredential]::new('', $tok).Password }
    $headers = @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
    $uri = "https://management.azure.com/$scope/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2023-11-01"

    # api caps a request at one month, so split on calendar month boundaries
    $chunks = @()
    $cursor = $startDate
    while ($cursor -le $endDate) {
        $monthEnd = $cursor.AddDays(1 - $cursor.Day).AddMonths(1).AddDays(-1)
        $chunkEnd = if ($monthEnd -lt $endDate) { $monthEnd } else { $endDate }
        $chunks += , @($cursor, $chunkEnd)
        $cursor = $chunkEnd.AddDays(1)
    }

    $inv         = [System.Globalization.CultureInfo]::InvariantCulture
    $floatStyle  = [System.Globalization.NumberStyles]::Float
    $dateFormats = [string[]]@('MM/dd/yyyy', 'M/d/yyyy', 'yyyy-MM-dd', 'yyyyMMdd')
    $rows        = [System.Collections.Generic.List[hashtable]]::new()
    $datesSeen   = @{}
    $costColUsed = $null

    foreach ($chunk in $chunks) {
        $body = @{
            metric     = $metric
            timePeriod = @{ start = $chunk[0].ToString('yyyy-MM-dd'); end = $chunk[1].ToString('yyyy-MM-dd') }
        } | ConvertTo-Json -Depth 5

        # throttling here is on report generations, so back off and try again
        $resp = $null
        foreach ($wait in 0, 60, 180, 480) {
            if ($wait) {
                Write-Warning "Cost Details throttled, waiting ${wait}s before retrying..."
                Start-Sleep -Seconds $wait
            }
            try {
                $resp = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
                break
            } catch {
                $code = [int]$_.Exception.Response.StatusCode
                if ($code -eq 429) { continue }
                if ($code -in 401, 403) {
                    Write-Warning "Cost Details refused ($code). The identity needs Cost Management Reader on $scope."
                } else {
                    Write-Warning "Cost Details request failed: $($_.Exception.Message)"
                }
                return
            }
        }
        if (-not $resp) {
            Write-Warning "Cost Details still throttled after backing off - no cost data collected."
            return
        }

        # 202 means go poll, 200 means azure already had this report cached
        $manifest = $null
        if ([int]$resp.StatusCode -eq 202) {
            $pollUrl = "$($resp.Headers['Location'])"
        } else {
            $manifest = $resp.Content | ConvertFrom-Json
        }

        $deadline = (Get-Date).AddMinutes($timeoutMinutes)
        while (-not $manifest) {
            if ((Get-Date) -gt $deadline) {
                Write-Warning "Cost Details report didn't finish within $timeoutMinutes minutes."
                return
            }
            try {
                $poll = Invoke-WebRequest -Uri $pollUrl -Method Get -Headers $headers -ErrorAction Stop
            } catch {
                Write-Warning "Lost track of the Cost Details report: $($_.Exception.Message)"
                return
            }
            if ([int]$poll.StatusCode -eq 202) {
                $ra = 20; $n = 0
                if ([int]::TryParse("$($poll.Headers['Retry-After'])", [ref]$n) -and $n -gt 0) { $ra = [Math]::Min(60, $n) }
                Start-Sleep -Seconds $ra
                continue
            }
            $parsed = $poll.Content | ConvertFrom-Json
            switch -Regex ("$($parsed.status)") {
                '^(Completed|NoDataFound)$' { $manifest = $parsed }
                '^(Failed|Cancel)' {
                    Write-Warning "Cost Details report $($parsed.status): $($parsed.error.message)"
                    return
                }
                default { Start-Sleep -Seconds 20 }
            }
        }

        if ("$($manifest.status)" -eq 'NoDataFound') { continue }

        foreach ($blob in @($manifest.manifest.blobs)) {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("silktco-costdetails-" + [guid]::NewGuid().ToString('n') + '.csv')
            try {
                # sas link - sending an auth header gets it rejected
                Invoke-WebRequest -Uri $blob.blobLink -OutFile $tmp -ErrorAction Stop
                $csv = @(Import-Csv -Path $tmp)
            } catch {
                Write-Warning "Couldn't download the Cost Details file: $($_.Exception.Message)"
                return
            } finally {
                Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            }
            if (-not $csv.Count) { continue }

            # column names move around by billing account type. usd first, since every
            # cost column we write out is labelled usd
            $hdr     = @($csv[0].PSObject.Properties.Name)
            $idCol   = @('ResourceId', 'InstanceId', 'InstanceName') | Where-Object { $hdr -contains $_ } | Select-Object -First 1
            $costCol = @('costInUsd', 'costInBillingCurrency', 'Cost', 'PreTaxCost') | Where-Object { $hdr -contains $_ } | Select-Object -First 1
            $dateCol = @('date', 'UsageDate', 'UsageDateTime') | Where-Object { $hdr -contains $_ } | Select-Object -First 1
            if (-not $idCol -or -not $costCol) {
                Write-Warning "Cost Details file has no recognisable resource id / cost column. Got: $($hdr -join ', ')"
                return
            }
            $costColUsed = $costCol

            foreach ($line in $csv) {
                # no resource id = subscription level charge, nothing to hang it on
                $rid = "$($line.$idCol)".ToLower()
                if (-not $rid.StartsWith('/subscriptions/')) { continue }

                $cost = 0.0
                if (-not [double]::TryParse("$($line.$costCol)", $floatStyle, $inv, [ref]$cost)) { continue }

                $day = ''
                if ($dateCol) {
                    $dt = [datetime]::MinValue
                    if ([datetime]::TryParseExact("$($line.$dateCol)", $dateFormats, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) {
                        $day = $dt.ToString('yyyy-MM-dd')
                        $datesSeen[$day] = $true
                    }
                }

                $qty = $null; $q = 0.0
                if ([double]::TryParse("$($line.quantity)", $floatStyle, $inv, [ref]$q)) { $qty = $q }
                $price = $null; $pr = 0.0
                if ([double]::TryParse("$($line.unitPrice)", $floatStyle, $inv, [ref]$pr)) { $price = $pr }

                $rows.Add(@{
                    ResourceId       = $rid
                    Date             = $day
                    Cost             = $cost
                    MeterCategory    = "$($line.meterCategory)"
                    MeterSubCategory = "$($line.meterSubCategory)"
                    MeterName        = "$($line.meterName)"
                    Quantity         = $qty
                    UnitPrice        = $price
                    UnitOfMeasure    = "$($line.unitOfMeasure)"
                    ChargeType       = "$($line.chargeType)"
                    PricingModel     = "$($line.pricingModel)"
                    ReservationId    = "$($line.reservationId)"
                    PublisherType    = "$($line.publisherType)"
                    PublisherName    = "$($line.publisherName)"
                    Tags             = "$($line.tags)"
                })
            }
        }
    }

    # did every day we asked for actually come back
    $requested = @()
    for ($d = $startDate; $d -le $endDate; $d = $d.AddDays(1)) { $requested += $d.ToString('yyyy-MM-dd') }
    $missing = @($requested | Where-Object { -not $datesSeen.ContainsKey($_) })

    if ($rows.Count -eq 0) {
        Write-Warning "Cost Details returned no resource cost for $startStr .. $endStr."
    } elseif ($missing) {
        Write-Warning "No cost data yet for $($missing -join ', '). Azure lags 8-48 hours so those days read as zero - use -offsetDays 2 for a settled day."
    }

    $result = New-Object psobject
    $result | Add-Member -MemberType NoteProperty -Name Scope -Value $scope
    $result | Add-Member -MemberType NoteProperty -Name StartDate -Value $startStr
    $result | Add-Member -MemberType NoteProperty -Name EndDate -Value $endStr
    $result | Add-Member -MemberType NoteProperty -Name Days -Value $days
    $result | Add-Member -MemberType NoteProperty -Name Metric -Value $metric
    $result | Add-Member -MemberType NoteProperty -Name CostColumn -Value $costColUsed
    $result | Add-Member -MemberType NoteProperty -Name DatesWithData -Value @($datesSeen.Keys | Sort-Object)
    $result | Add-Member -MemberType NoteProperty -Name MissingDates -Value $missing
    $result | Add-Member -MemberType NoteProperty -Name Rows -Value $rows

    $script:SilkTCOCostDetailsCache[$cacheKey] = $result
    return $result
}
