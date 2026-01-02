function getVMList {
    param(
        [Parameter()]    
        [string] $subscriptionName,
        [Parameter()]  
        [string] $inputFile,
        [Parameter()]  
        [array] $resourceGroupNames,
        [Parameter()] 
        [array] $zones,
        [Parameter()]
        [switch] $allVMs
    )
    # Generate list of VMs with intake or query
    if ($inputFile) {
        $vmlist = Get-Content $inputFile | ForEach-Object { Get-AzVM -Name $_ -Status }
    }
    else {
        $vmlist = Get-AzVM -Status
    }

    if ($resourceGroupNames) {
        $vmlist = foreach ($r in $resourceGroupNames) {
            $vmlist | Where-Object { $_.ResourceGroupName -contains $r }
        }
    }

    if ($zones) {
        $vmlist = foreach ($z in $zones) {    
            $vmlist | Where-Object { $_.Zones -contains $z }
        }
    }

    if (!$allVMs) {
        $vmlist = $vmlist | Where-Object { $_.PowerState -eq 'VM running' }
    }
    return $vmlist
}

function getVMMetrics {
    param(
        [Parameter()] 
        [string] $days = "1",
        [Parameter(Mandatory)]
        [array] $vmlist
    )


    # Set up some of the output table and vars
    $thelist = @()
    $timegrain = $days + ":" + "00" + ":" + "00" + ":" + '00'

    $totalDiskSizeGB = 0
    $totalDiskIOPS = 0
    $totalDiskMBps = 0
    $totalVMCost = 0
    $totalDiskCost = 0


    # Gather disk metrics. 
    $metrics = (
        'Composite Disk Read Bytes/sec',
        'Composite Disk Write Bytes/sec',
        'Composite Disk Read Operations/Sec',
        'Composite Disk Write Operations/Sec',
        'DiskPaidBurstIOPS'
    )

    # Set up the total vars for each disk metric. 
    foreach ($m in $metrics) {
        New-Variable -Name ($m.replace(' ', $null) + '-avg-total') -Value 0 -force
    }

    $date = Get-Date

    # loop through each VM
    foreach ($i in $vmlist) {
        Write-Verbose "-> Gathering info for VM - $($i.Name)" -Verbose

        # $cost = $i | Get-AZPVMCost
        $vmcost = [Math]::Round(($cost.retailPrice * 24) , 2)

        $totalVMCost = $totalVMCost + $vmcost

        # grab disk info for each VM
        $disklist = $i.StorageProfile.DataDisks
        try {
                $vmstatavg = Get-AzMetric -ResourceId $i.Id -TimeGrain $timegrain -StartTime $date.AddDays(-$days) -EndTime $date -MetricName 'Available Memory Bytes' -AggregationType Average -WarningAction SilentlyContinue
        } catch {
                Write-Verbose "-> Unable to gather VM metrics for $($i.Name)" -Verbose
                $vmstatavg = $null
        }

        if ($disklist) {
            foreach ($d in $disklist) {
                $diskInfo = Get-AzDisk -Name $d.Name -ResourceGroupName $i.ResourceGroupName
                $o = New-Object psobject

                # $cost = $diskInfo | Get-AZPDiskCost
                # $diskcost = [Math]::Ceiling($cost.retailPrice)
                $diskcost = [Math]::Round($cost.retailPrice, 2)

                $diskname = $diskInfo.Name

                Write-Verbose "-> Disk daily cost for - $diskname - $diskcost" -verbose

                # Collect desired info from VM and Disk queries
                $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
                # $o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value $vmcost
                try {
                    $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
                } catch {
                    $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
                }
                $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
                $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
                $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $diskInfo.Name
                $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $diskInfo.Sku.name
                # $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value $cost.armSkuName
                $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $diskInfo.DiskSizeGB
                # $o | Add-Member -MemberType NoteProperty -Name "Disk Cost 1Day" -Value $diskcost
                $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $diskInfo.Tier
                $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $diskInfo.DiskIOPSReadWrite
                $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $diskInfo.DiskMBpsReadWrite
                $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $diskInfo.ResourceGroupName
                $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $diskInfo.Location
                
                $totalDiskSizeGB = $totalDiskSizeGB + $diskInfo.DiskSizeGB
                $totalDiskIOPS = $totalDiskIOPS + $diskInfo.DiskIOPSReadWrite
                $totalDiskMBps = $totalDiskMBps + $diskInfo.DiskMBpsReadWrite
                $totalDiskCost = $totalDiskCost + $diskcost

                foreach ($m in $metrics) {
                    Write-Verbose "-- Gathering $m for $diskname --" -Verbose
                    $statavg = Get-AzMetric -ResourceId $diskInfo.Id -TimeGrain $timegrain -StartTime $date.AddDays(-$days) -EndTime $date -MetricName $m -AggregationType Average -WarningAction SilentlyContinue
                    $o | Add-Member -MemberType NoteProperty -Name ($m.replace(' ', $null) + '-avg') -Value $statavg.data.Average
                    if ($statavg.data.Average) {
                        New-Variable -Name ($m.replace(' ', $null) + '-avg-total') -Value ((Get-Variable -Name ($m.replace(' ', $null) + '-avg-total')).Value + $statavg.data.Average) -force
                    }
                }
                
                $thelist += $o
            } 
        } else {
            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
            # $o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value $vmcost
            try {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
            } catch {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
            }
            $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
            $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
            $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value 'N/A'
            # $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value 'N/A'
            # $o | Add-Member -MemberType NoteProperty -Name "Disk Cost 1Day" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value 'N/A'
            $o | Add-Member -MemberType NoteProperty -Name "Region" -Value 'N/A'

            $thelist += $o
        }
    }

    return $thelist
}


function generateVMReport {
    param(
        [Parameter()]    
        [string] $subscriptionName,
        [Parameter()]  
        [string] $inputFile,
        [Parameter()]  
        [array] $resourceGroupNames,
        [Parameter()] 
        [array] $zones,
        [Parameter()] 
        [string] $days = "1",
        [Parameter()]
        [switch] $allVMs
    )

    <#
        .SYNOPSIS 
        Generates an Azure VM report. 

        .EXAMPLE    
        generateVMReport -outputFile report.csv

        This generates the results and loads them into a simple CSV file named report.csv.

        .EXAMPLE    
        generateVMReport -inputFile vmlist.txt

        This generates a report based on a strict list of VMs specified in a file called `vmlist.txt`.

        .EXAMPLE    
        generateVMReport -zones 1,3

        This generates a report for objects contained in zones 1 and 3.

        .EXAMPLE    
        generateVMReport -resourceGroupNames RG1,RG2

        This generates a report for objects contained in the resource groups named RG1 and RG2.

        .EXAMPLE    
        generateVMReport -days 0 -hours 8

        This generates a report based on the last 8 hours of activity. It auto-generates a datestamped output file 
        and also shows results in the console output. 

    #>


    $ErrorActionPreference = "Stop"
    # -- Check for the required Az.Monitor and AZP modules.

    $requiredModules = @('Az.Monitor', 'azp')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Warning "$module module not found. Installing..."
            Install-Module -Name $module -Force -AllowClobber
        }
        Import-Module $module
    }

    # Stamp the date
    $date = Get-Date

    # Check the subscription
    if ($subscriptionName) {
        Set-AzContext -Subscription $subscriptionName
    }

    # Generate list of VMs with intake or query
    if ($inputFile) {
        $vmlist = Get-Content $inputFile | ForEach-Object { Get-AzVM -Name $_ -Status }
    }
    else {
        $vmlist = Get-AzVM -Status
    }

    if ($resourceGroupNames) {
        $vmlist = foreach ($r in $resourceGroupNames) {
            $vmlist | Where-Object { $_.ResourceGroupName -contains $r }
        }
    }

    if ($zones) {
        $vmlist = foreach ($z in $zones) {    
            $vmlist | Where-Object { $_.Zones -contains $z }
        }
    }

    $vmlist | Select-Object name, ResourceGroupName, zones[0] | Write-Verbose -Verbose



    # Output the totals. 
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value 'Totals:'
    $o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value ([Math]::Round($totalVMCost, 2))
    $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $totalDiskSizeGB
    $o | Add-Member -MemberType NoteProperty -Name "Disk Cost 1Day" -Value ([Math]::Round($totalDiskCost, 2))
    $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $totalDiskIOPS
    $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $totalDiskMBps
    $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $null
    $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $null
    foreach ($m in $metrics) {
        $o | Add-Member -MemberType NoteProperty -Name ($m.replace(' ', $null) + '-avg') -Value (Get-Variable -Name ($m.replace(' ', $null) + '-avg-total')).Value
    }

    $thelist += $o

    $html = makePretty -object $thelist

    [string]$outputFile = ([DateTimeOffset]$Date).ToUnixTimeSeconds().tostring() + ".csv"
    $thelist | Export-Csv -NoTypeInformation -Path $outputFile
    $html | Out-File -FilePath ($outputFile.replace('.csv', '.html')) -Encoding UTF8
    return $thelist
}
