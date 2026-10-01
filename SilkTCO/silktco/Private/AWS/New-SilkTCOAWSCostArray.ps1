<#
    .SYNOPSIS
    Calculates AWS Resource costs based on AWS Pricing API.

    .DESCRIPTION
    This function calculates costs for AWS resources (EC2 instances and EBS volumes)
    by querying the AWS Price List Service API for current list pricing. Costs are
    calculated for the specified number of days (default: 1 day).

    .EXAMPLE
    New-SilkTCOAWSCostArray -vmlist $vmlist -region 'us-east-1' -days 7

    Calculates costs for all resources in the vmlist over a 7-day period.
#>

function New-SilkTCOAWSCostArray {
    param(
        [Parameter(Mandatory)]
        [array] $vmlist,
        [Parameter()]
        [string] $region,
        [Parameter()]
        [int] $days = 1
    )

    # Infer region from vmlist if not provided
    if (-not $region -and $vmlist.Count -gt 0) {
        $availabilityZone = $vmlist[0].Placement.AvailabilityZone
        $region = $availabilityZone -replace '[a-z]$', ''  # Remove trailing letter (e.g., us-east-1a -> us-east-1)
        Write-Verbose "Auto-detected region from vmlist: $region" -Verbose
    }
    
    if (-not $region) {
        $region = 'us-east-1'
        Write-Warning "No region detected, defaulting to: $region"
    }

    # Ensure Pricing module is loaded
    $requiredModules = @('AWS.Tools.Pricing', 'AWS.Tools.EC2')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    Write-Verbose "Querying AWS Pricing API for current rates..." -Verbose

    # Map AWS region codes to pricing API region names
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

    # Cache for pricing lookups
    $ebsPricingCache = @{}
    $ec2PricingCache = @{}

    # Helper function to get EBS pricing from API
    function Get-EBSPricing {
        param(
            [string]$VolumeType,
            [string]$Region
        )

        $cacheKey = "$VolumeType-$Region"
        if ($ebsPricingCache.ContainsKey($cacheKey)) {
            return $ebsPricingCache[$cacheKey]
        }

        try {
            # Query AWS Pricing API for EBS
            $filters = @(
                @{Type='TERM_MATCH'; Field='productFamily'; Value='Storage'}
                @{Type='TERM_MATCH'; Field='volumeApiName'; Value=$VolumeType}
                @{Type='TERM_MATCH'; Field='location'; Value=$Region}
            )

            $products = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $filters -MaxResult 1 -Region us-east-1

            if ($products) {
                $priceJson = $products[0] | ConvertFrom-Json
                $terms = $priceJson.terms.OnDemand
                $firstTerm = $terms.PSObject.Properties.Value | Select-Object -First 1
                $priceDimension = $firstTerm.priceDimensions.PSObject.Properties.Value | Select-Object -First 1
                $pricePerUnit = [decimal]$priceDimension.pricePerUnit.USD

                $ebsPricingCache[$cacheKey] = $pricePerUnit
                return $pricePerUnit
            }
        } catch {
            Write-Verbose "Failed to get pricing for $VolumeType from API: $_" -Verbose
        }

        # Fallback to hardcoded pricing if API fails
        $fallbackPricing = @{
            'gp3' = 0.08; 'gp2' = 0.10; 'io1' = 0.125; 'io2' = 0.125
            'st1' = 0.045; 'sc1' = 0.015; 'standard' = 0.05
        }
        return $fallbackPricing[$VolumeType]
    }

    # Helper function to get EC2 pricing from API
    function Get-EC2Pricing {
        param(
            [string]$InstanceType,
            [string]$Region
        )

        $cacheKey = "$InstanceType-$Region"
        if ($ec2PricingCache.ContainsKey($cacheKey)) {
            return $ec2PricingCache[$cacheKey]
        }

        try {
            # Query AWS Pricing API for EC2
            $filters = @(
                @{Type='TERM_MATCH'; Field='instanceType'; Value=$InstanceType}
                @{Type='TERM_MATCH'; Field='location'; Value=$Region}
                @{Type='TERM_MATCH'; Field='tenancy'; Value='Shared'}
                @{Type='TERM_MATCH'; Field='operatingSystem'; Value='Linux'}
                @{Type='TERM_MATCH'; Field='preInstalledSw'; Value='NA'}
                @{Type='TERM_MATCH'; Field='capacitystatus'; Value='Used'}
            )

            $products = Get-PLSProduct -ServiceCode AmazonEC2 -Filter $filters -MaxResult 1 -Region us-east-1

            if ($products) {
                $priceJson = $products[0] | ConvertFrom-Json
                $terms = $priceJson.terms.OnDemand
                $firstTerm = $terms.PSObject.Properties.Value | Select-Object -First 1
                $priceDimension = $firstTerm.priceDimensions.PSObject.Properties.Value | Select-Object -First 1
                $pricePerHour = [decimal]$priceDimension.pricePerUnit.USD

                $ec2PricingCache[$cacheKey] = $pricePerHour
                return $pricePerHour
            }
        } catch {
            Write-Verbose "Failed to get pricing for $InstanceType from API: $_" -Verbose
        }

        # Fallback to hardcoded pricing if API fails
        $fallbackPricing = @{
            't3.small' = 0.0208; 't3.medium' = 0.0416; 't3.large' = 0.0832
            't3.xlarge' = 0.1664; 't3.2xlarge' = 0.3328
            't3a.small' = 0.0188; 't3a.medium' = 0.0376; 't3a.large' = 0.0752
            't3a.xlarge' = 0.1504; 't3a.2xlarge' = 0.3008
            'm5.large' = 0.096; 'm5.xlarge' = 0.192; 'm5.2xlarge' = 0.384
        }
        return $fallbackPricing[$InstanceType]
    }

    $costReport = @()

    foreach ($vm in $vmlist) {
        $instanceId = $vm.InstanceId
        $instanceType = $vm.InstanceType.Value

        # Get EC2 pricing from API
        $hourlyRate = Get-EC2Pricing -InstanceType $instanceType -Region $pricingRegion
        
        if ($hourlyRate) {
            $dailyVMCost = [Math]::Round($hourlyRate * 24, 4)
            $totalVMCost = [Math]::Round($dailyVMCost * $days, 4)

            $costItem = New-Object psobject
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $instanceId
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value $instanceType
            $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'EC2 Instance'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Compute'
            $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'EC2-Instances'
            $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $totalVMCost
            $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
            $costReport += $costItem

            Write-Verbose "  Instance: $instanceId ($instanceType) = `$$dailyVMCost/day × $days days = `$$totalVMCost" -Verbose
        } else {
            Write-Warning "No pricing data available for instance type: $instanceType"
        }

        # Get attached EBS volumes and calculate costs
        $volumes = Get-EC2Volume -Filter @{
            Name   = 'attachment.instance-id'
            Values = @($instanceId)
        } -ErrorAction SilentlyContinue

        if ($volumes) {
            foreach ($vol in $volumes) {
                $volumeId = $vol.VolumeId
                $volumeType = $vol.VolumeType.Value
                $volumeSize = $vol.Size
                $volumeIops = $vol.Iops

                # Get EBS storage pricing from API (per GB-month)
                $gbMonthPrice = Get-EBSPricing -VolumeType $volumeType -Region $pricingRegion
                
                $dailyStorageCost = 0
                if ($gbMonthPrice) {
                    $monthlyStorageCost = $gbMonthPrice * $volumeSize
                    $dailyStorageCost = [Math]::Round($monthlyStorageCost / 30, 4)
                }

                # Add IOPS cost for io1/io2 volumes (hardcoded as API query is complex)
                $dailyIopsCost = 0
                if ($volumeType -in @('io1', 'io2') -and $volumeIops) {
                    $iopsMonthlyRate = 0.065  # $0.065 per IOPS-month
                    $monthlyIopsCost = $iopsMonthlyRate * $volumeIops
                    $dailyIopsCost = [Math]::Round($monthlyIopsCost / 30, 4)
                }

                $totalDailyCost = $dailyStorageCost + $dailyIopsCost
                $totalPeriodCost = [Math]::Round($totalDailyCost * $days, 4)

                if ($totalPeriodCost -gt 0) {
                    $costItem = New-Object psobject
                    $costItem | Add-Member -MemberType NoteProperty -Name ResourceId -Value $volumeId
                    $costItem | Add-Member -MemberType NoteProperty -Name ResourceName -Value $volumeType
                    $costItem | Add-Member -MemberType NoteProperty -Name ResourceType -Value 'EBS Volume'
                    $costItem | Add-Member -MemberType NoteProperty -Name MeterCategory -Value 'Storage'
                    $costItem | Add-Member -MemberType NoteProperty -Name MeterSubCategory -Value 'EBS'
                    $costItem | Add-Member -MemberType NoteProperty -Name Cost -Value $totalPeriodCost
                    $costItem | Add-Member -MemberType NoteProperty -Name Currency -Value 'USD'
                    $costReport += $costItem

                    Write-Verbose "    Volume: $volumeId ($volumeType ${volumeSize}GB) = `$$totalDailyCost/day × $days days = `$$totalPeriodCost" -Verbose
                }
            }
        }
    }

    if ($costReport.Count -eq 0) {
        Write-Warning "No cost data calculated for the provided resources."
        return
    }

    Write-Verbose "Calculated costs for $($costReport.Count) resources." -Verbose
    return $costReport
}
