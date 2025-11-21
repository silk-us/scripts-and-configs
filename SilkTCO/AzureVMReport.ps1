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
    [string] $hours = "00",
    [Parameter()] 
    [string] $minutes = "00",
    [Parameter()]
    [switch] $allVMs
)

<#
    .SYNOPSIS 
    Generates an Azure VM report. 

    .EXAMPLE    
    ./AzureVMReportInput.ps1 -outputFile report.csv

    This generates the results and loads them into a simple CSV file named report.csv.

    .EXAMPLE    
    ./AzureVMReportInput.ps1 -inputFile vmlist.txt

    This generates a report based on a strict list of VMs specified in a file called `vmlist.txt`.

    .EXAMPLE    
    ./AzureVMReportInput.ps1 -zones 1,3

    This generates a report for objects contained in zones 1 and 3.

    .EXAMPLE    
    ./AzureVMReportInput.ps1 -resourceGroupNames RG1,RG2

    This generates a report for objects contained in the resource groups named RG1 and RG2.

    .EXAMPLE    
    ./AzureVMReportInput.ps1 -days 0 -hours 8

    This generates a report based on the last 8 hours of activity. It auto-generates a datestamped output file 
    and also shows results in the console output. 

#>

function makePretty {
    param (
        [Parameter(Mandatory)]
        [array]$object
    )

    $data = $object

    $style = @"
<style>
:root{--bg:#0b1220;--card:#0f1724;--muted:#9aa4b2;--accent:#60a5fa;--accent-2:#6ee7b7;--radius:12px;--glass:rgba(255,255,255,0.03);--font:Inter,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial}
*{box-sizing:border-box}
html,body{height:100%;margin:0;padding:20px;background:#2a0719ff;color:#e8f0fb;font-family:var(--font);-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale}
.container{max-width:1400px;margin:0 auto;padding:12px}
.card{background:rgba(255,255,255,0.02);border-radius:var(--radius);padding:18px;border:1px solid rgba(255,255,255,0.03);box-shadow:0 10px 30px rgba(2,6,23,0.6)}
.header-row{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.title{margin:0;font-size:16px;font-weight:600;color:#eaf4ff}
.meta{color:var(--muted);font-size:13px}
.table-wrap{margin-top:14px;overflow-x:auto;padding-bottom:8px;-webkit-overflow-scrolling:touch}
table.csv-table{width:100%;min-width:760px;border-collapse:separate;border-spacing:0;background:transparent;color:#e6eef6;font-size:13px;line-height:1.5}
.csv-table th,.csv-table td{white-space:nowrap;padding:10px 14px;text-align:left;vertical-align:middle;border-bottom:1px solid rgba(255,255,255,0.03)}
.csv-table thead th{position:sticky;top:0;background:var(--th-bg);backdrop-filter:blur(6px);color:#eaf4ff;font-weight:600;z-index:3;border-right:1px solid rgba(255,255,255,0.02)}
.csv-table tbody tr{transition:transform 120ms ease,box-shadow 120ms ease}
.csv-table tbody tr:nth-child(even){}
.csv-table tbody tr:hover{background-color:#ff0062ff}
.cell-inner{display:inline-block;overflow:visible;max-width:100%}
@media (max-width:800px) {
.container{padding:12px}
.title{font-size:15px}
table.csv-table{min-width:680px;font-size:13px}
}
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
<div class='container'>
  <div class='card'>
    <div class='header-row'>
      <div>
        <h1 class='title'>Silk TCO Report</h1>
        <div class='meta'>Generated: $(Get-Date -Format 'u')</div>
      </div>
      <div class='meta'>Rows: $((($data | Measure-Object).Count)) &nbsp;•&nbsp; Columns: $((($data | Select-Object -First 1).PSObject.Properties.Name).Count)</div>
    </div>

    <div class='table-wrap'>
      <table class='csv-table'>
        <tr>
"@

    foreach ($header in $data[0].PSObject.Properties.Name) {
        $html += "<th>$header</th>"
    }
    $html += "</tr>"

    foreach ($row in $data) {
        $html += "<tr>"
        foreach ($header in $data[0].PSObject.Properties.Name) {
            $html += "<td>$($row.$header)</td>"
        }
        $html += "</tr>"
    }

$html += @"
      </table>
    </div>
  </div>
</div>
</body>
</html>
"@

    return $html

}


$ErrorActionPreference = "Stop"
# -- Check for the required Az.Monitor and AZP modules.

try {
    Import-Module Az.Monitor -ErrorAction SilentlyContinue
}
catch {
    $errormsg = "Az.Monitor module not available, please install the module."
    return $errormsg | Write-Error
}

try {
    Import-Module azp -ErrorAction SilentlyContinue
}
catch {
    $errormsg = "Azure Price Calc module (azp) module not available, please install the module."
    return $errormsg | Write-Error
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

# Set up some of the output table and vars
$thelist = @()
$timegrain = $days + ":" + $hours + ":" + $minutes + ":" + '00'

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

if (!$allVMs) {
    $vmlist = $vmlist | Where-Object { $_.PowerState -eq 'VM running' }
}

# loop through each VM
foreach ($i in $vmlist) {
    Write-Verbose "-> Gathering info for VM - $($i.Name)" -Verbose

    $cost = $i | Get-AZPVMCost
    $vmcost = [Math]::Round(($cost.retailPrice * 24) , 2)

    $totalVMCost = $totalVMCost + $vmcost

    # grab disk info for each VM
    $disklist = $i.StorageProfile.DataDisks
    try {
            $vmstatavg = Get-AzMetric -ResourceId $i.Id -TimeGrain $timegrain -StartTime $date.AddHours(-$hours).AddDays(-$days).AddMinutes(-$minutes) -EndTime $date -MetricName 'Available Memory Bytes' -AggregationType Average -WarningAction SilentlyContinue
    } catch {
            Write-Verbose "-> Unable to gather VM metrics for $($i.Name)" -Verbose
            $vmstatavg = $null
    }

    if ($disklist) {
        foreach ($d in $disklist) {
            $diskInfo = Get-AzDisk -Name $d.Name -ResourceGroupName $i.ResourceGroupName
            $o = New-Object psobject

            $cost = $diskInfo | Get-AZPDiskCost
            # $diskcost = [Math]::Ceiling($cost.retailPrice)
            $diskcost = [Math]::Round($cost.retailPrice, 2)

            $diskname = $diskInfo.Name

            Write-Verbose "-> Disk daily cost for - $diskname - $diskcost" -verbose

            # Collect desired info from VM and Disk queries
            $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
            $o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value $vmcost
            try {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
            } catch {
                $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
            }
            $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
            $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
            $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $diskInfo.Name
            $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $diskInfo.Sku.name
            $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $diskInfo.DiskSizeGB
            $o | Add-Member -MemberType NoteProperty -Name "Disk Cost 1Day" -Value $diskcost
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
                $statavg = Get-AzMetric -ResourceId $diskInfo.Id -TimeGrain $timegrain -StartTime $date.AddHours(-$hours).AddDays(-$days).AddMinutes(-$minutes) -EndTime $date -MetricName $m -AggregationType Average -WarningAction SilentlyContinue
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
        $o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value $vmcost
        try {
            $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones[0]
        } catch {
            $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value 'N/A'            
        }
        $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
        $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ([Math]::Round(($vmstatavg.data.Average / 1GB) , 2))
        $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "Disk Cost 1Day" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value 'N/A'
        $o | Add-Member -MemberType NoteProperty -Name "Region" -Value 'N/A'

        $thelist += $o
    }
}

# Output the totals. 
$o = New-Object psobject
$o | Add-Member -MemberType NoteProperty -Name "VM name" -Value 'Totals:'
$o | Add-Member -MemberType NoteProperty -Name "VM cost 1Day" -Value ([Math]::Round($totalVMCost, 2))
$o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $null
$o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value $null
$o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $null
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


