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
    for ($i = 1; $i -le $menuarray.count; $i++) {
        Write-Host "$i. $($menuarray[$i-1].$property)"
        $menu.Add($i, ($menuarray[$i-1].$property))
    }
    Write-Host '------'
    [int]$mntselect = Read-Host $message
    $menu.Item($mntselect)
    Write-Host `n`n
}

# Remove any conflicting AWS modules that may be loaded
Write-Host "Checking for module conflicts..." -ForegroundColor Cyan

$conflictingModules = @('AWSPowerShell', 'AWSPowerShell.NetCore')
foreach ($conflictMod in $conflictingModules) {
    if (Get-Module -Name $conflictMod) {
        Write-Host "  Removing conflicting module: $conflictMod" -ForegroundColor Yellow
        Remove-Module $conflictMod -Force -ErrorAction SilentlyContinue
    }
}

$loadedAWSTools = Get-Module -Name 'AWS.Tools.*'
if ($loadedAWSTools) {
    Write-Host "  Clearing already-loaded AWS.Tools modules..." -ForegroundColor Gray
    $loadedAWSTools | Remove-Module -Force -ErrorAction SilentlyContinue
}

# Check required AWS.Tools modules
# AWS.Tools.CloudWatch is required to fetch current quota utilization via CloudWatch Usage metrics
$requiredModules = @(
    'AWS.Tools.Common',
    'AWS.Tools.SecurityToken',
    'AWS.Tools.EC2',
    'AWS.Tools.ServiceQuotas',
    'AWS.Tools.CloudWatch',
    'AWS.Tools.IdentityManagement',
    'AWS.Tools.Organizations',
    'AWS.Tools.S3'
)

Write-Host "Loading AWS.Tools modules..." -ForegroundColor Cyan

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Host "  Installing $mod..." -ForegroundColor Yellow
        try {
            Install-Module -Name $mod -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        } catch {
            Write-Host "Error installing $mod. Please install manually:" -ForegroundColor Red
            Write-Host "  Install-Module -Name AWS.Tools.Installer; Install-AWSToolsModule EC2,S3,SecurityToken,ServiceQuotas,CloudWatch,IdentityManagement,Organizations" -ForegroundColor Yellow
            throw
        }
    }
    try {
        Import-Module $mod -Force -ErrorAction Stop
        Write-Host "  v $mod" -ForegroundColor Green
    } catch {
        Write-Host "Error loading ${mod}: $_" -ForegroundColor Red
        Write-Host "Solution: Close all PowerShell windows, reopen, and run: Remove-Module AWS* -Force" -ForegroundColor Yellow
        throw
    }
}

# Determine region FIRST (needed for credential validation)
$userProvidedRegion = $PSBoundParameters.ContainsKey('region')

if (-not $region) {
    $region = Get-DefaultAWSRegion | Select-Object -ExpandProperty Region
    if (-not $region) {
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

# Validate account / profile
Write-Host "Validating AWS account context..." -ForegroundColor Cyan

try {
    $callerIdentity = Get-STSCallerIdentity
    $currentAccount = $callerIdentity.Account
} catch {
    Write-Host "Error: Unable to get AWS caller identity. Ensure AWS credentials are configured." -ForegroundColor Red
    Write-Host "  AWS_ACCESS_KEY_ID:     $($env:AWS_ACCESS_KEY_ID.Substring(0, [Math]::Min(10, $env:AWS_ACCESS_KEY_ID.Length)))..." -ForegroundColor Gray
    Write-Host "  AWS_SECRET_ACCESS_KEY: $(if($env:AWS_SECRET_ACCESS_KEY){'[SET]'}else{'[NOT SET]'})" -ForegroundColor Gray
    Write-Host "  AWS_SESSION_TOKEN:     $(if($env:AWS_SESSION_TOKEN){'[SET]'}else{'[NOT SET]'})" -ForegroundColor Gray
    throw
}

if ($account -and $currentAccount -ne $account) {
    Write-Host "Warning: Current AWS account ($currentAccount) does not match specified account ($account)." -ForegroundColor Yellow
    Write-Host "To target a different account, set your AWS credential profile." -ForegroundColor Yellow
    $profileList = Get-AWSCredential -ListProfileDetail
    if ($profileList) {
        $selectedProfile = Build-MenuFromArray -array $profileList -property 'ProfileName' -message 'Select AWS Profile'
        Set-AWSCredential -ProfileName $selectedProfile
        $callerIdentity = Get-STSCallerIdentity
        $currentAccount = $callerIdentity.Account
    }
}

if (-not $account) { $account = $currentAccount }

Write-Host "Using account: $currentAccount (ARN: $($callerIdentity.Arn))" -ForegroundColor Green

# Build Project Object
$Cluster = New-Object PSObject
$Cluster | Add-Member -MemberType NoteProperty -Name 'Account Id'  -Value $currentAccount
$Cluster | Add-Member -MemberType NoteProperty -Name 'Account ARN' -Value $callerIdentity.Arn
$Cluster | Add-Member -MemberType NoteProperty -Name 'User Id'     -Value $callerIdentity.UserId

try {
    $aliases = Get-IAMAccountAlias
    if ($aliases -and $aliases.Count -gt 0) {
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Account Alias' -Value ($aliases -join ', ')
    }
} catch {
    Write-Host "Warning: Could not retrieve account aliases." -ForegroundColor Yellow
}

# grab quotas
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

if ($userProvidedRegion) {
    $allRegions = $allRegions | Where-Object { $_.RegionName -eq $region }
}

Write-Host "Processing $($allRegions.Count) region(s) for quota information..." -ForegroundColor Cyan
$regionQuotas = @()

foreach ($r in $allRegions) {
    Write-Host "  Checking quotas for region: $($r.RegionName)" -ForegroundColor Gray

    $regionQuotaObject = New-Object PSObject
    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Region" -Value $r.RegionName

    try {
        $azInfo  = Get-EC2AvailabilityZone -Region $r.RegionName
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

                # Fetch current utilization via CloudWatch if the quota exposes a UsageMetric.
                # AWS populates UsageMetric on vCPU-class and other actively-monitored quotas.
                $currentUsage = 0
                if ($quotaResult.UsageMetric -and $quotaResult.UsageMetric.MetricName) {
                    try {
                        $cwDims = @()
                        foreach ($kv in $quotaResult.UsageMetric.MetricDimensions.GetEnumerator()) {
                            $cwDims += @{ Name = $kv.Key; Value = $kv.Value }
                        }
                        $statName = if ($quotaResult.UsageMetric.MetricStatisticRecommendation) {
                            $quotaResult.UsageMetric.MetricStatisticRecommendation
                        } else { 'Maximum' }

                        $cwResult = Get-CWMetricStatistic `
                            -Namespace  $quotaResult.UsageMetric.MetricNamespace `
                            -MetricName $quotaResult.UsageMetric.MetricName `
                            -Dimensions $cwDims `
                            -StartTime  (Get-Date).AddMinutes(-30) `
                            -EndTime    (Get-Date) `
                            -Period     1800 `
                            -Statistic  $statName `
                            -Region     $r.RegionName

                        $latest = $cwResult.Datapoints | Sort-Object Timestamp -Descending | Select-Object -First 1
                        if ($latest) {
                            $currentUsage = [math]::Round($latest.$statName, 0)
                        }
                    } catch {
                        Write-Host "      Warning: CloudWatch usage unavailable for '$($q.Name)': $($_.Exception.Message)" -ForegroundColor DarkGray
                    }
                }

                $quotaDetail = New-Object PSObject
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Name"          -Value $q.Name
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Service"       -Value $svc.ServiceCode
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Limit"         -Value $quotaResult.Value
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Adjustable"    -Value $quotaResult.Adjustable
                $quotaDetail | Add-Member -MemberType NoteProperty -Name "Current Usage" -Value $currentUsage
                $regionQuotaDetails += $quotaDetail

            } catch {
                # Try default (unapplied) quota as fallback
                try {
                    $quotaResult = Get-SQAWSDefaultServiceQuota -ServiceCode $svc.ServiceCode -QuotaCode $q.Code -Region $r.RegionName
                    $quotaDetail = New-Object PSObject
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Name"          -Value $q.Name
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Service"       -Value $svc.ServiceCode
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Limit"         -Value $quotaResult.Value
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Adjustable"    -Value $quotaResult.Adjustable
                    $quotaDetail | Add-Member -MemberType NoteProperty -Name "Current Usage" -Value 0
                    $regionQuotaDetails += $quotaDetail
                } catch {
                    # Quota not available in this region — skip
                }
            }
        }
    }

    $regionQuotaObject | Add-Member -MemberType NoteProperty -Name "Quotas" -Value $regionQuotaDetails
    $regionQuotas += $regionQuotaObject
    Write-Host "    Completed quota check for $($r.RegionName)" -ForegroundColor Green
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Region Quotas' -Value $regionQuotas

# Grab VPCs
Write-Host "Retrieving VPC information..." -ForegroundColor Cyan

if ($vpc -or $userProvidedRegion) {
    $vpcRegions = @($allRegions | Where-Object { $_.RegionName -eq $region } | Select-Object -First 1)
    if ($vpcRegions.Count -eq 0) {
        $vpcRegions = @(Get-EC2Region | Where-Object { $_.RegionName -eq $region } | Select-Object -First 1)
    }
} else {
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
        $allRouteTables    = @(Get-EC2RouteTable    -Region $vpcRegion.RegionName)
        $allNACLs          = @(Get-EC2NetworkAcl    -Region $vpcRegion.RegionName)

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
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Name"       -Value $vpcName
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "VPC Id"     -Value $v.VpcId
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Region"     -Value $vpcRegion.RegionName
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "CIDR Block" -Value $v.CidrBlock
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Is Default" -Value $v.IsDefault
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "State"      -Value $v.State

            if ($v.CidrBlockAssociationSet.Count -gt 1) {
                $additionalCidrs = @($v.CidrBlockAssociationSet | Where-Object { $_.CidrBlock -ne $v.CidrBlock } | ForEach-Object { $_.CidrBlock })
                $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Additional CIDR Blocks" -Value $additionalCidrs
            }

            # Subnets
            $subNetInfo = @()
            try {
                $subnets = @(Get-EC2Subnet -Filter @(@{Name='vpc-id'; Values=@($v.VpcId)}) -Region $vpcRegion.RegionName)
            } catch { $subnets = @() }

            foreach ($s in $subnets) {
                $subnetName = ($s.Tags | Where-Object { $_.Key -eq 'Name' }).Value
                if (-not $subnetName) { $subnetName = $s.SubnetId }

                $subnetObject = New-Object PSObject
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Name"                   -Value $subnetName
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Subnet Id"              -Value $s.SubnetId
                $subnetObject | Add-Member -MemberType NoteProperty -Name "CIDR Block"             -Value $s.CidrBlock
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Availability Zone"      -Value $s.AvailabilityZone
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Map Public IP On Launch" -Value $s.MapPublicIpOnLaunch
                $subnetObject | Add-Member -MemberType NoteProperty -Name "Available IP Count"     -Value $s.AvailableIpAddressCount

                # NACL
                $subnetNACL = $allNACLs | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.SubnetId -eq $s.SubnetId }) }
                if ($subnetNACL) {
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Network ACL" -Value $subnetNACL.NetworkAclId
                    $naclEntries = @()
                    foreach ($entry in $subnetNACL.Entries) {
                        $naclEntry = New-Object PSObject
                        $naclEntry | Add-Member -MemberType NoteProperty -Name "Rule Number" -Value $entry.RuleNumber
                        $naclEntry | Add-Member -MemberType NoteProperty -Name "Protocol"    -Value $entry.Protocol
                        $naclEntry | Add-Member -MemberType NoteProperty -Name "Rule Action" -Value $entry.RuleAction
                        $naclEntry | Add-Member -MemberType NoteProperty -Name "Egress"      -Value $entry.Egress
                        $naclEntry | Add-Member -MemberType NoteProperty -Name "CIDR Block"  -Value $entry.CidrBlock
                        $naclEntries += $naclEntry
                    }
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "NACL Entries" -Value $naclEntries
                } else {
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Network ACL"  -Value $null
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "NACL Entries" -Value $null
                }

                # Route table
                $subnetRT = $allRouteTables | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.SubnetId -eq $s.SubnetId }) }
                if (-not $subnetRT) {
                    $subnetRT = $allRouteTables | Where-Object { $_.VpcId -eq $v.VpcId -and ($_.Associations | Where-Object { $_.Main -eq $true }) }
                }
                if ($subnetRT) {
                    $rtName = ($subnetRT.Tags | Where-Object { $_.Key -eq 'Name' }).Value
                    if (-not $rtName) { $rtName = $subnetRT.RouteTableId }
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $rtName
                    $routes = @()
                    foreach ($route in $subnetRT.Routes) {
                        $routeObject = New-Object PSObject
                        $destination = if     ($route.DestinationCidrBlock)      { $route.DestinationCidrBlock      } `
                                       elseif ($route.DestinationIpv6CidrBlock)  { $route.DestinationIpv6CidrBlock  } `
                                       elseif ($route.DestinationPrefixListId)   { $route.DestinationPrefixListId   } `
                                       else   { $null }
                        $target      = if     ($route.GatewayId)                 { $route.GatewayId                 } `
                                       elseif ($route.NatGatewayId)              { $route.NatGatewayId              } `
                                       elseif ($route.NetworkInterfaceId)        { $route.NetworkInterfaceId        } `
                                       elseif ($route.TransitGatewayId)          { $route.TransitGatewayId          } `
                                       elseif ($route.VpcPeeringConnectionId)    { $route.VpcPeeringConnectionId    } `
                                       else   { "local" }
                        $routeObject | Add-Member -MemberType NoteProperty -Name "Destination" -Value $destination
                        $routeObject | Add-Member -MemberType NoteProperty -Name "Target"      -Value $target
                        $routeObject | Add-Member -MemberType NoteProperty -Name "State"       -Value $route.State
                        $routes += $routeObject
                    }
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Routes" -Value $routes
                } else {
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Route Table" -Value $null
                    $subnetObject | Add-Member -MemberType NoteProperty -Name "Routes"      -Value $null
                }

                $subNetInfo += $subnetObject
            }
            $clusterVPCObject | Add-Member -MemberType NoteProperty -Name "Subnets" -Value $subNetInfo

            # Security Groups
            $sgInfo = @()
            $vpcSGs = $allSecurityGroups | Where-Object { $_.VpcId -eq $v.VpcId }
            foreach ($sg in $vpcSGs) {
                $sgObject = New-Object PSObject
                $sgObject | Add-Member -MemberType NoteProperty -Name "Name"        -Value $sg.GroupName
                $sgObject | Add-Member -MemberType NoteProperty -Name "Group Id"    -Value $sg.GroupId
                $sgObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $sg.Description

                $ingressRules = @()
                foreach ($rule in $sg.IpPermissions) {
                    $ruleObject = New-Object PSObject
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "Protocol"               -Value $rule.IpProtocol
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "From Port"              -Value $rule.FromPort
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "To Port"                -Value $rule.ToPort
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "Source CIDRs"           -Value ($rule.Ipv4Ranges | ForEach-Object { $_.CidrIp })
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "Source Security Groups" -Value ($rule.UserIdGroupPairs | ForEach-Object { $_.GroupId })
                    $ingressRules += $ruleObject
                }
                $sgObject | Add-Member -MemberType NoteProperty -Name "Ingress Rules" -Value $ingressRules

                $egressRules = @()
                foreach ($rule in $sg.IpPermissionsEgress) {
                    $ruleObject = New-Object PSObject
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "Protocol"                    -Value $rule.IpProtocol
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "From Port"                   -Value $rule.FromPort
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "To Port"                     -Value $rule.ToPort
                    $ruleObject | Add-Member -MemberType NoteProperty -Name "Destination CIDRs"           -Value ($rule.Ipv4Ranges | ForEach-Object { $_.CidrIp })
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

# IAM query
Write-Host "Retrieving IAM Policies..." -ForegroundColor Cyan
try {
    $iamPolicyInfo = @()
    $iamPolicies = Get-IAMPolicyList -Scope Local
    Write-Host "Processing $($iamPolicies.Count) IAM policy/policies..." -ForegroundColor Cyan

    foreach ($iamPolicy in $iamPolicies) {
        try {
            Write-Host "  Processing IAM Policy: $($iamPolicy.PolicyName)" -ForegroundColor Gray
            $iamPolicyObject = New-Object PSObject
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Name"      -Value $iamPolicy.PolicyName
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Arn"       -Value $iamPolicy.Arn
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Id"        -Value $iamPolicy.PolicyId
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Description"      -Value $iamPolicy.Description
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Attachment Count" -Value $iamPolicy.AttachmentCount
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Create Date"      -Value $iamPolicy.CreateDate
            $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Update Date"      -Value $iamPolicy.UpdateDate

            try {
                $defaultVersion = Get-IAMPolicyVersion -PolicyArn $iamPolicy.Arn -VersionId $iamPolicy.DefaultVersionId
                if ($defaultVersion -and $defaultVersion.Document) {
                    $decodedDoc    = [System.Uri]::UnescapeDataString($defaultVersion.Document)
                    $policyDocument = $decodedDoc | ConvertFrom-Json
                    $iamPolicyObject | Add-Member -MemberType NoteProperty -Name "Policy Document" -Value $policyDocument
                }
            } catch {
                Write-Host "    Warning: Could not retrieve policy document for $($iamPolicy.PolicyName)" -ForegroundColor Yellow
            }

            try {
                $attachedEntities = Get-IAMEntitiesForPolicy -PolicyArn $iamPolicy.Arn
                $entityInfo = @{
                    Users  = @($attachedEntities.PolicyUsers  | ForEach-Object { $_.UserName  })
                    Groups = @($attachedEntities.PolicyGroups | ForEach-Object { $_.GroupName })
                    Roles  = @($attachedEntities.PolicyRoles  | ForEach-Object { $_.RoleName  })
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

# Service control policies - only available from the management account in an organization, so this may come back empty for many users. if we're in a member account, we'll log that and skip the collection rather than throwing an error.
Write-Host "Retrieving Service Control Policies..." -ForegroundColor Cyan
$scpInfo = @()

try {
    try {
        $orgInfo = Get-ORGOrganization -ErrorAction Stop
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Organization Id'              -Value $orgInfo.Id
        $Cluster | Add-Member -MemberType NoteProperty -Name 'Organization Master Account' -Value $orgInfo.MasterAccountId

        Write-Host "  Organization: $($orgInfo.Id)" -ForegroundColor Green
        Write-Host "  Management Account: $($orgInfo.MasterAccountId)" -ForegroundColor Gray
        Write-Host "  Current Account: $currentAccount" -ForegroundColor Gray

        if ($currentAccount -ne $orgInfo.MasterAccountId) {
            Write-Host "  This is a member account. SCPs can only be listed from the management account." -ForegroundColor Yellow
            Write-Host "  To retrieve SCPs, run this script from account: $($orgInfo.MasterAccountId)" -ForegroundColor Yellow
            throw "Member account - skipping SCP collection"
        }
    } catch {
        $errorMsg = $_.Exception.Message
        if     ($errorMsg -match "Member account")                                                    { <# already logged #> }
        elseif ($errorMsg -match "not.*organization" -or $errorMsg -match "AWSOrganizationsNotInUseException") { Write-Host "  This account is not part of an AWS Organization. Skipping SCPs." -ForegroundColor Yellow }
        elseif ($errorMsg -match "permissions" -or $errorMsg -match "AccessDenied")                  { Write-Host "  No access to AWS Organizations." -ForegroundColor Yellow }
        else                                                                                          { Write-Host "  Cannot access AWS Organizations: $errorMsg" -ForegroundColor Yellow }
        throw
    }

    $policies = Get-ORGPolicyList -Filter SERVICE_CONTROL_POLICY
    Write-Host "Processing $($policies.Count) SCP(s)..." -ForegroundColor Cyan

    foreach ($p in $policies) {
        try {
            Write-Host "  Processing SCP: $($p.Name)" -ForegroundColor Gray
            $policyObject = New-Object PSObject
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Name" -Value $p.Name
            $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Id"   -Value $p.Id
            $policyObject | Add-Member -MemberType NoteProperty -Name "Description" -Value $p.Description
            $policyObject | Add-Member -MemberType NoteProperty -Name "Type"        -Value $p.Type
            $policyObject | Add-Member -MemberType NoteProperty -Name "AWS Managed" -Value $p.AwsManaged

            try {
                $policyDetail  = Get-ORGPolicy -PolicyId $p.Id
                $policyContent = $policyDetail.Content | ConvertFrom-Json
                $policyObject | Add-Member -MemberType NoteProperty -Name "Policy Content" -Value $policyContent
            } catch {
                Write-Host "    Warning: Could not retrieve policy content for $($p.Name)" -ForegroundColor Yellow
            }

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
    # Exceptions handled and logged in inner blocks above
}

$Cluster | Add-Member -MemberType NoteProperty -Name 'Service Control Policies' -Value $scpInfo

# operator iam roles + permissions

Write-Host "Retrieving operator IAM roles and permissions..." -ForegroundColor Cyan

function Get-PolicyStatements {
    param($Document)
    if (-not $Document) { return @() }
    try {
        $doc = $Document
        if ($doc -is [string]) {
            # might be url-encoded (inline) - unescape is a no-op if it isnt
            $doc = [System.Uri]::UnescapeDataString($doc) | ConvertFrom-Json
        }
        return @($doc.Statement)
    } catch {
        return @()
    }
}

# flatten a statement array down to the action / resource buckets the report
# wants. mirrors how azure splits Actions / Not Actions.
function ConvertTo-PermissionBuckets {
    param($Statements)
    $allow = @(); $deny = @(); $notAction = @(); $resources = @()
    foreach ($st in @($Statements)) {
        $actions = @($st.Action)
        $notActions = @($st.NotAction)
        $res = @($st.Resource)
        if ($st.Effect -eq 'Deny') { $deny += $actions } else { $allow += $actions }
        $notAction += $notActions
        $resources += $res
    }
    $b = New-Object PSObject
    $b | Add-Member -MemberType NoteProperty -Name "Allow Actions"   -Value (@($allow      | Where-Object { $_ } | Select-Object -Unique))
    $b | Add-Member -MemberType NoteProperty -Name "Deny Actions"    -Value (@($deny       | Where-Object { $_ } | Select-Object -Unique))
    $b | Add-Member -MemberType NoteProperty -Name "Not Actions"     -Value (@($notAction  | Where-Object { $_ } | Select-Object -Unique))
    $b | Add-Member -MemberType NoteProperty -Name "Resources"       -Value (@($resources  | Where-Object { $_ } | Select-Object -Unique))
    return $b
}

# build one "role" object - in aws a permission set is a policy attached to the
# identity, so each attached/inline policy becomes a row (parallels azure roles).
function New-AwsRoleObject {
    param([string]$RoleName, [string]$Scope, [string]$AssignmentType, [string]$PolicyType, $Statements, [hashtable]$Extra)
    $buckets = ConvertTo-PermissionBuckets -Statements $Statements
    $o = New-Object PSObject
    $o | Add-Member -MemberType NoteProperty -Name "Role Name"       -Value $RoleName
    $o | Add-Member -MemberType NoteProperty -Name "Scope"           -Value $Scope
    $o | Add-Member -MemberType NoteProperty -Name "Assignment Type" -Value $AssignmentType
    $o | Add-Member -MemberType NoteProperty -Name "Policy Type"     -Value $PolicyType
    $o | Add-Member -MemberType NoteProperty -Name "Actions"         -Value $buckets.'Allow Actions'
    $o | Add-Member -MemberType NoteProperty -Name "Deny Actions"    -Value $buckets.'Deny Actions'
    $o | Add-Member -MemberType NoteProperty -Name "Not Actions"     -Value $buckets.'Not Actions'
    $o | Add-Member -MemberType NoteProperty -Name "Resources"       -Value $buckets.Resources
    if ($Extra) { foreach ($k in $Extra.Keys) { $o | Add-Member -MemberType NoteProperty -Name $k -Value $Extra[$k] } }
    return $o
}

# pull statements for a managed policy by arn (uses the default version)
function Get-ManagedPolicyStatements {
    param([string]$Arn, [string]$DefaultVersionId)
    try {
        if (-not $DefaultVersionId) {
            $pol = Get-IAMPolicy -PolicyArn $Arn
            $DefaultVersionId = $pol.DefaultVersionId
        }
        $ver = Get-IAMPolicyVersion -PolicyArn $Arn -VersionId $DefaultVersionId
        return (Get-PolicyStatements -Document $ver.Document)
    } catch {
        return @()
    }
}

$iamRoles = @()
try {
    $callerArn = $callerIdentity.Arn

    # arn tells us the identity type:
    #   arn:aws:iam::<acct>:user/<name>           -> iam user
    #   arn:aws:sts::<acct>:assumed-role/<role>/<session> -> assumed role
    if ($callerArn -match ':user/(.+)$') {
        $userName = ($Matches[1] -split '/')[ -1 ]
        Write-Host "  Caller is IAM user: $userName" -ForegroundColor Gray

        # attached managed policies on the user
        try {
            $attached = Get-IAMAttachedUserPolicyList -UserName $userName
            foreach ($ap in $attached) {
                Write-Host "    Managed policy: $($ap.PolicyName)" -ForegroundColor DarkGray
                $stmts = Get-ManagedPolicyStatements -Arn $ap.PolicyArn
                $iamRoles += New-AwsRoleObject -RoleName $ap.PolicyName -Scope $callerArn -AssignmentType 'User (Attached)' -PolicyType 'Managed' -Statements $stmts -Extra @{ 'Policy Arn' = $ap.PolicyArn }
            }
        } catch { Write-Host "    Warning: could not list attached user policies: $($_.Exception.Message)" -ForegroundColor Yellow }

        # inline policies on the user
        try {
            $inlineNames = Get-IAMUserPolicyList -UserName $userName
            foreach ($pn in $inlineNames) {
                Write-Host "    Inline policy: $pn" -ForegroundColor DarkGray
                $pd = Get-IAMUserPolicy -UserName $userName -PolicyName $pn
                $stmts = Get-PolicyStatements -Document $pd.PolicyDocument
                $iamRoles += New-AwsRoleObject -RoleName $pn -Scope $callerArn -AssignmentType 'User (Inline)' -PolicyType 'Inline' -Statements $stmts
            }
        } catch { Write-Host "    Warning: could not list inline user policies: $($_.Exception.Message)" -ForegroundColor Yellow }

        # group memberships - roles the user gets via a group (parallels azure's -ExpandPrincipalGroups)
        try {
            $groups = Get-IAMGroupForUser -UserName $userName
            foreach ($g in $groups) {
                # attached managed on the group
                try {
                    $gAttached = Get-IAMAttachedGroupPolicyList -GroupName $g.GroupName
                    foreach ($ap in $gAttached) {
                        $stmts = Get-ManagedPolicyStatements -Arn $ap.PolicyArn
                        $iamRoles += New-AwsRoleObject -RoleName $ap.PolicyName -Scope $g.Arn -AssignmentType "Group: $($g.GroupName) (Attached)" -PolicyType 'Managed' -Statements $stmts -Extra @{ 'Policy Arn' = $ap.PolicyArn }
                    }
                } catch {}
                # inline on the group
                try {
                    $gInline = Get-IAMGroupPolicyList -GroupName $g.GroupName
                    foreach ($pn in $gInline) {
                        $pd = Get-IAMGroupPolicy -GroupName $g.GroupName -PolicyName $pn
                        $stmts = Get-PolicyStatements -Document $pd.PolicyDocument
                        $iamRoles += New-AwsRoleObject -RoleName $pn -Scope $g.Arn -AssignmentType "Group: $($g.GroupName) (Inline)" -PolicyType 'Inline' -Statements $stmts
                    }
                } catch {}
            }
        } catch { Write-Host "    Warning: could not list user groups: $($_.Exception.Message)" -ForegroundColor Yellow }

    } elseif ($callerArn -match ':assumed-role/([^/]+)/') {
        # most common case - operator assumed a role
        $roleName = $Matches[1]
        Write-Host "  Caller is assumed-role: $roleName" -ForegroundColor Gray

        # $roleName = ($callerArn -split '/')[1]   # split index was off for the sts arn format

        # attached managed policies on the role
        try {
            $attached = Get-IAMAttachedRolePolicyList -RoleName $roleName
            foreach ($ap in $attached) {
                Write-Host "    Managed policy: $($ap.PolicyName)" -ForegroundColor DarkGray
                $stmts = Get-ManagedPolicyStatements -Arn $ap.PolicyArn
                $iamRoles += New-AwsRoleObject -RoleName $ap.PolicyName -Scope $callerArn -AssignmentType 'Role (Attached)' -PolicyType 'Managed' -Statements $stmts -Extra @{ 'Policy Arn' = $ap.PolicyArn }
            }
        } catch { Write-Host "    Warning: could not list attached role policies: $($_.Exception.Message)" -ForegroundColor Yellow }

        # inline policies on the role
        try {
            $inlineNames = Get-IAMRolePolicyList -RoleName $roleName
            foreach ($pn in $inlineNames) {
                Write-Host "    Inline policy: $pn" -ForegroundColor DarkGray
                $pd = Get-IAMRolePolicy -RoleName $roleName -PolicyName $pn
                $stmts = Get-PolicyStatements -Document $pd.PolicyDocument
                $iamRoles += New-AwsRoleObject -RoleName $pn -Scope $callerArn -AssignmentType 'Role (Inline)' -PolicyType 'Inline' -Statements $stmts
            }
        } catch { Write-Host "    Warning: could not list inline role policies: $($_.Exception.Message)" -ForegroundColor Yellow }

    } else {
        # root or some other principal - nothing granular to enumerate
        Write-Host "  Caller ARN not a user or assumed-role ($callerArn); skipping granular permission enumeration." -ForegroundColor Yellow
    }

    Write-Host "Processed $(@($iamRoles).Count) permission set(s) for the operator." -ForegroundColor Cyan
} catch {
    Write-Host "Error retrieving operator IAM roles: $($_.Exception.Message)" -ForegroundColor Red
    $iamRoles = @()
}

# bundle the same shape azure uses (report UI reads report.IAM.IAMRoles).
# aws has no PIM so that array stays empty, keeps the schema parallel.
$userScopes = New-Object PSObject
$userScopes | Add-Member -MemberType NoteProperty -Name IAMRoles -Value $iamRoles
$userScopes | Add-Member -MemberType NoteProperty -Name PIMRoles -Value @()

$Cluster | Add-Member -MemberType NoteProperty -Name IAM -Value $userScopes

# ---------------------------------------------------------------------------
# Output JSON
# ---------------------------------------------------------------------------
Write-Host "Generating JSON output file..." -ForegroundColor Cyan
try {
    $filedate     = (Get-Date -Format "yyyyMMdd-HHmmss").ToString()
    $accountLabel = if ($Cluster.'Account Alias') { $Cluster.'Account Alias' } else { $currentAccount }
    $outputFile   = "$accountLabel-$filedate.json"

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
