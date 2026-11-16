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
