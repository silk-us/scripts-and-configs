#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding(DefaultParameterSetName='Apply')]
param(
    [Parameter()]
    [ipaddress] $iSCSInicGateway,
    [Parameter()]
    [ipaddress] $DataSubnet,
    [Parameter()]
    [ValidateSet("255.255.255.240", "255.255.255.224", "255.255.255.128")]
    [ipaddress] $DataSubnetMask,
    [Parameter(ParameterSetName='Apply')]
    [switch] $AutoRestart,
    [Parameter()]
    [switch] $InstallPWSHModules,
    [Parameter(ParameterSetName='Audit')]
    [switch] $AuditOnly,
    [Parameter()]
    [switch] $NoTranscript
)


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
    (Apply mode) Suppresses the interactive confirmation prompt before each required restart.
    Omit for attended use; include for automated/unattended deployments.
    Cannot be combined with -AuditOnly.

.PARAMETER InstallPWSHModules
    Apply mode: installs or upgrades the silkiscsi and sdp PowerShell modules from PSGallery.
    Audit mode: reports installed version vs PSGallery latest for each module.
    Requires outbound internet access to PSGallery.

.PARAMETER AuditOnly
    (Audit mode) Reports compliance status without making any changes. No restart occurs.
    Script exits with code 1 if any settings are non-compliant.
    Cannot be combined with -AutoRestart.

.PARAMETER NoTranscript
    Disables session transcript logging. By default a timestamped log is written to $env:TEMP.

.EXAMPLE
    .\Invoke-SilkHostBestPractices.ps1

    Attended run with no route configuration. Applies all MPIO/MSDSM best practices,
    starts the iSCSI service, displays the host IQN, and prompts the operator before
    each required restart. This is the typical starting point for a new host.

.EXAMPLE
    .\Invoke-SilkHostBestPractices.ps1 -iSCSInicGateway 10.2.0.1 -DataSubnet 10.2.3.0 -DataSubnetMask 255.255.255.240 -InstallPWSHModules -AutoRestart

    Full automated deployment: applies all best practices, adds a persistent static route
    to the Silk data subnet, installs required PowerShell modules, and restarts without
    prompting. Use this form in RMM tools or deployment scripts.

.EXAMPLE
    .\Invoke-SilkHostBestPractices.ps1 -AutoRestart

    Minimal automated run. Applies MPIO/MSDSM best practices and restarts without
    prompting. Skips route configuration and module installation.

.EXAMPLE
    .\Invoke-SilkHostBestPractices.ps1 -AuditOnly

    Reports current compliance status without making any changes. Use before or after
    deployment to verify the host meets Silk best practices. Exits with code 1 if any
    settings are non-compliant.

.NOTES
    Must be run as Administrator.
    After an MPIO feature install restart, re-run this script to complete configuration.
    Can also be dot-sourced and called directly: . .\Invoke-SilkHostBestPractices.ps1; Invoke-SilkHostBestPractices @params
#>
[CmdletBinding(DefaultParameterSetName='Apply')]
param(
    [Parameter()]
    [ipaddress] $iSCSInicGateway,
    [Parameter()]
    [ipaddress] $DataSubnet,
    [Parameter()]
    [ValidateSet("255.255.255.240", "255.255.255.224", "255.255.255.128")]
    [ipaddress] $DataSubnetMask,
    [Parameter(ParameterSetName='Apply')]
    [switch] $AutoRestart,
    [Parameter()]
    [switch] $InstallPWSHModules,
    [Parameter(ParameterSetName='Audit')]
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
$Report          = [System.Collections.Generic.List[PSCustomObject]]::new()

#endregion


#region MPIO Windows Feature

# MPIO must be installed before MSDSM cmdlets and Set-MPIOSetting are available.
# The feature requires a restart before it is active; the script exits immediately after.
$mpioFeature = Get-WindowsFeature -Name Multipath-IO

$Report.Add([PSCustomObject]@{
    Section  = $("MPIO Feature")
    Name     = $("Multipath-IO Feature")
    Current  = if ($mpioFeature.Installed) { $("Installed") } else { $("Not installed") }
    Expected = $("Installed")
    Status   = if ($mpioFeature.Installed) { $("Pass") } else { $("Fail") }
})

if ( !$mpioFeature.Installed )
    {
        if ( $AuditOnly )
            {
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

#endregion


#region MSDSM and MPIO Settings

if ( $mpioFeature.Installed )
    {
        # All state captured upfront so the compliance check and every inner check
        # read from the same snapshot - no short-circuit evaluation side effects.
        $MSDSMSupportedHW                    = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9 -ErrorAction SilentlyContinue
        $MSDSMGlobalDefaultLoadBalancePolicy = Get-MSDSMGlobalDefaultLoadBalancePolicy
        $iSCSIMSDSMAutomaticClaimSettings    = (Get-MSDSMAutomaticClaimSettings)['iSCSI']
        $MPIOSettings                        = Get-MPIOSetting
        $ScheduledDefrag                     = Get-ScheduledTask -TaskName ScheduledDefrag
        $FSRegistry                          = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem"

        # Keyed ordered map defined at section scope so it is available for report building
        # and apply logic. Variable name $mpioSettingsMap avoids collision with $MPIOSettings.
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

        # Build report items from snapshot before any changes are applied.
        # Current values always reflect the state at script entry, making the report
        # accurate for both audit (compliance check) and apply (before/after reference).
        $Report.Add([PSCustomObject]@{
            Section  = $("MSDSM / MPIO Settings")
            Name     = $("Supported Hardware")
            Current  = if ($MSDSMSupportedHW) { $("{0}/{1}" -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId) } else { $("Missing") }
            Expected = $("MSFT2005/iSCSIBusType_0x9")
            Status   = if ($MSDSMSupportedHW) { $("Pass") } else { $("Fail") }
        })
        $Report.Add([PSCustomObject]@{
            Section  = $("MSDSM / MPIO Settings")
            Name     = $("Load Balance Policy")
            Current  = $MSDSMGlobalDefaultLoadBalancePolicy
            Expected = $("LQD")
            Status   = if ($MSDSMGlobalDefaultLoadBalancePolicy -eq 'LQD') { $("Pass") } else { $("Fail") }
        })
        $Report.Add([PSCustomObject]@{
            Section  = $("MSDSM / MPIO Settings")
            Name     = $("Automatic iSCSI Claim")
            Current  = $("{0}" -f $iSCSIMSDSMAutomaticClaimSettings)
            Expected = $("True")
            Status   = if ($iSCSIMSDSMAutomaticClaimSettings) { $("Pass") } else { $("Fail") }
        })
        foreach ( $entry in $mpioSettingsMap.GetEnumerator() )
            {
                $Report.Add([PSCustomObject]@{
                    Section  = $("MSDSM / MPIO Settings")
                    Name     = $entry.Key
                    Current  = $("{0}" -f $entry.Value.Current)
                    Expected = $("{0}" -f $entry.Value.Expected)
                    Status   = if ($entry.Value.Current -eq $entry.Value.Expected) { $("Pass") } else { $("Fail") }
                })
            }
        $Report.Add([PSCustomObject]@{
            Section  = $("MSDSM / MPIO Settings")
            Name     = $("ScheduledDefrag")
            Current  = $("{0}" -f $ScheduledDefrag.State)
            Expected = $("Disabled")
            Status   = if ($ScheduledDefrag.State -eq 'Disabled') { $("Pass") } else { $("Fail") }
        })
        $Report.Add([PSCustomObject]@{
            Section  = $("MSDSM / MPIO Settings")
            Name     = $("DisableDeleteNotification")
            Current  = $("{0}" -f $FSRegistry.DisableDeleteNotification)
            Expected = $("1")
            Status   = if ($FSRegistry.DisableDeleteNotification -eq 1) { $("Pass") } else { $("Fail") }
        })

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
                if ( $AuditOnly )
                    {
                        # Collect audit issue strings - the report handles all output.
                        if ( !$MSDSMSupportedHW )
                            { $auditIssues.Add($("MSDSM Supported Hardware entry missing")) }
                        if ( $MSDSMGlobalDefaultLoadBalancePolicy -ne 'LQD' )
                            { $auditIssues.Add($("Load balance policy is {0}" -f $MSDSMGlobalDefaultLoadBalancePolicy)) }
                        if ( !$iSCSIMSDSMAutomaticClaimSettings )
                            { $auditIssues.Add($("MSDSM automatic iSCSI claim not enabled")) }
                        foreach ( $entry in $mpioSettingsMap.GetEnumerator() )
                            {
                                if ( $entry.Value.Current -ne $entry.Value.Expected )
                                    { $auditIssues.Add($("MPIO {0} is {1}" -f $entry.Key, $entry.Value.Current)) }
                            }
                        if ( $ScheduledDefrag.State -ne 'Disabled' )
                            { $auditIssues.Add($("ScheduledDefrag state is {0}" -f $ScheduledDefrag.State)) }
                        if ( $FSRegistry.DisableDeleteNotification -ne 1 )
                            { $auditIssues.Add($("DisableDeleteNotification is {0}" -f $FSRegistry.DisableDeleteNotification)) }
                    }
                else
                    {
                        # --- MSDSM: Supported Hardware ---
                        # The MSFT2005/iSCSIBusType_0x9 entry tells MSDSM to claim iSCSI bus-type devices.
                        if ( !$MSDSMSupportedHW )
                            {
                                New-MSDSMSupportedHW -VendorID MSFT2005 -Product iSCSIBusType_0x9
                                $MSDSMSupportedHW = Get-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9
                                Write-Host $("MSDSM Supported Hardware {0}/{1}: added" -f $MSDSMSupportedHW.VendorId, $MSDSMSupportedHW.ProductId)
                                $restartRequired = $true
                            }

                        # --- MSDSM: Load Balance Policy ---
                        # LQD (Least Queue Depth) is the Silk-recommended policy for iSCSI multipathing.
                        if ( $MSDSMGlobalDefaultLoadBalancePolicy -ne 'LQD' )
                            {
                                Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
                                Write-Host $("MPIO Load Balance Policy: set to {0}" -f (Get-MSDSMGlobalDefaultLoadBalancePolicy))
                                $restartRequired = $true
                            }

                        # --- MSDSM: Automatic iSCSI Claim ---
                        if ( !$iSCSIMSDSMAutomaticClaimSettings )
                            {
                                Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
                                Write-Host $("MSDSM Automatic iSCSI Claim: set to {0}" -f (Get-MSDSMAutomaticClaimSettings)['iSCSI'])
                                $restartRequired = $true
                            }

                        # --- MPIO Settings ---
                        foreach ( $entry in $mpioSettingsMap.GetEnumerator() )
                            {
                                if ( $entry.Value.Current -ne $entry.Value.Expected )
                                    {
                                        Set-MPIOSetting @{ $entry.Value.SetParam = $entry.Value.Expected }
                                        Write-Host $("MPIO {0}: set to {1}" -f $entry.Key, $entry.Value.Expected)
                                        $restartRequired = $true
                                    }
                            }

                        # --- Scheduled Defrag ---
                        # Disk defragmentation must be disabled; it can disrupt MPIO path recovery timing.
                        if ( $ScheduledDefrag.State -ne 'Disabled' )
                            {
                                Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask | Out-Null
                                Write-Host $("ScheduledDefrag: disabled")
                                $restartRequired = $true
                            }

                        # --- TRIM/UNMAP Disable ---
                        # Prevents Windows from issuing TRIM/UNMAP commands to the storage target;
                        # the Silk array manages reclamation independently.
                        if ( $FSRegistry.DisableDeleteNotification -ne 1 )
                            {
                                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name DisableDeleteNotification -Value 1
                                Write-Host $("DisableDeleteNotification: set to 1")
                                $restartRequired = $true
                            }

                        if ( $restartRequired )
                            {
                                if ( !$AutoRestart ) { Read-Host -Prompt "Settings changed - restart required. Press Enter to restart or Ctrl+C to exit." }
                                if ( $transcriptStarted ) { Stop-Transcript | Out-Null }
                                Restart-Computer -Force
                                return
                            }
                    }
            }
    }

#endregion


#region iSCSI Initiator Service

$iSCSIService = Get-Service MSiSCSI

$Report.Add([PSCustomObject]@{
    Section  = $("iSCSI Service")
    Name     = $("Status")
    Current  = $("{0}" -f $iSCSIService.Status)
    Expected = $("Running")
    Status   = if ($iSCSIService.Status -eq 'Running') { $("Pass") } else { $("Fail") }
})
$Report.Add([PSCustomObject]@{
    Section  = $("iSCSI Service")
    Name     = $("Startup Type")
    Current  = $("{0}" -f $iSCSIService.StartType)
    Expected = $("Automatic")
    Status   = if ($iSCSIService.StartType -eq 'Automatic') { $("Pass") } else { $("Fail") }
})

if ( !$AuditOnly )
    {
        if ( $iSCSIService.Status -ne 'Running' )
            {
                Start-Service MSiSCSI
                Write-Host $("iSCSI service: started ({0})" -f (Get-Service MSiSCSI).Status)
            }
        if ( $iSCSIService.StartType -ne 'Automatic' )
            {
                $iSCSIService | Set-Service -StartupType Automatic
                Write-Host $("iSCSI service startup type: set to Automatic")
            }
    }
else
    {
        if ( $iSCSIService.Status -ne 'Running' )      { $auditIssues.Add($("iSCSI service not running")) }
        if ( $iSCSIService.StartType -ne 'Automatic' ) { $auditIssues.Add($("iSCSI service startup type is {0}" -f $iSCSIService.StartType)) }
    }

#endregion


#region Static Route to Data Subnet

# Adds a persistent (boot-surviving) route so iSCSI traffic to the Silk data subnet is
# directed through the iSCSI gateway rather than the default gateway.
# Find-NetRoute resolves the correct NIC interface index from the gateway IP alone.
$routeParamsProvided = @($DataSubnet, $DataSubnetMask, $iSCSInicGateway) | Where-Object { $_ }

if ( $routeParamsProvided.Count -gt 0 -and $routeParamsProvided.Count -lt 3 )
    {
        $Report.Add([PSCustomObject]@{
            Section  = $("Static Route")
            Name     = $("Route Parameters")
            Current  = $("Incomplete ({0}/3 provided)" -f $routeParamsProvided.Count)
            Expected = $("All 3 required")
            Status   = $("Warn")
        })
        Write-Warning $("Route configuration incomplete - all three params required: -iSCSInicGateway, -DataSubnet, -DataSubnetMask. Route skipped.")
    }

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

        $existingRoute = Get-NetRoute -DestinationPrefix $RouteParams.DestinationPrefix -NextHop $RouteParams.NextHop -ErrorAction SilentlyContinue
        $routeName     = $("{0} via {1}" -f $RouteParams.DestinationPrefix, $RouteParams.NextHop)

        $Report.Add([PSCustomObject]@{
            Section  = $("Static Route")
            Name     = $routeName
            Current  = if ($existingRoute) { $("Present") } else { $("Missing") }
            Expected = $("Present")
            Status   = if ($existingRoute) { $("Pass") } else { $("Fail") }
        })

        if ( !$existingRoute )
            {
                if ( $AuditOnly )
                    {
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
    }

#endregion


#region Host IQN

# The IQN must be registered in the Silk portal before iSCSI sessions can be established.
$HostIQN = (Get-InitiatorPort | Where-Object { $_.ConnectionType -eq 'iSCSI' } | Select-Object -First 1).NodeAddress

$Report.Add([PSCustomObject]@{
    Section  = $("Host IQN")
    Name     = $("iSCSI IQN")
    Current  = if ([string]::IsNullOrEmpty($HostIQN)) { $("Not found - confirm iSCSI service is running") } else { $HostIQN }
    Expected = $("N/A")
    Status   = $("Info")
})

if ( !$AuditOnly )
    {
        $iqnDisplay = if ([string]::IsNullOrEmpty($HostIQN)) { $("not found - confirm the iSCSI initiator service is running and a port is available.") } else { $HostIQN }
        Write-Host $("Host iSCSI IQN: {0}`n" -f $iqnDisplay)
        if ( !$AutoRestart ) { Read-Host -Prompt "Record the IQN above, then press Enter to continue" }
    }

#endregion


#region PowerShell Module Installation

$SilkModules = @("silkiscsi", "sdp")

if ( $AuditOnly )
    {
        # Always report module state in audit mode regardless of -InstallPWSHModules
        foreach ($Module in $SilkModules)
            {
                $InstalledModule = Get-Module -ListAvailable -Name $Module | Sort-Object Version -Descending | Select-Object -First 1
                $LatestModule    = $null
                try
                    {
                        $LatestModule = Find-Module -Name $Module -Repository PSGallery -ErrorAction Stop
                    }
                catch
                    {
                        $Report.Add([PSCustomObject]@{
                            Section  = $("PowerShell Modules")
                            Name     = $Module
                            Current  = if ($InstalledModule) { $("{0} (PSGallery unreachable)" -f $InstalledModule.Version) } else { $("Not installed (PSGallery unreachable)") }
                            Expected = $("N/A")
                            Status   = if ($InstalledModule) { $("Warn") } else { $("Fail") }
                        })
                        if ( !$InstalledModule ) { $auditIssues.Add($("Module {0} not installed" -f $Module)) }
                        continue
                    }

                if ( !$InstalledModule )
                    {
                        $Report.Add([PSCustomObject]@{
                            Section  = $("PowerShell Modules")
                            Name     = $Module
                            Current  = $("Not installed")
                            Expected = $("{0}" -f $LatestModule.Version)
                            Status   = $("Fail")
                        })
                        $auditIssues.Add($("Module {0} not installed" -f $Module))
                    }
                elseif ( $InstalledModule.Version -lt $LatestModule.Version )
                    {
                        $Report.Add([PSCustomObject]@{
                            Section  = $("PowerShell Modules")
                            Name     = $Module
                            Current  = $("{0}" -f $InstalledModule.Version)
                            Expected = $("{0}" -f $LatestModule.Version)
                            Status   = $("Warn")
                        })
                        $auditIssues.Add($("Module {0} outdated ({1} installed, {2} available)" -f $Module, $InstalledModule.Version, $LatestModule.Version))
                    }
                else
                    {
                        $Report.Add([PSCustomObject]@{
                            Section  = $("PowerShell Modules")
                            Name     = $Module
                            Current  = $("{0} (current)" -f $InstalledModule.Version)
                            Expected = $("{0}" -f $LatestModule.Version)
                            Status   = $("Pass")
                        })
                    }
            }
    }
elseif ( $InstallPWSHModules )
    {
        # Ensure NuGet provider is available - required by Install-Module from PSGallery
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
        foreach ($Module in $SilkModules)
            {
                $LatestModule = $null
                try
                    {
                        $LatestModule = Find-Module -Name $Module -Repository PSGallery -ErrorAction Stop
                    }
                catch
                    {
                        Write-Error $("Could not reach PSGallery for module '{0}': {1}" -f $Module, $_.Exception.Message)
                        $Report.Add([PSCustomObject]@{
                            Section  = $("PowerShell Modules")
                            Name     = $Module
                            Current  = $("PSGallery unreachable")
                            Expected = $("N/A")
                            Status   = $("Warn")
                        })
                        continue
                    }

                if ( !(Get-Module -ListAvailable -Name $Module | Select-Object -First 1 | Where-Object -FilterScript { $_.Version -ge $LatestModule.Version }) )
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
                                $Report.Add([PSCustomObject]@{
                                    Section  = $("PowerShell Modules")
                                    Name     = $Module
                                    Current  = $("Install failed")
                                    Expected = $("{0}" -f $LatestModule.Version)
                                    Status   = $("Error")
                                })
                                continue
                            }
                    }
                $Report.Add([PSCustomObject]@{
                    Section  = $("PowerShell Modules")
                    Name     = $Module
                    Current  = $("{0}" -f $LatestModule.Version)
                    Expected = $("{0}" -f $LatestModule.Version)
                    Status   = $("Pass")
                })
                Write-Host $("Module {0} version {1}: installed." -f $LatestModule.Name, $LatestModule.Version)
                if ( !(Get-Module -Name $Module) ) { Import-Module $Module }
            }
    }

#endregion


#region Report

$reportSeparator = $("=" * 72)
$modeLabel       = if ( $AuditOnly ) { $("Audit Report") } else { $("Apply Summary") }

Write-Host $("")
Write-Host $reportSeparator
Write-Host $("  Silk Host Best Practices - {0}" -f $modeLabel)
Write-Host $("  Host: {0}    {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host $reportSeparator

$currentSection = $("")
foreach ( $item in $Report )
    {
        if ( $item.Section -ne $currentSection )
            {
                $currentSection = $item.Section
                Write-Host $("")
                Write-Host $("  {0}" -f $currentSection)
            }

        $statusTag = switch ( $item.Status )
            {
                'Pass'  { if ( $AuditOnly ) { '[PASS]' } else { '[ OK ]' } }
                'Fail'  { if ( $AuditOnly ) { '[FAIL]' } else { '[CHGD]' } }
                'Warn'  { '[WARN]' }
                'Info'  { '[INFO]' }
                'Error' { '[ERR ]' }
                default { '[    ]' }
            }
        $color = switch ( $item.Status )
            {
                'Pass'  { 'Green' }
                'Fail'  { if ( $AuditOnly ) { 'Red' } else { 'Yellow' } }
                'Warn'  { 'Yellow' }
                'Info'  { 'Cyan' }
                'Error' { 'Red' }
                default { 'White' }
            }

        $nameCol = $("    {0}" -f $item.Name).PadRight(34)

        if ( $item.Status -eq 'Info' )
            {
                # Info items show value after the tag - IQNs can be long
                Write-Host $("{0}{1}  {2}" -f $nameCol, $statusTag, $item.Current) -ForegroundColor $color
            }
        elseif ( $item.Status -eq 'Pass' )
            {
                $currentCol = $("{0}" -f $item.Current).PadRight(26)
                Write-Host $("{0}{1}{2}" -f $nameCol, $currentCol, $statusTag) -ForegroundColor $color
            }
        else
            {
                $currentCol = $("{0}" -f $item.Current).PadRight(26)
                Write-Host $("{0}{1}{2}  (expected: {3})" -f $nameCol, $currentCol, $statusTag, $item.Expected) -ForegroundColor $color
            }
    }

$failCount = ($Report | Where-Object { $_.Status -eq 'Fail' }).Count
$warnCount = ($Report | Where-Object { $_.Status -eq 'Warn' }).Count

Write-Host $("")
Write-Host $reportSeparator

if ( $AuditOnly )
    {
        if ( $failCount -eq 0 -and $warnCount -eq 0 )
            {
                Write-Host $("  RESULT: Host is fully compliant. No changes required.") -ForegroundColor Green
            }
        else
            {
                Write-Host $("  RESULT: {0} issue(s) found." -f ($failCount + $warnCount)) -ForegroundColor Red
            }
    }
else
    {
        if ( $failCount -eq 0 )
            {
                Write-Host $("  RESULT: All settings already compliant. No changes made.") -ForegroundColor Green
            }
        else
            {
                Write-Host $("  RESULT: {0} setting(s) applied." -f $failCount) -ForegroundColor Yellow
            }
    }

Write-Host $reportSeparator

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
