param(
    [parameter(Mandatory)]
    [string] $URI,
    [parameter()]
    [string] $virtualNetwork,
    [parameter()]
    [string] $subscription,
    [parameter()]
    [string] $location,
    [parameter()]
    [switch] $global
)

# Menu function
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

# Check and/or validate subscription

Write-Host "Validating Azure subscription context..." -ForegroundColor Cyan

$azContext = Get-AzContext

if ($azContext.Subscription.Name -ne $subscription) {
    try {
        $azContext = Set-AzContext -Subscription $subscription -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "The provided subscription ID is not valid in the current Azure context." -ForegroundColor Red
        $subscription = $null
    }
}

if (-not $subscription) {
    $subs = Get-AzSubscription
    $subscription = Build-MenuFromArray -array $subs -property 'Name' -message 'Select Subscription'
    Set-AzContext -Subscription $subscription -ErrorAction Stop | Out-Null
    $azContext = Get-AzContext
}

Write-Host "Using subscription: $($azContext.Subscription.Name)" -ForegroundColor Green

# Build Project Object

$Cluster = New-Object PSObject
$Cluster | Add-Member -MemberType NoteProperty -Name 'Subscription Name' -Value $azContext.Subscription.Name
$Cluster | Add-Member -MemberType NoteProperty -Name 'Subscription Id' -Value $azContext.Subscription.Id

# Check host encryption enabled.
Write-Host "Checking host encryption feature status..." -ForegroundColor Cyan
try {
    $hostEncryption = Get-AzProviderFeature -FeatureName "EncryptionAtHost" -ProviderNamespace "Microsoft.Compute"
    $Cluster | Add-Member -MemberType NoteProperty -Name 'Host Encryption' -Value $hostEncryption.RegistrationState
    Write-Host "Host Encryption: $($hostEncryption.RegistrationState)" -ForegroundColor Green
} catch {
    Write-Host "Warning: Failed to check host encryption status - $($_.Exception.Message)" -ForegroundColor Yellow
    $Cluster | Add-Member -MemberType NoteProperty -Name 'Host Encryption' -Value "Unknown"
}

# Cluster details. 
$quotaList = @(
    "Standard Dsv5 Family vCPUs"
    "Standard Esv5 Family vCPUs"
    "Standard Lsv3 Family vCPUs"
    "Standard Laosv4 Family vCPUs"
    "PremiumV2TotalDiskSizeInGB",
    "Total Regional vCPUs"
)

Write-Host "Retrieving compute SKUs and locations..." -ForegroundColor Cyan
# $allskus = get-azComputeResourceSku
if (!$global) {
    $allLocations = Get-AzLocation | Where-Object GeographyGroup -match 'US'
} else {
    $allLocations = Get-AzLocation
}

if ($location) {
    $allLocations = $allLocations | Where-Object {$_.Location -eq $location}
}

Write-Host "Processing $($allLocations.Count) location(s) for quota information..." -ForegroundColor Cyan
$locationQuotas = @()

foreach ($l in $allLocations) {
     try {
        $allskus = get-azComputeResourceSku -Location $l.Location 
        $usage = Get-AzVMUsage -Location $l.Location
    } catch {
        Write-Host "    Error processing location $($l.Location): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }
   
    Write-Host "  Checking quotas for location: $($l.Location)" -ForegroundColor Gray
    $clusterLocation = New-Object PSObject  
    $clusterLocation | Add-Member -MemberType NoteProperty -Name "Location" -Value $l.Location

    $clusterLocationQuota = @()
    foreach ($quotaName in $quotaList) {
        $clusterLocationQuotaName = New-Object PSObject
        $quota = $usage | Where-Object {$_.name.LocalizedValue -eq $quotaName}
        $zones = ($allskus | Where-Object {$_.Family -eq $quota.Name.Value -and $_.LocationInfo.location -eq $l.Location} | Select-Object -First 1).LocationInfo.Zones | Sort-Object 

        $clusterLocationQuotaName | Add-Member -MemberType NoteProperty -Name "Name" -Value $quotaName
        $clusterLocationQuotaName | Add-Member -MemberType NoteProperty -Name "Current Usage" -Value $quota.CurrentValue
        $clusterLocationQuotaName | Add-Member -MemberType NoteProperty -Name "Limit" -Value $quota.Limit
        $clusterLocationQuotaName | Add-Member -MemberType NoteProperty -Name "Zones" -Value $zones

        $clusterLocationQuota += $clusterLocationQuotaName  
    }
    $clusterLocation | Add-Member -MemberType NoteProperty -Name "Quotas" -Value $clusterLocationQuota
    $locationQuotas += $clusterLocation
    Write-Host "    Completed quota check for $($l.Location)" -ForegroundColor Green

}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Location Quotas' -Value $locationQuotas

# Loop over VNets and grab details, subnets, NSGs, UDRs, etc.

Write-Host "Retrieving virtual network information..." -ForegroundColor Cyan
try {

    if ($virtualNetwork) {
        $allVNets = Get-AzVirtualNetwork -Name $virtualNetwork -ErrorAction SilentlyContinue
    } else {
        $allVNets = Get-AzVirtualNetwork
    }

    if ($location) {
        $allVNets = $allVNets | Where-Object {$_.Location -eq $location}
    }

    $clusterVNets = @()

    $allNSGs = Get-AzNetworkSecurityGroup
    $allUDRs = Get-AzRouteTable
    
    Write-Host "Processing $($allVNets.Count) virtual network(s)..." -ForegroundColor Cyan
} catch {
    Write-Host "Error retrieving virtual networks: $($_.Exception.Message)" -ForegroundColor Red
    $allVNets = @()
    $clusterVNets = @()
}

foreach ($v in $allVNets) {
    try {
        Write-Host "  Processing VNet: $($v.Name)" -ForegroundColor Gray
    $clusterVNetsObject = New-Object PSObject
    $clusterVNetsObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $v.Name
    $clusterVNetsObject | Add-Member -MemberType NoteProperty -Name "Resource Group" -Value $v.ResourceGroupName
    $clusterVNetsObject | Add-Member -MemberType NoteProperty -Name "Location" -Value $v.Location
    $clusterVNetsObject | Add-Member -MemberType NoteProperty -Name "Address Prefixes" -Value $v.AddressSpace.AddressPrefixes

    $subNetInfo = @()

    foreach ($s in $v.Subnets) {

        $subnetObject = New-Object PSObject
        $subnetObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $s.Name
        $subnetObject | Add-Member -MemberType NoteProperty -Name "Address Prefix" -Value $s.AddressPrefix
        
        if ($s.NetworkSecurityGroup.Id) {
            $sNSG = $allNSGs | Where-Object {$_.Id -eq $s.NetworkSecurityGroup.Id}
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Network Security Group" -Value $sNSG.Name
            $subnetObject | Add-Member -MemberType NoteProperty -Name "NSG Rules" -Value $sNSG.SecurityRules
        } else {
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Network Security Group" -Value $null
            $subnetObject | Add-Member -MemberType NoteProperty -Name "NSG Rules" -Value $null
        }
        
        if ($s.RouteTable.Id) {
            $sUDR = $allUDRs | Where-Object {$_.Id -eq $s.RouteTable.Id}
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $sUDR.Name
            $subnetObject | Add-Member -MemberType NoteProperty -Name "UDR Routes" -Value $sUDR.Routes
            
        } else {
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $null
            $subnetObject | Add-Member -MemberType NoteProperty -Name "UDR Routes" -Value $null
            
        }
        $subNetInfo += $subnetObject

    }

    $clusterVNetsObject | Add-Member -MemberType NoteProperty -Name "Subnets" -Value $subNetInfo
    $clusterVNets += $clusterVNetsObject
        Write-Host "    Completed processing VNet: $($v.Name)" -ForegroundColor Green
    } catch {
        Write-Host "    Error processing VNet $($v.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Virtual Networks' -Value $clusterVNets

# Loop through any applied policies in scope.

Write-Host "Retrieving policy assignments..." -ForegroundColor Cyan
try {
    $policyScope = "/subscriptions/$($azContext.Subscription.Id)"

    $policyAssignments = Get-AzPolicyAssignment -Scope $policyScope
    $policyDefinitions = Get-AzPolicyDefinition

    Write-Host "Processing $($policyAssignments.Count) policy assignment(s)..." -ForegroundColor Cyan
    $policyInfo = @()
    foreach ($pa in $policyAssignments) {
        try {
            Write-Host "  Processing policy: $($pa.Name)" -ForegroundColor Gray
            $policyObject = New-Object PSObject
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Assignment Name" -Value $pa.Name
            $policyObject | Add-Member -MemberType NoteProperty -Name "Scope" -Value $pa.Scope
            $policyObject | Add-Member -MemberType NoteProperty -Name "Enforcement Mode" -Value $pa.EnforcementMode
            $policyDef = $policyDefinitions | Where-Object {$_.Name  -eq $pa.PolicyDefinitionId}
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Name" -Value $policyDef.DisplayName
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Description" -Value $policyDef.Description
            $policyInfo += $policyObject
        } catch {
            Write-Host "    Error processing policy $($pa.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Error retrieving policy assignments: $($_.Exception.Message)" -ForegroundColor Red
    $policyInfo = @()
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Policy Assignments' -Value $policyInfo

Write-Host "Generating JSON output file..." -ForegroundColor Cyan
try {
    $filedate = (get-date -Format "yyyyMMdd-HHmmss").ToString()
    $outputFile = "$($azContext.Subscription.Name)-$filedate.json"

    $Cluster | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile
    Write-Host "JSON file created: $outputFile" -ForegroundColor Green
} catch {
    Write-Host "Error creating JSON file: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

Write-Host "Uploading file to Azure Storage..." -ForegroundColor Cyan
try {
    # parse container name and SAS token
    $SASuri = [Uri]$Uri
    $containerName = $SASuri.AbsolutePath.TrimStart('/')
    $sasToken = $SASuri.Query
    $storageAccount = $SASuri.Host.Split('.')[0]

    # create storage context
    $ctx = New-AzStorageContext -StorageAccountName $storageAccount -SasToken $sasToken

    # upload file
    $file = Get-Item -Path $outputFile 
    Set-AzStorageBlobContent -File $file.FullName -Container $containerName -Blob $outputFile -Context $ctx -Force | Out-Null
    Write-Host "File uploaded successfully to $storageAccount/$containerName/$outputFile" -ForegroundColor Green
} catch {
    Write-Host "Error uploading file to Azure Storage: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Local file available at: $outputFile" -ForegroundColor Yellow
}