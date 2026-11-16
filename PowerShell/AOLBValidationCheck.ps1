[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    # Point at the LB any one of three ways:
    #   -LoadBalancer  a Get-AzLoadBalancer object (also accepted from the pipeline, one LB per call)
    #   -ResourceId    the LB's full Azure resource ID
    #   -name          LB name; -ResourceGroupName is optional and the subscription is searched if omitted
    [parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
    [psobject] $LoadBalancer,
    [parameter(Mandatory, ParameterSetName = 'ById')]
    [string] $ResourceId,
    [parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
    [string] $name,
    [parameter(ParameterSetName = 'ByName')]
    [string] $ResourceGroupName,
    # Optional: if supplied, the frontend IP must match
    [parameter()]
    [IPAddress] $ListenerIP,
    # Optional: if supplied, the probe port must match
    [parameter()]
    [int] $probePort,
    [parameter()]
    [int]$ListenerPort = 1433,
    # Also query the WSFC cluster IP/network name resources via Run Command on the first backend VM
    [parameter()]
    [switch] $CheckCluster,
    # Return the result objects to the pipeline as well as the report
    [parameter()]
    [switch] $PassThru
)

$ErrorActionPreference = 'Stop'

# Helpers

$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param($Category, $Check, [ValidateSet('Pass','Fail','Warn','Info')]$Status, $Expected, $Actual, $Detail)
    $results.Add([pscustomobject]@{
        Category = $Category
        Check    = $Check
        Status   = $Status
        Expected = $Expected
        Actual   = $Actual
        Detail   = $Detail
    })
}

function Test-PortInRange {
    param($Ranges, [int]$Port)
    foreach ($r in @($Ranges)) {
        if ($r -eq '*') { return $true }
        if ($r -match '^(\d+)-(\d+)$') {
            if ($Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $true }
        }
        elseif ($r -match '^\d+$' -and [int]$r -eq $Port) { return $true }
    }
    return $false
}

# First inbound rule (by priority, defaults included) that matches the Azure LB probe source on the given TCP port
function Get-NsgVerdict {
    param($Nsg, [int]$Port)
    $rules = (@($Nsg.SecurityRules) + @($Nsg.DefaultSecurityRules)) | Where-Object { $_.Direction -eq 'Inbound' } | Sort-Object Priority
    foreach ($r in $rules) {
        $srcMatch = @($r.SourceAddressPrefix) | Where-Object { $_ -in '*','AzureLoadBalancer','168.63.129.16' }
        if (!$srcMatch) { continue }
        if ($r.Protocol -notin 'Tcp','*') { continue }
        if (!(Test-PortInRange -Ranges $r.DestinationPortRange -Port $Port)) { continue }
        return [pscustomobject]@{ Access = $r.Access; Rule = $r.Name; Priority = $r.Priority }
    }
    return $null
}

# Gather the LB

switch ($PSCmdlet.ParameterSetName) {
    'ByObject' {
        $idParts = $LoadBalancer.Id.Split('/')
    }
    'ById' {
        $idParts = $ResourceId.Split('/')
        if ($idParts.Count -lt 9 -or $idParts[7] -ne 'loadBalancers') { throw "Not a load balancer resource ID: $ResourceId" }
    }
    'ByName' {
        if ($ResourceGroupName) {
            $found = @(Get-AzLoadBalancer -Name $name -ResourceGroupName $ResourceGroupName)
        }
        else {
            # No RG given, search the current subscription
            $found = @(Get-AzLoadBalancer -Name $name)
        }
        if ($found.Count -eq 0) { throw "Load balancer '$name' not found" }
        if ($found.Count -gt 1) { throw "'$name' matches $($found.Count) load balancers ($($found.ResourceGroupName -join ', ')). Add -ResourceGroupName" }
        $idParts = $found[0].Id.Split('/')
    }
}

# Resolve everything else from the ID. Switch subscription context if the LB lives in another one
if ($idParts[2] -ne (Get-AzContext).Subscription.Id) {
    Write-Host "Switching context to subscription $($idParts[2])"
    $null = Set-AzContext -Subscription $idParts[2]
}
$ResourceGroupName = $idParts[4]
$name = $idParts[8]

# Always re-read the LB so the evaluation reflects live config, not a stale object
$lb = Get-AzLoadBalancer -Name $name -ResourceGroupName $ResourceGroupName

# Load balancer

Add-Check 'LB' 'SKU' $(if ($lb.Sku.Name -eq 'Standard') {'Pass'} else {'Fail'}) 'Standard' $lb.Sku.Name 'Basic is retired and lacks the features needed here'

# Frontend

$feSubnets = @()
foreach ($fe in $lb.FrontendIpConfigurations) {
    $cat = "Frontend ($($fe.Name))"

    Add-Check $cat 'Internal (private) frontend' $(if ($fe.PrivateIpAddress -and !$fe.PublicIpAddress) {'Pass'} else {'Fail'}) 'Private IP, no public IP' $(if ($fe.PublicIpAddress) {'Public IP attached'} else {$fe.PrivateIpAddress}) 'The listener LB should be internal'

    Add-Check $cat 'Static IP allocation' $(if ($fe.PrivateIpAllocationMethod -eq 'Static') {'Pass'} else {'Fail'}) 'Static' $fe.PrivateIpAllocationMethod 'Must match the listener IP permanently'

    if ($ListenerIP) {
        $want = $ListenerIP.IPAddressToString
        Add-Check $cat 'Matches expected listener IP' $(if ($fe.PrivateIpAddress -eq $want) {'Pass'} else {'Fail'}) $want $fe.PrivateIpAddress 'Frontend IP must equal the cluster listener IP'
    }

    if ($fe.Subnet.Id) { $feSubnets += $fe.Subnet.Id }

    $feZones = @($fe.Zones)
    Add-Check $cat 'Zone redundancy' $(if ($feZones.Count -gt 0) {'Pass'} else {'Warn'}) 'Zonal or zone-redundant' $(if ($feZones.Count) {$feZones -join ','} else {'None'}) 'No zone set on the frontend'
}

# Probes

if (!$lb.Probes) { Add-Check 'Probe' 'Probe defined' 'Fail' 'At least 1' '0' 'No health probe' }
foreach ($p in $lb.Probes) {
    $cat = "Probe ($($p.Name))"

    Add-Check $cat 'Protocol' $(if ($p.Protocol -eq 'Tcp') {'Pass'} else {'Fail'}) 'Tcp' $p.Protocol 'The cluster IP resource answers a plain TCP connect'

    if ($probePort) {
        Add-Check $cat 'Port matches expected' $(if ($p.Port -eq $probePort) {'Pass'} else {'Fail'}) $probePort $p.Port 'Must equal ProbePort on the cluster IP resource'
    }
    else {
        Add-Check $cat 'Port' 'Info' 'n/a' $p.Port 'Pass -probePort to validate'
    }

    Add-Check $cat 'Probe port not the SQL port' $(if ($p.Port -ne $ListenerPort) {'Pass'} else {'Fail'}) "Not $ListenerPort" $p.Port 'Probe port must differ from the listener port'

    Add-Check $cat 'Interval' $(if ($p.IntervalInSeconds -le 5) {'Pass'} else {'Warn'}) '<= 5s recommended' "$($p.IntervalInSeconds)s" 'Interval x count is your failover detection time'

    Add-Check $cat 'Unhealthy threshold' $(if ($p.NumberOfProbes -ge 2) {'Pass'} else {'Warn'}) '>= 2' $p.NumberOfProbes 'A single missed probe can trigger a false failover'

    $used = @($lb.LoadBalancingRules | Where-Object { $_.Probe.Id -eq $p.Id })
    Add-Check $cat 'Used by a rule' $(if ($used.Count -gt 0) {'Pass'} else {'Warn'}) 'Referenced by a rule' $used.Count 'Orphaned probe'
}

# Rules

if (!$lb.LoadBalancingRules) { Add-Check 'Rule' 'Rule defined' 'Fail' 'At least 1' '0' 'No load balancing rule' }
foreach ($r in $lb.LoadBalancingRules) {
    $cat = "Rule ($($r.Name))"

    Add-Check $cat 'Protocol' $(if ($r.Protocol -eq 'Tcp') {'Pass'} else {'Fail'}) 'Tcp' $r.Protocol ''

    Add-Check $cat 'Floating IP (DSR)' $(if ($r.EnableFloatingIP) {'Pass'} else {'Fail'}) 'Enabled' $r.EnableFloatingIP 'Required, connections fail without it. Cannot be changed in place'

    Add-Check $cat 'Frontend port = backend port' $(if ($r.FrontendPort -eq $r.BackendPort) {'Pass'} else {'Fail'}) 'Equal' "$($r.FrontendPort) / $($r.BackendPort)" 'Floating IP requires matching ports'

    Add-Check $cat 'Listener port' $(if ($r.FrontendPort -eq $ListenerPort) {'Pass'} else {'Warn'}) $ListenerPort $r.FrontendPort 'Rule port differs from the expected listener port'

    Add-Check $cat 'Probe attached' $(if ($r.Probe.Id) {'Pass'} else {'Fail'}) 'Probe referenced' $(if ($r.Probe.Id) {$r.Probe.Id.Split('/')[-1]} else {'None'}) ''

    Add-Check $cat 'Backend pool attached' $(if ($r.BackendAddressPool.Id) {'Pass'} else {'Fail'}) 'Pool referenced' $(if ($r.BackendAddressPool.Id) {$r.BackendAddressPool.Id.Split('/')[-1]} else {'None'}) ''

    Add-Check $cat 'Load distribution' $(if ($r.LoadDistribution -eq 'Default') {'Pass'} else {'Warn'}) 'Default' $r.LoadDistribution 'Only one backend answers the probe at a time, so this rarely matters'

    Add-Check $cat 'TCP reset' $(if ($r.EnableTcpReset) {'Pass'} else {'Warn'}) 'Enabled' $r.EnableTcpReset 'Gives clients a fast RST on a dead flow after failover'

    if ($r.Probe.Id) {
        $rp = $lb.Probes | Where-Object { $_.Id -eq $r.Probe.Id }
        if ($rp) {
            Add-Check $cat 'Probe port differs from rule port' $(if ($rp.Port -ne $r.FrontendPort) {'Pass'} else {'Fail'}) "Not $($r.FrontendPort)" $rp.Port ''
        }
    }
}

# Backend pool and NICs

$members = foreach ($pool in $lb.BackendAddressPools) {
    foreach ($c in $pool.BackendIpConfigurations) { [pscustomobject]@{ Pool = $pool.Name; Id = $c.Id } }
    if ($pool.BackendIpConfigurations.Count -eq 0 -and $pool.LoadBalancerBackendAddresses.Count -gt 0) {
        Add-Check "Pool ($($pool.Name))" 'NIC-based pool' 'Warn' 'NIC-based' 'IP-based' 'IP-based pool members were not evaluated'
    }
}
$members = @($members)

Add-Check 'Backend' 'Member count' $(if ($members.Count -ge 2) {'Pass'} else {'Fail'}) '>= 2 (all replicas)' $members.Count 'A missing replica means connections only work while the other one is primary'

$vmNames = @()
$vmRGs = @{}
$nicNsgs = @()
foreach ($m in $members) {
    $parts = $m.Id.Split('/')
    $nicRG = $parts[4]
    $nicName = $parts[8]
    $cfgName = $parts[10]
    $NIC = Get-AzNetworkInterface -Name $nicName -ResourceGroupName $nicRG
    $cfg = $NIC.IpConfigurations | Where-Object { $_.Name -eq $cfgName }
    $vmName = if ($NIC.VirtualMachine.Id) { $NIC.VirtualMachine.Id.Split('/')[-1] } else { '(unattached)' }
    $cat = "Backend ($vmName)"

    Add-Check $cat 'Primary IP configuration' $(if ($cfg.Primary) {'Pass'} else {'Fail'}) 'Primary' $(if ($cfg.Primary) {'Primary'} else {"Secondary ($cfgName)"}) 'Secondary IPs do not support floating IP'

    $subnetOk = $feSubnets -contains $cfg.Subnet.Id
    Add-Check $cat 'Same subnet as frontend' $(if ($subnetOk) {'Pass'} else {'Fail'}) ($feSubnets -join ',').Split('/')[-1] $cfg.Subnet.Id.Split('/')[-1] 'Floating IP/DSR needs the frontend in the same subnet as the backend'

    if ($NIC.VirtualMachine.Id) {
        $vm = Get-AzVM -Name $vmName -ResourceGroupName $NIC.VirtualMachine.Id.Split('/')[4]
        $vmNames += $vmName
        $vmRGs[$vmName] = $NIC.VirtualMachine.Id.Split('/')[4]
        if ($vm.Zones -and !@($lb.FrontendIpConfigurations.Zones).Count) {
            Add-Check $cat 'Zone alignment' 'Warn' 'Zonal frontend for zonal VMs' "VM zone $($vm.Zones -join ',')" 'Frontend is not zonal'
        }
    }

    if ($NIC.NetworkSecurityGroup.Id) {
        $nicNsgs += [pscustomobject]@{ Vm = $vmName; Id = $NIC.NetworkSecurityGroup.Id }
    }
}

# NSG: can the Azure LB probe reach the probe port?

$ports = @($lb.Probes.Port | Select-Object -Unique)
$nsgTargets = @()
foreach ($sid in ($feSubnets | Select-Object -Unique)) {
    $sp = $sid.Split('/')
    $vn = Get-AzVirtualNetwork -Name $sp[8] -ResourceGroupName $sp[4]
    $sn = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vn -Name $sp[10]
    if ($sn.NetworkSecurityGroup.Id) {
        $nsgTargets += [pscustomobject]@{ Scope = "subnet $($sp[10])"; Id = $sn.NetworkSecurityGroup.Id }
    }
    else {
        Add-Check "NSG (subnet $($sp[10]))" 'NSG present' 'Info' 'n/a' 'No NSG' 'Nothing to block the probe'
    }
}
foreach ($n in $nicNsgs) { $nsgTargets += [pscustomobject]@{ Scope = "NIC $($n.Vm)"; Id = $n.Id } }

foreach ($t in ($nsgTargets | Sort-Object Id, Scope -Unique)) {
    $np = $t.Id.Split('/')
    $nsg = Get-AzNetworkSecurityGroup -Name $np[-1] -ResourceGroupName $np[4]
    foreach ($port in $ports) {
        $v = Get-NsgVerdict -Nsg $nsg -Port $port
        $actual = if ($v) { "$($v.Access) by $($v.Rule) ($($v.Priority))" } else { 'No matching rule' }
        Add-Check "NSG ($($t.Scope))" "Probe port $port allowed from Azure LB" $(if ($v -and $v.Access -eq 'Allow') {'Pass'} else {'Fail'}) 'Allow from AzureLoadBalancer' $actual "NSG $($np[-1]). Source tags other than AzureLoadBalancer/168.63.129.16/* are not evaluated"
    }
}
Add-Check 'NSG' 'Client traffic to listener port' 'Info' 'n/a' 'Not evaluated' "Confirm clients can reach $ListenerPort on the listener IP and backend VMs"

# Optional: WSFC side

if ($CheckCluster) {
    if (!$vmNames) { Add-Check 'Cluster' 'Run Command target' 'Fail' 'A backend VM' 'None' 'No VM resolved from the backend pool' }
    else {
        $cs = @'
$ips = @(Get-ClusterResource | Where-Object { $_.ResourceType -eq 'IP Address' } | ForEach-Object {
    $p = $_ | Get-ClusterParameter
    [pscustomobject]@{
        Name       = $_.Name
        Group      = $_.OwnerGroup.Name
        State      = [string]$_.State
        Address    = ($p | Where-Object Name -eq 'Address').Value
        ProbePort  = ($p | Where-Object Name -eq 'ProbePort').Value
        SubnetMask = ($p | Where-Object Name -eq 'SubnetMask').Value
        EnableDhcp = ($p | Where-Object Name -eq 'EnableDhcp').Value
    }
})
$nns = @(Get-ClusterResource | Where-Object { $_.ResourceType -eq 'Network Name' } | ForEach-Object {
    $p = $_ | Get-ClusterParameter
    [pscustomobject]@{
        Name                   = $_.Name
        Group                  = $_.OwnerGroup.Name
        RegisterAllProvidersIP = ($p | Where-Object Name -eq 'RegisterAllProvidersIP').Value
        HostRecordTTL          = ($p | Where-Object Name -eq 'HostRecordTTL').Value
    }
})
[pscustomobject]@{ ips = $ips; nns = $nns } | ConvertTo-Json -Depth 4 -Compress
'@
        $vmTarget = $vmNames[0]
        # The VM's own RG, which is not necessarily the LB's
        $vmRG = $vmRGs[$vmTarget]
        $rc = Invoke-AzVMRunCommand -ResourceGroupName $vmRG -VMName $vmTarget -CommandId 'RunPowerShellScript' -ScriptString $cs
        $json = ($rc.Value | Where-Object { $_.Code -like '*StdOut*' }).Message
        try { $cl = $json | ConvertFrom-Json } catch { $cl = $null }

        if (!$cl) { Add-Check 'Cluster' 'Query' 'Fail' 'Cluster data' 'No data' "Run Command on $vmTarget returned nothing parseable" }
        else {
            foreach ($fe in $lb.FrontendIpConfigurations) {
                $ipRes = @($cl.ips) | Where-Object { $_.Address -eq $fe.PrivateIpAddress }
                $cat = "Cluster ($($fe.PrivateIpAddress))"
                if (!$ipRes) {
                    Add-Check $cat 'IP resource exists' 'Fail' 'Cluster IP resource with this address' 'None' 'Frontend IP does not match any cluster IP resource'
                    continue
                }
                Add-Check $cat 'IP resource' 'Info' 'n/a' "$($ipRes.Name) in $($ipRes.Group) ($($ipRes.State))" 'Offline is normal when the listener is active in another subnet'

                $probeSet = @($lb.Probes.Port) -contains [int]$ipRes.ProbePort
                Add-Check $cat 'ProbePort matches LB probe' $(if ($probeSet) {'Pass'} else {'Fail'}) ($lb.Probes.Port -join ',') $ipRes.ProbePort 'Cluster ProbePort must equal the LB probe port'

                Add-Check $cat 'SubnetMask' $(if ($ipRes.SubnetMask -eq '255.255.255.255') {'Pass'} else {'Fail'}) '255.255.255.255' $ipRes.SubnetMask 'Must be /32 so the node answers for the floating IP'

                Add-Check $cat 'EnableDhcp' $(if ([int]$ipRes.EnableDhcp -eq 0) {'Pass'} else {'Fail'}) 0 $ipRes.EnableDhcp ''

                # Another listener's IP resource using the same probe port will collide on a shared node
                $dupes = @($cl.ips | Where-Object { $_.Group -ne $ipRes.Group -and $_.ProbePort -eq $ipRes.ProbePort -and $_.ProbePort -ne 0 })
                Add-Check $cat 'ProbePort unique per listener' $(if ($dupes.Count -eq 0) {'Pass'} else {'Fail'}) 'No other group using it' $(if ($dupes) {($dupes.Group | Select-Object -Unique) -join ','} else {'Unique'}) 'Two listeners on one node cannot share a probe port'

                $nn = @($cl.nns) | Where-Object { $_.Group -eq $ipRes.Group } | Select-Object -First 1
                if ($nn) {
                    $multi = @($cl.ips | Where-Object { $_.Group -eq $ipRes.Group }).Count -gt 1
                    $rap = [int]$nn.RegisterAllProvidersIP
                    if ($multi) {
                        Add-Check $cat 'RegisterAllProvidersIP' $(if ($rap -eq 0) {'Pass'} else {'Warn'}) 0 $rap 'Multi-subnet listener: register only the active IP to avoid round-robin DNS disconnects'
                        Add-Check $cat 'HostRecordTTL' $(if ([int]$nn.HostRecordTTL -le 300) {'Pass'} else {'Warn'}) '<= 300' $nn.HostRecordTTL 'Short TTL speeds up client re-resolution after failover'
                    }
                    else {
                        Add-Check $cat 'RegisterAllProvidersIP' 'Info' 'n/a' $rap 'Single-IP listener, setting is not significant'
                    }
                }
            }
        }
    }
}

# Report

$order = @{ Fail = 0; Warn = 1; Pass = 2; Info = 3 }
$sorted = $results | Sort-Object { $order[$_.Status] }, Category

Write-Host "`nValidation: $name ($ResourceGroupName)`n"
$sorted | Where-Object { $_.Status -ne 'Pass' } | Format-Table Status, Category, Check, Expected, Actual -AutoSize -Wrap
Write-Host "Passed checks: $(@($results | Where-Object Status -eq 'Pass').Count)"

$fails = @($results | Where-Object Status -eq 'Fail')
$warns = @($results | Where-Object Status -eq 'Warn')
if ($fails) {
    Write-Host "`nDetail on failures:" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  [$($_.Category)] $($_.Check): $($_.Detail)" -ForegroundColor Red }
}

$verdict = if ($fails) { 'IMPROPER' } elseif ($warns) { 'PROPER (with warnings)' } else { 'PROPER' }
$color = if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' }
Write-Host "`nResult: $verdict  (Fail: $($fails.Count), Warn: $($warns.Count))`n" -ForegroundColor $color

if ($PassThru) { $sorted }
