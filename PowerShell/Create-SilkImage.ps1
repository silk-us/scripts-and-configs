param(
    [parameter()]
    [string] $target_rg,
    [parameter()]
    [string] $storage_container = 'silk',
    [parameter(Mandatory)]
    [string] $imageFileName,
    [parameter(Mandatory)]
    [string] $sasToken
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
$imageName = $imageFileName.replace('.vhd',$null)

# Check for image
$currentImage = Get-AzImage -Name $imageName -ResourceGroupName $target_rg -ErrorAction SilentlyContinue
if ($currentImage) {
    Write-Host -ForegroundColor yellow "Image -- $imageName -- Already exists in resource group -- $target_rg."
    exit 
}

# Create target storage account
Write-Host -ForegroundColor yellow "Creating Storage account $storage_accountname"
$sa = New-AzStorageAccount -Name $storage_accountname -ResourceGroupName $rg.ResourceGroupName -Location $rg.Location -SkuName Standard_LRS
$sc = $sa | New-AzStorageContainer -Name $storage_container 

# Generate storage contexts and copy blob
Write-Host -ForegroundColor yellow "Copying $imageFileName to $storage_accountname"
$sakeys = $sa | Get-AzStorageAccountKey

$srcContext = New-AzStorageContext -StorageAccountName silkimages -SasToken $sasToken 
$dstContext = New-AzStorageContext -StorageAccountName $sa.StorageAccountName -StorageAccountKey $sakeys[0].Value
Start-AzStorageBlobCopy -DestContainer $storage_container -SrcBlob $imageFileName -SrcContainer 'images' -DestContext $dstContext -Context $srcContext -DestBlob $imageFileName 

# Wait for file to be copied
Get-AzStorageBlobCopyState -Blob $imageFileName -Container $storage_container -Context $dstContext -WaitForComplete

# Create Image
$imageURI = $sc.CloudBlobContainer.Uri.AbsoluteUri + '/' + $imageFileName
$imageConfig = New-AzImageConfig -Location $rg.Location
$imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsType Linux -OsState Generalized -BlobUri $imageURI
New-AzImage -ImageName $imageName -ResourceGroupName $rg.ResourceGroupName -Image $imageConfig

