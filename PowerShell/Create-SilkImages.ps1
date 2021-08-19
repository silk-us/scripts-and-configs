param(
    [parameter()]
    [string] $target_rg,
    [parameter()]
    [string] $storage_container = 'silk',
    [parameter()]
    [string] $cnodeVersion,
    [parameter()]
    [string] $dnodeVersion,
    [parameter(Mandatory)]
    [string] $sasToken,
    [parameter()]
    [string] $souceStorageAccount = "silkimages"
)

function Build-MenuFromArray {
    param(
        [Parameter(Mandatory)]
        [array]$array,
        [Parameter(Mandatory)]
        [string]$property,
        [Parameter()]
        [string]$message = "Select item"
    )

    Write-Host '------'
    $menuarray = @()
        foreach ($i in $array) {
            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name $property -Value $i.$property
            $menuarray += $o
        }
    $menu = @{}
    for (
        $i=1
        $i -le $menuarray.count
        $i++
    ) { Write-Host "$i. $($menuarray[$i-1].$property)" 
        $menu.Add($i,($menuarray[$i-1].$property))
    }
    Write-Host '------'
    [int]$mntselect = Read-Host $message
    $menu.Item($mntselect)
    Write-Host `n`n
}

<#
# For later - secure entry for SAS Token
if (!$sasToken) {
    $sastokenSS = Read-Host -Prompt sasToken -AsSecureString
    $sasToken = $sastokenSS | ConvertFrom-SecureString -AsPlainText 
}
#>

if (!$cnodeVersion -and !$dnodeVersion) {
    Write-Host -ForegroundColor yellow "No image versions specified, please set -cnodeVersion or -dnodeVersion (or both)"
    exit
}

if (!$target_rg) {
    $rglist = Get-AzResourceGroup
    $target_rg = Build-MenuFromArray -array $rglist -property resourcegroupname -message "Select the appropriate Resource Group"
}


$rg = Get-AzResourceGroup -Name $target_rg -ErrorAction SilentlyContinue
if (!$rg) {
    Write-Host -ForegroundColor yellow "Resource group -- $target_rg -- Not found. Please check and try again."
    exit
}

$storage_accountname = 'images' + ( -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_})).ToLower()

if ($cnodeVersion) {
    $cImageName = "k2c-cnode-" + $cnodeVersion.Replace('.','-')
    $cImageFileName = $cImageName + ".vhd"
    $currentCImage = Get-AzImage -Name $cimageName -ResourceGroupName $target_rg -ErrorAction SilentlyContinue
    if ($currentCImage) {
        Write-Host -ForegroundColor yellow "Image -- $imageName -- Already exists in resource group -- $target_rg."
        exit 
    }
}

if ($dnodeVersion) {
    $dImageName = "azure-dnode-" + $dnodeVersion.Replace('.','-')
    $dImageFileName = $dImageName + ".vhd"
    $currentDImage = Get-AzImage -Name $dimageName -ResourceGroupName $target_rg -ErrorAction SilentlyContinue
    if ($currentDImage) {
        Write-Host -ForegroundColor yellow "Image -- $imageName -- Already exists in resource group -- $target_rg."
        exit 
    }
}






# Create target storage account
Write-Host -ForegroundColor yellow "Creating Storage account $storage_accountname"
$sa = New-AzStorageAccount -Name $storage_accountname -ResourceGroupName $rg.ResourceGroupName -Location $rg.Location -SkuName Standard_LRS -AllowBlobPublicAccess $false
$sc = $sa | New-AzStorageContainer -Name $storage_container 

# Generate storage contexts and 
Write-Host -ForegroundColor yellow "Copying $cimageFileName and $dimageFileName to $storage_accountname"
$sakeys = $sa | Get-AzStorageAccountKey

$srcContext = New-AzStorageContext -StorageAccountName $souceStorageAccount -SasToken $sasToken 
$dstContext = New-AzStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey $sakeys[0].Value
if ($cnodeVersion) {
    Start-AzStorageBlobCopy -DestContainer $storage_container -SrcBlob $cimageFileName -SrcContainer 'images' -DestContext $dstContext -Context $srcContext -DestBlob $cimageFileName 
}
if ($dnodeVersion) {
    Start-AzStorageBlobCopy -DestContainer $storage_container -SrcBlob $dimageFileName -SrcContainer 'images' -DestContext $dstContext -Context $srcContext -DestBlob $dimageFileName 
}

# Run VM size validation here

$badArray = @()

$response = Get-AzComputeResourceSku -Location $rg.Location | Where-Object {$_.Name -eq 'Standard_D64ds_v4' -or $_.Name -eq 'Standard_L8s_v2'}
$badResources = ($response | Where-Object {$_.Restrictions})
foreach ($r in $badResources) {
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "Location" -Value $r.LocationInfo.Location
    $o | Add-Member -MemberType NoteProperty -Name "VM Size" -Value $r.name
    $o | Add-Member -MemberType NoteProperty -Name "Restriction" -Value $r.Restrictions.reasoncode
    $o | Add-Member -MemberType NoteProperty -Name "Zones" -Value $r.Restrictions.RestrictionInfo.Zones

    $badArray += $o
}

Write-Host -ForegroundColor yellow  "Checking for VM deployment restructions..."
$badArray

# Wait for file to be copied
if ($cnodeVersion) {
    Get-AzStorageBlobCopyState -Blob $cimageFileName -Container $storage_container -Context $dstContext -WaitForComplete
}
if ($dnodeVersion) {
    Get-AzStorageBlobCopyState -Blob $dimageFileName -Container $storage_container -Context $dstContext -WaitForComplete
}

if ($cnodeVersion) {
    # Create cnode Image
    $cimageURI = $sc.CloudBlobContainer.Uri.AbsoluteUri + '/' + $cimageFileName
    $cimageConfig = New-AzImageConfig -Location $rg.Location
    $cimageConfig = Set-AzImageOsDisk -Image $cimageConfig -OsType Linux -OsState Generalized -BlobUri $cimageURI
    New-AzImage -ImageName $cimageName -ResourceGroupName $rg.ResourceGroupName -Image $cimageConfig
}

if ($dnodeVersion) {
    # Create dnode Image
    $dimageURI = $sc.CloudBlobContainer.Uri.AbsoluteUri + '/' + $dimageFileName
    $dimageConfig = New-AzImageConfig -Location $rg.Location
    $dimageConfig = Set-AzImageOsDisk -Image $dimageConfig -OsType Linux -OsState Generalized -BlobUri $dimageURI
    New-AzImage -ImageName $dimageName -ResourceGroupName $rg.ResourceGroupName -Image $dimageConfig
}


