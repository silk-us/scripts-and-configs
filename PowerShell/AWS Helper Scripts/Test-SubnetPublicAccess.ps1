<#
.SYNOPSIS
    Diagnoses whether an AWS subnet can reach the public internet (IGW path).

.DESCRIPTION
    Checks the four things that must be true for an instance in the subnet to talk
    to CloudFormation/S3/DNS via an Internet Gateway:
      1. An IGW is attached to the subnet's VPC.
      2. The subnet's route table has 0.0.0.0/0 -> that IGW.
      3. The subnet has MapPublicIpOnLaunch enabled.
      4. The subnet's NACL allows outbound 443, outbound UDP 53, and inbound ephemeral.
    Each check prints [ OK ] or [FAIL] with a short detail line.

.PARAMETER SubnetId
    The subnet to test (e.g. subnet-0abc123).

.PARAMETER Region
    AWS region the subnet lives in.

.PARAMETER ProfileName
    Optional named AWS credential profile.

.EXAMPLE
    .\Test-SubnetPublicAccess.ps1 -SubnetId subnet-0abc123 -Region us-east-1

.EXAMPLE
    .\Test-SubnetPublicAccess.ps1 -SubnetId subnet-0abc123 -Region us-east-1 -ProfileName silk-dev
#>
param(
    [Parameter(Mandatory)]
    [string]$SubnetId,
    [Parameter(Mandatory)]
    [string]$Region,
    [Parameter()]
    [string]$ProfileName
)

$awsCommon = @{ Region = $Region }
if ($ProfileName) { $awsCommon.ProfileName = $ProfileName }

$subnet = Get-EC2Subnet -SubnetId $SubnetId @awsCommon
if (-not $subnet) { Write-Error "Subnet $SubnetId not found in $Region."; exit 1 }
$vpcId = $subnet.VpcId
Write-Host "Subnet $SubnetId  (VPC $vpcId, CIDR $($subnet.CidrBlock))"

function Show {
    param([string]$Label, [bool]$Ok, [string]$Detail)
    $tag = if ($Ok) { '[ OK ]' } else { '[FAIL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host "$tag $Label" -ForegroundColor $color
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray }
}

# 1. IGW attached to VPC
$igw = Get-EC2InternetGateway @awsCommon -Filter @{Name='attachment.vpc-id'; Values=$vpcId} | Select-Object -First 1
Show -Label "IGW attached to VPC $vpcId" -Ok ([bool]$igw) `
     -Detail $(if ($igw) { $igw.InternetGatewayId } else { 'no IGW attached' })

# 2. Route table for the subnet -> IGW
$rt = Get-EC2RouteTable @awsCommon -Filter @{Name='association.subnet-id'; Values=$SubnetId} | Select-Object -First 1
$rtSource = 'subnet-associated'
if (-not $rt) {
    $rt = Get-EC2RouteTable @awsCommon -Filter @{Name='vpc-id'; Values=$vpcId} |
          Where-Object { $_.Associations.Main -eq $true } | Select-Object -First 1
    $rtSource = 'main (fallback)'
}
$defaultRoute = $rt.Routes | Where-Object { $_.DestinationCidrBlock -eq '0.0.0.0/0' }
$routeOk = $defaultRoute -and $igw -and ($defaultRoute.GatewayId -eq $igw.InternetGatewayId)
Show -Label "Route table $($rt.RouteTableId) ($rtSource): 0.0.0.0/0 -> IGW" -Ok $routeOk `
     -Detail $(if ($defaultRoute) { "current target: $($defaultRoute.GatewayId)$($defaultRoute.NatGatewayId)$($defaultRoute.TransitGatewayId)" } else { 'no default route' })

# 3. Subnet MapPublicIpOnLaunch
Show -Label "Subnet MapPublicIpOnLaunch=true" -Ok ([bool]$subnet.MapPublicIpOnLaunch) `
     -Detail "current value: $($subnet.MapPublicIpOnLaunch). If false, NEW instances boot with no public IP."

# 4. NACL — outbound 443 + outbound DNS + inbound ephemeral (return traffic)
$nacl = Get-EC2NetworkAcl @awsCommon |
        Where-Object { $_.Associations.SubnetId -contains $SubnetId } | Select-Object -First 1

function Test-NaclAllow {
    param($Entries, [bool]$Egress, [string]$Proto, [int]$Port)
    $protoNum = @{ tcp = '6'; udp = '17' }[$Proto]
    return $Entries | Where-Object {
        $_.Egress -eq $Egress -and $_.RuleAction.Value -eq 'allow' -and (
            $_.Protocol -eq '-1' -or
            ($_.Protocol -eq $protoNum -and $_.PortRange.From -le $Port -and $_.PortRange.To -ge $Port)
        )
    } | Sort-Object RuleNumber | Select-Object -First 1
}

$outHttps = Test-NaclAllow -Entries $nacl.Entries -Egress $true  -Proto tcp -Port 443
$outDns   = Test-NaclAllow -Entries $nacl.Entries -Egress $true  -Proto udp -Port 53
$inEph    = Test-NaclAllow -Entries $nacl.Entries -Egress $false -Proto tcp -Port 32768  # mid-ephemeral
$inEphUdp = Test-NaclAllow -Entries $nacl.Entries -Egress $false -Proto udp -Port 32768

Show -Label "NACL $($nacl.NetworkAclId): outbound TCP 443" -Ok ([bool]$outHttps) `
     -Detail $(if ($outHttps) { "rule $($outHttps.RuleNumber)" } else { 'blocked — cfn-signal cannot reach CloudFormation' })

Show -Label "NACL $($nacl.NetworkAclId): outbound UDP 53 (DNS)" -Ok ([bool]$outDns) `
     -Detail $(if ($outDns) { "rule $($outDns.RuleNumber)" } else { 'blocked — DNS resolution will fail' })

Show -Label "NACL $($nacl.NetworkAclId): inbound TCP ephemeral (return traffic)" -Ok ([bool]$inEph) `
     -Detail $(if ($inEph) { "rule $($inEph.RuleNumber)" } else { 'blocked — outbound TCP responses will be dropped' })

Show -Label "NACL $($nacl.NetworkAclId): inbound UDP ephemeral (DNS responses)" -Ok ([bool]$inEphUdp) `
     -Detail $(if ($inEphUdp) { "rule $($inEphUdp.RuleNumber)" } else { 'blocked — DNS responses will be dropped' })

Write-Host "`nSummary: any [FAIL] above will block cfn-signal or other internet-bound traffic."
