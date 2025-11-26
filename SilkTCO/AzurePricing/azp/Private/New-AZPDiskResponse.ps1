function New-AZPDiskResponse {
    param(
        [parameter(Mandatory)]
        [string] $cost,
        [parameter(Mandatory)]
        [string] $skuName,
        [parameter(Mandatory)]
        [string] $armSkuName,
        [parameter(Mandatory)]
        [string] $location,
        [parameter()]
        [ValidateSet('day','month')]
        [string] $unitOfMeasure = 'day'
    )

    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "skuName" -Value $skuName
    $o | Add-Member -MemberType NoteProperty -Name "armSkuName" -Value $armSkuName
    if ($unitOfMeasure -eq 'day') {  
        $o | Add-Member -MemberType NoteProperty -Name "unitOfMeasure" -Value "1 day"
    } elseif (($unitOfMeasure -eq 'month')) {
        $o | Add-Member -MemberType NoteProperty -Name "unitOfMeasure" -Value "1 month"
    }
    $o | Add-Member -MemberType NoteProperty -Name "retailPrice" -Value $cost
    $o | Add-Member -MemberType NoteProperty -Name "location" -Value $location

    return $o
}