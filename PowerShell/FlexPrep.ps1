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

    $policyAssignments = Get-AzPolicyAssignment -Scope $policyScope -IncludeDescendent

    Write-Host "Processing $($policyAssignments.Count) policy assignment(s)..." -ForegroundColor Cyan
    $policyInfo = @()
    foreach ($pa in $policyAssignments) {
        try {
            Write-Host "  Processing policy: $($pa.Name)" -ForegroundColor Gray
            $policyObject = New-Object PSObject
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Assignment Name" -Value $pa.Name
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Assignment Display Name" -Value $pa.DisplayName
            $policyObject | Add-Member -MemberType NoteProperty -Name "Scope" -Value $pa.Scope
            $policyObject | Add-Member -MemberType NoteProperty -Name "Enforcement Mode" -Value $pa.EnforcementMode
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Id" -Value $pa.PolicyDefinitionId
            $assignmentParameters = if ($pa.Properties -and $pa.Properties.Parameters) { $pa.Properties.Parameters } else { $pa.Parameters }
            if (-not $assignmentParameters) {
                $paRefresh = Get-AzPolicyAssignment -Name $pa.Name -Scope $pa.Scope -ErrorAction SilentlyContinue
                if ($paRefresh -and $paRefresh.Properties -and $paRefresh.Properties.Parameters) {
                    $assignmentParameters = $paRefresh.Properties.Parameters
                }
            }
            if (-not $assignmentParameters -and $pa.Id) {
                try {
                    $paRest = Invoke-AzRestMethod -Method GET -Path "$($pa.Id)?api-version=2023-04-01"
                    if ($paRest.StatusCode -eq 200 -and $paRest.Content) {
                        $paJson = $paRest.Content | ConvertFrom-Json
                        $assignmentParameters = $paJson.properties.parameters
                    }
                } catch {
                    Write-Host "    Warning: Could not retrieve assignment parameters via REST for $($pa.Name)" -ForegroundColor Yellow
                }
            }
            if ($assignmentParameters) {
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Assignment Parameters" -Value $assignmentParameters
            }
            if ($pa.PolicyDefinitionId -match "/policySetDefinitions/") {
                $policySetDef = Get-AzPolicySetDefinition -Id $pa.PolicyDefinitionId -ErrorAction SilentlyContinue
                if (-not $policySetDef) {
                    $policySetName = ($pa.PolicyDefinitionId -split '/')[ -1 ]
                    $policySetDef = Get-AzPolicySetDefinition -Name $policySetName -ErrorAction SilentlyContinue
                }
                $policySetRest = $null
                try {
                    $policySetId = if ($policySetDef -and $policySetDef.Id) { $policySetDef.Id } else { $pa.PolicyDefinitionId }
                    $psRest = Invoke-AzRestMethod -Method GET -Path "$policySetId?api-version=2023-04-01"
                    if ($psRest.StatusCode -eq 200 -and $psRest.Content) {
                        $policySetRest = $psRest.Content | ConvertFrom-Json
                    }
                } catch {
                    Write-Host "    Warning: Could not retrieve policy set via REST for $($pa.Name)" -ForegroundColor Yellow
                }
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Type" -Value "Policy Set"
                $policySetDisplayName = if ($policySetRest -and $policySetRest.properties -and $policySetRest.properties.displayName) { $policySetRest.properties.displayName } elseif ($policySetDef -and $policySetDef.Properties -and $policySetDef.Properties.DisplayName) { $policySetDef.Properties.DisplayName } else { $policySetDef.DisplayName }
                $policySetDescription = if ($policySetRest -and $policySetRest.properties -and $policySetRest.properties.description) { $policySetRest.properties.description } elseif ($policySetDef -and $policySetDef.Properties -and $policySetDef.Properties.Description) { $policySetDef.Properties.Description } else { $policySetDef.Description }
                $policySetRules = if ($policySetRest -and $policySetRest.properties -and $policySetRest.properties.policyDefinitions) { $policySetRest.properties.policyDefinitions } elseif ($policySetDef -and $policySetDef.Properties -and $policySetDef.Properties.PolicyDefinitions) { $policySetDef.Properties.PolicyDefinitions } else { $policySetDef.PolicyDefinitions }
                $policySetParameters = if ($policySetRest -and $policySetRest.properties -and $policySetRest.properties.parameters) { $policySetRest.properties.parameters } elseif ($policySetDef -and $policySetDef.Properties -and $policySetDef.Properties.Parameters) { $policySetDef.Properties.Parameters } else { $policySetDef.Parameters }
                if (-not $policySetParameters) {
                    try {
                        $policySetId = if ($policySetDef -and $policySetDef.Id) { $policySetDef.Id } else { $pa.PolicyDefinitionId }
                        $psRest = Invoke-AzRestMethod -Method GET -Path "$policySetId?api-version=2023-04-01"
                        if ($psRest.StatusCode -eq 200 -and $psRest.Content) {
                            $psJson = $psRest.Content | ConvertFrom-Json
                            $policySetParameters = $psJson.properties.parameters
                        }
                    } catch {
                        Write-Host "    Warning: Could not retrieve policy set parameters via REST for $($pa.Name)" -ForegroundColor Yellow
                    }
                }
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Name" -Value $policySetDisplayName
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Description" -Value $policySetDescription
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Rules" -Value $policySetRules
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Parameters" -Value $policySetParameters
            } else {
                $policyDef = Get-AzPolicyDefinition -Id $pa.PolicyDefinitionId -ErrorAction SilentlyContinue
                if (-not $policyDef) {
                    $policyDefName = ($pa.PolicyDefinitionId -split '/')[ -1 ]
                    $policyDef = Get-AzPolicyDefinition -Name $policyDefName -ErrorAction SilentlyContinue
                }
                $policyDefRest = $null
                try {
                    $policyDefId = if ($policyDef -and $policyDef.Id) { $policyDef.Id } else { $pa.PolicyDefinitionId }
                    $pdRest = Invoke-AzRestMethod -Method GET -Path "$policyDefId?api-version=2023-04-01"
                    if ($pdRest.StatusCode -eq 200 -and $pdRest.Content) {
                        $policyDefRest = $pdRest.Content | ConvertFrom-Json
                    }
                } catch {
                    Write-Host "    Warning: Could not retrieve policy definition via REST for $($pa.Name)" -ForegroundColor Yellow
                }
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Type" -Value "Policy"
                $policyDefDisplayName = if ($policyDefRest -and $policyDefRest.properties -and $policyDefRest.properties.displayName) { $policyDefRest.properties.displayName } elseif ($policyDef -and $policyDef.Properties -and $policyDef.Properties.DisplayName) { $policyDef.Properties.DisplayName } else { $policyDef.DisplayName }
                $policyDefDescription = if ($policyDefRest -and $policyDefRest.properties -and $policyDefRest.properties.description) { $policyDefRest.properties.description } elseif ($policyDef -and $policyDef.Properties -and $policyDef.Properties.Description) { $policyDef.Properties.Description } else { $policyDef.Description }
                $policyDefRule = if ($policyDefRest -and $policyDefRest.properties -and $policyDefRest.properties.policyRule) { $policyDefRest.properties.policyRule } elseif ($policyDef -and $policyDef.Properties -and $policyDef.Properties.PolicyRule) { $policyDef.Properties.PolicyRule } else { $policyDef.PolicyRule }
                $policyDefParameters = if ($policyDefRest -and $policyDefRest.properties -and $policyDefRest.properties.parameters) { $policyDefRest.properties.parameters } elseif ($policyDef -and $policyDef.Properties -and $policyDef.Properties.Parameters) { $policyDef.Properties.Parameters } else { $policyDef.Parameters }
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Name" -Value $policyDefDisplayName
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Description" -Value $policyDefDescription
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Rules" -Value $policyDefRule
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Definition Parameters" -Value $policyDefParameters
            }
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