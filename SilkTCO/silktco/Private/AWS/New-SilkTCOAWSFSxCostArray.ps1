<#
    .SYNOPSIS
    Calculates AWS FSx for NetApp ONTAP costs from the AWS Pricing API.

    .DESCRIPTION
    Prices the four things FSx ONTAP actually bills for: SSD capacity, capacity pool
    (tiered) capacity, provisioned throughput, and provisioned IOPS above baseline.
    Falls back to rough hardcoded rates if the API lookup fails. List price only -
    no reservations or savings plans are considered.

    .EXAMPLE
    New-SilkTCOAWSFSxCostArray -fslist $fslist -metrics $metrics -region 'us-east-1' -days 30
#>

function New-SilkTCOAWSFSxCostArray {
    param(
        [Parameter(Mandatory)]
        [array] $fslist,
        [Parameter()]
        [array] $metrics,
        [Parameter()]
        [string] $region,
        [Parameter()]
        [int] $days = 1
    )

    # figure out region from the metrics rows if not passed
    if (-not $region -and $metrics) {
        $r = ($metrics | Where-Object { $_.Region -and $_.Region -ne 'N/A' } | Select-Object -First 1).Region
        if ($r) {
            $region = $r
            Write-Verbose "Auto-detected region from fsx metrics: $region" -Verbose
        }
    }

    if (-not $region) {
        $region = 'us-east-1'
        Write-Warning "No region detected, defaulting to: $region"
    }

    $requiredModules = @('AWS.Tools.Pricing')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    Write-Verbose "Querying AWS Pricing API for FSx ONTAP rates..." -Verbose

    # region code -> pricing API location name. wider list than the ec2/rds copies since
    # fsx rates move around more by region and a silent us-east-1 fallback is a real problem
    $regionMapping = @{
        'us-east-1'      = 'US East (N. Virginia)'
        'us-east-2'      = 'US East (Ohio)'
        'us-west-1'      = 'US West (N. California)'
        'us-west-2'      = 'US West (Oregon)'
        'ca-central-1'   = 'Canada (Central)'
        'sa-east-1'      = 'South America (Sao Paulo)'
        'eu-west-1'      = 'EU (Ireland)'
        'eu-west-2'      = 'EU (London)'
        'eu-west-3'      = 'EU (Paris)'
        'eu-central-1'   = 'EU (Frankfurt)'
        'eu-north-1'     = 'EU (Stockholm)'
        'eu-south-1'     = 'EU (Milan)'
        'ap-east-1'      = 'Asia Pacific (Hong Kong)'
        'ap-south-1'     = 'Asia Pacific (Mumbai)'
        'ap-southeast-1' = 'Asia Pacific (Singapore)'
        'ap-southeast-2' = 'Asia Pacific (Sydney)'
        'ap-southeast-3' = 'Asia Pacific (Jakarta)'
        'ap-northeast-1' = 'Asia Pacific (Tokyo)'
        'ap-northeast-2' = 'Asia Pacific (Seoul)'
        'ap-northeast-3' = 'Asia Pacific (Osaka)'
        'me-south-1'     = 'Middle East (Bahrain)'
        'af-south-1'     = 'Africa (Cape Town)'
    }

    if ($regionMapping.ContainsKey($region)) {
        $pricingRegion = $regionMapping[$region]
    } else {
        # dont silently price everything as n.virginia, say so
        $pricingRegion = 'US East (N. Virginia)'
        Write-Warning "Region '$region' is not in the FSx pricing map - falling back to '$pricingRegion'. Costs will be wrong for this region."
    }

    $rateCache = @{}

    # generic pricing lookup against AmazonFSx. filters is an array of TERM_MATCH hashes.
    function Get-FSxRate {
        param(
            [string] $CacheKey,
            [array]  $Filters
        )

        if ($rateCache.ContainsKey($CacheKey)) {
            return $rateCache[$CacheKey]
        }

        try {
            $products = Get-PLSProduct -ServiceCode AmazonFSx -Filter $Filters -MaxResult 1 -Region us-east-1

            if ($products) {
                # Get-PLSProduct hands back one big string, indexing it grabs a character.
                # wrap in @() first or ConvertFrom-Json chokes (same trap as the rds array)
                $priceJson = @($products)[0] | ConvertFrom-Json
                $terms = $priceJson.terms.OnDemand
                $firstTerm = $terms.PSObject.Properties.Value | Select-Object -First 1
                $priceDimension = $firstTerm.priceDimensions.PSObject.Properties.Value | Select-Object -First 1
                $rate = [decimal]$priceDimension.pricePerUnit.USD

                $rateCache[$CacheKey] = $rate
                return $rate
            }
        } catch {
            Write-Verbose "Failed FSx pricing lookup for $CacheKey : $_" -Verbose
        }

        return $null
    }

    # rough us-east-1 list rates, used when the api lookup comes back empty.
    # single-az figures - multi-az roughly doubles capacity and throughput
    $fallback = @{
        'ssd'        = 0.125    # per GB-month
        'pool'       = 0.0219   # per GB-month
        'throughput' = 0.72     # per MBps-month
        'iops'       = 0.0060   # per IOPS-month above baseline
        'backup'     = 0.05     # per GB-month
    }

    $costReport = @()

    foreach ($fs in $fslist) {
        $fsId = $fs.FileSystemId
        $ontap = $fs.OntapConfiguration
        $deployRaw = $ontap.DeploymentType.Value
        $deployment = if ($deployRaw -like 'MULTI_AZ*') { 'Multi-AZ' } else { 'Single-AZ' }
        $azMultiplier = if ($deployment -eq 'Multi-AZ') { 2 } else { 1 }

        $haPairs = if ($ontap.HAPairs) { $ontap.HAPairs } else { 1 }
        $tputPerPair = if ($ontap.ThroughputCapacityPerHAPair) { $ontap.ThroughputCapacityPerHAPair } else { $ontap.ThroughputCapacity }
        $totalThroughput = $tputPerPair * $haPairs

        $m = $metrics | Where-Object { $_.FileSystemId -eq $fsId } | Select-Object -First 1

        # --- ssd capacity ---
        $ssdFilters = @(
            @{Type='TERM_MATCH'; Field='productFamily'; Value='Storage'}
            @{Type='TERM_MATCH'; Field='fileSystemType'; Value='ONTAP'}
            @{Type='TERM_MATCH'; Field='storageType'; Value='SSD'}
            @{Type='TERM_MATCH'; Field='deploymentOption'; Value=$deployment}
            @{Type='TERM_MATCH'; Field='location'; Value=$pricingRegion}
        )
        $ssdRate = Get-FSxRate -CacheKey "ssd-$deployment-$pricingRegion" -Filters $ssdFilters
        if (-not $ssdRate) { $ssdRate = $fallback['ssd'] * $azMultiplier }

        $ssdGB = $fs.StorageCapacity
        if ($ssdGB -and $ssdRate) {
            $dailySsd = [Math]::Round((($ssdRate * $ssdGB) / 30), 4)
            $periodSsd = [Math]::Round($dailySsd * $days, 4)

            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $fsId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value 'SSD'
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'FSx ONTAP Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'FSxN-SSD'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $periodSsd
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "  FSx: $fsId SSD ${ssdGB}GB = `$$dailySsd/day x $days days = `$$periodSsd" -Verbose
        }

        # --- capacity pool (tiered) storage. this is usually where most of the data lives ---
        $poolGB = if ($m -and $m.CapacityPoolUsedGB) { $m.CapacityPoolUsedGB } else { 0 }
        if ($poolGB -gt 0) {
            $poolFilters = @(
                @{Type='TERM_MATCH'; Field='productFamily'; Value='Storage'}
                @{Type='TERM_MATCH'; Field='fileSystemType'; Value='ONTAP'}
                @{Type='TERM_MATCH'; Field='storageType'; Value='Capacity Pool'}
                @{Type='TERM_MATCH'; Field='location'; Value=$pricingRegion}
            )
            $poolRate = Get-FSxRate -CacheKey "pool-$pricingRegion" -Filters $poolFilters
            if (-not $poolRate) { $poolRate = $fallback['pool'] }

            $dailyPool = [Math]::Round((($poolRate * $poolGB) / 30), 4)
            $periodPool = [Math]::Round($dailyPool * $days, 4)

            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $fsId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value 'CapacityPool'
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'FSx ONTAP Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'FSxN-CapacityPool'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $periodPool
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "    Capacity pool ${poolGB}GB = `$$dailyPool/day x $days days = `$$periodPool" -Verbose
        } elseif ($m) {
            # no datapoint doesnt mean no tiered data, it might just be a permissions/metric gap
            Write-Warning "$fsId - no capacity pool usage metric returned. If tiering is enabled this UNDERSTATES the storage bill."
        }

        # --- provisioned throughput. this is the 'compute' half of fsx ---
        $tputFilters = @(
            @{Type='TERM_MATCH'; Field='productFamily'; Value='Provisioned Throughput'}
            @{Type='TERM_MATCH'; Field='fileSystemType'; Value='ONTAP'}
            @{Type='TERM_MATCH'; Field='deploymentOption'; Value=$deployment}
            @{Type='TERM_MATCH'; Field='location'; Value=$pricingRegion}
        )
        $tputRate = Get-FSxRate -CacheKey "tput-$deployment-$pricingRegion" -Filters $tputFilters
        if (-not $tputRate) { $tputRate = $fallback['throughput'] * $azMultiplier }

        if ($totalThroughput -and $tputRate) {
            $dailyTput = [Math]::Round((($tputRate * $totalThroughput) / 30), 4)
            $periodTput = [Math]::Round($dailyTput * $days, 4)

            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $fsId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value "${totalThroughput}MBps"
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'FSx ONTAP Throughput'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Compute'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'FSxN-Throughput'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $periodTput
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "    Throughput ${totalThroughput}MBps ($haPairs HA pair(s)) = `$$dailyTput/day x $days days = `$$periodTput" -Verbose
        }

        # --- provisioned iops, only the bit above the 3 iops/GB baseline is chargeable ---
        if ($ontap.DiskIopsConfiguration.Mode.Value -eq 'USER_PROVISIONED' -and $ontap.DiskIopsConfiguration.Iops) {
            $baselineIops = $ssdGB * 3
            $billableIops = $ontap.DiskIopsConfiguration.Iops - $baselineIops

            if ($billableIops -gt 0) {
                $iopsFilters = @(
                    @{Type='TERM_MATCH'; Field='productFamily'; Value='Provisioned IOPS'}
                    @{Type='TERM_MATCH'; Field='fileSystemType'; Value='ONTAP'}
                    @{Type='TERM_MATCH'; Field='deploymentOption'; Value=$deployment}
                    @{Type='TERM_MATCH'; Field='location'; Value=$pricingRegion}
                )
                $iopsRate = Get-FSxRate -CacheKey "iops-$deployment-$pricingRegion" -Filters $iopsFilters
                if (-not $iopsRate) { $iopsRate = $fallback['iops'] * $azMultiplier }

                $dailyIops = [Math]::Round((($iopsRate * $billableIops) / 30), 4)
                $periodIops = [Math]::Round($dailyIops * $days, 4)

                $costItem = New-Object psobject
                $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $fsId
                $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value "${billableIops}IOPS"
                $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'FSx ONTAP IOPS'
                $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Compute'
                $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'FSxN-IOPS'
                $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $periodIops
                $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
                $costReport += $costItem
            }
        }
    }

    if ($costReport.Count -eq 0) {
        Write-Warning "No FSx cost data calculated for the provided file systems."
        return
    }

    Write-Verbose "Calculated FSx ONTAP costs for $($costReport.Count) line items." -Verbose
    return $costReport
}
