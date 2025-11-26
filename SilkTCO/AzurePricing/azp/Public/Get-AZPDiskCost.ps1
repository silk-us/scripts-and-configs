<#
    .DESCRIPTION
    This is a function that will return the acluclated retail cost for any azure disk object. 

    .EXAMPLE
    The following will provide the estimated retail cost for the disk SQL01-data in the resource group sql-rg:

    Get-AzDisk -Name SQL01-data -ResourceGroupName sql-rg | Get-AZPDiskCost

    .PARAMETER diskObject 
    This is a [System.Object] object that is accepted via pipe. 

    .PARAMETER priceType 
    This is a [string] value for the 3 supported pricing types supported by the Azure Retail Pricing API. By default it is set for 
    Consumption, but also supports Reservation and DevTestConsumption.

    .PARAMETER allLocations 
    By default queries will return the specified VMs most recent (sorted by the effectiveStartDate API response) location pricing 
    information as a singular disk. If you want to see an array that contains all of the locations for this VM sku, then simply specify 
    this [switch] parameter via -allLocations

    .PARAMETER allData
    This [switch] parameter will return all of the responses for the specific disk in the specific region. This will show all of the effectiveStartDate 
    and meterName responses. 

    .PARAMETER requestThrottle
    This [int] parameter defines the rest period in seconds beetween API requests. 1 second is default. 
#>

function Get-AZPDiskCost {
    param(
        [Parameter(ValueFromPipeline,Mandatory)]
        # [Microsoft.Azure.Commands.Compute.Automation.Models.PSDiskList] $diskObject,
        # [Microsoft.Azure.Commands.Compute.Automation.Models.PSDisk] $diskObject,
        [System.Object] $diskObject,
        [parameter()]
        [ValidateSet('Consumption','Reservation','DevTestConsumption')]
        [string] $priceType = 'Consumption',
        [parameter()]
        [ValidateSet('day','month')]
        [string] $unitOfMeasure = 'day',
        [parameter()]
        [switch] $allLocations,
        [parameter()]
        [switch] $allData,
        [parameter()]
        [int] $requestThrottle = 1
    )

    begin {
        Write-Verbose "parsing for $priceType"
    }

    process {
        # Test object typing for later armSku string 

        # Disk class:
        if ($diskObject.Sku.Name -like 'PremiumV2_*') {
            $class = "Pv2"
        } elseif ($diskObject.Sku.Name -like 'Premium_*') {
            $class = "Pv1"
        } elseif ($diskObject.Sku.Name -like 'UltraSSD_*') {
            $class = "Ult"
        } elseif ($diskObject.Sku.Name -like 'StandardSSD_*') {
            $class = "Std"
        }
        
        # Disk availability 
        if ($diskObject.Sku.Name -like '*LRS') {
            $avail = "LRS"
        } elseif ($diskObject.Sku.Name -like '*ZRS') {
            $avail = "ZRS"
        }

        if ($diskObject.Tier) {
            $tier = $diskObject.Tier
            $armSku = $tier + " " + $avail
            $meterName = $armSku + " Disk"
        } elseif ($class -eq "Pv2") {
            $tier = $false
            $armSku = "Premium " + $avail
            $meterName = $armSku + " Provisioned Base Unit"
        }

        Write-Verbose $class
        $diskName = $diskObject.Name
        $diskRG = $diskObject.ResourceGroupName
        Write-Verbose "-> Working with disk - $diskName - in - $diskRG - "

        if ($class -eq 'Pv1' -or $class -eq 'Pv2') {
            $spec = @{}
            $spec.Add("serviceName","Storage")
            if (!$allLocations) {
                $spec.Add("armRegionName",$diskObject.Location)
            }
            $spec.Add("priceType",$priceType)   
            # $spec.Add("armSkuName",$armSku)
            $spec.Add("skuName",$armSku)
            if ($meterName) {
                $spec.Add("meterName",$meterName)
            }
            if ($class -eq 'Pv1') {
                $spec.Add("productName","Premium SSD Managed Disks")
            } elseif ($class -eq 'Pv2') {
                $spec.add("productName","Azure Elastic SAN")
            }   
        } else {    
            $return = $null 
            Write-Verbose "---> $diskName in $diskRG is not Premium Managed Disk. Skipping..." -Verbose
            return $return
        }

        $return = Invoke-AZPRequest -spec $spec 
        
        if (!$allData) {
            try {
                $return = ($return | Sort-Object effectiveStartDate -Descending)[0]
            } catch {
                $return = $null 
                Write-Verbose "---> $diskName in $diskRG sku $armSku not found. Try different search parameters." -Verbose
                return $return
            }
        }

        $returnArray = @()

        foreach ($i in $return) {
            if ($class -eq "Pv2") {
                $cost = Get-AZPPv2Cost -rate $return.retailPrice -GiB $diskObject.DiskSizeGB -IOPS $diskObject.DiskIOPSReadWrite -MBps $diskObject.DiskMBpsReadWrite
            # } elseif ($class -eq "Ult") {
            } else {
                $cost = $i.retailPrice
            }

            if ($unitOfMeasure -eq 'day') {
                $cost = ($cost / 28)
            }
            
            $cost = [math]::Round($cost, 2)

            $r = New-AZPDiskResponse -cost $cost -skuName $i.skuName -location $i.location -unitOfMeasure $unitOfMeasure -armSkuName $i.armSkuName

            $returnArray += $r
        }

        return $returnArray

        Start-Sleep -Seconds $requestThrottle
    }
}
