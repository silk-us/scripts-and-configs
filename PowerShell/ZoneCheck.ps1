param (
    [parameter(Mandatory)]
    [string] $SubscriptionName
)

$type = 'Standard_PB6s'

Get-AzSubscription -SubscriptionName $SubscriptionName | Set-AzContext
$allSkus = Get-AzComputeResourceSku
$checkSKU = $allskus | Where-Object {$_.Name -eq $type -and $_.Locations -eq 'eastus'}
$badzone = $checkSKU.LocationInfo.zones
$response = "Slow zone is located in zone -- " + $badzone
return $response
