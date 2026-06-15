param(
    [parameter()]
    [string] $URI,
    [parameter()]
    [string] $network,
    [parameter()]
    [string] $project,
    [parameter()]
    [string] $region,
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
    for ($i = 1; $i -le $menuarray.count; $i++) {
        Write-Host "$i. $($menuarray[$i-1].$property)"
        $menu.Add($i, ($menuarray[$i-1].$property))
    }
    Write-Host '------'
    [int]$mntselect = Read-Host $message
    $menu.Item($mntselect)
    Write-Host `n`n
}

# little wrapper - run a gcloud cmd with --format=json and hand back parsed objects.
# GCloud writes progress to stderr so we only care about stdout here.
function Invoke-GcloudJson {
    param([Parameter(Mandatory)][string]$Arguments)
    try {
        $raw = Invoke-Expression "gcloud $Arguments --format=json 2>`$null"
        if (-not $raw) { return @() }
        $parsed = $raw | ConvertFrom-Json
        return $parsed
    } catch {
        Write-Host "  gcloud call failed: gcloud $Arguments" -ForegroundColor DarkGray
        return @()
    }
}

# make sure gcloud is actually here (it always is in cloud shell)
Write-Host "Checking for gcloud CLI..." -ForegroundColor Cyan
$gcloudCmd = Get-Command gcloud -ErrorAction SilentlyContinue
if (-not $gcloudCmd) {
    Write-Host "gcloud CLI not found. Run this from GCP Cloud Shell, or install the Google Cloud SDK." -ForegroundColor Red
    throw "gcloud not available"
}

# Validate account / project context
Write-Host "Validating GCP context..." -ForegroundColor Cyan

$activeAccount = (gcloud config get-value account 2>$null)
if (-not $activeAccount) {
    Write-Host "No active gcloud account. Run 'gcloud auth login' first." -ForegroundColor Red
    throw "No active GCP account"
}
Write-Host "Active account: $activeAccount" -ForegroundColor Green

# project - param, else current config, else prompt from the list
if (-not $project) {
    $project = (gcloud config get-value project 2>$null)
}
if (-not $project) {
    $projList = Invoke-GcloudJson -Arguments "projects list"
    if (-not $projList -or @($projList).Count -eq 0) {
        Write-Host "No projects available to this account." -ForegroundColor Red
        throw "No GCP projects found"
    }
    $project = Build-MenuFromArray -array @($projList) -property 'projectId' -message 'Select Project'
}

# point gcloud at the chosen project for the rest of the run
gcloud config set project $project 2>$null | Out-Null

$projectInfo = Invoke-GcloudJson -Arguments "projects describe $project"
if (-not $projectInfo) {
    Write-Host "Could not describe project '$project'. Check the id and your permissions." -ForegroundColor Red
    throw "Invalid GCP project"
}
Write-Host "Using project: $($projectInfo.name) ($project)" -ForegroundColor Green

# Build Project Object
# keep the same key names the report UI sniffs for (Project / Project ID)
$Cluster = New-Object PSObject
$Cluster | Add-Member -MemberType NoteProperty -Name 'Project'        -Value $projectInfo.name
$Cluster | Add-Member -MemberType NoteProperty -Name 'Project ID'     -Value $project
$Cluster | Add-Member -MemberType NoteProperty -Name 'Project Number' -Value $projectInfo.projectNumber

# region quotas
Write-Host "Retrieving compute regions and quotas..." -ForegroundColor Cyan

# which metrics we care about for a flex deploy
$quotaMetrics = @(
    "CPUS"
    "N2_CPUS"
    "C2_CPUS"
    "DISKS_TOTAL_GB"
    "SSD_TOTAL_GB"
    "LOCAL_SSD_TOTAL_GB"
    "IN_USE_ADDRESSES"
    "NETWORKS"
    "SUBNETWORKS"
)

$allRegions = Invoke-GcloudJson -Arguments "compute regions list"

if ($region) {
    $allRegions = @($allRegions | Where-Object { $_.name -eq $region })
} elseif (-not $global) {
    # default: US regions only (us-east1, us-central1, us-west1, ...)
    $allRegions = @($allRegions | Where-Object { $_.name -match '^us-' })
}

Write-Host "Processing $(@($allRegions).Count) region(s) for quota information..." -ForegroundColor Cyan
$regionQuotas = @()

foreach ($r in @($allRegions)) {
    Write-Host "  Checking quotas for region: $($r.name)" -ForegroundColor Gray

    $regionQuotaObject = New-Object PSObject
    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Region" -Value $r.name

    # zones come back as full self-links, trim to the short zone name
    $zoneNames = @($r.zones | ForEach-Object { ($_ -split '/')[ -1 ] }) | Sort-Object
    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Availability Zones" -Value $zoneNames

    $regionQuotaDetails = @()
    foreach ($metric in $quotaMetrics) {
        $q = $r.quotas | Where-Object { $_.metric -eq $metric } | Select-Object -First 1
        if (-not $q) { continue }

        $quotaDetail = New-Object PSObject
        $quotaDetail | Add-Member -MemberType NoteProperty -Name "Name"          -Value $metric
        $quotaDetail | Add-Member -MemberType NoteProperty -Name "Service"       -Value "compute"
        $quotaDetail | Add-Member -MemberType NoteProperty -Name "Limit"         -Value $q.limit
        $quotaDetail | Add-Member -MemberType NoteProperty -Name "Current Usage" -Value $q.usage
        $regionQuotaDetails += $quotaDetail
    }

    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Quotas" -Value $regionQuotaDetails
    $regionQuotas += $regionQuotaObject
    Write-Host "    Completed quota check for $($r.name)" -ForegroundColor Green
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Region Quotas' -Value $regionQuotas

# VPC queries
# networks are global, subnets per-region - pull subnets+firewalls once, bucket by network
Write-Host "Retrieving VPC network information..." -ForegroundColor Cyan

if ($network) {
    $allNetworks = Invoke-GcloudJson -Arguments "compute networks list --filter=`"name=$network`""
} else {
    $allNetworks = Invoke-GcloudJson -Arguments "compute networks list"
}

# grab all subnets + firewalls up front, filter in-memory per network
$allSubnets   = Invoke-GcloudJson -Arguments "compute networks subnets list"
$allFirewalls = Invoke-GcloudJson -Arguments "compute firewall-rules list"

Write-Host "Processing $(@($allNetworks).Count) network(s)..." -ForegroundColor Cyan
$clusterNetworks = @()

foreach ($n in @($allNetworks)) {
    try {
        Write-Host "  Processing network: $($n.name)" -ForegroundColor Gray

        $netObject = New-Object PSObject
        $netObject | Add-Member -MemberType NoteProperty -Name "Name"             -Value $n.name
        $netObject | Add-Member -MemberType NoteProperty -Name "Routing Mode"     -Value $n.routingConfig.routingMode
        $netObject | Add-Member -MemberType NoteProperty -Name "Auto Create Subnets" -Value $n.autoCreateSubnetworks
        $netObject | Add-Member -MemberType NoteProperty -Name "MTU"              -Value $n.mtu

        # subnets that belong to this network (match on the network self-link tail)
        $subNetInfo = @()
        $netSubnets = @($allSubnets | Where-Object { ($_.network -split '/')[ -1 ] -eq $n.name })
        foreach ($s in $netSubnets) {
            $subnetObject = New-Object PSObject
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Name"           -Value $s.name
            # report UI reads 'Address Prefix' for the cidr, keep that name
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Address Prefix" -Value $s.ipCidrRange
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Region"         -Value (($s.region -split '/')[ -1 ])
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Private Google Access" -Value $s.privateIpGoogleAccess
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Gateway"        -Value $s.gatewayAddress

            # secondary ranges (alias IP / GKE pods+services)
            if ($s.secondaryIpRanges) {
                $secondaries = @($s.secondaryIpRanges | ForEach-Object {
                    $sr = New-Object PSObject
                    $sr | Add-Member -MemberType NoteProperty -Name "Range Name"  -Value $_.rangeName
                    $sr | Add-Member -MemberType NoteProperty -Name "CIDR"         -Value $_.ipCidrRange
                    $sr
                })
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Secondary Ranges" -Value $secondaries
            }
            $subNetInfo += $subnetObject
        }
        $netObject | Add-Member -MemberType NoteProperty -Name "Subnets" -Value $subNetInfo

        # firewall rules on this network
        $fwInfo = @()
        $netFirewalls = @($allFirewalls | Where-Object { ($_.network -split '/')[ -1 ] -eq $n.name })
        foreach ($fw in $netFirewalls) {
            $fwObject = New-Object PSObject
            $fwObject | Add-Member -MemberType NoteProperty -Name "Name"      -Value $fw.name
            $fwObject | Add-Member -MemberType NoteProperty -Name "Direction" -Value $fw.direction
            $fwObject | Add-Member -MemberType NoteProperty -Name "Priority"  -Value $fw.priority
            $fwObject | Add-Member -MemberType NoteProperty -Name "Action"    -Value $(if ($fw.allowed) { 'ALLOW' } elseif ($fw.denied) { 'DENY' } else { 'N/A' })
            $fwObject | Add-Member -MemberType NoteProperty -Name "Source Ranges"      -Value @($fw.sourceRanges)
            $fwObject | Add-Member -MemberType NoteProperty -Name "Destination Ranges" -Value @($fw.destinationRanges)

            # flatten allowed/denied protocol+port rules to readable strings
            $ruleSet = if ($fw.allowed) { $fw.allowed } else { $fw.denied }
            $protoPorts = @($ruleSet | ForEach-Object {
                $ports = if ($_.ports) { ($_.ports -join ',') } else { 'all' }
                "$($_.IPProtocol):$ports"
            })
            $fwObject | Add-Member -MemberType NoteProperty -Name "Rules" -Value $protoPorts
            $fwInfo += $fwObject
        }
        $netObject | Add-Member -MemberType NoteProperty -Name "Firewall Rules" -Value $fwInfo

        $clusterNetworks += $netObject
        Write-Host "    Completed processing network: $($n.name)" -ForegroundColor Green
    } catch {
        Write-Host "    Error processing network $($n.name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'VPC Networks' -Value $clusterNetworks

# org policies (the gcp version of azure policy / aws SCPs)
Write-Host "Retrieving organization policies..." -ForegroundColor Cyan
$orgPolicyInfo = @()
try {
    $orgPolicies = Invoke-GcloudJson -Arguments "resource-manager org-policies list --project=$project"
    Write-Host "Processing $(@($orgPolicies).Count) org policy/policies..." -ForegroundColor Cyan
    foreach ($op in @($orgPolicies)) {
        $opObject = New-Object PSObject
        $opObject | Add-Member -MemberType NoteProperty -Name "Constraint" -Value $op.constraint
        # listPolicy vs booleanPolicy - record whichever is set
        if ($op.booleanPolicy) {
            $opObject | Add-Member -MemberType NoteProperty -Name "Type"    -Value "boolean"
            $opObject | Add-Member -MemberType NoteProperty -Name "Enforced" -Value $op.booleanPolicy.enforced
        } elseif ($op.listPolicy) {
            $opObject | Add-Member -MemberType NoteProperty -Name "Type"          -Value "list"
            $opObject | Add-Member -MemberType NoteProperty -Name "Allowed Values" -Value @($op.listPolicy.allowedValues)
            $opObject | Add-Member -MemberType NoteProperty -Name "Denied Values"  -Value @($op.listPolicy.deniedValues)
        }
        $orgPolicyInfo += $opObject
    }
} catch {
    Write-Host "Warning: Could not retrieve org policies: $($_.Exception.Message)" -ForegroundColor Yellow
    $orgPolicyInfo = @()
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Org Policies' -Value $orgPolicyInfo

# operator iam roles + permissions
# pull the project iam policy, find the bindings the caller is in, describe each role for its perms
Write-Host "Retrieving operator IAM roles and permissions..." -ForegroundColor Cyan

$roleDefCache = @{}
# describe a role -> its includedPermissions. predefined roles use the bare id
# (roles/...), custom roles need the project scope. cache so we dont re-describe.
function Get-GcpRolePermissions {
    param([string]$Role, [string]$ProjectId)
    if (-not $Role) { return @() }
    if ($roleDefCache.ContainsKey($Role)) { return $roleDefCache[$Role] }

    $desc = $null
    if ($Role -like 'projects/*' -or $Role -like 'organizations/*') {
        # custom role - already fully qualified
        $desc = Invoke-GcloudJson -Arguments "iam roles describe $Role"
    } else {
        # predefined role like roles/compute.admin
        $desc = Invoke-GcloudJson -Arguments "iam roles describe $Role"
    }
    $perms = @($desc.includedPermissions)
    $roleDefCache[$Role] = $perms
    return $perms
}

$iamRoles = @()
try {
    $iamPolicy = Invoke-GcloudJson -Arguments "projects get-iam-policy $project"

    # member strings we count as "the operator": the user themselves, plus any
    # group/domain binding (cant cheaply expand group membership from gcloud, so
    # we surface group bindings and note them).
    $userMember = "user:$activeAccount"

    Write-Host "Processing $(@($iamPolicy.bindings).Count) IAM binding(s)..." -ForegroundColor Cyan
    foreach ($binding in @($iamPolicy.bindings)) {
        $members = @($binding.members)

        # is the operator in this binding? direct user match, or a group/domain
        # binding we want to flag as possibly-applies.
        # $directMatch = $members -eq $userMember   # -eq on an array filters, doesnt give a bool
        $directMatch = $members -contains $userMember
        $groupBindings = @($members | Where-Object { $_ -like 'group:*' -or $_ -like 'domain:*' })

        if (-not $directMatch -and $groupBindings.Count -eq 0) { continue }

        $assignmentType = if ($directMatch) { 'User (Direct)' } else { "Group/Domain ($($groupBindings -join ', '))" }

        Write-Host "  Role: $($binding.role) [$assignmentType]" -ForegroundColor Gray
        $perms = Get-GcpRolePermissions -Role $binding.role -ProjectId $project

        # match the standardized role object shape (Role Name / Scope / Actions)
        $o = New-Object PSObject
        $o | Add-Member -MemberType NoteProperty -Name "Role Name"       -Value $binding.role
        $o | Add-Member -MemberType NoteProperty -Name "Scope"           -Value "projects/$project"
        $o | Add-Member -MemberType NoteProperty -Name "Assignment Type" -Value $assignmentType
        $o | Add-Member -MemberType NoteProperty -Name "Is Custom"       -Value ($binding.role -like 'projects/*' -or $binding.role -like 'organizations/*')
        $o | Add-Member -MemberType NoteProperty -Name "Actions"         -Value $perms
        $o | Add-Member -MemberType NoteProperty -Name "Members"         -Value $members
        $iamRoles += $o
    }
    Write-Host "Processed $(@($iamRoles).Count) role binding(s) for the operator." -ForegroundColor Cyan
} catch {
    Write-Host "Error retrieving IAM roles: $($_.Exception.Message)" -ForegroundColor Red
    $iamRoles = @()
}

# bundle the same shape azure/aws use (report UI reads report.IAM.IAMRoles).
# gcp has no PIM so that array stays empty, keeps the schema parallel.
$userScopes = New-Object PSObject
$userScopes | Add-Member -MemberType NoteProperty -Name IAMRoles -Value $iamRoles
$userScopes | Add-Member -MemberType NoteProperty -Name PIMRoles -Value @()

$Cluster | Add-Member -MemberType NoteProperty -Name IAM -Value $userScopes

# write the json out
Write-Host "Generating JSON output file..." -ForegroundColor Cyan
try {
    $filedate   = (Get-Date -Format "yyyyMMdd-HHmmss").ToString()
    $outputFile = "$project-$filedate.json"

    $Cluster | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile
    Write-Host "JSON file created: $outputFile" -ForegroundColor Green
} catch {
    Write-Host "Error creating JSON file: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

if ($URI) {
    Write-Host "Uploading file to Azure Storage..." -ForegroundColor Cyan
    try {
        $SASuri         = [Uri]$URI
        $containerName  = $SASuri.AbsolutePath.TrimStart('/')
        $sasToken       = $SASuri.Query
        $storageAccount = $SASuri.Host.Split('.')[0]

        $blobUrl   = "https://$storageAccount.blob.core.windows.net/$containerName/$outputFile$sasToken"
        $file      = Get-Item -Path $outputFile
        $fileBytes = [System.IO.File]::ReadAllBytes($file.FullName)

        $headers = @{
            'x-ms-blob-type' = 'BlockBlob'
            'Content-Type'   = 'application/json'
        }

        Invoke-RestMethod -Uri $blobUrl -Method Put -Headers $headers -Body $fileBytes -UseBasicParsing | Out-Null
        Write-Host "File uploaded successfully to $storageAccount/$containerName/$outputFile" -ForegroundColor Green
    } catch {
        Write-Host "Error uploading file to Azure Storage: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Local file available at: $outputFile" -ForegroundColor Yellow
    }
}
