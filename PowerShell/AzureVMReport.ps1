param(
    [Parameter()]    
    [string] $subscriptionName,
    [Parameter()]  
    [string] $inputFile,
    [Parameter()] 
    [string] $outputFile,
    [Parameter()] 
    [string] $days = "1",
    [Parameter()] 
    [string] $hours = "00",
    [Parameter()] 
    [string] $minutes = "00"
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
    ./AzureVMReportInput.ps1 -days 0 -hours 8

    This generates a report based on the last 8 hours of activity. It auto-generates a datestamped output file 
    and also shows results in the console output. 

#>

$ErrorActionPreference = "Stop"
# -- Check for the required Az.Monitor module

try {
    Import-Module Az.Monitor -ErrorAction SilentlyContinue
} catch {
    $errormsg = "Az.Monitor module not available, please install the module."
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
    $vmlist = Get-Content $inputFile | ForEach-Object {Get-AzVM -Name $_}
} else {
    $vmlist = Get-AzVM
}

# Set up some of the output table and vars
$thelist = @()
$timegrain = $days + ":" + $hours + ":" + $minutes + ":" + '00'

$totalDiskSizeGB = 0
$totalDiskIOPS = 0
$totalDiskMBps = 0

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
    New-Variable -Name ($m.replace(' ',$null) + '-avg-total') -Value 0 -force
}

# loop through each VM
foreach ($i in $vmlist) {

    # grab disk info for each VM
    $disklist = $i.StorageProfile.DataDisks

    if ($disklist) {
        foreach ($d in $disklist) {
            $diskInfo = Get-AzDisk -Name $d.Name -ResourceGroupName $i.ResourceGroupName
            $o = New-Object psobject

            # Collect desired info from VM and Disk queries
            $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.Name
            $o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $i.Zones
            $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize

            $statavg = Get-AzMetric -ResourceId $i.Id -TimeGrain $timegrain -StartTime $date.AddHours(-$hours).AddDays(-$days).AddMinutes(-$minutes) -EndTime $date -MetricName 'Available Memory Bytes' -AggregationType Average -WarningAction SilentlyContinue
            $o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value ($statavg.data.Average / 1GB )

            $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $diskInfo.Name
            $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $diskInfo.Sku.name
            $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $diskInfo.DiskSizeGB
            $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $diskInfo.Tier
            $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $diskInfo.DiskIOPSReadWrite
            $o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $diskInfo.DiskMBpsReadWrite
            $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $diskInfo.ResourceGroupName
            $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $diskInfo.Location
            
            $totalDiskSizeGB = $totalDiskSizeGB + $diskInfo.DiskSizeGB
            $totalDiskIOPS = $totalDiskIOPS + $diskInfo.DiskIOPSReadWrite
            $totalDiskMBps = $totalDiskMBps + $diskInfo.DiskMBpsReadWrite

            foreach ($m in $metrics) {
                $diskname = $diskInfo.Name
                Write-Verbose "-- Gathering $m for $diskname --" -Verbose
                $statavg = Get-AzMetric -ResourceId $diskInfo.Id -TimeGrain $timegrain -StartTime $date.AddHours(-$hours).AddDays(-$days).AddMinutes(-$minutes) -EndTime $date -MetricName $m -AggregationType Average -WarningAction SilentlyContinue
                $o | Add-Member -MemberType NoteProperty -Name ($m.replace(' ',$null) + '-avg') -Value $statavg.data.Average
                if ($statavg.data.Average) {
                    New-Variable -Name ($m.replace(' ',$null) + '-avg-total') -Value ((Get-Variable -Name ($m.replace(' ',$null) + '-avg-total')).Value + $statavg.data.Average) -force
                }
            }
            
            $thelist += $o
        }
    }   
}

# Output the totals. 
$o = New-Object psobject
$o | Add-Member -MemberType NoteProperty -Name "VM name" -Value 'Totals:'
$o | Add-Member -MemberType NoteProperty -Name "VM Zone" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $null
$o | Add-Member -MemberType NoteProperty -Name 'AvailableMemoryBytesGB' -Value $null
$o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $totalDiskSizeGB
$o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $totalDiskIOPS
$o | Add-Member -MemberType NoteProperty -Name "Disk MBps" -Value $totalDiskMBps
$o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $null
$o | Add-Member -MemberType NoteProperty -Name "Region" -Value $null
foreach ($m in $metrics) {
    $o | Add-Member -MemberType NoteProperty -Name ($m.replace(' ',$null) + '-avg') -Value (Get-Variable -Name ($m.replace(' ',$null) + '-avg-total')).Value
}

$thelist += $o

if ($outputFile) {
    $thelist | Export-Csv -NoTypeInformation -Path $outputFile
} else {
    [string]$outputFile = ([DateTimeOffset]$Date).ToUnixTimeSeconds().tostring() + ".csv"
    $thelist | Export-Csv -NoTypeInformation -Path $outputFile
    return $thelist
}