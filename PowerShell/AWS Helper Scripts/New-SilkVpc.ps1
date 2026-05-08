[CmdletBinding(DefaultParameterSetName='Create')]
param(
    [Parameter(Mandatory)]
    [string]$Region,
    [Parameter(Mandatory, ParameterSetName='Create')]
    [ipaddress]$IpSpace,
    [Parameter(ParameterSetName='Create')]
    [ValidateSet('small','medium','large')]
    [string]$ClusterSize = 'small',
    [Parameter()]
    [string]$ProfileName,
    [Parameter()]
    [string]$NameTag = 'silk',
    [Parameter(ParameterSetName='Create')]
    [switch]$OpenVPC,
    [Parameter(Mandatory, ParameterSetName='Cleanup')]
    [switch]$Cleanup,
    [Parameter(ParameterSetName='Create')]
    [Parameter(ParameterSetName='Cleanup')]
    [string]$VpcId
)

foreach ($mod in @('AWS.Tools.EC2')) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Error "Required module '$mod' not installed. Run: Install-Module $mod -Force"; exit 1
    }
    Import-Module $mod -ErrorAction Stop
}

$awsCommon = @{ Region = $Region }
if ($ProfileName) { $awsCommon.ProfileName = $ProfileName }

try {
    Get-STSCallerIdentity @awsCommon | Out-Null
} catch {
    Write-Error "AWS auth failed: $_"; exit 1
}

# --- Cleanup mode: tear down everything in the named/identified VPC and exit ---
if ($Cleanup) {
    if (-not $VpcId) {
        $vpcs = Get-EC2Vpc @awsCommon -Filter @{Name='tag:Name'; Values="$NameTag-vpc"}
        if (-not $vpcs)             { Write-Error "No VPC tagged Name=$NameTag-vpc found in $Region. Pass -VpcId."; exit 1 }
        if ($vpcs.Count -gt 1)      { Write-Error "Multiple VPCs tagged Name=$NameTag-vpc found. Pass -VpcId to disambiguate."; exit 1 }
        $VpcId = $vpcs[0].VpcId
    }
    Write-Host "Cleanup VPC $VpcId in $Region" -ForegroundColor Yellow

    # 1. Detach + delete IGW(s)
    foreach ($igw in (Get-EC2InternetGateway @awsCommon -Filter @{Name='attachment.vpc-id'; Values=$VpcId})) {
        Dismount-EC2InternetGateway -InternetGatewayId $igw.InternetGatewayId -VpcId $VpcId @awsCommon | Out-Null
        Remove-EC2InternetGateway   -InternetGatewayId $igw.InternetGatewayId @awsCommon -Force        | Out-Null
        Write-Host "  IGW deleted: $($igw.InternetGatewayId)"
    }

    # 2. Delete subnets (this fails if any ENIs still attached — surface error)
    foreach ($s in (Get-EC2Subnet @awsCommon -Filter @{Name='vpc-id'; Values=$VpcId})) {
        try {
            Remove-EC2Subnet -SubnetId $s.SubnetId @awsCommon -Force | Out-Null
            Write-Host "  Subnet deleted: $($s.SubnetId) ($($s.CidrBlock))"
        } catch { Write-Warning "  Subnet $($s.SubnetId) NOT deleted: $_" }
    }

    # 3. Delete route tables (skip the main)
    foreach ($rt in (Get-EC2RouteTable @awsCommon -Filter @{Name='vpc-id'; Values=$VpcId})) {
        if ($rt.Associations | Where-Object Main) { continue }
        try {
            Remove-EC2RouteTable -RouteTableId $rt.RouteTableId @awsCommon -Force | Out-Null
            Write-Host "  Route table deleted: $($rt.RouteTableId)"
        } catch { Write-Warning "  Route table $($rt.RouteTableId) NOT deleted: $_" }
    }

    # 4. Delete custom NACLs (default NACL can't be deleted; AWS will reuse it)
    foreach ($nacl in (Get-EC2NetworkAcl @awsCommon -Filter @{Name='vpc-id'; Values=$VpcId})) {
        if ($nacl.IsDefault) { continue }
        try {
            Remove-EC2NetworkAcl -NetworkAclId $nacl.NetworkAclId @awsCommon -Force | Out-Null
            Write-Host "  NACL deleted: $($nacl.NetworkAclId)"
        } catch { Write-Warning "  NACL $($nacl.NetworkAclId) NOT deleted: $_" }
    }

    # 5. Delete custom SGs (default SG can't be deleted)
    foreach ($sg in (Get-EC2SecurityGroup @awsCommon -Filter @{Name='vpc-id'; Values=$VpcId})) {
        if ($sg.GroupName -eq 'default') { continue }
        try {
            Remove-EC2SecurityGroup -GroupId $sg.GroupId @awsCommon -Force | Out-Null
            Write-Host "  SG deleted: $($sg.GroupId)"
        } catch { Write-Warning "  SG $($sg.GroupId) NOT deleted: $_" }
    }

    # 6. Delete the VPC itself
    try {
        Remove-EC2Vpc -VpcId $VpcId @awsCommon -Force | Out-Null
        Write-Host "VPC $VpcId deleted." -ForegroundColor Green
    } catch { Write-Error "VPC $VpcId NOT deleted: $_"; exit 1 }
    return
}

# Cluster sizing: VPC prefix, cluster-subnet prefix (flex/mgmt/data1/data2), internal-subnet prefix.
# SubBlock/IntBlock are host counts per subnet, used for offset arithmetic.
$sizing = @{
    small  = @{ VpcPrefix = 24; SubPrefix = 28; IntPrefix = 26; SubBlock = 16;  IntBlock = 64  }
    medium = @{ VpcPrefix = 23; SubPrefix = 27; IntPrefix = 25; SubBlock = 32;  IntBlock = 128 }
    large  = @{ VpcPrefix = 21; SubPrefix = 26; IntPrefix = 24; SubBlock = 64;  IntBlock = 256 }
}
$cfg = $sizing[$ClusterSize]

function ConvertTo-IpInt {
    param([ipaddress]$Ip)
    $b = $Ip.GetAddressBytes()
    [Array]::Reverse($b)
    return [BitConverter]::ToUInt32($b, 0)
}

function ConvertFrom-IpInt {
    param([uint32]$IpInt)
    $b = [BitConverter]::GetBytes($IpInt)
    [Array]::Reverse($b)
    return [ipaddress]::new($b).ToString()
}

function Get-OffsetCidr {
    param(
        [ipaddress]$Base,
        [int]$Offset,
        [int]$Prefix
    )
    $ipInt = ConvertTo-IpInt -Ip $Base
    return "$(ConvertFrom-IpInt -IpInt ($ipInt + $Offset))/$Prefix"
}

$baseIpStr = $IpSpace.ToString()
$vpcCidr   = "$baseIpStr/$($cfg.VpcPrefix)"

# Layout: flex, mgmt, data1, data2 packed first (each SubBlock), then internal1, internal2 (each IntBlock).
$subnets = [ordered]@{
    flex        = Get-OffsetCidr -Base $IpSpace -Offset (0 * $cfg.SubBlock) -Prefix $cfg.SubPrefix
    management  = Get-OffsetCidr -Base $IpSpace -Offset (1 * $cfg.SubBlock) -Prefix $cfg.SubPrefix
    data1       = Get-OffsetCidr -Base $IpSpace -Offset (2 * $cfg.SubBlock) -Prefix $cfg.SubPrefix
    data2       = Get-OffsetCidr -Base $IpSpace -Offset (3 * $cfg.SubBlock) -Prefix $cfg.SubPrefix
    internal1   = Get-OffsetCidr -Base $IpSpace -Offset (1 * $cfg.IntBlock) -Prefix $cfg.IntPrefix
    internal2   = Get-OffsetCidr -Base $IpSpace -Offset (2 * $cfg.IntBlock) -Prefix $cfg.IntPrefix
}

Write-Host "Region:       $Region"
Write-Host "Cluster size: $ClusterSize"
Write-Host "VPC CIDR:     $vpcCidr"
$subnets.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-11} {1}" -f $_.Key, $_.Value) }

# --- VPC: create new, or reuse the one passed via -VpcId ---
if ($VpcId) {
    try {
        $vpc = Get-EC2Vpc -VpcId $VpcId @awsCommon -ErrorAction Stop
    } catch {
        Write-Error "VPC '$VpcId' not found in $Region. $_"; exit 1
    }
    if (-not $vpc) {
        Write-Error "VPC '$VpcId' not found in $Region."; exit 1
    }
    Write-Host "Using existing VPC: $($vpc.VpcId) (primary CIDR $($vpc.CidrBlock))"

    # Expand IP space: associate $vpcCidr as a secondary block if not already present.
    # CidrBlockAssociationSet typically includes the primary too, but we union both to be safe.
    $existingCidrs = @($vpc.CidrBlock)
    if ($vpc.CidrBlockAssociationSet) {
        $existingCidrs += $vpc.CidrBlockAssociationSet | ForEach-Object { $_.CidrBlock }
    }
    $existingCidrs = $existingCidrs | Where-Object { $_ } | Select-Object -Unique
    if ($existingCidrs -contains $vpcCidr) {
        Write-Host "  CIDR $vpcCidr already associated; no expansion needed"
    } else {
        try {
            Register-EC2VpcCidrBlock -VpcId $vpc.VpcId -CidrBlock $vpcCidr @awsCommon | Out-Null
            Write-Host "  CIDR $vpcCidr associated with VPC $($vpc.VpcId)"
        } catch {
            Write-Error "Failed to associate $vpcCidr with VPC $($vpc.VpcId). $_"; exit 1
        }
    }
} else {
    $vpc = New-EC2Vpc -CidrBlock $vpcCidr @awsCommon
    $vpcTag = New-Object Amazon.EC2.Model.Tag
    $vpcTag.Key = 'Name'; $vpcTag.Value = "$NameTag-vpc"
    New-EC2Tag -Resource $vpc.VpcId -Tag $vpcTag @awsCommon | Out-Null
    Write-Host "VPC created: $($vpc.VpcId)"
}

# --- Subnets ---
$az = "${Region}a"
$subnetIds = @{}
foreach ($entry in $subnets.GetEnumerator()) {
    $sn = New-EC2Subnet -VpcId $vpc.VpcId -CidrBlock $entry.Value -AvailabilityZone $az @awsCommon
    $tag = New-Object Amazon.EC2.Model.Tag
    $tag.Key = 'Name'; $tag.Value = "$NameTag-$($entry.Key)"
    New-EC2Tag -Resource $sn.SubnetId -Tag $tag @awsCommon | Out-Null
    $subnetIds[$entry.Key] = $sn.SubnetId
    Write-Host "Subnet $($entry.Key): $($sn.SubnetId) ($($entry.Value))"
}

# --- Internet Gateway + public route table ---
# Required so the flex instance can reach the CloudFormation endpoint for cfn-signal,
# pull the AMI Marketplace token, talk to S3, and so we can attach an EIP later.
$igw = New-EC2InternetGateway @awsCommon
$igwTag = New-Object Amazon.EC2.Model.Tag
$igwTag.Key = 'Name'; $igwTag.Value = "$NameTag-igw"
New-EC2Tag -Resource $igw.InternetGatewayId -Tag $igwTag @awsCommon | Out-Null
Add-EC2InternetGateway -InternetGatewayId $igw.InternetGatewayId -VpcId $vpc.VpcId @awsCommon | Out-Null
Write-Host "IGW: $($igw.InternetGatewayId) attached to $($vpc.VpcId)"

$publicRt = New-EC2RouteTable -VpcId $vpc.VpcId @awsCommon
$rtTag = New-Object Amazon.EC2.Model.Tag
$rtTag.Key = 'Name'; $rtTag.Value = "$NameTag-public-rt"
New-EC2Tag -Resource $publicRt.RouteTableId -Tag $rtTag @awsCommon | Out-Null
New-EC2Route -RouteTableId $publicRt.RouteTableId -DestinationCidrBlock '0.0.0.0/0' -GatewayId $igw.InternetGatewayId @awsCommon | Out-Null
Write-Host "Route table $($publicRt.RouteTableId) : 0.0.0.0/0 -> $($igw.InternetGatewayId)"

# Associate the public route table with subnets that need internet egress.
# Flex needs it for cfn-signal/EIP. Management needs it for the outbound services
# called out in the spec (DNS, NTP, LDAP, SMTP, etc.).
foreach ($name in @('flex','management')) {
    Register-EC2RouteTable -SubnetId $subnetIds[$name] -RouteTableId $publicRt.RouteTableId @awsCommon | Out-Null
    Write-Host "Associated $name subnet with public route table"
}

# Auto-assign a public IP at launch for any instance in the flex subnet.
# This is what lets cfn-signal phone home before you (optionally) replace the auto IP with an EIP.
Edit-EC2SubnetAttribute -SubnetId $subnetIds['flex'] -MapPublicIpOnLaunch $true @awsCommon
Write-Host "Flex subnet : MapPublicIpOnLaunch=true"

# --- NACL helpers ---
function New-AclRule {
    param(
        [string]$AclId,
        [int]$RuleNumber,
        [ValidateSet('tcp','udp','icmp','all')] [string]$Proto,
        [string]$Cidr,
        [int]$FromPort,
        [int]$ToPort,
        [switch]$Egress
    )
    $protoMap = @{ tcp = '6'; udp = '17'; icmp = '1'; all = '-1' }
    $params = @{
        NetworkAclId = $AclId
        RuleNumber   = $RuleNumber
        Protocol     = $protoMap[$Proto]
        RuleAction   = 'allow'
        Egress       = [bool]$Egress
        CidrBlock    = $Cidr
    }
    if ($Proto -eq 'icmp') {
        $params.IcmpTypeCode_Type = -1
        $params.IcmpTypeCode_Code = -1
    } elseif ($Proto -in @('tcp','udp')) {
        $params.PortRange_From = $FromPort
        $params.PortRange_To   = $ToPort
    }
    New-EC2NetworkAclEntry @params @awsCommon | Out-Null
}

function New-NamedAcl {
    param([string]$Name, [string]$SubnetId)
    $acl = New-EC2NetworkAcl -VpcId $vpc.VpcId @awsCommon
    $tag = New-Object Amazon.EC2.Model.Tag
    $tag.Key = 'Name'; $tag.Value = "$NameTag-$Name-acl"
    New-EC2Tag -Resource $acl.NetworkAclId -Tag $tag @awsCommon | Out-Null

    # Replace the default ACL association on the subnet with this new one.
    $existing = (Get-EC2NetworkAcl @awsCommon |
        Where-Object { $_.VpcId -eq $vpc.VpcId } |
        ForEach-Object { $_.Associations } |
        Where-Object { $_.SubnetId -eq $SubnetId } |
        Select-Object -First 1)
    if ($existing) {
        Set-EC2NetworkAclAssociation -AssociationId $existing.NetworkAclAssociationId -NetworkAclId $acl.NetworkAclId @awsCommon | Out-Null
    }
    Write-Host "ACL $Name -> $($acl.NetworkAclId) (subnet $SubnetId)"
    return $acl.NetworkAclId
}

$any = '0.0.0.0/0'
$silkClarity = '34.120.213.129/32'
$flexCidr = $subnets['flex']

# --- Flex ACL ---
# NACLs are stateless: every connection needs an explicit allow rule in BOTH directions.
# Spec-mandated rules sit at 100-129 (per the Silk image). Rules 130+ are operational
# extras the spec doesn't list but the instance can't function without:
#   - outbound 443 to any (cfn-signal, S3 manifest pull, AMI Marketplace token)
#   - outbound UDP 53 (DNS for any of the above)
#   - outbound TCP ephemeral (response traffic to inbound 22/443)
#   - inbound  TCP/UDP ephemeral (response traffic to outbound 443/53)
$aclFlex = New-NamedAcl -Name 'flex' -SubnetId $subnetIds['flex']
# Inbound — spec
New-AclRule -AclId $aclFlex -RuleNumber 100 -Proto tcp  -Cidr $any -FromPort 22  -ToPort 22
New-AclRule -AclId $aclFlex -RuleNumber 110 -Proto tcp  -Cidr $any -FromPort 443 -ToPort 443
New-AclRule -AclId $aclFlex -RuleNumber 120 -Proto icmp -Cidr $any -FromPort 0   -ToPort 0
# Inbound — ephemeral return traffic for outbound calls (CFN, S3, DNS responses)
New-AclRule -AclId $aclFlex -RuleNumber 130 -Proto tcp  -Cidr $any -FromPort 1024 -ToPort 65535
New-AclRule -AclId $aclFlex -RuleNumber 140 -Proto udp  -Cidr $any -FromPort 1024 -ToPort 65535

# Outbound — spec
New-AclRule -AclId $aclFlex -RuleNumber 100 -Proto tcp  -Cidr $silkClarity -FromPort 443 -ToPort 443 -Egress
# Outbound — operational
New-AclRule -AclId $aclFlex -RuleNumber 110 -Proto tcp  -Cidr $any -FromPort 443  -ToPort 443  -Egress
New-AclRule -AclId $aclFlex -RuleNumber 120 -Proto udp  -Cidr $any -FromPort 53   -ToPort 53   -Egress
New-AclRule -AclId $aclFlex -RuleNumber 130 -Proto tcp  -Cidr $any -FromPort 1024 -ToPort 65535 -Egress

# --- External Management ACL ---
$aclMgmt = New-NamedAcl -Name 'management' -SubnetId $subnetIds['management']
$mgmtInTcp  = @(22, 443, 3192, 3260, 514)
$mgmtOutTcp = @(22, 25, 53, 88, 123, 389, 443, 587, 636)
$mgmtOutUdp = @(53, 88, 123, 389, 636)
$rn = 100
foreach ($p in $mgmtInTcp) { New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto tcp -Cidr $any -FromPort $p -ToPort $p; $rn += 10 }
New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto udp  -Cidr $any -FromPort 514 -ToPort 514; $rn += 10
New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto icmp -Cidr $any -FromPort 0 -ToPort 0
$rn = 100
foreach ($p in $mgmtOutTcp) { New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto tcp -Cidr $any -FromPort $p -ToPort $p -Egress; $rn += 10 }
foreach ($p in $mgmtOutUdp) { New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto udp -Cidr $any -FromPort $p -ToPort $p -Egress; $rn += 10 }
New-AclRule -AclId $aclMgmt -RuleNumber $rn -Proto udp -Cidr $any -FromPort 161 -ToPort 162 -Egress

# --- Data 1 / Data 2 ACL (identical rules) ---
$dataAclIds = @{}
foreach ($name in @('data1','data2')) {
    $acl = New-NamedAcl -Name $name -SubnetId $subnetIds[$name]
    $dataAclIds[$name] = $acl
    New-AclRule -AclId $acl -RuleNumber 100 -Proto tcp  -Cidr $any -FromPort 3260  -ToPort 3260
    New-AclRule -AclId $acl -RuleNumber 110 -Proto tcp  -Cidr $any -FromPort 55855 -ToPort 55858
    New-AclRule -AclId $acl -RuleNumber 120 -Proto icmp -Cidr $any -FromPort 0 -ToPort 0
    New-AclRule -AclId $acl -RuleNumber 100 -Proto tcp  -Cidr $any -FromPort 3260  -ToPort 3260  -Egress
    New-AclRule -AclId $acl -RuleNumber 110 -Proto tcp  -Cidr $any -FromPort 55855 -ToPort 55858 -Egress
}

# --- Internal 1 ACL ---
$aclInt1 = New-NamedAcl -Name 'internal1' -SubnetId $subnetIds['internal1']
New-AclRule -AclId $aclInt1 -RuleNumber 100 -Proto tcp  -Cidr $flexCidr -FromPort 22 -ToPort 22
New-AclRule -AclId $aclInt1 -RuleNumber 110 -Proto icmp -Cidr $flexCidr -FromPort 0  -ToPort 0
New-AclRule -AclId $aclInt1 -RuleNumber 100 -Proto icmp -Cidr $any      -FromPort 0  -ToPort 0  -Egress

# --- Internal 2 ACL ---
# NOTE: source image is truncated for Internal 2 — only "Inbound ICMP allowed" is visible.
# The cluster-subnet header reads "Allow all required intra-cluster traffic"; we implement
# that intent below by allowing all traffic from/to the VPC CIDR on every NACL.
$aclInt2 = New-NamedAcl -Name 'internal2' -SubnetId $subnetIds['internal2']
New-AclRule -AclId $aclInt2 -RuleNumber 100 -Proto icmp -Cidr $flexCidr -FromPort 0 -ToPort 0

# --- Intra-cluster: allow all traffic from/to the VPC CIDR on every NACL (rule 1000) ---
# NACLs are stateless and per-port rules between subnets get unwieldy fast. The spec calls
# for "Allow all required intra-cluster traffic"; the simplest correct implementation is to
# allow all intra-VPC traffic at the NACL layer and let security groups enforce the
# fine-grained rules between specific instances.
# Gated on -OpenVPC so the strict spec rules can stand on their own when desired.
if ($OpenVPC) {
    $allClusterAcls = [ordered]@{
        flex      = $aclFlex
        mgmt      = $aclMgmt
        data1     = $dataAclIds['data1']
        data2     = $dataAclIds['data2']
        internal1 = $aclInt1
        internal2 = $aclInt2
    }
    foreach ($e in $allClusterAcls.GetEnumerator()) {
        # Rule 1000: well above any spec rule (mgmt outbound goes up to ~240) so no collision.
        New-AclRule -AclId $e.Value -RuleNumber 1000 -Proto all -Cidr $vpcCidr -FromPort 0 -ToPort 0
        New-AclRule -AclId $e.Value -RuleNumber 1000 -Proto all -Cidr $vpcCidr -FromPort 0 -ToPort 0 -Egress
        Write-Host "ACL $($e.Key) -> rule 1000 added: allow all from/to $vpcCidr (in + out)"
    }
} else {
    Write-Host "OpenVPC not set: skipping intra-VPC any/any rule 1000 (strict spec ACLs only)"
}

Write-Host "`nDone. VPC $($vpc.VpcId) in $Region with $ClusterSize cluster sizing."
