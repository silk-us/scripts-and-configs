param(
    [parameter()]
    [string] $URI,
    [parameter()]
    [string] $vpc,
    [parameter()]
    [string] $account,
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

# Remove any conflicting AWS modules that may be loaded
Write-Host "Checking for module conflicts..." -ForegroundColor Cyan

# Remove old AWSPowerShell modules if loaded (conflicts with AWS.Tools)
$conflictingModules = @('AWSPowerShell', 'AWSPowerShell.NetCore')
foreach ($conflictMod in $conflictingModules) {
    if (Get-Module -Name $conflictMod) {
        Write-Host "  Removing conflicting module: $conflictMod" -ForegroundColor Yellow
        Remove-Module $conflictMod -Force -ErrorAction SilentlyContinue
    }
}

# Remove any already-loaded AWS.Tools modules to avoid version conflicts
$loadedAWSTools = Get-Module -Name 'AWS.Tools.*'
if ($loadedAWSTools) {
    Write-Host "  Clearing already-loaded AWS.Tools modules..." -ForegroundColor Gray
    $loadedAWSTools | Remove-Module -Force -ErrorAction SilentlyContinue
}

# Check required AWS.Tools modules
$requiredModules = @('AWS.Tools.Common', 'AWS.Tools.SecurityToken', 'AWS.Tools.EC2', 'AWS.Tools.ServiceQuotas', 'AWS.Tools.IdentityManagement', 'AWS.Tools.Organizations', 'AWS.Tools.S3')

Write-Host "Loading AWS.Tools modules..." -ForegroundColor Cyan

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "  Installing $mod..." -ForegroundColor Yellow
        try {
            Install-Module -Name $mod -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        } catch {
            Write-Host "Error installing $mod. Please install AWS.Tools modules: Install-Module -Name AWS.Tools.Installer; Install-AWSToolsModule EC2,S3,SecurityToken,ServiceQuotas,IdentityManagement,Organizations" -ForegroundColor Red
            throw
        }
    }
    
    try {
        Import-Module $mod -Force -ErrorAction Stop
        Write-Host "  ✓ $mod" -ForegroundColor Green
    } catch {
        Write-Host "Error loading $mod : $_" -ForegroundColor Red
        Write-Host "Solution: Close all PowerShell windows, reopen, and run: Remove-Module AWS* -Force" -ForegroundColor Yellow
        throw
    }
}

# Determine region FIRST (needed for credential validation)
$userProvidedRegion = $PSBoundParameters.ContainsKey('region')

if (-not $region) {
    $region = Get-DefaultAWSRegion | Select-Object -ExpandProperty Region
    if (-not $region) {
        # Check environment variable
        $region = $env:AWS_DEFAULT_REGION
        if (-not $region) {
            $region = "us-east-1"
            Write-Host "No region configured, defaulting to: $region" -ForegroundColor Yellow
        }
    }
}

Set-DefaultAWSRegion -Region $region
if ($userProvidedRegion) {
    Write-Host "Using region: $region (user specified)" -ForegroundColor Cyan
} else {
    Write-Host "Using default region for credentials: $region" -ForegroundColor Cyan
    Write-Host "Will scan all $(if($global){'global'}else{'US'}) regions for resources (use -region to limit)" -ForegroundColor Gray
}

# Check and/or validate account / profile

Write-Host "Validating AWS account context..." -ForegroundColor Cyan

try {
    $callerIdentity = Get-STSCallerIdentity
    $currentAccount = $callerIdentity.Account
} catch {
    Write-Host "Error: Unable to get AWS caller identity. Ensure AWS credentials are configured." -ForegroundColor Red
    Write-Host "Current credentials:" -ForegroundColor Yellow
    Write-Host "  AWS_ACCESS_KEY_ID: $($env:AWS_ACCESS_KEY_ID.Substring(0, [Math]::Min(10, $env:AWS_ACCESS_KEY_ID.Length)))..." -ForegroundColor Gray
    Write-Host "  AWS_SECRET_ACCESS_KEY: $(if($env:AWS_SECRET_ACCESS_KEY){'[SET]'}else{'[NOT SET]'})" -ForegroundColor Gray
    Write-Host "  AWS_SESSION_TOKEN: $(if($env:AWS_SESSION_TOKEN){'[SET]'}else{'[NOT SET]'})" -ForegroundColor Gray
    throw
}

if ($account -and $currentAccount -ne $account) {
    Write-Host "Warning: Current AWS account ($currentAccount) does not match specified account ($account)." -ForegroundColor Yellow
    Write-Host "To target a different account, set your AWS credential profile." -ForegroundColor Yellow

    # List available profiles as an option
    $profileList = Get-AWSCredential -ListProfileDetail
    if ($profileList) {
        $selectedProfile = Build-MenuFromArray -array $profileList -property 'ProfileName' -message 'Select AWS Profile'
        Set-AWSCredential -ProfileName $selectedProfile
        $callerIdentity = Get-STSCallerIdentity
        $currentAccount = $callerIdentity.Account
    }
}

if (-not $account) {
    $account = $currentAccount
}

Write-Host "Using account: $currentAccount (ARN: $($callerIdentity.Arn))" -ForegroundColor Green

# Build Project Object

$Cluster = New-Object PSObject
$Cluster | Add-Member -MemberType NoteProperty -Name 'Account Id' -Value $currentAccount
$Cluster | Add-Member -MemberType NoteProperty -Name 'Account ARN' -Value $callerIdentity.Arn
$Cluster | Add-Member -MemberType NoteProperty -Name 'User Id' -Value $callerIdentity.UserId

# Get account alias if available
try {
    $aliases = Get-IAMAccountAlias
    if ($aliases -and $aliases.Count -gt 0) {
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Account Alias' -Value ($aliases -join ', ')
    }
} catch {
    Write-Host "Warning: Could not retrieve account aliases." -ForegroundColor Yellow
}

# Check service quotas / limits per region
$quotaServiceCodes = @(
    @{ ServiceCode = "ec2"; QuotaCodes = @(
        @{ Code = "L-1216C47A"; Name = "Running On-Demand Standard instances" }
        @{ Code = "L-43DA4232"; Name = "Running On-Demand High Memory instances" }
        @{ Code = "L-34B43A08"; Name = "Number of EIPs - VPC EIPs" }
    )}
    @{ ServiceCode = "vpc"; QuotaCodes = @(
        @{ Code = "L-F678F1CE"; Name = "VPCs per Region" }
        @{ Code = "L-A4707A72"; Name = "Internet gateways per Region" }
        @{ Code = "L-DF5E4CA3"; Name = "Network interfaces per Region" }
    )}
    @{ ServiceCode = "ebs"; QuotaCodes = @(
        @{ Code = "L-D18FCD1D"; Name = "General Purpose SSD (gp2) volume storage" }
        @{ Code = "L-7A658000"; Name = "General Purpose SSD (gp3) volume storage" }
        @{ Code = "L-DE3D0C80"; Name = "Provisioned IOPS SSD (io1) volume storage" }
    )}
)

Write-Host "Retrieving service quotas..." -ForegroundColor Cyan

if (!$global) {
    $allRegions = @(Get-EC2Region -Filter @(@{Name='opt-in-status'; Values=@('opt-in-not-required','opted-in')}) | Where-Object { $_.RegionName -match '^us-' })
} else {
    $allRegions = @(Get-EC2Region -Filter @(@{Name='opt-in-status'; Values=@('opt-in-not-required','opted-in')}))
}

# Only filter to specific region if user explicitly provided it
if ($userProvidedRegion) {
    $allRegions = $allRegions | Where-Object { $_.RegionName -eq $region }
}

Write-Host "Processing $($allRegions.Count) region(s) for quota information..." -ForegroundColor Cyan
$regionQuotas = @()

foreach ($r in $allRegions) {
    Write-Host "  Checking quotas for region: $($r.RegionName)" -ForegroundColor Gray
    $regionQuotaObject = New-Object PSObject
    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Region" -Value $r.RegionName

    # Get AZs for this region
    try {
        $azInfo = Get-EC2AvailabilityZone -Region $r.RegionName
        $azNames = @($azInfo | Where-Object { $_.State -eq 'available' } | ForEach-Object { $_.ZoneName }) | Sort-Object
        $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Availability Zones" -Value $azNames
    } catch {
        $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Availability Zones" -Value @()
    }

    $regionQuotaDetails = @()
    foreach ($svc in $quotaServiceCodes) {
        foreach ($q in $svc.QuotaCodes) {
            try {
                $quotaResult = Get-SQServiceQuota -ServiceCode $svc.ServiceCode -QuotaCode $q.Code -Region $r.RegionName
                $quotaDetail = New-Object PSObject
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Name" -Value $q.Name
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Service" -Value $svc.ServiceCode
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Limit" -Value $quotaResult.Value
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Adjustable" -Value $quotaResult.Adjustable
                $regionQuotaDetails += $quotaDetail
            } catch {
                # Try default quota
                try {
                    $quotaResult = Get-SQAWSDefaultServiceQuota -ServiceCode $svc.ServiceCode -QuotaCode $q.Code -Region $r.RegionName
                    $quotaDetail = New-Object PSObject
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Name" -Value $q.Name
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Service" -Value $svc.ServiceCode
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Limit" -Value $quotaResult.Value
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Adjustable" -Value $quotaResult.Adjustable
                    $regionQuotaDetails += $quotaDetail
                } catch {
                    # Skip if quota not available
                }
            }
        }
    }
    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Quotas" -Value $regionQuotaDetails
    $regionQuotas += $regionQuotaObject
    Write-Host "    Completed quota check for $($r.RegionName)" -ForegroundColor Green
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Region Quotas' -Value $regionQuotas

# Loop over VPCs and grab details, subnets, security groups, route tables, NACLs, etc.

Write-Host "Retrieving VPC information..." -ForegroundColor Cyan

# Determine which regions to process for VPCs
if ($vpc -or $userProvidedRegion) {
    # If specific VPC or specific region is requested, only check that region
    $vpcRegions = @($allRegions | Where-Object { $_.RegionName -eq $region } | Select-Object -First 1)
    if ($vpcRegions.Count -eq 0) {
        # Region might not be in the filtered list, get it directly
        $vpcRegions = @(Get-EC2Region | Where-Object { $_.RegionName -eq $region } | Select-Object -First 1)
    }
} else {
    # Otherwise use the same regions as quotas (all US or global regions)
    $vpcRegions = $allRegions
}

Write-Host "Processing VPCs in $($vpcRegions.Count) region(s)..." -ForegroundColor Cyan
$clusterVPCs = @()

foreach ($vpcRegion in $vpcRegions) {
    try {
        Write-Host "  Retrieving VPCs in region: $($vpcRegion.RegionName)" -ForegroundColor Gray
        
        if ($vpc) {
            $allVPCs = @(Get-EC2Vpc -VpcId $vpc -Region $vpcRegion.RegionName -ErrorAction SilentlyContinue)
        } else {
            $allVPCs = @(Get-EC2Vpc -Region $vpcRegion.RegionName -ErrorAction SilentlyContinue)
        }
        
        if ($allVPCs.Count -eq 0) {
            Write-Host "    No VPCs found in $($vpcRegion.RegionName)" -ForegroundColor Gray
            continue
        }

        $allSecurityGroups = @(Get-EC2SecurityGroup -Region $vpcRegion.RegionName)
        $allRouteTables = @(Get-EC2RouteTable -Region $vpcRegion.RegionName)
        $allNACLs = @(Get-EC2NetworkAcl -Region $vpcRegion.RegionName)

        Write-Host "    Processing $($allVPCs.Count) VPC(s) in $($vpcRegion.RegionName)..." -ForegroundColor Cyan
    } catch {
        Write-Host "    Error retrieving VPCs in $($vpcRegion.RegionName): $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    foreach ($v in $allVPCs) {
        try {
            $vpcName = ($v.Tags | Where-Object { $_.Key -eq 'Name' }).Value
            if (-not $vpcName) { $vpcName = $v.VpcId }
            Write-Host "      Processing VPC: $vpcName ($($v.VpcId))" -ForegroundColor Gray

            $clusterVPCObject = New-Object PSObject
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $vpcName
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "VPC Id" -Value $v.VpcId
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Region" -Value $vpcRegion.RegionName
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "CIDR Block" -Value $v.CidrBlock
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Is Default" -Value $v.IsDefault
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "State" -Value $v.State

        if ($v.CidrBlockAssociationSet.Count -gt 1) {
            $additionalCidrs = @($v.CidrBlockAssociationSet | Where-Object { $_.CidrBlock -ne $v.CidrBlock } | ForEach-Object { $_.CidrBlock })
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Additional CIDR Blocks" -Value $additionalCidrs
        }

        # Get subnets for this VPC
        $subNetInfo = @()
        try {
            $subnets = @(Get-EC2Subnet -Filter @(@{Name='vpc-id'; Values=@($v.VpcId)}) -Region $vpcRegion.RegionName)
        } catch {
            $subnets = @()
        }

        foreach ($s in $subnets) {
            $subnetName = ($s.Tags | Where-Object { $_.Key -eq 'Name' }).Value
            if (-not $subnetName) { $subnetName = $s.SubnetId }

            $subnetObject = New-Object PSObject
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $subnetName
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Subnet Id" -Value $s.SubnetId
            $subnetObject | Add-Member -MemberType NoteProperty -Name "CIDR Block" -Value $s.CidrBlock
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Availability Zone" -Value $s.AvailabilityZone
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Map Public IP On Launch" -Value $s.MapPublicIpOnLaunch
            $subnetObject | Add-Member -MemberType NoteProperty -Name "Available IP Count" -Value $s.AvailableIpAddressCount

            # NACLs for this subnet
            $subnetNACL = $allNACLs | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.SubnetId -eq $s.SubnetId }) }
            if ($subnetNACL) {
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Network ACL" -Value $subnetNACL.NetworkAclId
                $naclEntries = @()
                foreach ($entry in $subnetNACL.Entries) {
                    $naclEntry = New-Object PSObject
                    $naclEntry | Add-Member -MemberType NoteProperty -Name "Rule Number" -Value $entry.RuleNumber
                    $naclEntry | Add-Member -MemberType NoteProperty -Name "Protocol" -Value $entry.Protocol
                    $naclEntry | Add-Member -MemberType NoteProperty -Name "Rule Action" -Value $entry.RuleAction
                    $naclEntry | Add-Member -MemberType NoteProperty -Name "Egress" -Value $entry.Egress
                    $naclEntry | Add-Member -MemberType NoteProperty -Name "CIDR Block" -Value $entry.CidrBlock
                    $naclEntries += $naclEntry
                }
                $subnetObject | Add-Member -MemberType NoteProperty -Name "NACL Entries" -Value $naclEntries
            } else {
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Network ACL" -Value $null
                $subnetObject | Add-Member -MemberType NoteProperty -Name "NACL Entries" -Value $null
            }

            # Route table for this subnet
            $subnetRT = $allRouteTables | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.SubnetId -eq $s.SubnetId }) }
            if (-not $subnetRT) {
                # Use main route table
                $subnetRT = $allRouteTables | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.Main -eq $true }) }
            }
            if ($subnetRT) {
                $rtName = ($subnetRT.Tags | Where-Object { $_.Key -eq 'Name' }).Value
                if (-not $rtName) { $rtName = $subnetRT.RouteTableId }
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $rtName
                $routes = @()
                foreach ($route in $subnetRT.Routes) {
                    $routeObject = New-Object PSObject
                    $destination = if ($route.DestinationCidrBlock) { $route.DestinationCidrBlock } elseif ($route.DestinationIpv6CidrBlock) { $route.DestinationIpv6CidrBlock } elseif ($route.DestinationPrefixListId) { $route.DestinationPrefixListId } else { $null }
                    $target = if ($route.GatewayId) { $route.GatewayId } elseif ($route.NatGatewayId) { $route.NatGatewayId } elseif ($route.NetworkInterfaceId) { $route.NetworkInterfaceId } elseif ($route.TransitGatewayId) { $route.TransitGatewayId } elseif ($route.VpcPeeringConnectionId) { $route.VpcPeeringConnectionId } else { "local" }
                    $routeObject | Add-Member -MemberType NoteProperty -Name "Destination" -Value $destination
                    $routeObject | Add-Member -MemberType NoteProperty -Name "Target" -Value $target
                    $routeObject | Add-Member -MemberType NoteProperty -Name "State" -Value $route.State
                    $routes += $routeObject
                }
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Routes" -Value $routes
            } else {
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $null
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Routes" -Value $null
            }

            $subNetInfo += $subnetObject
        }

        $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Subnets" -Value $subNetInfo

        # Security Groups for this VPC
        $sgInfo = @()
        $vpcSGs = $allSecurityGroups | Where-Object { $_.VpcId -eq $v.VpcId }
        foreach ($sg in $vpcSGs) {
            $sgObject = New-Object PSObject
            $sgObject | Add-Member -MemberType NoteProperty -Name "Name" -Value $sg.GroupName
            $sgObject | Add-Member -MemberType NoteProperty -Name "Group Id" -Value $sg.GroupId
            $sgObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $sg.Description

            $ingressRules = @()
            foreach ($rule in $sg.IpPermissions) {
                $ruleObject = New-Object PSObject
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Protocol" -Value $rule.IpProtocol
                $ruleObject | Add-Member -MemberType NoteProperty -Name "From Port" -Value $rule.FromPort
                $ruleObject | Add-Member -MemberType NoteProperty -Name "To Port" -Value $rule.ToPort
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Source CIDRs" -Value ($rule.Ipv4Ranges | ForEach-Object { $_.CidrIp })
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Source Security Groups" -Value ($rule.UserIdGroupPairs | ForEach-Object { $_.GroupId })
                $ingressRules += $ruleObject
            }
            $sgObject | Add-Member -MemberType NoteProperty -Name "Ingress Rules" -Value $ingressRules

            $egressRules = @()
            foreach ($rule in $sg.IpPermissionsEgress) {
                $ruleObject = New-Object PSObject
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Protocol" -Value $rule.IpProtocol
                $ruleObject | Add-Member -MemberType NoteProperty -Name "From Port" -Value $rule.FromPort
                $ruleObject | Add-Member -MemberType NoteProperty -Name "To Port" -Value $rule.ToPort
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Destination CIDRs" -Value ($rule.Ipv4Ranges | ForEach-Object { $_.CidrIp })
                $ruleObject | Add-Member -MemberType NoteProperty -Name "Destination Security Groups" -Value ($rule.UserIdGroupPairs | ForEach-Object { $_.GroupId })
                $egressRules += $ruleObject
            }
            $sgObject | Add-Member -MemberType NoteProperty -Name "Egress Rules" -Value $egressRules

            $sgInfo += $sgObject
        }
        $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Security Groups" -Value $sgInfo

            $clusterVPCs += $clusterVPCObject
            Write-Host "        Completed processing VPC: $vpcName" -ForegroundColor Green
        } catch {
            Write-Host "        Error processing VPC $($v.VpcId): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "    Completed region: $($vpcRegion.RegionName)" -ForegroundColor Green
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'VPC Networks' -Value $clusterVPCs

# IAM Policies (Customer Managed)

Write-Host "Retrieving IAM Policies..." -ForegroundColor Cyan
try {
    $iamPolicyInfo = @()
    
    # Get customer-managed policies only (not AWS managed)
    $iamPolicies = Get-IAMPolicyList -Scope Local
    
    Write-Host "Processing $($iamPolicies.Count) IAM policy/policies..." -ForegroundColor Cyan
    foreach ($iamPolicy in $iamPolicies) {
        try {
            Write-Host "  Processing IAM Policy: $($iamPolicy.PolicyName)" -ForegroundColor Gray
            $iamPolicyObject = New-Object PSObject
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Name" -Value $iamPolicy.PolicyName
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Arn" -Value $iamPolicy.Arn
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Id" -Value $iamPolicy.PolicyId
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $iamPolicy.Description
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Attachment Count" -Value $iamPolicy.AttachmentCount
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Create Date" -Value $iamPolicy.CreateDate
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Update Date" -Value $iamPolicy.UpdateDate
            
            # Get policy document/content
            try {
                $defaultVersion = Get-IAMPolicyVersion -PolicyArn $iamPolicy.Arn -VersionId $iamPolicy.DefaultVersionId
                if ($defaultVersion -and $defaultVersion.Document) {
                    # Decode URL-encoded policy document
                    $decodedDoc = [System.Uri]::UnescapeDataString($defaultVersion.Document)
                    $policyDocument = $decodedDoc | ConvertFrom-Json
                    $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Document" -Value $policyDocument
                }
            } catch {
                Write-Host "    Warning: Could not retrieve policy document for $($iamPolicy.PolicyName)" -ForegroundColor Yellow
            }
            
            # Get entities attached to this policy
            try {
                $attachedEntities = Get-IAMEntitiesForPolicy -PolicyArn $iamPolicy.Arn
                $entityInfo = @{
                    Users = @($attachedEntities.PolicyUsers | ForEach-Object { $_.UserName })
                    Groups = @($attachedEntities.PolicyGroups | ForEach-Object { $_.GroupName })
                    Roles = @($attachedEntities.PolicyRoles | ForEach-Object { $_.RoleName })
                }
                $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Attached To" -Value $entityInfo
            } catch {
                Write-Host "    Warning: Could not retrieve attached entities for $($iamPolicy.PolicyName)" -ForegroundColor Yellow
            }
            
            $iamPolicyInfo += $iamPolicyObject
        } catch {
            Write-Host "    Error processing IAM policy $($iamPolicy.PolicyName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "Warning: Could not retrieve IAM policies: $($_.Exception.Message)" -ForegroundColor Yellow
    $iamPolicyInfo = @()
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'IAM Policies' -Value $iamPolicyInfo

# Service Control Policies (SCPs) - AWS Organizations Policies

Write-Host "Retrieving Service Control Policies..." -ForegroundColor Cyan
$scpInfo = @()

try {
    # Check if Organizations is available
    try {
        $orgInfo = Get-ORGOrganization -ErrorAction Stop
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Organization Id' -Value $orgInfo.Id
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Organization Master Account' -Value $orgInfo.MasterAccountId
        
        Write-Host "  Organization: $($orgInfo.Id)" -ForegroundColor Green
        Write-Host "  Management Account: $($orgInfo.MasterAccountId)" -ForegroundColor Gray
        Write-Host "  Current Account: $currentAccount" -ForegroundColor Gray
        
        # Check if we're in the management account
        if ($currentAccount -ne $orgInfo.MasterAccountId) {
            Write-Host "  This is a member account. SCPs can only be listed from the management account." -ForegroundColor Yellow
            Write-Host "  To retrieve SCPs, run this script from account: $($orgInfo.MasterAccountId)" -ForegroundColor Yellow
            throw "Member account - skipping SCP collection"
        }
        
    } catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "Member account") {
            # Already logged above
        } elseif ($errorMsg -match "not.*organization" -or $errorMsg -match "AWSOrganizationsNotInUseException") {
            Write-Host "  This account is not part of an AWS Organization. Skipping SCPs." -ForegroundColor Yellow
        } elseif ($errorMsg -match "permissions" -or $errorMsg -match "AccessDenied") {
            Write-Host "  No access to AWS Organizations" -ForegroundColor Yellow
        } else {
            Write-Host "  Cannot access AWS Organizations: $errorMsg" -ForegroundColor Yellow
        }
        throw  # Re-throw to skip the rest
    }

    # List policies (only reached if we're in management account)
    $policies = Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY

    Write-Host "Processing $($policies.Count) SCP(s)..." -ForegroundColor Cyan
    foreach ($p in $policies) {
        try {
            Write-Host "  Processing SCP: $($p.Name)" -ForegroundColor Gray
            $policyObject = New-Object PSObject
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Name" -Value $p.Name
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Id" -Value $p.Id
            $policyObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $p.Description
            $policyObject | Add-Member -MemberType NoteProperty -Name "Type" -Value $p.Type
            $policyObject | Add-Member -MemberType NoteProperty -Name "AWS Managed" -Value $p.AwsManaged

            # Get policy content
            try {
                $policyDetail = Get-ORGPolicy -PolicyId $p.Id
                $policyContent = $policyDetail.Content | ConvertFrom-Json
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Content" -Value $policyContent
            } catch {
                Write-Host "    Warning: Could not retrieve policy content for $($p.Name)" -ForegroundColor Yellow
            }

            # Get targets for this policy
            try {
                $targets = Get-ORGTargetForPolicy -PolicyId $p.Id
                $policyObject | Add-Member -MemberType NoteProperty -Name "Targets" -Value $targets
            } catch {
                Write-Host "    Warning: Could not retrieve targets for $($p.Name)" -ForegroundColor Yellow
            }

            $scpInfo += $policyObject
        } catch {
            Write-Host "    Error processing SCP $($p.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} catch {
    # Exceptions are already handled and logged in inner try-catch
}

# Always add the Service Control Policies member (will be empty array if not accessible)
$Cluster | Add-Member -MemberType NoteProperty -Name 'Service Control Policies' -Value $scpInfo

Write-Host "Generating JSON output file..." -ForegroundColor Cyan
try {
    $filedate = (Get-Date -Format "yyyyMMdd-HHmmss").ToString()
    $accountLabel = if ($Cluster.'Account Alias') { $Cluster.'Account Alias' } else { $currentAccount }
    $outputFile = "$accountLabel-$filedate.json"

    $Cluster | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile
    Write-Host "JSON file created: $outputFile" -ForegroundColor Green
} catch {
    Write-Host "Error creating JSON file: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

if ($URI) {
    Write-Host "Uploading file to S3..." -ForegroundColor Cyan
    try {
        if ($URI -match '^s3://') {
            # s3:// URI format - parse bucket and prefix
            $s3Path = $URI -replace '^s3://', ''
            $bucketName = $s3Path.Split('/')[0]
            $keyPrefix = ($s3Path.Split('/', 2) | Select-Object -Last 1).TrimEnd('/')
            $s3Key = if ($keyPrefix -and $keyPrefix -ne $bucketName) { "$keyPrefix/$outputFile" } else { $outputFile }

            Write-S3Object -BucketName $bucketName -Key $s3Key -File $outputFile
            Write-Host "File uploaded successfully to s3://$bucketName/$s3Key" -ForegroundColor Green
        } else {
            # Pre-signed URL - use Invoke-WebRequest to upload
            $filePath = (Get-Item -Path $outputFile).FullName
            $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
            Invoke-WebRequest -Uri $URI -Method PUT -ContentType 'application/json' -Body $fileBytes -UseBasicParsing | Out-Null
            Write-Host "File uploaded successfully via pre-signed URL." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error uploading file to S3: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Local file available at: $outputFile" -ForegroundColor Yellow
    }
}
