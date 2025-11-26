<#
    .DESCRIPTION
    This function serves as a REST handler of sorts for the public Azure pricing API. 

    .NOTES
    This is a simple wrapper function for more-easily building queries against the pricing API as it is documented here:
    https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices

    .EXAMPLE
    In this example, I am going to build a small $spec hashtable that contains the key/value pairs for and submit it to the API.
    This will be for Virtual Machines in the eastus2 region. 

    $spec = @{}
    $spec.Add("serviceName","Virtual Machines")
    $spec.Add("armRegionName","eastus2")

    $eastus2VMs = Invoke-AZPRequest -spec $spec

    .PARAMETER spec
    This is a [hashtable] parameter that includes key/value pairs for the query. These pairs are currently treated as `eq` operators for the purposes 
    of the API request. You can provide any of the parameters listed in the azure retail pricing as part of this hashtable. 

    .PARAMETER loop
    This is an [int] parameter that indicates how many times the .NextPageLink will be followed. By default it is 100. 

    .PARAMETER currencyCode
    This is for the [string] value for the desired currency code. By default it is set for USD, but you can use any of the documented currencyCode values 
    supported by the API. 
#>

function Invoke-AZPRequest {
    param(
        [parameter(Mandatory)]
        [hashtable] $spec,
        [parameter()]
        [string] $currencyCode = 'USD',
        [parameter()]
        [int] $loop = 100
    )

    # Declare the URI
    $specURI = (Get-Variable -Scope Global -Name AZPURI -ErrorAction SilentlyContinue).Value
    if ($specURI) {
        $uri = $specURI
    } else {
        $uri = 'https://prices.azure.com/api/retail/prices'
    }
    
    # $uri = 'https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview'

    $body = New-AZPFilterBody -spec $spec -currencyCode $currencyCode

    $priceArrayQuery = Invoke-RestMethod -Method GET -Uri $uri -body $body 

    # If you specified a loop value, loop through the nextpagelinks until you either run out of loop or reach the end. 

    if ($loop) {
        $items = $priceArrayQuery.Items
        $addPriceArrayQuery = $priceArrayQuery
        $loopCheck = 0
        while ($loopCheck -lt $loop) {
            if ($addPriceArrayQuery.NextPageLink) {
                $uri = $addPriceArrayQuery.NextPageLink
                $addPriceArrayQuery = Invoke-RestMethod -Method GET -Uri $uri
                $items += $addPriceArrayQuery.items
                $loopCheck++
                Write-Verbose $uri
                Start-Sleep -Seconds 1
            } else {
                break 
                Write-Verbose "no more URIs, breaking..." -Verbose
            }
        } 
        $return = $items
    } else {
        $return = $priceArrayQuery.Items
    }
    # return ($priceArrayQuery.Items | Sort-Object effectiveStartDate -Descending)[0] 
    return $return

}

