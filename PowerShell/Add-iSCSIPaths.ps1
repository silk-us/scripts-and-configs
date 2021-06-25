param(
    [parameter(Mandatory)]
    [string] $dataInterface,
    [parameter(Mandatory)]
    [IPAddress] $targetIP,
    [parameter()]
    [switch] $setMPIO,
    [parameter()]
    [int] $sessionsPerPath = 1
)

<#
    .SYNOPSIS 
    Quickly generates a specific number of iscsi sessions along a specific path. 

    .EXAMPLE    
    ./Add-iSCSIPaths -DataInterface 'Ethernet 5' -targetIP 10.12.0.20 -sessionsPerPath 6

    This will create 6 iSCSI sessions to the iSCSI targtet specified. 

#>

$iSCSIData1 = Get-NetIPAddress -InterfaceAlias $DataInterface -AddressFamily ipv4

if ($setMPIO) {
    # Set the global MPIO policy to round robin
    Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
    Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
    Set-MPIOSetting -NewPathVerificationState Enabled
    Set-MPIOSetting -NewPathVerificationPeriod 1
    Set-MPIOSetting -NewDiskTimeout 60
    Set-MPIOSetting -NewRetryCount 3
    Set-MPIOSetting -NewPDORemovePeriod 80
}

$session = 0
while ($session -lt $sessionsPerPath) {
    New-IscsiTargetPortal -TargetPortalAddress $targetIP.IPAddressToString -TargetPortalPortNumber 3260 -InitiatorPortalAddress $iSCSIData1.IPAddress
    $SDPIQN = Get-IscsiTarget
    Connect-IscsiTarget -NodeAddress $SDPIQN.NodeAddress -TargetPortalAddress $targetIP.IPAddressToString -TargetPortalPortNumber 3260 -InitiatorPortalAddress $iSCSIData1.IPAddress -IsPersistent $true -IsMultipathEnabled $true
    $session++
}


