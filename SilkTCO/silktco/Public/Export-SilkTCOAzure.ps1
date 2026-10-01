Function Export-SilkTCOAzure {
    param(
        [Parameter()] 
        [array] $resourceGroupNames,
        [Parameter()]
        [ValidateRange(1, 365)]
        [int] $days = 1,
        [Parameter()]
        [ValidateRange(0, 365)]
        [int] $offsetDays = 1,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $vmlist = New-SilkTCOAzureVMList -resourceGroupNames $resourceGroupNames 
    $metrics = New-SilkTCOAzureVMMetrics -vmlist $vmlist -days $days -offsetDays $offsetDays -Verbose
    # $costs = New-SilkTCOAzureCostArray -days $days
    $costs = New-SilkTCOAzureCostArray -ResourceGroupName $resourceGroupNames -days $days -offsetDays $offsetDays -costMetric $costMetric
    $report = Merge-SilkTCOAzureData -vmlist $vmlist -metrics $metrics -costs $costs

    $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'Azure' -PassThru } 
    $report | export-csv -Path ".\SilkTCO_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
}
