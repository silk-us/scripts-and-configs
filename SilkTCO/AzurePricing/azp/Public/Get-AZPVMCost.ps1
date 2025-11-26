<#
    .DESCRIPTION
    This is a simple VM cost request function that accepts any Azure VM object that is returned as part of a Get-AzVM query. 

    .EXAMPLE
    The following will return the retail pricing request for the VM named SQL01 in the resource group named sql-rq:

    Get-AzVM -Name SQL01 -ResourceGroupName sql-rg | Get-AZPVMCost

    .EXAMPLE
    The following will return all region and meter pricing for the VM named SQL01 in the resource group named sql-rq:

    Get-AzVM -Name SQL01 -ResourceGroupName sql-rg | Get-AZPVMCost -allData -allLocations 

    .PARAMETER vmObject 
    This is a [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachineList] that is accepted across a pipe. 

    .PARAMETER priceType 
    This is a [string] value for the 3 supported pricing types supported by the Azure Retail Pricing API. By default it is set for 
    Consumption, but also supports Reservation and DevTestConsumption.

    .PARAMETER allLocations 
    By default queries will return the specified VMs most recent (sorted by the effectiveStartDate API response) location pricing 
    information as a singular VM. If you want to see an array that contains all of the locations for this VM sku, then simply specify 
    this [switch] parameter via -allLocations

    .PARAMETER allData
    This [switch] parameter will return all of the responses for the specific VM in the specific region. This will show all of the effectiveStartDate 
    and meterName responses. 

    .PARAMETER requestThrottle
    This [int] parameter defines the rest period in seconds beetween API requests. 1 second is default. 
#>

function Get-AZPVMCost {
    param(
        [Parameter(ValueFromPipeline,Mandatory)]
        [System.Object] $vmObject,
        [parameter()]
        [ValidateSet('Consumption','Reservation','DevTestConsumption')]
        [string] $priceType = 'Consumption',
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
        $spec = @{}
        $spec.Add("serviceName","Virtual Machines")
        if (!$allLocations) {
            $spec.Add("armRegionName",$vmObject.Location)
        }
        $spec.Add("priceType",$priceType)   
        $spec.Add("armSkuName",$vmObject.HardwareProfile.VmSize)

        $return = Invoke-AZPRequest -spec $spec 
        
        if (!$allData) {
            $return = ($return | Sort-Object effectiveStartDate -Descending)[0]
        }
        
        return $return
        Start-Sleep -Seconds $requestThrottle
    }
}