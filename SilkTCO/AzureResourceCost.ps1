param(
    [Parameter()]
    [string]$ResourceGroupName,
    [Parameter()]
    [int]$days = 1
)

<#
    .SYNOPSIS 
    Generates an Azure Resource Cost report. 

    .EXAMPLE    
    ./AzureResourceCost.ps1 -ResourceGroupName MyResourceGroup

    This generates the cost reports for the RG MyResourceGroup and loads them into a simple date-stamped CSV report. 

    .EXAMPLE    
    ./AzureResourceCost.ps1 -days 28 

    This generates the cost reports for the current azure subscription context and loads them into a simple date-stamped CSV report for the last 28 days.


#>

function makePretty {
    param (
        [Parameter(Mandatory)]
        [array]$object
    )

    $data = $object

    $style = @"
<style>
:root{--bg:#0b1220;--font:Inter,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial}
*{box-sizing:border-box}
html,body{height:100%;margin:0;padding:0;background:#2a0719ff;color:#e8f0fb;font-family:var(--font);-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}
table.csv-table{width:100%;border-collapse:separate;border-spacing:0;background:transparent;color:#e6eef6;font-size:13px;line-height:1.5}
.csv-table th,.csv-table td{white-space:nowrap;padding:10px 14px;text-align:left;vertical-align:middle;border-bottom:1px solid rgba(255,255,255,0.03)}
.csv-table thead th{position:sticky;top:0;background:#2a0719ff;backdrop-filter:blur(6px);color:#eaf4ff;font-weight:600;z-index:3;border-right:1px solid rgba(255,255,255,0.02)}
.csv-table tbody tr{transition:transform 120ms ease,box-shadow 120ms ease}
.csv-table tbody tr:hover{background-color:#ff0062ff}
</style>
"@

    $html = @"
<html>
<head>
<meta charset='UTF-8'>
<title>CSV Report</title>
$style
</head>
<body>
<table class='csv-table'>
<thead>
<tr>
"@

    foreach ($header in $data[0].PSObject.Properties.Name) {
        $html += "<th>$header</th>"
    }
    $html += "</tr></thead><tbody>"

    foreach ($row in $data) {
        $html += "<tr>"
        foreach ($header in $data[0].PSObject.Properties.Name) {
            $html += "<td>$($row.$header)</td>"
        }
        $html += "</tr>"
    }

$html += @"
</tbody>
</table>
</body>
</html>
"@

    return $html

}

$requiredModules = @('Az.CostManagement', 'Az.Resources')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Warning "$module module not found. Installing..."
        Install-Module -Name $module -Force -AllowClobber
    }
    Import-Module $module
}

$subscription = get-azcontext
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ($ResourceGroupName) {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (!$rg) {
        Write-Error "Resource group '$ResourceGroupName' not found."
        exit 1
    }
    $scope = "/subscriptions/$($subscription.subscription.id)/resourceGroups/$ResourceGroupName"
    $sanitizedRgName = $ResourceGroupName -replace '[^\w-]', '_'
    $csvPath = "RG-$sanitizedRgName-Costs-$timestamp.csv"
} else {
    $scope = "/subscriptions/$($subscription.subscription.id)"
    $sanitizedSubscriptionName = $subscription.subscription.name -replace '[^\w-]', '_'
    $csvPath = "$sanitizedSubscriptionName-Costs-$timestamp.csv"
}

Write-Verbose "Subscription: $($subscription.subscription.name)" -Verbose
Write-Verbose "Resource Group: $ResourceGroupName" -Verbose
Write-Verbose "Location: $($rg.Location)" -Verbose

# Get that date range - last 24 hours
$endDate = Get-Date
$startDate = $endDate.AddDays(-$days)

$startDateString = $startDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
$endDateString = $endDate.ToString('yyyy-MM-ddTHH:mm:ssZ')
Write-Verbose "Period: $($startDateString)) to $($endDateString)" -Verbose


Write-Verbose "Querying cost data for $($scope) (this may take a moment)..." -Verbose

# Create query for cost data using hashtable structure
$aggregation = @{
    totalCost = @{
        name = 'PreTaxCost'
        function = 'Sum'
    }
}

$grouping = @(
    @{
        type = 'Dimension'
        name = 'ResourceId'
    },
    @{
        type = 'Dimension'
        name = 'ResourceType'
    },
    @{
        type = 'Dimension'
        name = 'MeterCategory'
    },
    @{
        type = 'Dimension'
        name = 'MeterSubCategory'
    }
)

# Execute the query
$costData = Invoke-AzCostManagementQuery -Scope $scope -Type 'Usage' -Timeframe 'Custom' -TimePeriodFrom $startDateString -TimePeriodTo $endDateString -DatasetGranularity 'None' -DatasetAggregation $aggregation -DatasetGrouping $grouping

if (!$costData -or !$costData.Row -or $costData.Row.Count -eq 0) {
    Write-Verbose "--> No cost data found for scope - $($scope) - in the last $days days." -Verbose
    Write-Verbose "--> Note: Cost data may have a delay of up to 24-48 hours." -Verbose
    exit
}

Write-Verbose "Retrieved $($costData.Row.Count) cost records." -Verbose

# Parse the results
$columnNames = $costData.Column.Name
$report = $costData.Row | ForEach-Object {
    $row = $_
    $rowData = @{}
    for ($i = 0; $i -lt $columnNames.Count; $i++) {
        $rowData[$columnNames[$i]] = $row[$i]
    }
    
    $resourceId = $rowData['ResourceId']
    $resourceName = if ($resourceId) { ($resourceId -split '/')[-1] } else { 'N/A' }
    
    [PSCustomObject]@{
        ResourceName = $resourceName
        ResourceType = $rowData['ResourceType']
        MeterCategory = $rowData['MeterCategory']
        MeterSubCategory = $rowData['MeterSubCategory']
        Cost = [decimal]$rowData['PreTaxCost']
        Currency = $rowData['Currency']
        ResourceId = $resourceId
    }
}

# Filter out zero-cost entries and sort
$sortedReport = $report | Where-Object { $_.Cost -gt 0 } | Sort-Object -Property Cost -Descending

if ($sortedReport.Count -eq 0) {
    Write-Error "No resources with costs found in the last 24 hours."
    exit
}

$costByType = $sortedReport | 
    Group-Object -Property ResourceType | 
    ForEach-Object {
        [PSCustomObject]@{
            ResourceType = $_.Name
            Count = $_.Count
            TotalCost = ($_.Group | Measure-Object -Property Cost -Sum).Sum
            Currency = $_.Group[0].Currency
        }
    } | 
    Sort-Object -Property TotalCost -Descending

$costByType | Format-Table -AutoSize

# Export to CSV
$sortedReport | Export-Csv -Path $csvPath -NoTypeInformation
$html = makePretty -object $sortedReport
$htmlPath = [System.IO.Path]::ChangeExtension($csvPath, '.html')
$html | Out-File -FilePath $htmlPath -Encoding UTF8
Write-Verbose "Detailed report exported to: $csvPath" -Verbose
Write-Verbose "Detailed HTML report exported to: $htmlPath" -Verbose