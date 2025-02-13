param(
    [parameter()]
    [string] $fileName,
    [parameter()]
    [string] $nameFilter = "SQL",
    [parameter()]
    [int] $days = 1
)

try {
    Import-Module Az.Monitor -ErrorAction SilentlyContinue
} catch {
    $errormsg = "Az.Monitor module not available, please install the module."
    return $errormsg | Write-Error
}

$VMs = Get-AzVM | Where-Object {$_.name -match $nameFilter}
$date = Get-Date
$metricArray = @()

$metrics = (
    'Percentage CPU',
    'Network In',
    'Network Out',
    'Data Disk Read Bytes/sec',
    'Data Disk Write Bytes/sec',
    'Data Disk Read Operations/Sec',
    'Data Disk Write Operations/Sec',
    'Data Disk Latency',
    'Data Disk Bandwidth Consumed Percentage',
    'Data Disk IOPS Consumed Percentage',
    'Data Disk Target Bandwidth',
    'Data Disk Target IOPS',
    'OS Disk Read Bytes/sec',
    'OS Disk Write Bytes/sec',
    'OS Disk Read Operations/Sec',
    'OS Disk Write Operations/Sec',
    'OS Disk Bandwidth Consumed Percentage',
    'OS Disk IOPS Consumed Percentage',
    'OS Disk Target Bandwidth',
    'OS Disk Target IOPS',
    'VM Uncached Bandwidth Consumed Percentage',
    'VM Uncached IOPS Consumed Percentage',
    'Network In Total',
    'Network Out Total',
    'Available Memory Bytes'
)

foreach ($i in $VMs) {
    $stats = foreach ($m in $metrics) {
        Get-AzMetric -ResourceId $i.Id -TimeGrain 01:00:00 -StartTime $date.AddDays(-$days) -EndTime $date -MetricName $m
    }

    $sqlVM = Get-AzSqlVM -Name $i.Name -ResourceGroupName $i.ResourceGroupName -ErrorAction SilentlyContinue

    $o = New-Object psobject 
    $o | Add-Member -MemberType NoteProperty -Name 'VM Name' -Value $i.name 
    $o | Add-Member -MemberType NoteProperty -Name 'VM SKU' -Value $i.HardwareProfile.VmSize
    $o | Add-Member -MemberType NoteProperty -Name 'Region' -Value $i.Location
    $o | Add-Member -MemberType NoteProperty -Name 'OS Info' -Value $i.StorageProfile.ImageReference
    $o | Add-Member -MemberType NoteProperty -Name 'DataDisks' -Value $i.StorageProfile.DataDisks

    if ($sqlVM) {
        $o | Add-Member -MemberType NoteProperty -Name 'SQL Offer' -Value $i.SqlImageOffer
        $o | Add-Member -MemberType NoteProperty -Name 'SQL SKU' -Value $i.Location
    } else {
        $o | Add-Member -MemberType NoteProperty -Name 'SQL Offer' -Value $null
        $o | Add-Member -MemberType NoteProperty -Name 'SQL SKU' -Value $null
    }

    $o | Add-Member -MemberType NoteProperty -Name 'Metrcis' -Value $stats
    $metricArray += $o
}

if (!$fileName) {
    $fileName = (Get-Random).toString()  + '.json'
}

$metricArray | ConvertTo-Json -Depth 10 | Out-File $fileName

<#
Valid metrics to select:

Percentage CPU
Network In
Network Out
Disk Read Bytes
Disk Write Bytes
Disk Read Operations/Sec
Disk Write Operations/Sec
CPU Credits Remaining
CPU Credits Consumed
Data Disk Read Bytes/sec
Data Disk Write Bytes/sec
Data Disk Read Operations/Sec
Data Disk Write Operations/Sec
Data Disk Queue Depth
Data Disk Latency
Data Disk Bandwidth Consumed Percentage
Data Disk IOPS Consumed Percentage
Data Disk Target Bandwidth
Data Disk Target IOPS
Data Disk Max Burst Bandwidth
Data Disk Max Burst IOPS
Data Disk Used Burst BPS Credits Percentage
Data Disk Used Burst IO Credits Percentage
OS Disk Read Bytes/sec
OS Disk Write Bytes/sec
OS Disk Read Operations/Sec
OS Disk Write Operations/Sec
OS Disk Queue Depth
OS Disk Latency
OS Disk Bandwidth Consumed Percentage
OS Disk IOPS Consumed Percentage
OS Disk Target Bandwidth
OS Disk Target IOPS
OS Disk Max Burst Bandwidth
OS Disk Max Burst IOPS
OS Disk Used Burst BPS Credits Percentage
OS Disk Used Burst IO Credits Percentage
Temp Disk Latency
Temp Disk Read Bytes/sec
Temp Disk Write Bytes/sec
Temp Disk Read Operations/Sec
Temp Disk Write Operations/Sec
Temp Disk Queue Depth
Inbound Flows
Outbound Flows
Inbound Flows Maximum Creation Rate
Outbound Flows Maximum Creation Rate
Premium Data Disk Cache Read Hit
Premium Data Disk Cache Read Miss
Premium OS Disk Cache Read Hit
Premium OS Disk Cache Read Miss
VM Cached Bandwidth Consumed Percentage
VM Cached IOPS Consumed Percentage
VM Uncached Bandwidth Consumed Percentage
VM Uncached IOPS Consumed Percentage
Network In Total
Network Out Total
Available Memory Bytes
VmAvailabilityMetric
VM Remote Used Burst IO Credits Percentage
VM Remote Used Burst BPS Credits Percentage
VM Local Used Burst IO Credits Percentage
VM Local Used Burst BPS Credits Percentage
#>