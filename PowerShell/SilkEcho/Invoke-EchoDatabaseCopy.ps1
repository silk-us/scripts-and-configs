#Requires -Version 5.1
<#
.SYNOPSIS
    Presents a copy of one Silk Echo host's databases on one or more other hosts,
    creating the copies on the first run and refreshing them on every run after.

.DESCRIPTION
    A single entry point for an unattended job. It loads SilkEcho.psm1 from the
    same folder, connects to Flex, reconciles the destinations against the
    source, and exits with a status code the caller can branch on.

    Intended to be driven by a SQL Server Agent job step, which an external
    automation tool starts on demand or on a schedule to refresh an environment.

    HOW IT DECIDES WHAT TO DO

    The desired state is "these destination hosts present a copy of the source
    host's databases". Every run reads the current state of every host from the
    Echo API and does only what the difference calls for. Per database, per
    destination:

        absent from the destination     create it (clone)
        already there                   replace its volumes from the new
                                        snapshot (refresh)
        a copy whose source is gone     report it, or remove it with
                                        -RemoveOrphaned

    Whether Flex will accept an operation is Flex's call. Every mutation is put
    through the matching __validate endpoint first, so anything it will not do is
    reported in its own words before anything changes.

    Leave -SourceDatabase out and the source host's database list is read fresh
    on every run, so a database added there is picked up and one dropped there
    stops being copied, with no job definition to edit.

    ONE SNAPSHOT FOR EVERY DESTINATION

    -DestinationHost takes a list. All of them are served from a single snapshot,
    so ten environments cost one snapshot and one quiesce of the source, and all
    ten end up on identical data.

    WHEN THINGS GO WRONG

    Flex runs one operation at a time. A submission made while something else is
    running is accepted and then fails on a resource lock, so every step waits for
    the task queue to clear first, and any that fails anyway is resubmitted while
    watching the queue rather than sleeping. Destination hosts are independent:
    one that cannot be served is reported and the others still get refreshed.

    Exit codes:
        0   every destination succeeded
        1   bad parameters or a missing prerequisite
        2   could not reach or authenticate to Flex
        3   the copy failed, no destination was updated
        4   Flex stayed busy with other work, so nothing was attempted
        5   partial: some destinations were updated, some failed

.PARAMETER Server
    Flex hostname, FQDN or IP. Falls back to the FLEX_URL or FLEX_IP environment
    variable.

.PARAMETER Token
    A static Flex application token, generated in Flex. Falls back to the
    FLEX_TOKEN environment variable. Used exactly as supplied: this script does
    not store, cache or manage it.

.PARAMETER SourceHost
    Echo host holding the databases to copy.

.PARAMETER DestinationHost
    One or more Echo hosts that receive the copies, comma separated. All are
    served from the same snapshot.

.PARAMETER SourceDatabase
    Databases to copy, named explicitly. Omit to copy every database Echo can see
    on the source host, rediscovered on every run. Cannot be combined with
    -ExcludeDatabase.

.PARAMETER ExcludeDatabase
    Names to leave out of discovery. Only valid when -SourceDatabase is omitted.

.PARAMETER DestinationDatabase
    Explicit names for the copies, in the same order as -SourceDatabase. Requires
    -SourceDatabase and cannot be combined with -DestinationSuffix.

.PARAMETER DestinationSuffix
    Appended to each source database name to name the copy, for example _Dev
    turns SalesDB into SalesDB_Dev.

.PARAMETER RemoveOrphaned
    Delete copies on a destination whose source database no longer exists on the
    source host. Off by default, in which case they are reported and left alone.

.PARAMETER ConsistencyLevel
    application (default) or crash. See the README for which to pick.

.PARAMETER NoVss
    Take an application consistent snapshot without the Silk VSS provider.
    SQL Server 2022 and later support this.

.PARAMETER TargetState
    online (default) or recovery.

.PARAMETER SnapshotPrefix
    Snapshot name prefix. Derived from the first database in scope when omitted.


.PARAMETER SkipValidation
    Skip the Flex __validate call before each mutation. Faster, and the only way
    through if a Flex build's validation endpoint misbehaves, at the cost of
    Flex's own reason for a refusal arriving after the attempt instead of before.

.PARAMETER StepAttempts
    How many times to submit each operation before giving up on it. Default 3.

.PARAMETER IdleWaitMinutes
    How long to wait for the Flex task queue to clear before each step.
    Default 15. Zero exits with code 4 straight away when Flex is busy.

.PARAMETER SkipIdleCheck
    Do not wait for Flex to be idle. Only safe when nothing else uses this Flex.

.PARAMETER RequireValidCertificate
    Enforce certificate validation. Off by default: Flex ships a self signed
    certificate and this runs unattended, so a flag that would be passed on every
    run would only mean the first scheduled run fails with nobody there.

.PARAMETER PollSeconds
    How often to look at the Flex task queue, in seconds. Default 2.

.PARAMETER TimeoutMinutes
    How long to wait for any single Echo task. Default 15.

.EXAMPLE
    # Every database on sql-prod, presented on sql-dev. Same command every run.
    .\Invoke-EchoDatabaseCopy.ps1 -Server flex.contoso.com -Token $token `
        -SourceHost sql-prod -DestinationHost sql-dev

.EXAMPLE
    # Several environments, all from one snapshot, mirroring source drops.
    .\Invoke-EchoDatabaseCopy.ps1 -Server flex.contoso.com -Token $token `
        -SourceHost sql-prod -DestinationHost sql-dev,sql-qa,sql-uat `
        -RemoveOrphaned

.EXAMPLE
    # Show what would change, without changing anything
    .\Invoke-EchoDatabaseCopy.ps1 -Server flex.contoso.com -Token $token `
        -SourceHost sql-prod -DestinationHost sql-dev -WhatIf

.NOTES
    Requires nothing beyond Windows PowerShell 5.1 and network access to Flex.
    It talks only to the Echo API: no database engine is contacted, no T-SQL is
    issued, and nothing is discovered on either host.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Server,

    [string]$Token,

    [Parameter(Mandatory = $true)]
    [string]$SourceHost,

    [Parameter(Mandatory = $true)]
    [string[]]$DestinationHost,

    [string[]]$SourceDatabase,

    [string[]]$ExcludeDatabase,

    [string[]]$DestinationDatabase,

    [string]$DestinationSuffix,

    [switch]$RemoveOrphaned,

    [switch]$SkipValidation,

    [ValidateSet('application', 'crash')]
    [string]$ConsistencyLevel = 'application',

    [switch]$NoVss,

    [ValidateSet('online', 'recovery')]
    [string]$TargetState = 'online',

    [string]$SnapshotPrefix,

    [ValidateRange(1, 20)]
    [int]$StepAttempts = 3,

    [ValidateRange(0, 240)]
    [int]$IdleWaitMinutes = 15,

    [switch]$SkipIdleCheck,

    [switch]$RequireValidCertificate,

    [ValidateRange(1, 300)]
    [int]$PollSeconds = 2,

    [ValidateRange(1, 240)]
    [int]$TimeoutMinutes = 15
)

$ErrorActionPreference = 'Stop'

# A CmdExec job step passes one flat string, and callers vary in whether they
# split lists. Accept "a,b" as well as a,b for every list parameter.
function Expand-NameList {
    param([string[]]$Value)

    if (-not $Value) { return @() }

    return @(
        $Value |
            Where-Object { $null -ne $_ } |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

try {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'SilkEcho.psm1'
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-Error -ErrorAction Continue -Message "SilkEcho.psm1 was not found next to this script (looked in '$PSScriptRoot'). Keep the two files together."
        exit 1
    }
    Import-Module $modulePath -Force -DisableNameChecking

    $DestinationHost     = Expand-NameList -Value $DestinationHost
    $SourceDatabase      = Expand-NameList -Value $SourceDatabase
    $ExcludeDatabase     = Expand-NameList -Value $ExcludeDatabase
    $DestinationDatabase = Expand-NameList -Value $DestinationDatabase

    if (-not $DestinationHost) {
        Write-Error -ErrorAction Continue -Message 'At least one destination host is required.'
        exit 1
    }
    if ($SourceDatabase -and $ExcludeDatabase) {
        Write-Error -ErrorAction Continue -Message '-SourceDatabase names the databases to copy and -ExcludeDatabase filters a discovered list. Use one or the other.'
        exit 1
    }
    if ($DestinationDatabase -and $DestinationSuffix) {
        Write-Error -ErrorAction Continue -Message 'Use either -DestinationDatabase or -DestinationSuffix, not both.'
        exit 1
    }
    if ($DestinationDatabase -and -not $SourceDatabase) {
        Write-Error -ErrorAction Continue -Message '-DestinationDatabase names each copy, so it needs -SourceDatabase to line up against. Use -DestinationSuffix to rename a discovered set.'
        exit 1
    }
}
catch {
    Write-Error -ErrorAction Continue -Message "Startup failed: $($_.Exception.Message)"
    exit 1
}

# -- Connect -------------------------------------------------------------------
try {
    $connectArgs = @{
        RequireValidCertificate = $RequireValidCertificate
        PollSeconds             = $PollSeconds
        TimeoutMinutes          = $TimeoutMinutes
        IdleWaitMinutes         = $IdleWaitMinutes
        SkipIdleCheck           = $SkipIdleCheck
    }
    if ($Server) { $connectArgs.Server = $Server }
    if ($Token)  { $connectArgs.Token = $Token }

    $null = Connect-SilkFlex @connectArgs
}
catch {
    Write-Error -ErrorAction Continue -Message "Could not connect to Flex: $($_.Exception.Message)"
    exit 2
}

# -- Copy ----------------------------------------------------------------------
$exitCode = 0

try {
    $copyArgs = @{
        SourceHost                = $SourceHost
        DestinationHost           = $DestinationHost
        ConsistencyLevel          = $ConsistencyLevel
        TargetState               = $TargetState
        NoVss                     = $NoVss
        RemoveOrphaned            = $RemoveOrphaned
        SkipValidation            = $SkipValidation
        StepAttempts              = $StepAttempts
        Confirm                   = $false
        WhatIf                    = $WhatIfPreference
    }
    if ($SourceDatabase)      { $copyArgs.SourceDatabase = $SourceDatabase }
    if ($ExcludeDatabase)     { $copyArgs.ExcludeDatabase = $ExcludeDatabase }
    if ($DestinationDatabase) { $copyArgs.DestinationDatabase = $DestinationDatabase }
    if ($DestinationSuffix)   { $copyArgs.DestinationSuffix = $DestinationSuffix }
    if ($SnapshotPrefix)      { $copyArgs.SnapshotPrefix = $SnapshotPrefix }

    $result = Copy-SilkEchoDatabase @copyArgs

    if ($null -eq $result) {
        Write-Warning 'The copy did not run.'
        $exitCode = 3
    }
    else {
        Write-Host ''
        Write-Host 'Result'
        Write-Host '------'
        Write-Host ("  Mode          : {0}" -f $result.Mode)
        Write-Host ("  Source        : {0} [{1}]" -f $result.SourceHost, ($result.SourceDatabases -join ', '))
        Write-Host ("  Snapshot      : {0}" -f $result.SnapshotId)
        Write-Host ("  Consistency   : {0}" -f $result.ConsistencyLevel)
        foreach ($d in @($result.Destinations)) {
            $state = if (-not $d.Success) { 'FAILED' } elseif ($result.WhatIf) { 'planned' } else { 'ok' }
            Write-Host ("  {0,-13} : {1}  cloned {2}, refreshed {3}, orphaned {4} ({5} removed)" -f
                $d.Host, $state, $d.Cloned, $d.Refreshed, $d.Orphaned, $d.OrphansRemoved)
            if (-not $d.Success) { Write-Host ("                  {0}" -f $d.Error) }
        }
        Write-Host ("  Duration      : {0}s" -f $result.DurationSeconds)
        Write-Host ''

        if ($result.Success)      { $exitCode = 0 }
        elseif ($result.Partial)  { $exitCode = 5 }
        else                      { $exitCode = 3 }
    }
}
catch [System.TimeoutException] {
    # Raised by the idle gate only, which runs before anything is changed. This
    # is the "try again later" case, kept distinct from a real failure so a
    # scheduled job can treat it differently.
    Write-Error -ErrorAction Continue -Message "Flex was busy: $($_.Exception.Message)"
    $exitCode = 4
}
catch {
    Write-Error -ErrorAction Continue -Message "Echo copy failed: $($_.Exception.Message)"
    $exitCode = 3
}
finally {
    try { Disconnect-SilkFlex } catch { }
}

exit $exitCode
