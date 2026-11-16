<#
.SYNOPSIS
Sets the load balancer probe port (and the required /32 settings) on an Always On listener's cluster IP resource.

.DESCRIPTION
Finds the cluster IP resource carrying the listener IP, sets ProbePort, SubnetMask 255.255.255.255 and
EnableDhcp 0, opens the probe port in the Windows firewall on every node, and optionally cycles the IP
resource so the change takes effect. Run on a cluster node, elevated. Run once per subnet IP resource
for a multi-subnet listener.

.PARAMETER ListenerIP
The listener IP for this subnet. Must equal the load balancer frontend IP.

.PARAMETER probePort
Must match the LB health probe, differ from the SQL port, and be unique per listener on the cluster.

.PARAMETER Restart
Cycles the IP resource so the new ProbePort takes effect. Takes the listener offline for a few seconds.
Without it the change applies at the next failover or restart of the resource.

.PARAMETER SkipFirewall
Do not create the Windows firewall rule on the cluster nodes.

.EXAMPLE
.\Set-AGProbePort.ps1 -ListenerIP 10.10.1.50

Sets ProbePort 59999 on the IP resource for 10.10.1.50. Does not restart it.

.EXAMPLE
.\Set-AGProbePort.ps1 -ListenerIP 10.10.1.50 -probePort 59999 -Restart

Sets the port and cycles the resource so it is live now.

.EXAMPLE
.\Set-AGProbePort.ps1 -ListenerIP 10.10.1.50 -Restart
.\Set-AGProbePort.ps1 -ListenerIP 10.10.2.50 -Restart

Multi-subnet listener: one run per subnet's IP resource. The offline subnet's resource just picks the
value up the next time it comes online.

.EXAMPLE
.\Set-AGProbePort.ps1 -ListenerIP 10.10.1.51 -probePort 59998

Second AG listener on the same cluster, using its own probe port.
#>
param(
    [parameter(Mandatory)]
    [IPAddress] $ListenerIP,
    [parameter()]
    [int] $probePort = 59999,
    [parameter()]
    [switch] $Restart,
    [parameter()]
    [switch] $SkipFirewall,
    # ADDED: carried over from the original snippet. IP resource OverrideAddressMatch
    [parameter()]
    [int] $OverrideAddressMatch = 1,
    # ADDED: network name DNS settings from the original snippet
    [parameter()]
    [int] $HostRecordTTL = 60,
    [parameter()]
    [int] $PublishPTRRecords = 1
)

$ErrorActionPreference = 'Stop'

Import-Module FailoverClusters
$ip = $ListenerIP.IPAddressToString

# Find the cluster IP resource carrying the listener IP (one per subnet in a multi-subnet listener)
$res = Get-ClusterResource | Where-Object { $_.ResourceType -eq 'IP Address' -and
    ($_ | Get-ClusterParameter -Name Address).Value -eq $ip }
if (!$res) { throw "No cluster IP resource with address $ip" }
if (@($res).Count -gt 1) { throw "More than one IP resource has address ${ip}: $($res.Name -join ', ')" }

# Refuse a probe port another listener's IP resource is already using
$dupes = Get-ClusterResource | Where-Object { $_.ResourceType -eq 'IP Address' -and $_.OwnerGroup.Name -ne $res.OwnerGroup.Name } |
    Where-Object { ($_ | Get-ClusterParameter -Name ProbePort).Value -eq $probePort }
if ($dupes) { throw "Probe port $probePort is already used by: $($dupes.Name -join ', ') (group $($dupes.OwnerGroup.Name -join ', '))" }

# Reuse the cluster network the resource is already bound to
$network = ($res | Get-ClusterParameter -Name Network).Value

# Show what is there before changing it
Write-Host "`nBefore ($($res.Name), $($res.OwnerGroup.Name), $($res.State)):"
$res | Get-ClusterParameter ProbePort, SubnetMask, EnableDhcp, Address | Format-Table Name, Value -AutoSize

# ADDED: OverrideAddressMatch alongside the probe/mask/DHCP settings
$res | Set-ClusterParameter -Multiple @{
    Address              = $ip
    ProbePort            = $probePort
    SubnetMask           = '255.255.255.255'
    Network              = $network
    EnableDhcp           = 0
    OverrideAddressMatch = $OverrideAddressMatch
}

# ADDED: network name DNS settings (short TTL so clients re-resolve quickly after failover)
$nn = $res.OwnerGroup | Get-ClusterResource | Where-Object { $_.ResourceType -eq 'Network Name' }
if ($nn) {
    $nn | Set-ClusterParameter -Name HostRecordTTL -Value $HostRecordTTL
    $nn | Set-ClusterParameter -Name PublishPTRRecords -Value $PublishPTRRecords
}
else {
    Write-Warning "No Network Name resource found in group $($res.OwnerGroup.Name), skipped TTL/PTR settings"
}

# Open the probe port in the Windows firewall on every node
if (!$SkipFirewall) {
    foreach ($node in (Get-ClusterNode).Name) {
        Invoke-Command -ComputerName $node -ArgumentList $probePort -ScriptBlock {
            param($p)
            if (!(Get-NetFirewallRule -DisplayName "AG probe $p" -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName "AG probe $p" -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow | Out-Null
            }
        }
        Write-Host "Firewall rule for TCP $probePort present on $node"
    }
}

# New parameters only apply after the resource restarts
if ($res.State -eq 'Online') {
    if ($Restart) {
        Write-Host "`nCycling $($res.Name), listener will be offline for a few seconds"
        Stop-ClusterResource $res | Out-Null
        # Starting the network name brings the IP back through the dependency
        Start-ClusterResource $nn | Out-Null
    }
    else {
        Write-Warning "ProbePort is set but not live until the IP resource is cycled. Re-run with -Restart or fail over."
    }
}
else {
    Write-Host "`n$($res.Name) is $($res.State), the new ProbePort applies when it next comes online"
}

Write-Host "`nAfter:"
Get-ClusterResource -Name $res.Name | Get-ClusterParameter ProbePort, SubnetMask, EnableDhcp, Address, OverrideAddressMatch | Format-Table Name, Value -AutoSize
if ($nn) { $nn | Get-ClusterParameter HostRecordTTL, PublishPTRRecords, RegisterAllProvidersIP | Format-Table Name, Value -AutoSize }
