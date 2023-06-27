param(
    [Parameter()]    
    [string] $subscriptionName,
    [Parameter()]  
    [string] $inputFile,
    [Parameter()] 
    [string] $outputFile
)

<#
    .SYNOPSIS 
    Generates an Azure VM report. 

    .EXAMPLE    
    ./AzureVMReport.ps1 -outputFile report.csv

    This generates the results and loads tem into a simple CSV file named report.csv

#>

if ($subscriptionName) {
    Set-AzContext -Subscription $subscriptionName
}

# Generate list of VMs with intake or query
if ($inputFile) {
    $vmlist = Get-Content $inputFile | ForEach-Object {Get-AzVM -Name $_}
} else {
    $vmlist = Get-AzVM
}

$thelist = @()

# loop through each VM
foreach ($i in $vmlist) {

    # attempt to Get-AzSQLVm for each VM
    $SQLVM = Get-AzSqlVM -Name $i.name -ResourceGroupName $i.ResourceGroupName -ErrorAction SilentlyContinue

    # grab disk info for each VM
    $disklist = $i.StorageProfile.DataDisks

    foreach ($d in $disklist) {
        $diskInfo = Get-AzDisk -Name $d.Name -ResourceGroupName $i.ResourceGroupName
        $o = New-Object psobject

        # Collect desired info from VM and Disk queries
        $o | Add-Member -MemberType NoteProperty -Name "VM name" -Value $i.name
        $o | Add-Member -MemberType NoteProperty -Name "VM size" -Value $i.HardwareProfile.VmSize
        $o | Add-Member -MemberType NoteProperty -Name "Disk Name" -Value $diskInfo.Name
        $o | Add-Member -MemberType NoteProperty -Name "DiskSKU" -Value $diskInfo.Sku.name
        $o | Add-Member -MemberType NoteProperty -Name "DiskSizeGB" -Value $diskInfo.DiskSizeGB
        $o | Add-Member -MemberType NoteProperty -Name "Disk Tier" -Value $diskInfo.Tier
        $o | Add-Member -MemberType NoteProperty -Name "Disk IOPS" -Value $diskInfo.DiskIOPSReadWrite
        $o | Add-Member -MemberType NoteProperty -Name "ResourceGroup" -Value $i.ResourceGroupName
        $o | Add-Member -MemberType NoteProperty -Name "Region" -Value $i.Location
        $o | Add-Member -MemberType NoteProperty -Name "Zone" -Value $i.Zones[0]

        if ($SQLVM) {
            $o | Add-Member -MemberType NoteProperty -Name "SQLVersion" -Value $SQLVM.Offer
            $o | Add-Member -MemberType NoteProperty -Name "SQLSKU" -Value $SQLVM.Sku
        } else {
            $o | Add-Member -MemberType NoteProperty -Name "SQLVersion" -Value $null
            $o | Add-Member -MemberType NoteProperty -Name "SQLSKU" -Value $null
        }
        $o 
        $thelist += $o
    }
    
}

if ($outputFile) {
    $thelist | Export-Csv -NoTypeInformation -Path $outputFile
} else {
    return $thelist
}