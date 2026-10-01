<#
    .SYNOPSIS
    Reads the real Azure spend behind a Cloud Block Store deployment.

    .DESCRIPTION
    CBS is a marketplace managed application, so the infrastructure it runs on bills to the
    customer's own subscription inside a managed resource group. We read that spend directly
    rather than inferring it from the CBS model - blob storage is broken out on its own
    because with data landing in blob it's usually the largest and most variable line.

    Cost comes from the shared Cost Details report, filtered to the managed resource group,
    over whole UTC days.

    Deployed performance ceiling is derived from what's actually there (controller VM SKUs,
    provisioned disk IOPS) instead of a datasheet table that goes stale every hardware refresh.
#>

function New-SilkTCOCBSAzureCost {
    param(
        [Parameter(Mandatory)]
        [string] $resourceGroupName,
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $result = New-Object psobject

    # --- deployed footprint, which is also the performance ceiling ---
    $controllerSkus = @()
    $totalDiskIops = 0
    $totalDiskMBps = 0
    $totalDiskGiB = 0
    $diskCount = 0

    if (Install-SilkTCOModule -Name 'Az.Compute') {
        try {
            foreach ($vm in @(Get-AzVM -ResourceGroupName $resourceGroupName -ErrorAction Stop)) {
                $controllerSkus += $vm.HardwareProfile.VmSize
            }
        } catch {
            Write-Warning "Could not enumerate VMs in '$resourceGroupName'. Managed app resource groups carry a deny assignment - reads are normally allowed, so check the RG name. Detail: $($_.Exception.Message)"
        }

        try {
            foreach ($disk in @(Get-AzDisk -ResourceGroupName $resourceGroupName -ErrorAction Stop)) {
                $diskCount++
                if ($disk.DiskIOPSReadWrite) { $totalDiskIops += $disk.DiskIOPSReadWrite }
                if ($disk.DiskMBpsReadWrite) { $totalDiskMBps += $disk.DiskMBpsReadWrite }
                if ($disk.DiskSizeGB) { $totalDiskGiB += $disk.DiskSizeGB }
            }
        } catch {
            Write-Verbose "-> could not enumerate disks in $resourceGroupName" -Verbose
        }
    } else {
        Write-Warning "Az.Compute unavailable - skipping the deployed footprint, cost will still be collected."
    }

    $infra = New-Object psobject
    $infra | Add-Member -MemberType NoteProperty -Name ManagedResourceGroup -Value $resourceGroupName
    $infra | Add-Member -MemberType NoteProperty -Name ControllerVMSizes -Value (($controllerSkus | Sort-Object -Unique) -join '; ')
    $infra | Add-Member -MemberType NoteProperty -Name ControllerVMCount -Value $controllerSkus.Count
    $infra | Add-Member -MemberType NoteProperty -Name BackingDiskCount -Value $diskCount
    $infra | Add-Member -MemberType NoteProperty -Name BackingDiskGiB -Value $totalDiskGiB
    $infra | Add-Member -MemberType NoteProperty -Name DeployedDiskIOPSCeiling -Value $(if ($totalDiskIops) { $totalDiskIops } else { $null })
    $infra | Add-Member -MemberType NoteProperty -Name DeployedDiskMBpsCeiling -Value $(if ($totalDiskMBps) { $totalDiskMBps } else { $null })
    $result | Add-Member -MemberType NoteProperty -Name Infrastructure -Value $infra

    # --- actual billed spend for the managed rg ---
    $lines = @()
    $marketplaceSeen = $false

    $cd = Get-SilkTCOAzureCostDetails -days $days -offsetDays $offsetDays -metric $costMetric
    if ($cd) {
        $rgPath = "/resourcegroups/$($resourceGroupName.ToLower())/"

        # one line per resource per meter category per publisher
        $agg = @{}
        foreach ($r in $cd.Rows) {
            if (-not $r.ResourceId.Contains($rgPath)) { continue }
            $key = "$($r.ResourceId)|$($r.MeterCategory)|$($r.PublisherType)"
            if (-not $agg.ContainsKey($key)) {
                $agg[$key] = @{ ResourceId = $r.ResourceId; MeterCategory = $r.MeterCategory; PublisherType = $r.PublisherType; Cost = 0.0 }
            }
            $agg[$key].Cost += $r.Cost
        }

        foreach ($a in $agg.Values) {
            $resType = Get-SilkTCOResourceType -resourceId $a.ResourceId
            $meterCat = $a.MeterCategory
            $pubType = $a.PublisherType

            if ($pubType -match 'marketplace') { $marketplaceSeen = $true }

            # marketplace first - a license billed against a vm is still the license. then
            # bandwidth before resource type, or a vm's egress gets filed as compute
            $bucket = if ($pubType -match 'marketplace') {
                'MarketplaceLicense'
            } else {
                switch -Regex ("$resType|$meterCat") {
                    'Bandwidth|Load Balancer|IP Address|microsoft\.network' { 'Network'; break }
                    'microsoft\.storage|Storage Accounts|Blob'             { 'BlobStorage'; break }
                    'microsoft\.compute/disks'                              { 'ManagedDisk'; break }
                    'microsoft\.compute/virtualmachines|Virtual Machines'   { 'ControllerVM'; break }
                    default                                                 { 'Other' }
                }
            }

            $l = New-Object psobject
            $l | Add-Member -MemberType NoteProperty -Name Bucket -Value $bucket
            $l | Add-Member -MemberType NoteProperty -Name ResourceId -Value $a.ResourceId
            $l | Add-Member -MemberType NoteProperty -Name ResourceType -Value $resType
            $l | Add-Member -MemberType NoteProperty -Name MeterCategory -Value $meterCat
            $l | Add-Member -MemberType NoteProperty -Name PublisherType -Value $pubType
            $l | Add-Member -MemberType NoteProperty -Name CostPeriod -Value ([Math]::Round($a.Cost, 4))
            $l | Add-Member -MemberType NoteProperty -Name CostMonthly -Value ([Math]::Round(($a.Cost / $days) * 30, 2))
            $lines += $l
        }

        if ($lines) {
            Write-Verbose "Found $($lines.Count) cost line(s) in $resourceGroupName for $($cd.StartDate) .. $($cd.EndDate)." -Verbose
        } else {
            Write-Warning "No cost found in '$resourceGroupName' for $($cd.StartDate) .. $($cd.EndDate). Check the managed resource group name."
        }
    }

    $result | Add-Member -MemberType NoteProperty -Name CostLines -Value @($lines)

    # the license may simply not be here. evergreen//one subscriptions are billed by pure
    # directly and never touch the azure bill - reporting infra as 'total' would be badly low
    $result | Add-Member -MemberType NoteProperty -Name MarketplaceLicenseDetected -Value $marketplaceSeen
    if ($lines -and -not $marketplaceSeen) {
        Write-Warning "No Marketplace license charge found in '$resourceGroupName'. If CBS was bought as a Pure subscription (Evergreen//One) the license is billed outside Azure and this report shows INFRASTRUCTURE ONLY."
    }

    return $result
}
