param(
    [parameter(Mandatory)]
    $filename,
    [parameter(Mandatory)]
    $peername
)

<#
    .SYNOPSIS
    Example for generating numerous replication sessions fed via text file list of desired volume groups

    .EXAMPLE 
    ./MassReplicationSession.ps1 -filename inputlist.txt -peername replication-peer 

    .NOTES
    Authored by J.R. Phillips (GitHub: JayAreP)

#>

$vglist = Get-Content $filename
foreach ($v in $vglist) {
    $repSessionName = $v + "-rep" 
    if ($repSessionName.Length -gt 41) {
        $repSessionName = $vg.id + "-rep-" + (get-random) 
    }
    New-SDPReplicationSession -name $repSessionName -volumeGroupName $v -replicationPeerName $peername -retentionPolicyName Replication_Retention -externalRetentionPolicyName Replication_Retention -RPO 1200 -mapped | Start-SDPReplicationSession 

}
