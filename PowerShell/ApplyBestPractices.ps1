function Invoke-SilkHostBestPractices {
<#
.SYNOPSIS
    Applies Silk Data Platform best-practice host configuration to a Windows iSCSI initiator.

.DESCRIPTION
    Configures a Windows Server host for use with the Silk Data Platform by:
      - Installing the Multipath I/O (MPIO) Windows feature if absent (restart required)
      - Applying Silk-recommended MSDSM and MPIO settings (restart required if changed)
      - Disabling NTFS TRIM/UNMAP notifications (DisableDeleteNotification registry key)
      - Starting the Microsoft iSCSI Initiator service and setting it to automatic startup
      - Optionally adding a persistent static route to the Silk data subnet
      - Displaying the host IQN for registration in the Silk portal
      - Optionally installing the silkiscsi and sdp PowerShell modules from PSGallery

    If MPIO is not installed, the script installs it and immediately restarts.
    Re-run after restart to complete the remaining configuration steps.

.PARAMETER iSCSInicGateway
    IP address of the gateway on the iSCSI/data network. Used to identify the correct NIC
    and build the persistent static route to the data subnet.

.PARAMETER DataSubnet
    Network address of the Silk data subnet (e.g. 10.2.3.0). Combined with -DataSubnetMask
    to form the route destination prefix.

.PARAMETER DataSubnetMask
    Subnet mask for the Silk data network.
    Accepted values: 255.255.255.240 (/28), 255.255.255.224 (/27), 255.255.255.128 (/25).

.PARAMETER AutoRestart
    Suppresses the interactive confirmation prompt before each required restart.
    Omit for attended use; include for automated/unattended deployments.

.PARAMETER InstallPWSHModules
    Installs the silkiscsi and sdp PowerShell modules needed for Silk management operations.
    Requires outbound internet access to PSGallery.

.EXAMPLE
    .\ApplyBestPractices.ps1 -iSCSInicGateway 10.2.0.1 -DataSubnet 10.2.3.0 -DataSubnetMask 255.255.255.240 -InstallPWSHModules

    Applies all best practices, adds a persistent data-subnet route, installs required
    PowerShell modules, and prompts the operator before each restart.

.EXAMPLE
    .\ApplyBestPractices.ps1 -AutoRestart

    Applies MPIO/MSDSM best practices and restarts without prompting if required.
    Skips route configuration and module installation.

.NOTES
    Must be run as Administrator.
    After an MPIO feature install restart, re-run this script to complete configuration.
    Can also be dot-sourced and called directly: . .\ApplyBestPractices.ps1; Invoke-SilkHostBestPractices @params
#>
param(
    [Parameter()]
    [ipaddress] $iSCSInicGateway,
    [Parameter()]
    [ipaddress] $DataSubnet,
    [Parameter()]
    [ValidateSet("255.255.255.240", "255.255.255.224", "255.255.255.128")]
    [ipaddress] $DataSubnetMask,
    [Parameter()]
    [switch] $AutoRestart,
    [Parameter()]
    [switch] $InstallPWSHModules
)


#region MPIO Windows Feature

# MPIO must be installed before MSDSM cmdlets and Set-MPIOSetting are available.
# The feature requires a restart before it is active; the script exits immediately after.
if ( !(Get-WindowsFeature -Name Multipath-IO).Installed )
    {
        Write-Host $("Windows Feature Multipath-IO Installed: {0}. Installing..." -f (Get-WindowsFeature -Name Multipath-io).Installed)
        Add-WindowsFeature Multipath-IO -IncludeAllSubFeature -IncludeManagementTools
        Write-Host $("Windows Feature Multipath-IO now Installed: {0}" -f (Get-WindowsFeature -Name Multipath-io).Installed)

        if ( !$AutoRestart ) { Read-Host -Prompt "Restart Required. Press Enter to continue with restart or Ctrl+C to exit." }
        shutdown /r /t 0
    }
else
    {
        Write-Host $("Windows Feature Multipath-IO already Installed: {0}" -f (Get-WindowsFeature -Name Multipath-io).Installed)
    }

#endregion


#region MSDSM and MPIO Settings

# All state is captured upfront so the compliance check and every inner check
# read from the same snapshot — no short-circuit evaluation side effects.
$MSDSMSupportedHW                    = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9 -ErrorAction SilentlyContinue
$MSDSMGlobalDefaultLoadBalancePolicy = Get-MSDSMGlobalDefaultLoadBalancePolicy
$iSCSIMSDSMAutomaticClaimSettings    = (Get-MSDSMAutomaticClaimSettings)['iSCSI']
$MPIOSettings                        = Get-MPIOSetting
$ScheduledDefrag                     = Get-ScheduledTask -TaskName ScheduledDefrag
$FSRegistry                          = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem"

if (
    !$MSDSMSupportedHW -or
    $MSDSMGlobalDefaultLoadBalancePolicy -ne 'LQD' -or
    !$iSCSIMSDSMAutomaticClaimSettings -or
    $MPIOSettings.PathVerificationState -ne "Enabled" -or
    $MPIOSettings.PathVerificationPeriod -ne 1 -or
    $MPIOSettings.PDORemovePeriod -ne 20 -or
    $MPIOSettings.RetryCount -ne 3 -or
    $MPIOSettings.RetryInterval -ne 3 -or
    $MPIOSettings.UseCustomPathRecoveryTime -ne "Enabled" -or
    $MPIOSettings.CustomPathRecoveryTime -ne 20 -or
    $MPIOSettings.DiskTimeoutValue -ne 100 -or
    $ScheduledDefrag.State -ne 'Disabled' -or
    $FSRegistry.DisableDeleteNotification -ne 1
)
    {
        # --- MSDSM: Supported Hardware ---
        # The MSFT2005/iSCSIBusType_0x9 entry tells MSDSM to claim iSCSI bus-type devices.
        if ( !$MSDSMSupportedHW )
            {
                New-MSDSMSupportedHW -VendorID MSFT2005 -Product iSCSIBusType_0x9
                Write-Host $("MSDSM Supported Hardware Vendor Id: {0} Product: {1} Added." -f ($MSDSMSupportedHW = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9).VendorId, $MSDSMSupportedHW.ProductId)
            }
        else
            {
                Write-Host $("MSDSM Supported Hardware Vendor Id: {0} Product: {1} Present." -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
            }

        # --- MSDSM: Load Balance Policy ---
        # LQD (Least Queue Depth) is the Silk-recommended policy for iSCSI multipathing.
        if ( $MSDSMGlobalDefaultLoadBalancePolicy -ne 'LQD' )
            {
                Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
                Write-Host $("MPIO LoadBalancePolicy updated to: {0}. Restart Required!" -f (Get-MSDSMGlobalDefaultLoadBalancePolicy))
            }
        else
            {
                Write-Host $("MPIO LoadBalancePolicy is already set to: {0}." -f $MSDSMGlobalDefaultLoadBalancePolicy)
            }

        # --- MSDSM: Automatic iSCSI Claim ---
        if ( !$iSCSIMSDSMAutomaticClaimSettings )
            {
                Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
                Write-Host $("Automatic Claim for iSCSI devices updated to {0}. Restart Required!" -f (Get-MSDSMAutomaticClaimSettings)['iSCSI'])
            }
        else
            {
                Write-Host $("Automatic Claim for iSCSI devices is already: {0}." -f $iSCSIMSDSMAutomaticClaimSettings)
            }

        # --- MPIO Settings ---
        if ( $MPIOSettings.PathVerificationState -ne "Enabled" )
            {
                Set-MPIOSetting -NewPathVerificationState Enabled
                Write-Host $("MPIO PathVerificationState is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).PathVerificationState)
            }
        else
            {
                Write-Host $("MPIO PathVerificationState is already set to: {0}" -f $MPIOSettings.PathVerificationState)
            }

        if ( $MPIOSettings.PathVerificationPeriod -ne 1 )
            {
                Set-MPIOSetting -NewPathVerificationPeriod 1
                Write-Host $("MPIO PathVerificationPeriod is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).PathVerificationPeriod)
            }
        else
            {
                Write-Host $("MPIO PathVerificationPeriod is already set to: {0}" -f $MPIOSettings.PathVerificationPeriod)
            }

        if ( $MPIOSettings.PDORemovePeriod -ne 20 )
            {
                Set-MPIOSetting -NewPDORemovePeriod 20
                Write-Host $("MPIO PDORemovePeriod is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).PDORemovePeriod)
            }
        else
            {
                Write-Host $("MPIO PDORemovePeriod is already set to: {0}" -f $MPIOSettings.PDORemovePeriod)
            }

        if ( $MPIOSettings.RetryCount -ne 3 )
            {
                Set-MPIOSetting -NewRetryCount 3
                Write-Host $("MPIO RetryCount is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).RetryCount)
            }
        else
            {
                Write-Host $("MPIO RetryCount is already set to: {0}" -f $MPIOSettings.RetryCount)
            }

        if ( $MPIOSettings.RetryInterval -ne 3 )
            {
                Set-MPIOSetting -newRetryInterval 3
                Write-Host $("MPIO RetryInterval is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).RetryInterval)
            }
        else
            {
                Write-Host $("MPIO RetryInterval is already set to: {0}" -f $MPIOSettings.RetryInterval)
            }

        if ( $MPIOSettings.UseCustomPathRecoveryTime -ne "Enabled" )
            {
                Set-MPIOSetting -CustomPathRecovery Enabled
                Write-Host $("MPIO UseCustomPathRecoveryTime is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).UseCustomPathRecoveryTime)
            }
        else
            {
                Write-Host $("MPIO UseCustomPathRecoveryTime is already set to: {0}" -f $MPIOSettings.UseCustomPathRecoveryTime)
            }

        if ( $MPIOSettings.CustomPathRecoveryTime -ne 20 )
            {
                Set-MPIOSetting -NewPathRecoveryInterval 20
                Write-Host $("MPIO CustomPathRecoveryTime is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).CustomPathRecoveryTime)
            }
        else
            {
                Write-Host $("MPIO CustomPathRecoveryTime is already set to: {0}" -f $MPIOSettings.CustomPathRecoveryTime)
            }

        if ( $MPIOSettings.DiskTimeoutValue -ne 100 )
            {
                Set-MPIOSetting -NewDiskTimeout 100
                Write-Host $("MPIO DiskTimeoutValue is now set to: {0}. Restart Required!" -f (Get-MPIOSetting).DiskTimeoutValue)
            }
        else
            {
                Write-Host $("MPIO DiskTimeoutValue is already set to: {0}" -f $MPIOSettings.DiskTimeoutValue)
            }

        # --- Scheduled Defrag ---
        # Disk defragmentation must be disabled; it can disrupt MPIO path recovery timing.
        if ( $ScheduledDefrag.State -ne 'Disabled' )
            {
                Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask
                Write-Host $("ScheduledDefrag Task State updated to: {0}. Restart Required!" -f (Get-ScheduledTask -TaskName ScheduledDefrag).State)
            }
        else
            {
                Write-Host $("ScheduledDefrag task state: '{0}' expected: 'Disabled'" -f $ScheduledDefrag.State)
            }

        # --- TRIM/UNMAP Disable ---
        # Prevents Windows from issuing TRIM/UNMAP commands to the storage target;
        # the Silk array manages reclamation independently.
        if ( $FSRegistry.DisableDeleteNotification -ne 1 )
            {
                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name DisableDeleteNotification -Value 1
                Write-Host $("DisableDeleteNotification updated to: {0}. Restart Required!" -f (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem").DisableDeleteNotification)
            }
        else
            {
                Write-Host $("DisableDeleteNotification is already set to: {0}" -f $FSRegistry.DisableDeleteNotification)
            }

        if ( !$AutoRestart ) { Read-Host -Prompt "Restart Required. Press Enter to continue with restart or Ctrl+C to exit." }
        shutdown /r /t 0
    }
else
    {
        Write-Host $("MSDSM Supported Hardware Vendor Id: {0} Product: {1} Present." -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
        Write-Host $("MPIO LoadBalancePolicy is set to: {0}." -f $MSDSMGlobalDefaultLoadBalancePolicy)
        Write-Host $("Automatic Claim for iSCSI devices is: {0}." -f $iSCSIMSDSMAutomaticClaimSettings)
        Write-Host $("MPIO PathVerificationState is set to: {0}" -f $MPIOSettings.PathVerificationState)
        Write-Host $("MPIO PathVerificationPeriod is set to: {0}" -f $MPIOSettings.PathVerificationPeriod)
        Write-Host $("MPIO PDORemovePeriod is set to: {0}" -f $MPIOSettings.PDORemovePeriod)
        Write-Host $("MPIO RetryCount is set to: {0}" -f $MPIOSettings.RetryCount)
        Write-Host $("MPIO RetryInterval is set to: {0}" -f $MPIOSettings.RetryInterval)
        Write-Host $("MPIO UseCustomPathRecoveryTime is set to: {0}" -f $MPIOSettings.UseCustomPathRecoveryTime)
        Write-Host $("MPIO CustomPathRecoveryTime is set to: {0}" -f $MPIOSettings.CustomPathRecoveryTime)
        Write-Host $("MPIO DiskTimeoutValue is set to: {0}" -f $MPIOSettings.DiskTimeoutValue)
        Write-Host $("ScheduledDefrag task state: '{0}' expected: 'Disabled'" -f $ScheduledDefrag.State)
        Write-Host $("DisableDeleteNotification is set to: {0}" -f $FSRegistry.DisableDeleteNotification)
        Write-Host "All MSDSM and MPIO best practices are applied. No changes made."
    }

#endregion


#region iSCSI Initiator Service

$iSCSIService = Get-Service MSiSCSI
if ( $iSCSIService.Status -ne 'Running' )
    {
        Start-Service MSiSCSI
        Write-Host $("iSCSI Service status now: {0}" -f ($iSCSIService = Get-Service MSiSCSI).Status)
    }
else
    {
        Write-Host $("iSCSI Service status already: {0}" -f $iSCSIService.Status)
    }

if ( $iSCSIService.StartType -ne 'Automatic' )
    {
        $iSCSIService | Set-Service -StartupType Automatic
        Write-Host $("iSCSI Service startup type now: {0}" -f (Get-Service MSiSCSI).StartType)
    }
else
    {
        Write-Host $("iSCSI Service startup type already: {0}" -f $iSCSIService.StartType)
    }

#endregion


#region Static Route to Data Subnet

# Adds a persistent (boot-surviving) route so iSCSI traffic to the Silk data subnet is
# directed through the iSCSI gateway rather than the default gateway.
# Find-NetRoute resolves the correct NIC interface index from the gateway IP alone.
if ( $DataSubnet -and $DataSubnetMask -and $iSCSInicGateway )
    {
        $PrefixLength = ( ([IPAddress]$DataSubnetMask.IPAddressToString).GetAddressBytes() |
            ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') } ) -join '' |
            ForEach-Object { ($_ -replace '0+$').Length }
        $iSCSIInterfaceIndex = (Find-NetRoute -RemoteIPAddress $iSCSInicGateway.IPAddressToString).InterfaceIndex
        $RouteParams = @{
            DestinationPrefix = "$DataSubnet/$PrefixLength"
            NextHop           = $iSCSInicGateway.IPAddressToString
            InterfaceIndex    = $iSCSIInterfaceIndex
            RouteMetric       = 1
            PolicyStore       = 'PersistentStore'
        }
        if ( !( Get-NetRoute -DestinationPrefix $RouteParams.DestinationPrefix -NextHop $RouteParams.NextHop -ErrorAction SilentlyContinue ) )
            {
                New-NetRoute @RouteParams | Out-Null
                Write-Host $("Persistent route added: {0} via {1}" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)
            }
        else
            {
                Write-Host $("Persistent route already exists: {0} via {1}" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)
            }
    }

#endregion


#region Host IQN

# The IQN must be registered in the Silk portal before iSCSI sessions can be established.
$HostIQN = (Get-InitiatorPort | Where-Object { $_.ConnectionType -eq 'iSCSI' } | Select-Object -First 1).NodeAddress
Write-Host $("Host iSCSI IQN: {0}`n`n" -f $HostIQN)
Read-Host -Prompt "Record the IQN above, then press Enter to continue"

#endregion


#region PowerShell Module Installation

if ( $InstallPWSHModules )
    {
        # Ensure NuGet provider is available — required by Install-Module from PSGallery
        if ( !($NuGetVersion = Get-PackageProvider | Where-Object -FilterScript { $_.Name -eq "NuGet" -and $_.Version -ge 2.8.5.201 }) )
            {
                Write-Host "NuGet Package Provider not found. Installing..."
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
                $NuGetVersion = Get-PackageProvider | Where-Object -FilterScript { $_.Name -eq "NuGet" }
            }

        Write-Host $("{0} Package Provider version {1} installed." -f $NuGetVersion.Name, $NuGetVersion.Version)

        # Trust PSGallery to suppress per-install confirmation prompts
        if ( $(Get-PSRepository -Name psgallery).InstallationPolicy -ne "Trusted" )
            {
                Get-PSRepository -Name psgallery | Set-PSRepository -InstallationPolicy Trusted
            }

        # Install silkiscsi and sdp from PSGallery; upgrade if an older version is already present
        $Modules = @("silkiscsi", "sdp")
        foreach ($Module in $Modules)
            {
                $LatestModule = Find-Module -Name $Module -Repository PSGallery -ErrorAction SilentlyContinue
                if ( !($FoundModule = Get-Module -ListAvailable -Name $Module | Select-Object -First 1 | Where-Object -FilterScript { $_.Version -ge $LatestModule.Version }) )
                    {
                        Write-Host $("Module {0} latest version {1} not found. Installing..." -f $LatestModule.Name, $LatestModule.Version)
                        Install-Module -Name $Module -MinimumVersion $LatestModule.Version -Force -Confirm:$false
                        $LatestModule = Get-Module -ListAvailable -Name $Module | Select-Object -First 1
                    }
                Write-Host $("Module {0} latest version {1} installed." -f $LatestModule.Name, $LatestModule.Version)
                if ( !(Get-Module -Name $Module) ) { Import-Module $Module }
            }
    }

#endregion

} # end function Invoke-SilkHostBestPractices


# Run the function, forwarding all parameters passed to the script
Invoke-SilkHostBestPractices @PSBoundParameters
