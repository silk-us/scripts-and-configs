<#
    .SYNOPSIS
    Calculates AWS RDS costs based on the AWS Pricing API.

    .DESCRIPTION
    Calculates instance + storage (and provisioned IOPS) costs for standard
    RDS database instances using the AWS Price List Service API. Falls back to
    hardcoded rates if the API lookup fails. Costs are for the specified number
    of days (default: 1 day).

    .EXAMPLE
    New-SilkTCOAWSRDSCostArray -rdslist $rdslist -region 'us-east-1' -days 7
#>

function New-SilkTCOAWSRDSCostArray {
    param(
        [Parameter(Mandatory)]
        [array] $rdslist,
        [Parameter()]
        [string] $region,
        [Parameter()]
        [int] $days = 1
    )

    # figure out region from the db list if not passed
    if (-not $region -and $rdslist.Count -gt 0) {
        $az = $rdslist[0].AvailabilityZone
        if ($az) { $region = $az -replace '[a-z]$', '' }
        Write-Verbose "Auto-detected region from rdslist: $region" -Verbose
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

    Write-Verbose "Querying AWS Pricing API for RDS rates..." -Verbose

    # region code -> pricing API location name
    $regionMapping = @{
        'us-east-1'      = 'US East (N. Virginia)'
        'us-east-2'      = 'US East (Ohio)'
        'us-west-1'      = 'US West (N. California)'
        'us-west-2'      = 'US West (Oregon)'
        'eu-west-1'      = 'EU (Ireland)'
        'eu-central-1'   = 'EU (Frankfurt)'
        'ap-southeast-1' = 'Asia Pacific (Singapore)'
        'ap-southeast-2' = 'Asia Pacific (Sydney)'
        'ap-northeast-1' = 'Asia Pacific (Tokyo)'
    }

    $pricingRegion = if ($regionMapping.ContainsKey($region)) {
        $regionMapping[$region]
    } else {
        'US East (N. Virginia)'
    }

    # RDS engine value -> pricing API databaseEngine name
    $engineMapping = @{
        'postgres'      = 'PostgreSQL'
        'mysql'         = 'MySQL'
        'mariadb'       = 'MariaDB'
        'oracle-se2'    = 'Oracle'
        'oracle-se2-cdb' = 'Oracle'
        'oracle-ee'     = 'Oracle'
        'oracle-ee-cdb' = 'Oracle'
        'sqlserver-se'  = 'SQL Server'
        'sqlserver-ee'  = 'SQL Server'
        'sqlserver-ex'  = 'SQL Server'
        'sqlserver-web' = 'SQL Server'
    }

    # storage type -> pricing volumeType name
    $volumeTypeMapping = @{
        'gp2'      = 'General Purpose'
        'gp3'      = 'General Purpose-GP3'
        'io1'      = 'Provisioned IOPS'
        'io2'      = 'Provisioned IOPS'
        'standard' = 'Magnetic'
    }

    $instanceCache = @{}
    $storageCache = @{}

    # rds instance hourly rate from the api
    function Get-RDSInstancePricing {
        param(
            [string] $InstanceClass,
            [string] $Engine,
            [string] $Deployment,
            [string] $Region
        )

        $cacheKey = "$InstanceClass-$Engine-$Deployment-$Region"
        if ($instanceCache.ContainsKey($cacheKey)) {
            return $instanceCache[$cacheKey]
        }

        try {
            $filters = @(
                @{Type='TERM_MATCH'; Field='productFamily'; Value='Database Instance'}
                @{Type='TERM_MATCH'; Field='instanceType'; Value=$InstanceClass}
                @{Type='TERM_MATCH'; Field='databaseEngine'; Value=$Engine}
                @{Type='TERM_MATCH'; Field='deploymentOption'; Value=$Deployment}
                @{Type='TERM_MATCH'; Field='location'; Value=$Region}
            )

            $products = Get-PLSProduct -ServiceCode AmazonRDS -Filter $filters -MaxResult 1 -Region us-east-1

            if ($products) {
                # Get-PLSProduct returns one big string, not an array. indexing it grabs
                # the first CHARACTER, so wrap in @() first or the json parse blows up
                # $priceJson = $products[0] | ConvertFrom-Json
                $priceJson = @($products)[0] | ConvertFrom-Json
                $terms = $priceJson.terms.OnDemand
                $firstTerm = $terms.PSObject.Properties.Value | Select-Object -First 1
                $priceDimension = $firstTerm.priceDimensions.PSObject.Properties.Value | Select-Object -First 1
                $pricePerHour = [decimal]$priceDimension.pricePerUnit.USD

                $instanceCache[$cacheKey] = $pricePerHour
                return $pricePerHour
            }
        } catch {
            Write-Verbose "Failed to get RDS instance pricing for $InstanceClass from API: $_" -Verbose
        }

        # rough fallback rates (single-az, postgres-ish). doubled below for multi-az
        $fallback = @{
            'db.t3.small' = 0.034; 'db.t3.medium' = 0.068; 'db.t3.large' = 0.136
            'db.t3.xlarge' = 0.272; 'db.t3.2xlarge' = 0.544
            'db.t4g.micro' = 0.016; 'db.t4g.small' = 0.032; 'db.t4g.medium' = 0.065
            'db.t4g.large' = 0.129; 'db.t4g.xlarge' = 0.258; 'db.t4g.2xlarge' = 0.516
            'db.m5.large' = 0.178; 'db.m5.xlarge' = 0.356; 'db.m5.2xlarge' = 0.712
            'db.m5.4xlarge' = 1.424; 'db.r5.large' = 0.24; 'db.r5.xlarge' = 0.48
        }
        $rate = $fallback[$InstanceClass]
        if ($rate -and $Deployment -eq 'Multi-AZ') { $rate = $rate * 2 }
        return $rate
    }

    # rds storage GB-month rate from the api
    function Get-RDSStoragePricing {
        param(
            [string] $VolumeType,
            [string] $Deployment,
            [string] $Region
        )

        $cacheKey = "$VolumeType-$Deployment-$Region"
        if ($storageCache.ContainsKey($cacheKey)) {
            return $storageCache[$cacheKey]
        }

        try {
            $filters = @(
                @{Type='TERM_MATCH'; Field='productFamily'; Value='Database Storage'}
                @{Type='TERM_MATCH'; Field='volumeType'; Value=$VolumeType}
                @{Type='TERM_MATCH'; Field='deploymentOption'; Value=$Deployment}
                @{Type='TERM_MATCH'; Field='location'; Value=$Region}
            )

            $products = Get-PLSProduct -ServiceCode AmazonRDS -Filter $filters -MaxResult 1 -Region us-east-1

            if ($products) {
                # Get-PLSProduct returns one big string, not an array. indexing it grabs
                # the first CHARACTER, so wrap in @() first or the json parse blows up
                # $priceJson = $products[0] | ConvertFrom-Json
                $priceJson = @($products)[0] | ConvertFrom-Json
                $terms = $priceJson.terms.OnDemand
                $firstTerm = $terms.PSObject.Properties.Value | Select-Object -First 1
                $priceDimension = $firstTerm.priceDimensions.PSObject.Properties.Value | Select-Object -First 1
                $pricePerUnit = [decimal]$priceDimension.pricePerUnit.USD

                $storageCache[$cacheKey] = $pricePerUnit
                return $pricePerUnit
            }
        } catch {
            Write-Verbose "Failed to get RDS storage pricing for $VolumeType from API: $_" -Verbose
        }

        # fallback GB-month rates (single-az)
        $fallback = @{
            'General Purpose' = 0.115; 'General Purpose-GP3' = 0.115
            'Provisioned IOPS' = 0.125; 'Magnetic' = 0.10
        }
        $rate = $fallback[$VolumeType]
        if ($rate -and $Deployment -eq 'Multi-AZ') { $rate = $rate * 2 }
        return $rate
    }

    $costReport = @()

    foreach ($db in $rdslist) {
        $dbId = $db.DBInstanceIdentifier
        $instanceClass = $db.DBInstanceClass
        $deployment = if ($db.MultiAZ) { 'Multi-AZ' } else { 'Single-AZ' }
        $engine = if ($engineMapping.ContainsKey($db.Engine)) { $engineMapping[$db.Engine] } else { $db.Engine }

        # --- instance cost ---
        $hourlyRate = Get-RDSInstancePricing -InstanceClass $instanceClass -Engine $engine -Deployment $deployment -Region $pricingRegion

        if ($hourlyRate) {
            $dailyCost = [Math]::Round($hourlyRate * 24, 4)
            $totalCost = [Math]::Round($dailyCost * $days, 4)

            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $dbId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value $instanceClass
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'RDS Instance'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Compute'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'RDS-Instances'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $totalCost
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "  RDS: $dbId ($instanceClass/$deployment) = `$$dailyCost/day x $days days = `$$totalCost" -Verbose
        } else {
            Write-Warning "No pricing data available for RDS class: $instanceClass"
        }

        # --- storage cost ---
        $volType = if ($volumeTypeMapping.ContainsKey($db.StorageType)) { $volumeTypeMapping[$db.StorageType] } else { 'General Purpose' }
        $gbMonthRate = Get-RDSStoragePricing -VolumeType $volType -Deployment $deployment -Region $pricingRegion

        $dailyStorageCost = 0
        if ($gbMonthRate -and $db.AllocatedStorage) {
            $monthly = $gbMonthRate * $db.AllocatedStorage
            $dailyStorageCost = [Math]::Round($monthly / 30, 4)
        }

        # provisioned iops adder for io1/io2 (hardcoded, api query is fiddly)
        $dailyIopsCost = 0
        if ($db.StorageType -in @('io1', 'io2') -and $db.Iops) {
            $iopsMonthlyRate = 0.10  # ~$0.10 per IOPS-month for RDS io1
            if ($deployment -eq 'Multi-AZ') { $iopsMonthlyRate = $iopsMonthlyRate * 2 }
            $dailyIopsCost = [Math]::Round(($iopsMonthlyRate * $db.Iops) / 30, 4)
        }

        $totalDaily = $dailyStorageCost + $dailyIopsCost
        $totalStoragePeriod = [Math]::Round($totalDaily * $days, 4)

        if ($totalStoragePeriod -gt 0) {
            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $dbId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value $db.StorageType
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'RDS Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Storage'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'RDS'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $totalStoragePeriod
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "    Storage: $dbId ($($db.StorageType) $($db.AllocatedStorage)GB) = `$$totalDaily/day x $days days = `$$totalStoragePeriod" -Verbose
        }
    }

    if ($costReport.Count -eq 0) {
        Write-Warning "No RDS cost data calculated for the provided resources."
        return
    }

    Write-Verbose "Calculated RDS costs for $($costReport.Count) line items." -Verbose
    return $costReport
}
