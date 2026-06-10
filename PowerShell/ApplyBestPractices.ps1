#Requires -RunAsAdministrator
#Requires -Version 5.1

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

    Use -AuditOnly to report compliance without making any changes.

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

.PARAMETER AuditOnly
    Reports compliance status without making any changes. No restart occurs.
    Script exits with code 1 if any settings are non-compliant.

.PARAMETER NoTranscript
    Disables session transcript logging. By default a timestamped log is written to $env:TEMP.

.EXAMPLE
    .\ApplyBestPractices.ps1

    Attended run with no route configuration. Applies all MPIO/MSDSM best practices,
    starts the iSCSI service, displays the host IQN, and prompts the operator before
    each required restart. This is the typical starting point for a new host.

.EXAMPLE
    .\ApplyBestPractices.ps1 -iSCSInicGateway 10.2.0.1 -DataSubnet 10.2.3.0 -DataSubnetMask 255.255.255.240 -InstallPWSHModules -AutoRestart

    Full automated deployment: applies all best practices, adds a persistent static route
    to the Silk data subnet, installs required PowerShell modules, and restarts without
    prompting. Use this form in RMM tools or deployment scripts.

.EXAMPLE
    .\ApplyBestPractices.ps1 -AutoRestart

    Minimal automated run. Applies MPIO/MSDSM best practices and restarts without
    prompting. Skips route configuration and module installation.

.EXAMPLE
    .\ApplyBestPractices.ps1 -AuditOnly

    Reports current compliance status without making any changes. Use before or after
    deployment to verify the host meets Silk best practices. Exits with code 1 if any
    settings are non-compliant.

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
    [switch] $InstallPWSHModules,
    [Parameter()]
    [switch] $AuditOnly,
    [Parameter()]
    [switch] $NoTranscript
)


#region Preflight

$transcriptStarted = $false
if ( !$NoTranscript )
    {
        $transcriptFile = $("{0}\SilkBestPractices_{1}.log" -f $env:TEMP, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Start-Transcript -Path $transcriptFile -Append | Out-Null
        $transcriptStarted = $true
        Write-Host $("Transcript: {0}" -f $transcriptFile)
    }

# Get-WindowsFeature / Add-WindowsFeature only exist on Server editions.
$osProductType = (Get-CimInstance Win32_OperatingSystem).ProductType
if ( $osProductType -eq 1 )
    {
        Write-Error $("This script requires Windows Server. Detected desktop OS (ProductType={0})." -f $osProductType)
        if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
        return
    }

$restartRequired = $false
$auditIssues     = [System.Collections.Generic.List[string]]::new()

#endregion


#region MPIO Windows Feature

# MPIO must be installed before MSDSM cmdlets and Set-MPIOSetting are available.
# The feature requires a restart before it is active; the script exits immediately after.
$mpioFeature = Get-WindowsFeature -Name Multipath-IO

if ( !$mpioFeature.Installed )
    {
        if ( $AuditOnly )
            {
                Write-Host $("AUDIT: MPIO feature: NOT INSTALLED")
                $auditIssues.Add($("MPIO feature not installed"))
            }
        else
            {
                Write-Host $("MPIO feature: not installed. Installing...")
                try
                    {
                        Add-WindowsFeature Multipath-IO -IncludeAllSubFeature -IncludeManagementTools -ErrorAction Stop | Out-Null
                        Write-Host $("MPIO feature: installed.")
                    }
                catch
                    {
                        Write-Error $("Failed to install MPIO feature: {0}" -f $_.Exception.Message)
                        if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
                        return
                    }
                if ( !$AutoRestart ) { Read-Host -Prompt "Restart required. Press Enter to restart or Ctrl+C to exit." }
                if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
                Restart-Computer -Force
                return
            }
    }
else
    {
        Write-Host $("MPIO feature: installed.")
    }

#endregion


#region MSDSM and MPIO Settings

if ( $mpioFeature.Installed )
    {
        # All state captured upfront so the compliance check and every inner check
        # read from the same snapshot — no short-circuit evaluation side effects.
        $MSDSMSupportedHW                    = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9 -ErrorAction SilentlyContinue
        $MSDSMGlobalDefaultLoadBalancePolicy = Get-MSDSMGlobalDefaultLoadBalancePolicy
        $iSCSIMSDSMAutomaticClaimSettings    = (Get-MSDSMAutomaticClaimSettings)['iSCSI']
        $MPIOSettings                        = Get-MPIOSetting
        $ScheduledDefrag                     = Get-ScheduledTask -TaskName ScheduledDefrag
        $FSRegistry                          = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem"

        $msdsmCompliant = (
            $MSDSMSupportedHW -and
            $MSDSMGlobalDefaultLoadBalancePolicy      -eq 'LQD' -and
            $iSCSIMSDSMAutomaticClaimSettings -and
            $MPIOSettings.PathVerificationState       -eq "Enabled" -and
            $MPIOSettings.PathVerificationPeriod      -eq 1 -and
            $MPIOSettings.PDORemovePeriod             -eq 20 -and
            $MPIOSettings.RetryCount                  -eq 3 -and
            $MPIOSettings.RetryInterval               -eq 3 -and
            $MPIOSettings.UseCustomPathRecoveryTime   -eq "Enabled" -and
            $MPIOSettings.CustomPathRecoveryTime      -eq 20 -and
            $MPIOSettings.DiskTimeoutValue            -eq 100 -and
            $ScheduledDefrag.State                    -eq 'Disabled' -and
            $FSRegistry.DisableDeleteNotification     -eq 1
        )

        if ( !$msdsmCompliant )
            {
                # --- MSDSM: Supported Hardware ---
                # The MSFT2005/iSCSIBusType_0x9 entry tells MSDSM to claim iSCSI bus-type devices.
                if ( !$MSDSMSupportedHW )
                    {
                        if ( $AuditOnly )
                            {
                                Write-Host $("AUDIT: MSDSM Supported Hardware (MSFT2005/iSCSIBusType_0x9): MISSING")
                                $auditIssues.Add($("MSDSM Supported Hardware entry missing"))
                            }
                        else
                            {
                                New-MSDSMSupportedHW -VendorID MSFT2005 -Product iSCSIBusType_0x9
                                $MSDSMSupportedHW = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9
                                Write-Host $("MSDSM Supported Hardware {0}/{1}: added" -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
                                $restartRequired = $true
                            }
                    }
                else
                    {
                        Write-Host $("MSDSM Supported Hardware {0}/{1}: present" -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
                    }

                # --- MSDSM: Load Balance Policy ---
                # LQD (Least Queue Depth) is the Silk-recommended policy for iSCSI multipathing.
                if ( $MSDSMGlobalDefaultLoadBalancePolicy -ne 'LQD' )
                    {
                        if ( $AuditOnly )
                            {
                                Write-Host $("AUDIT: MPIO Load Balance Policy: {0} (expected: LQD)" -f $MSDSMGlobalDefaultLoadBalancePolicy)
                                $auditIssues.Add($("Load balance policy is {0}" -f $MSDSMGlobalDefaultLoadBalancePolicy))
                            }
                        else
                            {
                                Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
                                Write-Host $("MPIO Load Balance Policy: set to {0}" -f (Get-MSDSMGlobalDefaultLoadBalancePolicy))
                                $restartRequired = $true
                            }
                    }
                else
                    {
                        Write-Host $("MPIO Load Balance Policy: {0}" -f $MSDSMGlobalDefaultLoadBalancePolicy)
                    }

                # --- MSDSM: Automatic iSCSI Claim ---
                if ( !$iSCSIMSDSMAutomaticClaimSettings )
                    {
                        if ( $AuditOnly )
                            {
                                Write-Host $("AUDIT: MSDSM Automatic iSCSI Claim: not enabled")
                                $auditIssues.Add($("MSDSM automatic iSCSI claim not enabled"))
                            }
                        else
                            {
                                Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
                                Write-Host $("MSDSM Automatic iSCSI Claim: set to {0}" -f (Get-MSDSMAutomaticClaimSettings)['iSCSI'])
                                $restartRequired = $true
                            }
                    }
                else
                    {
                        Write-Host $("MSDSM Automatic iSCSI Claim: {0}" -f $iSCSIMSDSMAutomaticClaimSettings)
                    }

                # --- MPIO Settings ---
                # Keyed ordered map so output is consistent and each setting applies via splatting.
                # Variable name $mpioSettingsMap avoids collision with $MPIOSettings (Get-MPIOSetting result).
                $mpioSettingsMap = [ordered]@{
                    PathVerificationState     = @{ Current = $MPIOSettings.PathVerificationState;     Expected = "Enabled"; SetParam = "NewPathVerificationState"  }
                    PathVerificationPeriod    = @{ Current = $MPIOSettings.PathVerificationPeriod;    Expected = 1;         SetParam = "NewPathVerificationPeriod"  }
                    PDORemovePeriod           = @{ Current = $MPIOSettings.PDORemovePeriod;           Expected = 20;        SetParam = "NewPDORemovePeriod"         }
                    RetryCount                = @{ Current = $MPIOSettings.RetryCount;                Expected = 3;         SetParam = "NewRetryCount"              }
                    RetryInterval             = @{ Current = $MPIOSettings.RetryInterval;             Expected = 3;         SetParam = "newRetryInterval"           }
                    UseCustomPathRecoveryTime = @{ Current = $MPIOSettings.UseCustomPathRecoveryTime; Expected = "Enabled"; SetParam = "CustomPathRecovery"         }
                    CustomPathRecoveryTime    = @{ Current = $MPIOSettings.CustomPathRecoveryTime;    Expected = 20;        SetParam = "NewPathRecoveryInterval"    }
                    DiskTimeoutValue          = @{ Current = $MPIOSettings.DiskTimeoutValue;          Expected = 100;       SetParam = "NewDiskTimeout"             }
                }

                foreach ( $entry in $mpioSettingsMap.GetEnumerator() )
                    {
                        if ( $entry.Value.Current -ne $entry.Value.Expected )
                            {
                                if ( $AuditOnly )
                                    {
                                        Write-Host $("AUDIT: MPIO {0}: {1} (expected: {2})" -f $entry.Key, $entry.Value.Current, $entry.Value.Expected)
                                        $auditIssues.Add($("MPIO {0} is {1}" -f $entry.Key, $entry.Value.Current))
                                    }
                                else
                                    {
                                        Set-MPIOSetting @{ $entry.Value.SetParam = $entry.Value.Expected }
                                        Write-Host $("MPIO {0}: set to {1}" -f $entry.Key, $entry.Value.Expected)
                                        $restartRequired = $true
                                    }
                            }
                        else
                            {
                                Write-Host $("MPIO {0}: {1}" -f $entry.Key, $entry.Value.Current)
                            }
                    }

                # --- Scheduled Defrag ---
                # Disk defragmentation must be disabled; it can disrupt MPIO path recovery timing.
                if ( $ScheduledDefrag.State -ne 'Disabled' )
                    {
                        if ( $AuditOnly )
                            {
                                Write-Host $("AUDIT: ScheduledDefrag: {0} (expected: Disabled)" -f $ScheduledDefrag.State)
                                $auditIssues.Add($("ScheduledDefrag state is {0}" -f $ScheduledDefrag.State))
                            }
                        else
                            {
                                Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask | Out-Null
                                Write-Host $("ScheduledDefrag: disabled")
                                $restartRequired = $true
                            }
                    }
                else
                    {
                        Write-Host $("ScheduledDefrag: Disabled")
                    }

                # --- TRIM/UNMAP Disable ---
                # Prevents Windows from issuing TRIM/UNMAP commands to the storage target;
                # the Silk array manages reclamation independently.
                if ( $FSRegistry.DisableDeleteNotification -ne 1 )
                    {
                        if ( $AuditOnly )
                            {
                                Write-Host $("AUDIT: DisableDeleteNotification: {0} (expected: 1)" -f $FSRegistry.DisableDeleteNotification)
                                $auditIssues.Add($("DisableDeleteNotification is {0}" -f $FSRegistry.DisableDeleteNotification))
                            }
                        else
                            {
                                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name DisableDeleteNotification -Value 1
                                Write-Host $("DisableDeleteNotification: set to 1")
                                $restartRequired = $true
                            }
                    }
                else
                    {
                        Write-Host $("DisableDeleteNotification: 1")
                    }

                if ( !$AuditOnly -and $restartRequired )
                    {
                        if ( !$AutoRestart ) { Read-Host -Prompt "Settings changed — restart required. Press Enter to restart or Ctrl+C to exit." }
                        if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
                        Restart-Computer -Force
                        return
                    }
            }
        else
            {
                Write-Host $("MSDSM Supported Hardware {0}/{1}: present" -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
                Write-Host $("MPIO Load Balance Policy: {0}" -f $MSDSMGlobalDefaultLoadBalancePolicy)
                Write-Host $("MSDSM Automatic iSCSI Claim: {0}" -f $iSCSIMSDSMAutomaticClaimSettings)
                Write-Host $("MPIO PathVerificationState: {0}" -f $MPIOSettings.PathVerificationState)
                Write-Host $("MPIO PathVerificationPeriod: {0}" -f $MPIOSettings.PathVerificationPeriod)
                Write-Host $("MPIO PDORemovePeriod: {0}" -f $MPIOSettings.PDORemovePeriod)
                Write-Host $("MPIO RetryCount: {0}" -f $MPIOSettings.RetryCount)
                Write-Host $("MPIO RetryInterval: {0}" -f $MPIOSettings.RetryInterval)
                Write-Host $("MPIO UseCustomPathRecoveryTime: {0}" -f $MPIOSettings.UseCustomPathRecoveryTime)
                Write-Host $("MPIO CustomPathRecoveryTime: {0}" -f $MPIOSettings.CustomPathRecoveryTime)
                Write-Host $("MPIO DiskTimeoutValue: {0}" -f $MPIOSettings.DiskTimeoutValue)
                Write-Host $("ScheduledDefrag: {0}" -f $ScheduledDefrag.State)
                Write-Host $("DisableDeleteNotification: {0}" -f $FSRegistry.DisableDeleteNotification)
                Write-Host $("All MSDSM and MPIO settings compliant.")
            }
    }

#endregion


#region iSCSI Initiator Service

$iSCSIService = Get-Service MSiSCSI

if ( $iSCSIService.Status -ne 'Running' )
    {
        if ( $AuditOnly )
            {
                Write-Host $("AUDIT: iSCSI service status: {0} (expected: Running)" -f $iSCSIService.Status)
                $auditIssues.Add($("iSCSI service not running"))
            }
        else
            {
                Start-Service MSiSCSI
                Write-Host $("iSCSI service: started ({0})" -f (Get-Service MSiSCSI).Status)
            }
    }
else
    {
        Write-Host $("iSCSI service status: {0}" -f $iSCSIService.Status)
    }

if ( $iSCSIService.StartType -ne 'Automatic' )
    {
        if ( $AuditOnly )
            {
                Write-Host $("AUDIT: iSCSI service startup type: {0} (expected: Automatic)" -f $iSCSIService.StartType)
                $auditIssues.Add($("iSCSI service startup type is {0}" -f $iSCSIService.StartType))
            }
        else
            {
                $iSCSIService | Set-Service -StartupType Automatic
                Write-Host $("iSCSI service startup type: set to Automatic")
            }
    }
else
    {
        Write-Host $("iSCSI service startup type: {0}" -f $iSCSIService.StartType)
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
        $iSCSIInterfaceIndex = (Find-NetRoute -RemoteIPAddress $iSCSInicGateway.IPAddressToString | Select-Object -First 1).InterfaceIndex
        $RouteParams = @{
            DestinationPrefix = $("{0}/{1}" -f $DataSubnet.IPAddressToString, $PrefixLength)
            NextHop           = $iSCSInicGateway.IPAddressToString
            InterfaceIndex    = $iSCSIInterfaceIndex
            RouteMetric       = 1
            PolicyStore       = 'PersistentStore'
        }

        if ( !(Get-NetRoute -DestinationPrefix $RouteParams.DestinationPrefix -NextHop $RouteParams.NextHop -ErrorAction SilentlyContinue) )
            {
                if ( $AuditOnly )
                    {
                        Write-Host $("AUDIT: Persistent route {0} via {1}: missing" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)
                        $auditIssues.Add($("Persistent route {0} missing" -f $RouteParams.DestinationPrefix))
                    }
                else
                    {
                        try
                            {
                                New-NetRoute @RouteParams | Out-Null
                                Write-Host $("Persistent route added: {0} via {1}" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)
                            }
                        catch
                            {
                                Write-Error $("Failed to add route {0}: {1}" -f $RouteParams.DestinationPrefix, $_.Exception.Message)
                            }
                    }
            }
        else
            {
                Write-Host $("Persistent route: {0} via {1}" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)
            }
    }

#endregion


#region Host IQN

# The IQN must be registered in the Silk portal before iSCSI sessions can be established.
$HostIQN = (Get-InitiatorPort | Where-Object { $_.ConnectionType -eq 'iSCSI' } | Select-Object -First 1).NodeAddress

if ( [string]::IsNullOrEmpty($HostIQN) )
    {
        Write-Host $("Host iSCSI IQN: not found — confirm the iSCSI initiator service is running and a port is available.")
    }
else
    {
        Write-Host $("Host iSCSI IQN: {0}`n" -f $HostIQN)
    }

if ( !$AutoRestart -and !$AuditOnly )
    {
        Read-Host -Prompt "Record the IQN above, then press Enter to continue"
    }

#endregion


#region PowerShell Module Installation

if ( $InstallPWSHModules -and !$AuditOnly )
    {
        # Ensure NuGet provider is available — required by Install-Module from PSGallery
        if ( !($NuGetVersion = Get-PackageProvider | Where-Object -FilterScript { $_.Name -eq "NuGet" -and $_.Version -ge 2.8.5.201 }) )
            {
                Write-Host $("NuGet Package Provider not found. Installing...")
                try
                    {
                        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop
                    }
                catch
                    {
                        Write-Error $("Failed to install NuGet provider: {0}" -f $_.Exception.Message)
                        if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
                        return
                    }
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
                $LatestModule = $null
                try
                    {
                        $LatestModule = Find-Module -Name $Module -Repository PSGallery -ErrorAction Stop
                    }
                catch
                    {
                        Write-Error $("Could not reach PSGallery for module '{0}': {1}" -f $Module, $_.Exception.Message)
                        continue
                    }

                if ( !($FoundModule = Get-Module -ListAvailable -Name $Module | Select-Object -First 1 | Where-Object -FilterScript { $_.Version -ge $LatestModule.Version }) )
                    {
                        Write-Host $("Module {0} version {1}: installing..." -f $LatestModule.Name, $LatestModule.Version)
                        try
                            {
                                Install-Module -Name $Module -MinimumVersion $LatestModule.Version -Force -Confirm:$false -ErrorAction Stop
                                $LatestModule = Get-Module -ListAvailable -Name $Module | Select-Object -First 1
                            }
                        catch
                            {
                                Write-Error $("Failed to install module '{0}': {1}" -f $Module, $_.Exception.Message)
                                continue
                            }
                    }
                Write-Host $("Module {0} version {1}: installed." -f $LatestModule.Name, $LatestModule.Version)
                if ( !(Get-Module -Name $Module) ) { Import-Module $Module }
            }
    }

#endregion


#region Audit Summary

if ( $AuditOnly )
    {
        Write-Host $("")
        if ( $auditIssues.Count -eq 0 )
            {
                Write-Host $("AUDIT COMPLETE: Host is fully compliant. No changes required.")
            }
        else
            {
                Write-Host $("AUDIT COMPLETE: {0} issue(s) found:" -f $auditIssues.Count)
                foreach ($issue in $auditIssues)
                    {
                        Write-Host $("  - {0}" -f $issue)
                    }
            }
    }

#endregion


if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
if ( $AuditOnly ) { return $auditIssues.Count }

} # end function Invoke-SilkHostBestPractices


# Run the function, forwarding all parameters passed to the script
$silkResult = Invoke-SilkHostBestPractices @PSBoundParameters
if ( $PSBoundParameters.ContainsKey('AuditOnly') -and ($null -ne $silkResult) -and ($silkResult -gt 0) )
    {
        exit 1
    }
