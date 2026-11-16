<#
.SYNOPSIS
Builds an internal Standard load balancer for an Always On availability group listener.

.DESCRIPTION
Creates the ILB (static private frontend, TCP probe, floating IP rule), adds the replica VM NICs to
the backend pool without disturbing other pools, and adds an NSG rule allowing the Azure LB probe.
Azure side only: ProbePort, /32 SubnetMask and EnableDhcp=0 must still be set on the listener's
cluster IP resource. Run once per subnet for a multi-subnet listener. Safe to re-run.
View these examples with: Get-Help .\New-AOLB.ps1 -Examples

.PARAMETER name
Name of the load balancer.

.PARAMETER ListenerIP
Static IP for the frontend. Must equal the listener IP in the cluster.

.PARAMETER vmnamePrefix
Prefix used to name the probe, rule, frontend and backend pool. Also the wildcard used to find VMs
when -vmList is not supplied.

.PARAMETER vmList
Names of the replica VMs to add to the pool. Use this when VMs in different subnets share a prefix.

.PARAMETER probePort
Health probe port. Must be unique per listener and must not equal the listener port.

.PARAMETER nsgRuleNumber
Starting NSG priority. The next free priority at or above this is used.

.PARAMETER zone
Optional frontend zones, e.g. 1,2,3 for zone redundancy when the VMs are zonal.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag01-ilb -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql -ListenerIP 10.10.1.50 -vmnamePrefix sqlag01

Single-subnet AG. Finds every VM in rg-sql named sqlag01*, builds the ILB for 10.10.1.50 on 1433 with
probe port 59999, and attaches the VM NICs.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag01-ilb -ResourceGroupName rg-sql -vnet vnet-prod -vnetRG rg-network -subnet snet-sql -ListenerIP 10.10.1.50 -vmnamePrefix sqlag01

VNet and subnet live in a different resource group (rg-network) than the VMs and the LB.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag01-ilb-a -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql-a -ListenerIP 10.10.1.50 -vmnamePrefix sqlag01-a -vmList sqlag01-n1,sqlag01-n2
.\New-AOLB.ps1 -name sqlag01-ilb-b -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql-b -ListenerIP 10.10.2.50 -vmnamePrefix sqlag01-b -vmList sqlag01-n3

Multi-subnet listener: one ILB per subnet, each with its own frontend IP and only the VMs in that
subnet. Distinct prefixes keep the resource and NSG rule names unique. The NSG priority walks up
automatically if both subnets share an NSG.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag02-ilb -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql -ListenerIP 10.10.1.51 -vmnamePrefix sqlag02 -vmList sqlag01-n1,sqlag01-n2 -probePort 59998

Second AG listener on the same VMs. Needs its own probe port, and the NIC attach adds this pool
alongside the first AG's pool instead of replacing it.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag01-ilb -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql -ListenerIP 10.10.1.50 -vmnamePrefix sqlag01 -zone 1,2,3 -probeInterval 5 -probeCount 2 -nsgRuleNumber 200

Zone-redundant frontend for zonal VMs, probe every 5s with 2 failures (about 10s detection), and the
NSG rule starting at priority 200.

.EXAMPLE
.\New-AOLB.ps1 -name sqlag01-ilb -ResourceGroupName rg-sql -vnet vnet-prod -subnet snet-sql -ListenerIP 10.10.1.50 -vmnamePrefix sqlag01 -Verbose
.\AOLBValidationCheck.ps1 sqlag01-ilb -ListenerIP 10.10.1.50 -probePort 59999 -CheckCluster

Build, then validate the result against the expected IP and probe port, including the cluster side.
#>
param(
    [parameter(Mandatory)]
    [string] $name,
    [parameter(Mandatory)]
    [string] $ResourceGroupName,
    [parameter(Mandatory)]
    [string] $vnet,
    [parameter()]
    [string] $vnetRG = $ResourceGroupName,
    [parameter(Mandatory)]
    [string] $subnet,
    [parameter(Mandatory)]
    [IPAddress] $ListenerIP,
    [parameter(Mandatory)]
    [string] $vmnamePrefix,
    # CHANGED: now a list of VM names (was [string], which broke the default Get-AzVM path)
    [parameter()]
    [string[]] $vmList,
    [parameter()]
    [int] $probePort = 59999,
    [parameter()]
    [int]$ListenerPort = 1433,
    [parameter()]
    [int]$nsgRuleNumber = 144,
    # ADDED: probe timing is now tunable. 5s x 2 = ~10s detection (was hardcoded 15s x 2 = ~30s)
    [parameter()]
    [int]$probeInterval = 5,
    [parameter()]
    [int]$probeCount = 2,
    # ADDED: optional zones for the frontend IP, e.g. -zone 1,2,3 when the VMs are zonal
    [parameter()]
    [string[]] $zone
)

# ADDED: stop on any error so a failed step can't cascade into the next one
$ErrorActionPreference = 'Stop'

# Gather object meta

$vnetObj = Get-AzVirtualNetwork -Name $vnet -ResourceGroupName $vnetRG
$subnetObj = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetObj -Name $subnet

# CHANGED: resolve names to VM objects in $vms. Typed [string] $vmList could never hold VM objects
if ($vmList) {
    $vms = foreach ($v in $vmList) { Get-AzVM -Name $v -ResourceGroupName $ResourceGroupName }
}
else {
    $vms = Get-AzVM -Name "$vmnamePrefix*" -ResourceGroupName $ResourceGroupName
}
# ADDED: bail early if nothing matched
if (!$vms) { throw "No VMs found in $ResourceGroupName matching '$vmnamePrefix'" }

# Declare some vars

$Location = $vnetObj.Location
$lbIP = $ListenerIP.IPAddressToString
$lbProbeName = $vmnamePrefix + "-probe-" + $ListenerPort
$lbRuleName = $vmnamePrefix + "-rule-" + $ListenerPort
$feConfigName = $vmnamePrefix + "-FE"
$beConfigName = $vmnamePrefix + "-BE"

# build the objects

# CHANGED: splatted so -Zone is only passed when requested
$feParams = @{
    Name             = $feConfigName
    PrivateIpAddress = $lbIP
    SubnetId         = $SubnetObj.id
}
if ($zone) { $feParams.Zone = $zone }
$feConfig = New-AzLoadBalancerFrontendIpConfig @feParams
$beConfig = New-AzLoadBalancerBackendAddressPoolConfig -Name $beConfigName
# CHANGED: interval/count come from params
$lbProbe = New-AzLoadBalancerProbeConfig -Name $lbProbeName -Protocol tcp -Port $ProbePort -IntervalInSeconds $probeInterval -ProbeCount $probeCount
# CHANGED: added -EnableTcpReset so clients on a dead flow get an RST at failover instead of timing out
$lbRule = New-AzLoadBalancerRuleConfig -Name $lbRuleName -FrontendIpConfiguration $feConfig -BackendAddressPool $beConfig -Probe $lbProbe -Protocol tcp -FrontendPort $ListenerPort -BackendPort $ListenerPort -LoadDistribution Default -EnableFloatingIP -EnableTcpReset

# ADDED: New-AzLoadBalancer is a PUT, so a re-run updates in place. Just say so.
if (Get-AzLoadBalancer -Name $name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) {
    Write-Warning "Load balancer $name already exists, updating in place"
}
# CHANGED: -Sku Standard set explicitly (Basic is retired)
$lb = New-AzLoadBalancer -Location $Location -Name $name -ResourceGroupName $ResourceGroupName -Sku Standard -FrontendIpConfiguration $feConfig -BackendAddressPool $beConfig -LoadBalancingRule $lbRule -Probe $lbProbe

# configure the VM Nics

$bePool = Get-AzLoadBalancerBackendAddressPoolConfig -Name $beConfigName -LoadBalancer $lb
foreach($i in $vms) {
        # CHANGED: single-NIC VMs can report Primary as null, so fall back to the first NIC
        $nicRef = $i.NetworkProfile.NetworkInterfaces | Where-Object {$_.Primary}
        if (!$nicRef) { $nicRef = $i.NetworkProfile.NetworkInterfaces[0] }
        $NICName = $nicRef.id.split('/')[-1]
        # CHANGED: NIC RG parsed from its ID instead of assuming it matches the VM RG
        $NICRG = $nicRef.id.split('/')[4]
        $NIC = Get-AzNetworkInterface -name $NICName -ResourceGroupName $NICRG
        # CHANGED: pick the primary ipconfig instead of blindly using [0]
        $ipConfig = $NIC.IpConfigurations | Where-Object {$_.Primary}
        if (!$ipConfig) { $ipConfig = $NIC.IpConfigurations[0] }
        # CHANGED: ADD to the pool list instead of overwriting it. The old assignment wiped any other LB
        # pools on the NIC (e.g. a second listener/AG on the same VMs). Also skips NICs already in the pool.
        if ($ipConfig.LoadBalancerBackendAddressPools.Id -notcontains $bePool.Id) {
            $ipConfig.LoadBalancerBackendAddressPools.Add($bePool)
            Set-AzNetworkInterface -NetworkInterface $NIC | Out-Null
        }
    }

# REMOVED: the "Restart backend VMs" Write-Verbose. Nothing restarted, and attaching to an LB doesn't need it

# Update the NSG rule

# CHANGED: handle a subnet with no NSG, and parse the NSG's own RG from its ID (it isn't necessarily $vnetRG)
$nsgId = $subnetObj.NetworkSecurityGroup.id
if ($nsgId) {
    [string] $nsgname = $nsgId.Split('/')[-1]
    [string] $nsgRG = $nsgId.Split('/')[4]
    [string] $ruleName = $beConfigName + "-in"

    $nsgarray = Get-AzNetworkSecurityGroup -Name $nsgname -ResourceGroupName $nsgRG

    # ADDED: skip if the rule already exists (re-run safe)
    if (!($nsgarray.SecurityRules | Where-Object {$_.Name -eq $ruleName})) {
        # CHANGED: $nsgRuleNumber is now a starting point. Walk up to the next free priority so
        # one-ILB-per-subnet runs against a shared NSG don't collide
        [int] $priority = $nsgRuleNumber
        $usedPriorities = $nsgarray.SecurityRules.Priority
        while ($usedPriorities -contains $priority) { $priority++ }

        # CHANGED: AzureLoadBalancer service tag instead of 168.63.129.16, TCP only, probe port only (was * / *)
        $nsgarray | Add-AzNetworkSecurityRuleConfig -Name $ruleName -Access Allow -Protocol Tcp -Direction Inbound -Priority $priority -SourceAddressPrefix 'AzureLoadBalancer' -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $probePort | Out-Null
        $nsgarray | Set-AzNetworkSecurityGroup | Out-Null
    }
}
else {
    Write-Warning "Subnet $subnet has no NSG, skipping probe rule"
}
