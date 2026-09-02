#Requires -Version 5.1
<#
    SilkEcho.psm1

    A dependency-free PowerShell module for driving Silk Echo database clone and
    refresh operations through the Flex REST API.

    Nothing outside of Windows PowerShell 5.1 is required. There is no Silk
    PowerShell module, no SqlServer module, and no external package. Every call
    is a plain Invoke-RestMethod against the documented Flex endpoints:

        https://github.com/Kaminario/echo-public-docs

    The headline function is Copy-SilkEchoDatabase, which performs the whole
    "copy a database from host A to host B" flow and decides on its own whether
    each destination database needs to be created for the first time (clone) or
    replaced in place from a brand new snapshot (refresh).

    Copyright (c) Silk Technologies, Inc. Licensed under the repository LICENSE.
#>

Set-Variable -Name SilkEchoModuleVersion -Value '1.3.0' -Scope Script -Option ReadOnly -Force -WhatIf:$false -Confirm:$false

# ---------------------------------------------------------------------------
# Module state
# ---------------------------------------------------------------------------

$script:FlexSession   = $null
$script:PollSeconds   = 2      # how often to look at the task queue
$script:TimeoutMin    = 15     # how long one Echo task may take
$script:ReadAttempts  = 4      # a read that hiccups must not fail the run
$script:OpAttempts    = 3      # how many times to submit an operation
$script:ReadBackoff   = 1

# Reads are support work: the topology, the task list, host and database
# listings. They exist only so an operation can be decided on, so a transient
# failure in one must never take the run down. They are retried on anything that
# is not a settled answer.
#
# 401 and 403 mean the token is no good and will stay no good. 404 means the
# thing is not there. Neither improves by asking again.
$script:ReadNoRetryStatus = @(401, 403, 404)

# A task that reaches 'failed' is retried unless its error is provably
# permanent. That way round on purpose: nobody is watching, and a refresh that
# gives up on a transient failure costs the whole night's environment refresh,
# while a retry of a genuinely broken operation costs a few minutes. Flex's own
# __validate call already rejects most permanent problems before submission, so
# what reaches this point is usually worth another go.
#
# Extend it as real failures are observed. Every unmatched task failure is
# logged in full so its error text can be added here.
$script:PermanentFailurePatterns = @(
    'not found'
    'does not exist'
    'no such'
    'permission'
    'denied'
    'unauthorized'
    'forbidden'
    'DB_NAME_IS_IN_USE'
    'already in use'
    'rejected by Flex validation'
)

# Snapshot name_prefix contract from the Echo API docs:
#   pattern ^[a-z][a-z0-9_-]+$ , length 4-20
$script:PrefixMinLength = 4
$script:PrefixMaxLength = 20

# Flex executes one operation at a time. A snapshot, clone, refresh or delete
# submitted while another is in flight is accepted and started, and then dies on
# a resource lock, so the cost of not waiting is a burned job. Every mutation in
# this module waits for the queue to clear first, and the module never issues two
# of its own concurrently: each is polled to completion before the next begins.
$script:IdleWaitMinutes    = 15
$script:IdleCheckEnabled   = $true
$script:TerminalTaskStates = @('completed', 'failed', 'aborted')


# ---------------------------------------------------------------------------
# Logging
#
# Console only. Where the output is captured is the caller's decision: a SQL
# Server Agent step has an output file, a scheduler has its own capture. This
# module does not open files.
# ---------------------------------------------------------------------------

function Write-EchoLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'STEP', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level.PadRight(5), $Message

    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
}

function Test-HasProperty {
    param($InputObject, [string]$Name)

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [hashtable]) { return $InputObject.ContainsKey($Name) }
    return [bool]($InputObject.PSObject.Properties.Name -contains $Name)
}


# ---------------------------------------------------------------------------
# TLS
# ---------------------------------------------------------------------------

function Set-SilkFlexTls {
<#
.SYNOPSIS
    Enables modern TLS and, unless told otherwise, accepts the Flex certificate.

.DESCRIPTION
    Windows PowerShell 5.1 still negotiates TLS 1.0 by default on some builds,
    which Flex refuses.

    Certificate validation is off by default. Flex ships with a self signed
    certificate, and this module exists to run unattended: making the caller pass
    a flag it would pass every single time only means the first scheduled run
    fails at 2am with nobody there to add it. Pass -RequireValidCertificate where
    Flex has a certificate that actually chains.

    The change is process wide for the life of the session.
#>
    [CmdletBinding()]
    param(
        [switch]$RequireValidCertificate
    )

    $isPS7 = $PSVersionTable.PSVersion.Major -ge 7

    try {
        if ($isPS7) {
            try {
                [System.Net.ServicePointManager]::SecurityProtocol =
                    [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
            }
            catch {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            }
        }
        else {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        }
    }
    catch {
        Write-EchoLog -Level 'WARN' -Message "Could not set the TLS protocol version: $($_.Exception.Message)"
    }

    if ($RequireValidCertificate) { return }

    if ($isPS7) {
        # PowerShell 7 honours -SkipCertificateCheck per call, which
        # Invoke-SilkFlexApi already passes. The callback is belt and braces for
        # any nested .NET client.
        try { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } } catch { }
    }
    else {
        $current = [System.Net.ServicePointManager]::CertificatePolicy
        if ($null -eq $current -or $current.GetType().FullName -ne 'SilkEchoTrustAllCertsPolicy') {
            if (-not ('SilkEchoTrustAllCertsPolicy' -as [type])) {
                Add-Type @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class SilkEchoTrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
'@
            }
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object SilkEchoTrustAllCertsPolicy
        }
    }

    Write-EchoLog -Level 'INFO' -Message 'Accepting the Flex certificate without validation. Pass -RequireValidCertificate to enforce it.'
}


# ---------------------------------------------------------------------------
# Authentication
#
# Flex uses bearer token authentication, and the token is used exactly as given.
# This module does not store, encrypt, cache or otherwise manage it: the token is
# an input, supplied by whatever calls this. Where it comes from and how it is
# protected in transit is the caller's business, not this module's.
# ---------------------------------------------------------------------------

function Connect-SilkFlex {
<#
.SYNOPSIS
    Opens a session against a Silk Flex server for the rest of the module to use.

.DESCRIPTION
    Authentication is by static application token, generated in Flex. Pass it as
    -Token, or set FLEX_TOKEN, which is the convention Silk's own examples use.

    The token is held in memory for the life of the session and used as supplied.
    Nothing is written anywhere.

    Connect-SilkFlex makes one real API call before returning, so a token that is
    wrong for this Flex fails here with a clear message rather than halfway
    through a copy.

.PARAMETER Server
    Flex hostname, FQDN or IP. https is assumed when no scheme is given.
    Falls back to the FLEX_URL or FLEX_IP environment variable.

.PARAMETER Token
    The Flex application token. Falls back to the FLEX_TOKEN environment variable.

.PARAMETER RequireValidCertificate
    Enforce certificate validation. Off by default because Flex ships with a self
    signed certificate and this is built to run unattended: a flag that would be
    passed on every single run only means the first scheduled run fails.

.PARAMETER PollSeconds
    How often to look at the Flex task queue, in seconds. Default 2.

.PARAMETER TimeoutMinutes
    How long to wait for any single Echo task. Default 15.

.PARAMETER IdleWaitMinutes
    Flex runs Echo mutations one at a time. Before every snapshot, clone,
    refresh or delete, this module waits up to this long for the Flex task queue
    to clear, whatever is in it and whoever started it. Default 15. Zero fails
    immediately when Flex is busy instead of waiting.

.PARAMETER SkipIdleCheck
    Do not wait for Flex to go idle. Only sensible when you know nothing else
    touches this Flex, because a mutation issued while another is running is
    rejected rather than queued.

.EXAMPLE
    Connect-SilkFlex -Server flex.contoso.com -Token $token
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Server,

        [Parameter(Position = 1)]
        [string]$Token,

        [switch]$RequireValidCertificate,

        [ValidateRange(1, 300)]
        [int]$PollSeconds = 2,

        [ValidateRange(1, 240)]
        [int]$TimeoutMinutes = 15,

        [ValidateRange(0, 240)]
        [int]$IdleWaitMinutes = 15,

        [switch]$SkipIdleCheck
    )

    if (-not $Server) { $Server = $env:FLEX_URL }
    if (-not $Server) { $Server = $env:FLEX_IP }
    if (-not $Server) {
        throw 'No Flex server supplied. Pass -Server, or set the FLEX_URL or FLEX_IP environment variable.'
    }

    if (-not $Token) { $Token = $env:FLEX_TOKEN }
    if (-not $Token) {
        throw 'No Flex token supplied. Pass -Token or set the FLEX_TOKEN environment variable.'
    }
    $Token = $Token.Trim()

    $baseUrl = $Server.Trim().TrimEnd('/')
    if ($baseUrl -notmatch '^https?://') { $baseUrl = "https://$baseUrl" }

    $script:PollSeconds       = $PollSeconds
    $script:TimeoutMin        = $TimeoutMinutes
    $script:IdleWaitMinutes   = $IdleWaitMinutes
    $script:IdleCheckEnabled  = -not $SkipIdleCheck.IsPresent

    Set-SilkFlexTls -RequireValidCertificate:$RequireValidCertificate

    $script:FlexSession = [pscustomobject]@{
        BaseUrl              = $baseUrl
        Token                = $Token
        SkipCertificateCheck = (-not $RequireValidCertificate.IsPresent)
    }

    Write-EchoLog -Level 'INFO' -Message "SilkEcho $script:SilkEchoModuleVersion loaded from $PSCommandPath"
    Write-EchoLog -Level 'STEP' -Message "Connecting to Silk Flex at $baseUrl"

    # Prove the token works before any caller starts a mutation, so a bad token
    # fails here rather than partway through a copy.
    $null = Invoke-SilkFlexApi -Path '/api/v1/hosts'
    Write-EchoLog -Level 'INFO' -Message 'Flex connection verified.'

    if ($script:IdleCheckEnabled) {
        Write-EchoLog -Level 'INFO' -Message "Echo mutations will wait up to $IdleWaitMinutes minute(s) for Flex to be idle before starting."
    }
    else {
        Write-EchoLog -Level 'WARN' -Message 'Idle checking is disabled. A mutation issued while Flex is busy will be rejected.'
    }

    return (Get-SilkFlexSession)
}

function Disconnect-SilkFlex {
<#
.SYNOPSIS
    Discards the cached Flex session and token.
#>
    [CmdletBinding()]
    param()

    $script:FlexSession = $null
    Write-EchoLog -Level 'INFO' -Message 'Flex session cleared.'
}

function Get-SilkFlexSession {
<#
.SYNOPSIS
    Returns the current Flex session. Never includes the token itself.
#>
    [CmdletBinding()]
    param()

    if (-not $script:FlexSession) { return $null }

    return [pscustomobject]@{
        BaseUrl              = $script:FlexSession.BaseUrl
        SkipCertificateCheck = $script:FlexSession.SkipCertificateCheck
        IdleCheckEnabled     = $script:IdleCheckEnabled
        IdleWaitMinutes      = $script:IdleWaitMinutes
    }
}

function Assert-FlexSession {
    if (-not $script:FlexSession) {
        throw 'Not connected to Flex. Call Connect-SilkFlex first.'
    }
}


# ---------------------------------------------------------------------------
# REST plumbing
# ---------------------------------------------------------------------------

function Expand-FlexResponse {
<#
.SYNOPSIS
    Emits an API response as individual objects, however deeply the collection
    arrived wrapped.

.DESCRIPTION
    Observed against a live Flex: a JSON array came back as an array containing
    one element which was itself the array of results. Every caller wrapping the
    call in @() therefore got a single element that was the whole collection, so
    a foreach over it ran exactly once with the entire array bound to the loop
    variable.

    That is quietly catastrophic rather than loud. Member access on an array
    enumerates, so $h.host_id yielded every id, and 'array -eq scalar' in
    PowerShell is not a boolean test but a filter: it returns the matching
    elements, which is truthy when anything matches. So a lookup for one host
    matched, and returned all of them.

    Peeling the wrapper here fixes every caller at once, rather than each of them
    having to know the response might be nested.
#>
    param($Response)

    if ($null -eq $Response) { return }

    $items = @($Response)
    while ($items.Count -eq 1 -and $items[0] -is [System.Array]) {
        $items = @($items[0])
    }

    foreach ($item in $items) { Write-Output $item }
}

function Get-FlexErrorText {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $status  = $null
    $message = $ErrorRecord.Exception.Message
    $response = $ErrorRecord.Exception.Response

    if ($null -ne $response) {
        if ($response.PSObject.Properties.Match('StatusCode').Count -gt 0) {
            try { $status = [int]$response.StatusCode } catch { $status = $null }
        }

        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            # PowerShell 6/7 has already read and disposed the response stream,
            # so ErrorDetails is the only place the body still exists.
            $message = $ErrorRecord.ErrorDetails.Message
        }
        elseif ($response -is [System.Net.HttpWebResponse]) {
            try {
                $stream = $response.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    try { $message = $reader.ReadToEnd() } finally { $reader.Dispose() }
                }
            }
            catch {
                # Stream already consumed or disposed. Keep the exception text.
            }
        }
    }

    $statusText = if ($status) { "HTTP $status" } else { 'no HTTP response' }
    return "$statusText - $message"
}

function Get-FlexErrorStatus {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    if ($null -eq $response) { return $null }
    if ($response.PSObject.Properties.Match('StatusCode').Count -eq 0) { return $null }
    try { return [int]$response.StatusCode } catch { return $null }
}

function Invoke-SilkFlexApi {
<#
.SYNOPSIS
    Calls a Flex REST endpoint with retry, re-authentication and error decoding.

.PARAMETER Path
    Endpoint path such as /api/echo/v1/topology, or a full URL.

.PARAMETER Method
    HTTP verb. Default GET.

.PARAMETER Body
    Hashtable or object serialised to JSON. Omit for GET and DELETE without a body.

.PARAMETER RefId
    Optional 6 to 8 character operation tag sent as the hs-ref-id header, which
    Silk support can use to find the operation in the Flex logs. Generated when
    omitted.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [string]$RefId
    )

    Assert-FlexSession

    if (-not $RefId) {
        $RefId = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
    }

    $uri = if ($Path -match '^https?://') { $Path } else { "$($script:FlexSession.BaseUrl)$Path" }

    $attempt      = 0
    $delaySeconds = $script:ReadBackoff
    $isRead       = ($Method -eq 'GET')

    while ($true) {
        $attempt++

        $params = @{
            Uri         = $uri
            Method      = $Method
            ContentType = 'application/json'
            Headers     = @{
                Authorization = "Bearer $($script:FlexSession.Token)"
                Accept        = 'application/json'
                'hs-ref-id'   = $RefId
            }
        }

        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
        }

        if ($script:FlexSession.SkipCertificateCheck -and
            (Get-Command Invoke-RestMethod).Parameters.ContainsKey('SkipCertificateCheck')) {
            $params.SkipCertificateCheck = $true
        }

        try {
            Write-Verbose "Flex $Method $uri (ref $RefId)"
            $response = Invoke-RestMethod @params
            return (Expand-FlexResponse -Response $response)
        }
        catch {
            $status = Get-FlexErrorStatus -ErrorRecord $_
            $text   = Get-FlexErrorText   -ErrorRecord $_

            # 401 and 403 both mean "this token is no good". Flex answers an
            # unauthenticated /api/v1/hosts with 403, not 401. There is nothing
            # to retry: an application token cannot be refreshed, so say plainly
            # what has to be fixed rather than hammering the endpoint.
            if ($status -eq 401 -or $status -eq 403) {
                throw ("Flex rejected the token on $Path ($status). It is revoked, belongs to a " +
                       "different Flex, or lacks access to this endpoint.")
            }

            # Reads are retried on anything that is not a settled answer: a
            # timeout, a reset, a 500, a proxy blip. Nothing is changed by a GET,
            # so replaying one is free, and letting a momentary hiccup while
            # reading the topology end a scheduled refresh would be absurd.
            #
            # Writes are never replayed here. A POST or DELETE that failed with a
            # transport error may well have reached Flex and started a task, so
            # re-sending it could run the operation twice. Those surface to
            # Invoke-EchoOperation, which knows what the operation was and waits
            # for the queue to settle before deciding.
            $retryable = $isRead -and ($script:ReadNoRetryStatus -notcontains $status)

            if ($retryable -and $attempt -lt $script:ReadAttempts) {
                Write-EchoLog -Level 'WARN' -Message "Flex $Method $Path failed ($text). Retry $attempt of $($script:ReadAttempts - 1) in ${delaySeconds}s."
                Start-Sleep -Seconds $delaySeconds
                $delaySeconds = [Math]::Min($delaySeconds * 2, 10)
                continue
            }

            throw "Flex $Method $Path failed (ref $RefId): $text"
        }
    }
}

function Wait-SilkEchoTask {
<#
.SYNOPSIS
    Polls an Echo task to completion and returns the finished task object.

.PARAMETER Task
    The task envelope returned by an Echo mutation, containing request_id and
    optionally location.

.PARAMETER Activity
    Label used in log lines.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Task,

        [string]$Activity = 'Echo task'
    )

    if (-not (Test-HasProperty $Task 'request_id')) {
        # Some endpoints answer synchronously with no task envelope at all.
        return $Task
    }

    $taskPath = "/api/echo/v1/tasks/$($Task.request_id)"
    if ((Test-HasProperty $Task 'location') -and $Task.location) {
        $taskPath = if ($Task.location.StartsWith('/') -or $Task.location -match '^https?://') { $Task.location } else { "/$($Task.location)" }
    }

    Write-EchoLog -Level 'INFO' -Message "$Activity started: $($Task.command_type) (task $($Task.request_id))"

    $current  = $Task
    $deadline = (Get-Date).AddMinutes($script:TimeoutMin)
    $lastState = $null

    while ($current.state -eq 'running' -or $current.state -eq 'queued') {
        if ((Get-Date) -gt $deadline) {
            throw "$Activity (task $($Task.request_id)) did not finish within $($script:TimeoutMin) minute(s). It may still be running in Flex."
        }

        Start-Sleep -Seconds $script:PollSeconds
        $current = Invoke-SilkFlexApi -Path $taskPath

        if ($current.state -ne $lastState) {
            Write-EchoLog -Level 'INFO' -Message "$Activity state: $($current.state)"
            $lastState = $current.state
        }
    }

    if ($current.state -ne 'completed') {
        $detail = if ($current.error) { $current.error } else { ($current.result | ConvertTo-Json -Compress -Depth 6) }
        throw "$Activity failed with state '$($current.state)': $detail"
    }

    Write-EchoLog -Level 'INFO' -Message "$Activity completed."
    return $current
}

function Assert-EchoValidation {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Method,
        $Body,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    $result = Invoke-SilkFlexApi -Path $Path -Method $Method -Body $Body

    if ($null -eq $result -or -not (Test-HasProperty $result 'valid')) {
        Write-EchoLog -Level 'WARN' -Message "$Activity validation returned no verdict, continuing."
        return
    }

    if ($result.valid) {
        Write-EchoLog -Level 'INFO' -Message "$Activity validation passed."
        return
    }

    $issues = @()
    foreach ($issue in @($result.issues)) {
        $issues += ('{0}: {1}' -f $issue.issue_type, $issue.description)
    }
    if (-not $issues) { $issues = @('no detail supplied by Flex') }

    throw "$Activity was rejected by Flex validation:`n  - $($issues -join "`n  - ")"
}


# ---------------------------------------------------------------------------
# Concurrency
#
# Flex is single threaded for Echo mutations. Everything below exists so that
# this module never starts work while Flex is busy, whether the other work is
# ours or somebody else's.
# ---------------------------------------------------------------------------

function Get-SilkEchoTask {
<#
.SYNOPSIS
    Lists Echo tasks, or fetches one by id.

.PARAMETER TaskId
    Return a single task.

.PARAMETER State
    Return only tasks in this state.

.PARAMETER Active
    Return only tasks that have not finished, which is what makes Flex busy.

.EXAMPLE
    Get-SilkEchoTask -Active | Format-Table request_id, command_type, state, create_ts
#>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'Single', Mandatory = $true, Position = 0)]
        [string]$TaskId,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('running', 'queued', 'completed', 'failed', 'aborted')]
        [string]$State,

        [Parameter(ParameterSetName = 'Active')]
        [switch]$Active
    )

    if ($TaskId) { return Invoke-SilkFlexApi -Path "/api/echo/v1/tasks/$TaskId" }

    # One shape of request, filtered here. The endpoint hands back everything on
    # the Flex anyway, so a server side filter buys nothing and only narrows what
    # can be asked of the result.
    $all = @(Invoke-SilkFlexApi -Path '/api/echo/v1/tasks')

    if ($Active) { return @($all | Where-Object { $_ -and $script:TerminalTaskStates -notcontains $_.state }) }
    if ($State)  { return @($all | Where-Object { $_ -and $_.state -eq $State }) }

    return $all
}

function Get-ActiveEchoTask {
    # Everything that has not finished, whoever started it and whatever it is.
    # SDP work reaches the queue through a different endpoint but takes the same
    # locks, so there is nothing to be gained by filtering to Echo commands.
    return @(Get-SilkEchoTask -Active)
}

function Wait-SilkEchoIdle {
<#
.SYNOPSIS
    Blocks until the Flex task queue is empty.

.DESCRIPTION
    Flex runs one operation at a time. A submission made while something else is
    running is accepted and started, and then fails on a resource lock, so the
    cost of not waiting is a burned job rather than a cheap rejection. Waiting is
    the whole defence.

    The wait is a continuous poll, never a fixed sleep. The moment the queue
    empties, this returns and the caller submits. Sleeping through that moment is
    how a caller loses a race it was otherwise going to win.

    The poll interval carries a little randomness so that two jobs waiting on the
    same busy Flex drift out of lockstep instead of sampling together forever and
    racing on every tick.

.PARAMETER TimeoutMinutes
    How long to wait. Omit for the session default. Zero checks once and gives up
    if anything is running.

.PARAMETER ExcludeTaskId
    Task ids to disregard, for a caller that already owns one.

.PARAMETER Activity
    Name of the operation that is waiting, used in the log lines.

.OUTPUTS
    Nothing on success. Throws System.TimeoutException if the queue is still busy
    when the timeout expires, which callers catch to tell "Flex was busy and
    nothing was attempted" apart from a real failure.
#>
    [CmdletBinding()]
    param(
        [int]$TimeoutMinutes = -1,

        [string[]]$ExcludeTaskId,

        [string]$Activity = 'this operation'
    )

    if ($TimeoutMinutes -lt 0) { $TimeoutMinutes = $script:IdleWaitMinutes }

    $deadline  = (Get-Date).AddMinutes($TimeoutMinutes)
    $waited    = $false
    $lastDetail = $null

    while ($true) {
        $active = @(Get-ActiveEchoTask | Where-Object { $ExcludeTaskId -notcontains $_.request_id })

        if ($active.Count -eq 0) {
            if ($waited) { Write-EchoLog -Level 'INFO' -Message "Flex is idle. Continuing with $Activity." }
            return
        }

        $detail = ($active | ForEach-Object { "$($_.command_type) [$($_.request_id)] $($_.state)" }) -join '; '

        if ($detail -ne $lastDetail) {
            Write-EchoLog -Level 'INFO' -Message "Flex is busy, so $Activity is waiting: $detail"
            $lastDetail = $detail
            $waited     = $true
        }

        if ((Get-Date) -ge $deadline) {
            throw (New-Object System.TimeoutException(
                "Flex was still busy after $TimeoutMinutes minute(s), so $Activity was never started and nothing has been changed. Outstanding: $detail"))
        }

        # Jitter, so two waiters do not sample in lockstep and collide every time
        # the queue frees up.
        Start-Sleep -Milliseconds (($script:PollSeconds * 1000) + (Get-Random -Minimum 0 -Maximum 750))
    }
}

function Wait-EchoIdleGate {
    # Honours the session wide opt out. Everything that changes something goes
    # through here first.
    param([string]$Activity = 'this operation')

    if (-not $script:IdleCheckEnabled) { return }
    Wait-SilkEchoIdle -Activity $Activity
}

function Test-EchoPermanentFailure {
<#
.SYNOPSIS
    True when a failure will still be a failure however many times it is tried.

.DESCRIPTION
    Deliberately the pessimistic half of the decision. Anything not matched here
    gets retried, because this runs unattended: a refresh that gives up on a
    transient failure costs a whole cycle, while retrying a genuinely broken
    operation costs a couple of minutes and then reports the same error.

    Flex's own __validate call rejects most permanent problems before submission,
    so a failure that gets this far has usually earned another attempt.

    $script:PermanentFailurePatterns is the list. Add to it as real failures are
    seen: every unmatched one is logged in full precisely so its text can be
    lifted into the list.
#>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)

    foreach ($pattern in $script:PermanentFailurePatterns) {
        if ($Message -match $pattern) { return $true }
    }
    return $false
}

function Invoke-EchoOperation {
<#
.SYNOPSIS
    Runs one Echo operation end to end: wait for the queue, submit, track it to
    completion, and try again if it did not stick.

.DESCRIPTION
    Every mutation goes through here, so waiting, tracking and retrying are one
    behaviour rather than something each caller reimplements. Read only calls do
    not: fetching the topology or the task list is support work, and putting it
    behind the queue would add a wait to every trivial lookup for no benefit.
    Reads get their own retry inside Invoke-SilkFlexApi.

    The loop is deliberately shaped so there is no blind sleep anywhere in it.
    After a failure it goes straight back to watching the queue, and submits the
    instant that queue is empty. A fixed backoff would mean not watching during
    the very window the slot frees up, which is how a caller loses the same race
    over and over.

    Two failure shapes are handled:

      the task ran and failed    the usual collision. It reached a terminal
                                 state, so nothing is still in flight and
                                 resubmitting is safe.
      the submission itself      the outcome is unknown: it may have reached
      errored                    Flex. Waiting for the queue to settle before
                                 resubmitting means any task it did start has
                                 finished first, and a duplicate then either
                                 lands harmlessly or is refused as permanent.

.PARAMETER Activity
    What is being attempted, for the log lines.

.PARAMETER Submit
    Runs the mutation and returns the Flex task envelope.

.PARAMETER Attempts
    How many times to submit in total. Default 3.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Activity,
        [Parameter(Mandatory = $true)][scriptblock]$Submit,
        [ValidateRange(1, 20)][int]$Attempts = 3
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {

        # The wait, and the only wait. Returns the moment the queue is clear.
        Wait-EchoIdleGate -Activity $Activity

        $task = $null
        try {
            $task = & $Submit
            return Wait-SilkEchoTask -Task $task -Activity $Activity
        }
        catch {
            $message = $_.Exception.Message

            # A timeout waiting for the queue is not this loop's problem: it means
            # nothing was attempted, and the caller wants to hear that as-is.
            if ($_.Exception -is [System.TimeoutException]) { throw }

            if (Test-EchoPermanentFailure -Message $message) {
                throw "Not retrying, this will not succeed on another attempt. $message"
            }

            if ($attempt -ge $Attempts) {
                throw "Gave up after $Attempts attempts. $message"
            }

            # Log the whole task so the reason can be read back later. Until the
            # exact text Flex uses for a lock collision is known from a real one,
            # this is where it will show up.
            if ($task) {
                Write-EchoLog -Level 'WARN' -Message "$Activity did not stick on attempt $attempt of $Attempts. Full task: $($task | ConvertTo-Json -Depth 6 -Compress)"
            }
            Write-EchoLog -Level 'WARN' -Message "$Activity failed on attempt $attempt of $($Attempts): $message"
            Write-EchoLog -Level 'INFO' -Message "Watching the Flex queue and resubmitting as soon as it is clear."
        }
    }
}


# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

function Get-SilkEchoHost {
<#
.SYNOPSIS
    Lists the hosts Echo knows about, or resolves one by name.

.DESCRIPTION
    With no name, every registered host. With a name, exactly one host or an
    error, never a list. See Resolve-SilkEchoHost for why that matters.

.PARAMETER Name
    Host name or host id.

.EXAMPLE
    Get-SilkEchoHost | Format-Table host_id, host_name, is_connected, db_engine_version
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @(Invoke-SilkFlexApi -Path '/api/v1/hosts')
    }

    return Resolve-SilkEchoHost -Name $Name
}

function Resolve-SilkEchoHost {
<#
.SYNOPSIS
    Resolves one host name to exactly one host object, or throws.

.DESCRIPTION
    Deliberately incapable of returning a list. A function that returns every
    host on one path and one host on another has a failure mode where a name
    that does not arrive turns into every host, and that array then flows into
    -HostName and every downstream call as a silently wrong answer instead of an
    error. Listing lives in Get-SilkEchoHost with no name; resolving lives here
    and has exactly two outcomes.

    Matching, in order: host id, host name, then short name against a registered
    FQDN so 'sql01' finds 'sql01.contoso.com'. String -eq is case insensitive in
    PowerShell, so each pass covers both casings.

.PARAMETER Name
    Host name or host id. Empty is an error, never "give me everything".
#>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Resolve-SilkEchoHost was called without a host name. That is a bug in the caller, not a request for every host.'
    }

    $needle = $Name.Trim()
    $all    = @(Invoke-SilkFlexApi -Path '/api/v1/hosts')

    # foreach with an early return, not a pipeline: this cannot emit more than
    # one object however the input is shaped.
    foreach ($h in $all) { if ($h.host_id   -eq $needle) { return $h } }
    foreach ($h in $all) { if ($h.host_name -eq $needle) { return $h } }
    foreach ($h in $all) { if ($h.host_name -and $h.host_name -like "$needle.*") { return $h } }

    $known = ($all | ForEach-Object { $_.host_name }) -join ', '
    if (-not $known) { $known = 'none' }
    throw "Host '$Name' is not registered in Echo. Registered hosts: $known"
}

function Assert-SingleEchoHost {
    # Resolving is supposed to yield exactly one host. If it ever yields more,
    # that array goes on to be passed as -HostName and the run dies several
    # calls later with a type conversion error that says nothing about the cause.
    # Fail here instead, naming what came back.
    param(
        $Resolved,
        [string]$Requested,
        [string]$Role
    )

    $count = @($Resolved).Count
    if ($count -eq 1) { return }

    $got = (@($Resolved) | ForEach-Object { $_.host_id }) -join ', '
    throw ("$Role host '$Requested' resolved to $count hosts instead of one: $got. " +
           "The module loaded is not behaving as its source says it should. Check the SilkEcho version line above " +
           "against the file you deployed.")
}

function Assert-EchoHostUsable {
    param(
        [Parameter(Mandatory = $true)]$EchoHost,
        [Parameter(Mandatory = $true)][string]$Role
    )

    if (-not $EchoHost.is_connected) {
        throw "$Role host '$($EchoHost.host_name)' is registered but its Silk Agent is not connected. Start the Silk Agent service on that host and retry."
    }

    if ((Test-HasProperty $EchoHost 'is_operational') -and -not $EchoHost.is_operational) {
        $reason = if ($EchoHost.not_operational_reason) { $EchoHost.not_operational_reason } else { 'no reason reported' }
        throw "$Role host '$($EchoHost.host_name)' is not operational for Echo operations: $reason"
    }
}

function Get-SilkEchoDatabase {
<#
.SYNOPSIS
    Lists the databases Echo can see on a host.

.PARAMETER HostName
    Host name or host id.

.PARAMETER Name
    Optional database name to filter to.

.EXAMPLE
    Get-SilkEchoDatabase -HostName sql-prod | Format-Table id, name, status
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$HostName,

        [Parameter(Position = 1)]
        [string]$Name
    )

    $echoHost = Resolve-SilkEchoHost -Name $HostName
    $databases = @(Invoke-SilkFlexApi -Path "/api/v1/hosts/$($echoHost.host_id)/databases")

    if ($Name) {
        return @($databases | Where-Object { $_.name -eq $Name -or $_.name.ToLowerInvariant() -eq $Name.ToLowerInvariant() })
    }

    return $databases
}

function Get-SilkEchoTopology {
<#
.SYNOPSIS
    Returns the full host to database to snapshot topology.

.DESCRIPTION
    This is the only endpoint that reports database lineage. A database whose
    'parent' is populated is an Echo clone, and parent.src_host_id and
    parent.src_db_id say what it was cloned from. That is what makes the
    clone versus refresh decision possible.
#>
    [CmdletBinding()]
    param()

    return @(Invoke-SilkFlexApi -Path '/api/echo/v1/topology')
}

function Get-TopologyHostEntry {
    # A host with no Echo databases has no topology entry, and a freshly cleaned
    # environment has no topology at all. Both are ordinary states, not errors,
    # so nothing here is mandatory and an empty result is a legitimate answer.
    param(
        $Topology,
        [string]$HostId
    )

    if (-not $Topology -or -not $HostId) { return $null }

    foreach ($entry in @($Topology)) {
        if ($entry -and $entry.host -and $entry.host.id -eq $HostId) { return $entry }
    }
    return $null
}

function Get-DatabaseLineage {
    param([Parameter(Mandatory = $true)]$Database)

    # Topology reports lineage under 'parent'. Some Flex builds also flatten it
    # onto the database itself. Accept either shape.
    $srcHostId = $null
    $srcDbId   = $null
    $srcDbName = $null
    $snapId    = $null

    if ((Test-HasProperty $Database 'parent') -and $Database.parent) {
        $srcHostId = $Database.parent.src_host_id
        $srcDbId   = $Database.parent.src_db_id
        $snapId    = $Database.parent.snap_id
    }

    if (-not $srcHostId -and (Test-HasProperty $Database 'source_host_id')) { $srcHostId = $Database.source_host_id }
    if (-not $srcDbId   -and (Test-HasProperty $Database 'source_db_id'))   { $srcDbId   = $Database.source_db_id }
    if ((Test-HasProperty $Database 'source_db_name'))                      { $srcDbName = $Database.source_db_name }

    return [pscustomobject]@{
        IsEchoClone  = [bool]($srcHostId -and $srcDbId)
        SourceHostId = $srcHostId
        SourceDbId   = if ($null -ne $srcDbId) { [string]$srcDbId } else { $null }
        SourceDbName = $srcDbName
        SnapshotId   = $snapId
    }
}


# ---------------------------------------------------------------------------
# Snapshot name prefix
# ---------------------------------------------------------------------------

function ConvertTo-EchoNamePrefix {
<#
.SYNOPSIS
    Coerces a string into a legal Echo snapshot name_prefix.

.DESCRIPTION
    Flex enforces ^[a-z][a-z0-9_-]+$ with a length of 4 to 20. A database name
    like 'SilkEDW.Reporting' or 'DB1' fails that outright, so anything derived
    from a database name has to be normalised before it reaches the API.

.EXAMPLE
    ConvertTo-EchoNamePrefix -InputString 'SilkEDW.Reporting'   # silkedw-reporting
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string]$InputString
    )

    $value = $InputString.ToLowerInvariant()
    $value = [regex]::Replace($value, '[^a-z0-9_-]', '-')
    $value = [regex]::Replace($value, '-{2,}', '-')
    $value = $value.TrimStart([char[]]@('-', '_', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'))
    $value = $value.TrimEnd([char[]]@('-', '_'))

    if ($value.Length -eq 0) { $value = 'snap' }
    if ($value -notmatch '^[a-z]') { $value = "s$value" }

    while ($value.Length -lt $script:PrefixMinLength) { $value = "${value}x" }

    if ($value.Length -gt $script:PrefixMaxLength) {
        $value = $value.Substring(0, $script:PrefixMaxLength).TrimEnd([char[]]@('-', '_'))
    }

    return $value
}


# ---------------------------------------------------------------------------
# Echo operations
# ---------------------------------------------------------------------------

function New-SilkEchoSnapshot {
<#
.SYNOPSIS
    Takes a snapshot of one or more databases on a source host.

.PARAMETER SourceHost
    Host name or host id holding the databases.

.PARAMETER Database
    One or more database names on that host. All are captured in a single,
    point in time consistent snapshot.

.PARAMETER NamePrefix
    Snapshot name prefix. Derived from the first database name when omitted and
    always normalised to the Flex pattern.

.PARAMETER ConsistencyLevel
    How the snapshot is taken. Three states, and the set is exhaustive so no two
    can be asked for at once:

      application         (default) the Silk Agent quiesces the database through
                          the VSS provider, so the copy comes up immediately
                          usable. Sends consistency_level=application, use_vss=true.
      application-novss   application consistent without the VSS provider, which
                          SQL Server 2022 and later support. Sends
                          consistency_level=application, use_vss=false.
      crash               no quiesce, nothing asked of the database engine, and
                          the copy may come up in recovery on first attach.
                          Sends consistency_level=crash. VSS does not apply.

    use_vss is always sent explicitly for the application levels rather than left
    to the API default. Whether a copy comes up usable or in recovery is too
    important to inherit from a server side default that could differ between
    builds: the request says what it wants, and the log says what was asked for.

    Flex reports which path it took in the task command_type, so a run can be
    checked after the fact: CreateVssDbSnapshotCommand, CreateGenericDBSnapshotCommand
    or CreateDBSnapshotCrashLevelCommand.

.PARAMETER SkipValidation
    Do not call the Flex validation endpoint first.

.OUTPUTS
    An object with SnapshotId, TaskId, DatabaseIds and DurationSeconds.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourceHost,

        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$Database,

        [string]$NamePrefix,

        [ValidateSet('application', 'application-novss', 'crash')]
        [string]$ConsistencyLevel = 'application',

        [switch]$SkipValidation,

        [ValidateRange(1, 20)]
        [int]$Attempts = $script:OpAttempts
    )

    $started  = Get-Date
    $echoHost = Resolve-SilkEchoHost -Name $SourceHost
    Assert-EchoHostUsable -EchoHost $echoHost -Role 'Source'

    $available = Get-SilkEchoDatabase -HostName $echoHost.host_id

    $dbIds   = @()
    $dbNames = @()
    foreach ($name in $Database) {
        $match = $available | Where-Object { $_.name -ceq $name } | Select-Object -First 1
        if (-not $match) { $match = $available | Where-Object { $_.name.ToLowerInvariant() -eq $name.ToLowerInvariant() } | Select-Object -First 1 }
        if (-not $match) {
            $known = ($available | ForEach-Object { $_.name }) -join ', '
            throw "Database '$name' was not found on host '$($echoHost.host_name)'. Databases Echo can see there: $known"
        }
        $dbIds   += [string]$match.id
        $dbNames += $match.name
    }

    if (-not $NamePrefix) { $NamePrefix = $dbNames[0] }
    $prefix = ConvertTo-EchoNamePrefix -InputString $NamePrefix

    # One place where the three states become the two API fields. use_vss is
    # sent rather than omitted: leaving it to the server default means the
    # difference between a usable copy and one in recovery is inherited rather
    # than requested, and nothing in the payload would say which was wanted.
    $body = @{
        source_host_id    = $echoHost.host_id
        database_ids      = @($dbIds)
        name_prefix       = $prefix
        consistency_level = if ($ConsistencyLevel -eq 'crash') { 'crash' } else { 'application' }
    }
    if ($ConsistencyLevel -eq 'application')       { $body.use_vss = $true }
    if ($ConsistencyLevel -eq 'application-novss') { $body.use_vss = $false }
    # For crash, use_vss is not sent: the API ignores it, so sending it would
    # only imply a choice that is not being made.

    $described = switch ($ConsistencyLevel) {
        'application'       { 'application consistent, using VSS' }
        'application-novss' { 'application consistent, without VSS' }
        default             { 'crash consistent' }
    }

    $target = "$($dbNames -join ', ') on $($echoHost.host_name)"
    if (-not $PSCmdlet.ShouldProcess($target, "Create $described snapshot")) { return $null }

    Write-EchoLog -Level 'STEP' -Message "Creating a snapshot of $target ($described, prefix '$prefix')"

    $completed = Invoke-EchoOperation -Activity "the snapshot of $target" -Attempts $Attempts -Submit {
        if (-not $SkipValidation) {
            Assert-EchoValidation -Path '/api/echo/v1/db_snapshots/__validate' -Method 'POST' -Body $body -Activity 'Snapshot'
        }
        Invoke-SilkFlexApi -Path '/api/echo/v1/db_snapshots' -Method 'POST' -Body $body
    }

    $snapshotId = $null
    if ((Test-HasProperty $completed 'result') -and $completed.result -and (Test-HasProperty $completed.result 'db_snapshot')) {
        $snapshotId = $completed.result.db_snapshot.id
    }

    if (-not $snapshotId) {
        # Fall back to the snapshot list, newest first for this host and database.
        $snapshots = @(Invoke-SilkFlexApi -Path '/api/echo/v1/db_snapshots')
        $candidate = $snapshots |
            Where-Object { $_.host_id -eq $echoHost.host_id -and (@($_.databases) | Where-Object { $dbNames -contains $_.db_name }) } |
            Sort-Object -Property timestamp -Descending |
            Select-Object -First 1
        if ($candidate) { $snapshotId = $candidate.id }
    }

    if (-not $snapshotId) {
        throw "The snapshot task completed but Flex did not report a snapshot id. Task $($completed.request_id) result: $($completed.result | ConvertTo-Json -Compress -Depth 6)"
    }

    $duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    Write-EchoLog -Level 'INFO' -Message "Snapshot $snapshotId created in ${duration}s."

    return [pscustomobject]@{
        SnapshotId       = $snapshotId
        TaskId           = $completed.request_id
        SourceHostId     = $echoHost.host_id
        SourceHostName   = $echoHost.host_name
        DatabaseIds      = $dbIds
        DatabaseNames    = $dbNames
        ConsistencyLevel = $ConsistencyLevel
        DurationSeconds  = $duration
    }
}

function Get-SilkEchoSnapshot {
<#
.SYNOPSIS
    Lists Echo snapshots, optionally filtered to one id or one source host.

.PARAMETER SnapshotId
    Return only the snapshot with this id.

.PARAMETER SourceHost
    Return only snapshots taken on this host.
#>
    [CmdletBinding()]
    param(
        [string]$SnapshotId,
        [string]$SourceHost
    )

    $snapshots = @(Invoke-SilkFlexApi -Path '/api/echo/v1/db_snapshots')

    if ($SnapshotId) {
        return @($snapshots | Where-Object { $_.id -eq $SnapshotId })
    }

    if ($SourceHost) {
        $echoHost = Resolve-SilkEchoHost -Name $SourceHost
        return @($snapshots | Where-Object { $_.host_id -eq $echoHost.host_id })
    }

    return $snapshots
}

function New-SilkEchoClone {
<#
.SYNOPSIS
    Mounts a new Echo database on a destination host from an existing snapshot.

.DESCRIPTION
    Use this for a destination database that does not exist yet. To replace an
    existing Echo database in place, use Update-SilkEchoClone.

    The Echo API carries host_id per destination, so a single call can mount
    databases onto several hosts at once from one snapshot. Pass a HostId on each
    destination to use that, or -DestinationHost to send them all to one host.

.PARAMETER SnapshotId
    Snapshot to clone from.

.PARAMETER DestinationHost
    Host name or host id that will receive every destination that does not name
    its own HostId.

.PARAMETER Destination
    One or more hashtables with SourceDatabaseId and DatabaseName keys, mapping a
    database inside the snapshot to the name it will be mounted as. An optional
    HostId key sends that one to a specific host.

.PARAMETER TargetState
    online (default) or recovery.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SnapshotId,

        [string]$DestinationHost,

        [Parameter(Mandatory = $true)]
        [hashtable[]]$Destination,

        [ValidateSet('online', 'recovery')]
        [string]$TargetState = 'online',

        [switch]$SkipValidation,

        [ValidateRange(1, 20)]
        [int]$Attempts = $script:OpAttempts
    )

    $started = Get-Date

    $defaultHostId = $null
    $defaultName   = $null
    if ($DestinationHost) {
        $echoHost = Resolve-SilkEchoHost -Name $DestinationHost
        Assert-EchoHostUsable -EchoHost $echoHost -Role 'Destination'
        $defaultHostId = $echoHost.host_id
        $defaultName   = $echoHost.host_name
    }

    $destinations = @()
    $hostIds      = @()
    foreach ($d in $Destination) {
        $hostId = if ($d.ContainsKey('HostId') -and $d.HostId) { [string]$d.HostId } else { $defaultHostId }
        if (-not $hostId) {
            throw "New-SilkEchoClone: destination '$($d.DatabaseName)' has no HostId and no -DestinationHost was given."
        }
        $destinations += @{
            host_id = $hostId
            db_id   = [string]$d.SourceDatabaseId
            db_name = [string]$d.DatabaseName
        }
        if ($hostIds -notcontains $hostId) { $hostIds += $hostId }
    }

    $body = @{
        destinations = @($destinations)
        target_state = $TargetState
    }

    $names  = ($destinations | ForEach-Object { $_.db_name }) -join ', '
    $target = if ($defaultName -and $hostIds.Count -eq 1) { "$names on $defaultName" } else { "$names across $($hostIds.Count) host(s)" }

    if (-not $PSCmdlet.ShouldProcess($target, "Clone from snapshot $SnapshotId")) { return $null }

    Write-EchoLog -Level 'STEP' -Message "Cloning snapshot $SnapshotId to $target"

    $completed = Invoke-EchoOperation -Activity "the clone of $target" -Attempts $Attempts -Submit {
        if (-not $SkipValidation) {
            Assert-EchoValidation -Path "/api/echo/v1/db_snapshots/$SnapshotId/echo_db/__validate" -Method 'POST' -Body $body -Activity 'Clone'
        }
        Invoke-SilkFlexApi -Path "/api/echo/v1/db_snapshots/$SnapshotId/echo_db" -Method 'POST' -Body $body
    }

    $duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    Write-EchoLog -Level 'INFO' -Message "Clone of $target finished in ${duration}s."

    return [pscustomobject]@{
        TaskId          = $completed.request_id
        SnapshotId      = $SnapshotId
        HostIds         = $hostIds
        Databases       = ($destinations | ForEach-Object { $_.db_name })
        ClonedDbs       = if ((Test-HasProperty $completed 'result') -and $completed.result) { $completed.result.cloned_dbs } else { $null }
        DurationSeconds = $duration
    }
}

function Update-SilkEchoClone {
<#
.SYNOPSIS
    Refreshes existing Echo databases in place from a snapshot.

.DESCRIPTION
    Flex detaches the current volumes, clones fresh ones from the snapshot and
    reattaches them under the same database names. The databases keep their
    names and their identity on the host, and the previous contents are gone.

    Every named database has to already exist on the host as an Echo clone whose
    lineage points at the source captured in the snapshot.

.PARAMETER HostName
    Host holding the databases to refresh.

.PARAMETER Database
    Names of the databases on that host to replace.

.PARAMETER SnapshotId
    Snapshot supplying the new contents.

.PARAMETER TargetState
    online (default) or recovery.
#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$HostName,

        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$Database,

        [Parameter(Mandatory = $true)]
        [string]$SnapshotId,

        [ValidateSet('online', 'recovery')]
        [string]$TargetState = 'online',

        [switch]$SkipValidation,

        [ValidateRange(1, 20)]
        [int]$Attempts = $script:OpAttempts
    )

    $started  = Get-Date
    $echoHost = Resolve-SilkEchoHost -Name $HostName
    Assert-EchoHostUsable -EchoHost $echoHost -Role 'Destination'

    $body = @{
        snapshot_id  = $SnapshotId
        db_names     = @($Database)
        target_state = $TargetState
    }

    $names  = $Database -join ', '
    $target = "$names on $($echoHost.host_name)"

    if (-not $PSCmdlet.ShouldProcess($target, "Refresh from snapshot $SnapshotId")) { return $null }

    $path = "/api/echo/v1/hosts/$($echoHost.host_id)/databases/_refresh"

    Write-EchoLog -Level 'STEP' -Message "Refreshing $target from snapshot $SnapshotId"

    $completed = Invoke-EchoOperation -Activity "the refresh of $target" -Attempts $Attempts -Submit {
        if (-not $SkipValidation) {
            Assert-EchoValidation -Path "$path/__validate" -Method 'POST' -Body $body -Activity 'Refresh'
        }
        Invoke-SilkFlexApi -Path $path -Method 'POST' -Body $body
    }

    $duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    Write-EchoLog -Level 'INFO' -Message "Refresh of $names finished in ${duration}s."

    return [pscustomobject]@{
        TaskId          = $completed.request_id
        SnapshotId      = $SnapshotId
        HostId          = $echoHost.host_id
        HostName        = $echoHost.host_name
        Databases       = $Database
        ClonedDbs       = if ((Test-HasProperty $completed 'result') -and $completed.result) { $completed.result.cloned_dbs } else { $null }
        DurationSeconds = $duration
    }
}

function Remove-SilkEchoClone {
<#
.SYNOPSIS
    Detaches and deletes an Echo clone from a host, along with its thin volumes.

.PARAMETER HostName
    Host holding the clone.

.PARAMETER DatabaseId
    Echo database id on that host.

.PARAMETER Cascade
    Also delete anything cloned from this Echo database. Without it Flex refuses
    the delete when dependents exist.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$HostName,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$DatabaseId,

        [switch]$Cascade,

        [ValidateRange(1, 20)]
        [int]$Attempts = $script:OpAttempts
    )

    $echoHost = Resolve-SilkEchoHost -Name $HostName

    $body = @{
        host_id     = $echoHost.host_id
        database_id = [string]$DatabaseId
        cascade     = [bool]$Cascade
    }

    if (-not $PSCmdlet.ShouldProcess("database id $DatabaseId on $($echoHost.host_name)", 'Delete Echo clone')) { return $null }

    Write-EchoLog -Level 'STEP' -Message "Deleting Echo clone id $DatabaseId from $($echoHost.host_name)"

    return Invoke-EchoOperation -Activity "the delete of database id $DatabaseId on $($echoHost.host_name)" -Attempts $Attempts -Submit {
        Invoke-SilkFlexApi -Path '/api/echo/v1/echo_dbs' -Method 'DELETE' -Body $body
    }
}

function Remove-SilkEchoSnapshot {
<#
.SYNOPSIS
    Deletes an Echo snapshot.

.PARAMETER SnapshotId
    Snapshot to delete.

.PARAMETER Cascade
    Also delete every Echo database cloned from it. Without this, Flex refuses
    the delete while dependents exist.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SnapshotId,

        [switch]$Cascade,

        [ValidateRange(1, 20)]
        [int]$Attempts = $script:OpAttempts
    )

    if (-not $PSCmdlet.ShouldProcess($SnapshotId, 'Delete Echo snapshot')) { return $null }

    Write-EchoLog -Level 'INFO' -Message "Deleting snapshot $SnapshotId"

    return Invoke-EchoOperation -Activity "the delete of snapshot $SnapshotId" -Attempts $Attempts -Submit {
        if ($Cascade) {
            Invoke-SilkFlexApi -Path "/api/echo/v1/db_snapshots/$SnapshotId" -Method 'DELETE' -Body @{ cascade = $true }
        }
        else {
            Invoke-SilkFlexApi -Path "/api/echo/v1/db_snapshots/$SnapshotId" -Method 'DELETE'
        }
    }
}


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

function Copy-SilkEchoDatabase {
<#
.SYNOPSIS
    Presents a copy of one Echo host's databases on one or more other hosts, and
    keeps those copies current on later runs.

.DESCRIPTION
    Reconciliation, not a script of steps. The desired state is "these
    destination hosts present a copy of the source host's databases". Every run
    reads the current state of every host involved from Echo, works out what has
    to change, and does only that.

    Per database, per destination, the current state decides the action:

      not present                     clone. Net new volumes are presented.
      already there                   refresh. Flex swaps the volumes for fresh
                                      ones from the new snapshot, same name.
      a copy whose source is gone     reported, or deleted with -RemoveOrphaned

    Whether Flex will actually accept an operation is Flex's call, not this
    script's. Every mutation is put through the matching __validate endpoint
    first, so anything Flex will not do is reported in Flex's own words before
    anything changes.

    Only databases Echo knows about are ever considered, on either end. Nothing
    is discovered locally and no database engine is contacted: every decision
    comes from the Echo API.

    ONE SNAPSHOT, MANY DESTINATIONS

    All destination hosts are served from a single snapshot of the source. Ten
    hosts cost one snapshot and one quiesce of the source, and every destination
    ends up on identical data. Running this once per host instead would take ten
    snapshots at ten different points in time, hold ten of them open, and quiesce
    production ten times over.

    COLLISIONS

    Flex runs one operation at a time, and a submission made while something else
    is running is accepted and then fails on a resource lock. So every operation
    waits for the task queue to clear before submitting, and any that fails
    anyway is resubmitted, watching the queue rather than sleeping between tries.
    See Invoke-EchoOperation.

    PARTIAL FAILURE

    Destination hosts are handled independently. One that cannot be refreshed is
    recorded and the rest carry on, so a single bad host does not leave every
    other environment stale. The returned object reports Success as false and
    lists what failed. Only a failure to snapshot the source stops everything,
    since nothing can proceed without it.

.PARAMETER SourceHost
    Host name or host id holding the databases to copy.

.PARAMETER DestinationHost
    One or more hosts that receive the copies. All are served from the same
    snapshot. Duplicates are collapsed.

.PARAMETER SourceDatabase
    Databases to copy, named explicitly. A run fails if one of them is not on the
    source host, which is the point of naming them.

    Omit it and every database Echo can see on the source host is copied,
    rediscovered on every run, so a database added there is picked up and one
    dropped there stops being copied with no job definition to edit. That is
    usually what a scheduled environment refresh wants.

.PARAMETER ExcludeDatabase
    Names to leave out of discovery. Only valid when -SourceDatabase is omitted,
    since naming databases and then excluding some of them is contradictory. The
    parameter sets enforce that: the two cannot be passed together.

.PARAMETER DestinationSuffix
    Appended to each source database name to produce the copy name, for example
    a suffix of _Dev turns SalesDB into SalesDB_Dev. Omit it and the copy keeps
    the source name, which is fine on a different host.

.PARAMETER DestinationDatabase
    Explicit names for the copies, in the same order as -SourceDatabase, applied
    on every destination host. Cannot be combined with -DestinationSuffix or with
    discovery: the parameter sets enforce both.

.PARAMETER RemoveOrphaned
    Delete copies on a destination whose source database no longer exists on the
    source host. Off by default, in which case they are reported and left alone,
    so dropping a database on the source never silently destroys the copy of it.
    Only applies when databases are discovered rather than named.

.PARAMETER ConsistencyLevel
    How the snapshot is taken. Three states, and the set is exhaustive so no two
    can be asked for at once:

      application         (default) the Silk Agent quiesces the database through
                          the VSS provider, so the copy comes up immediately
                          usable. Sends consistency_level=application, use_vss=true.
      application-novss   application consistent without the VSS provider, which
                          SQL Server 2022 and later support. Sends
                          consistency_level=application, use_vss=false.
      crash               no quiesce, nothing asked of the database engine, and
                          the copy may come up in recovery on first attach.
                          Sends consistency_level=crash. VSS does not apply.

    use_vss is always sent explicitly for the application levels rather than left
    to the API default. Whether a copy comes up usable or in recovery is too
    important to inherit from a server side default that could differ between
    builds: the request says what it wants, and the log says what was asked for.

    Flex reports which path it took in the task command_type, so a run can be
    checked after the fact: CreateVssDbSnapshotCommand, CreateGenericDBSnapshotCommand
    or CreateDBSnapshotCrashLevelCommand.

.PARAMETER TargetState
    State the copies are left in. online (default) or recovery.

.PARAMETER SnapshotPrefix
    Name prefix for the snapshot. Derived from the first database in scope when
    omitted, and always normalised to the Flex pattern of 4 to 20 characters
    matching ^[a-z][a-z0-9_-]+$.


.PARAMETER SkipValidation
    Skip the Flex __validate call before each mutation. Faster, worse errors.

.PARAMETER StepAttempts
    How many times to submit each operation before giving up on it. Default 3.
    An operation only fails outright when its error is provably permanent.

.PARAMETER IdleWaitMinutes
    How long each step waits for Flex to be free before submitting. Overrides the
    session default for this call. Zero gives up immediately when Flex is busy.

.PARAMETER SkipIdleCheck
    Do not wait for Flex to be idle. See Connect-SilkFlex -SkipIdleCheck.

.EXAMPLE
    # Every database on sql-prod, presented on sql-dev under the same names.
    # First run creates them, every run after refreshes them.
    Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev

.EXAMPLE
    # Ten environments refreshed from one snapshot, all on identical data.
    Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost $envHosts -RemoveOrphaned

.EXAMPLE
    # Skip one database and suffix the copies.
    Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev `
                          -ExcludeDatabase Scratch -DestinationSuffix _Dev

.EXAMPLE
    # Pinned to named databases.
    Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev `
                          -SourceDatabase SalesDB,Inventory -DestinationSuffix _Dev

.EXAMPLE
    # Show what would change, without changing anything.
    Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev -WhatIf
#>
    [CmdletBinding(DefaultParameterSetName = 'Discover', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourceHost,

        [Parameter(Mandatory = $true, Position = 1)]
        [string[]]$DestinationHost,

        # Naming databases and excluding databases are different jobs. The
        # parameter sets make them mutually exclusive at bind time rather than
        # accepting both and quietly ignoring one.
        [Parameter(ParameterSetName = 'Explicit', Position = 2)]
        [Parameter(ParameterSetName = 'ExplicitRenamed', Position = 2)]
        [string[]]$SourceDatabase,

        [Parameter(ParameterSetName = 'Discover')]
        [string[]]$ExcludeDatabase,

        [Parameter(ParameterSetName = 'Discover')]
        [Parameter(ParameterSetName = 'Explicit')]
        [string]$DestinationSuffix,

        [Parameter(ParameterSetName = 'ExplicitRenamed', Mandatory = $true)]
        [string[]]$DestinationDatabase,

        [switch]$RemoveOrphaned,

        [ValidateSet('application', 'application-novss', 'crash')]
        [string]$ConsistencyLevel = 'application',

        [ValidateSet('online', 'recovery')]
        [string]$TargetState = 'online',

        [string]$SnapshotPrefix,

        [switch]$SkipValidation,

        [ValidateRange(1, 20)]
        [int]$StepAttempts = $script:OpAttempts,

        [ValidateRange(0, 240)]
        [int]$IdleWaitMinutes = -1,

        [switch]$SkipIdleCheck
    )

    Assert-FlexSession
    $started = Get-Date

    # Per call overrides for the concurrency gate. Restored in the finally block
    # so one call cannot leak its settings into the next.
    $priorIdleWait  = $script:IdleWaitMinutes
    $priorIdleCheck = $script:IdleCheckEnabled
    if ($PSBoundParameters.ContainsKey('IdleWaitMinutes')) { $script:IdleWaitMinutes = $IdleWaitMinutes }
    if ($SkipIdleCheck) { $script:IdleCheckEnabled = $false }

    try {
        $wholeHost = ($PSCmdlet.ParameterSetName -eq 'Discover')

        # Nothing above is Mandatory on purpose: a missing mandatory parameter
        # makes PowerShell prompt, and a prompt in a scheduled job hangs it
        # forever. Whatever the parameter sets cannot express is checked here.
        if ($PSCmdlet.ParameterSetName -ne 'Discover' -and -not $SourceDatabase) {
            throw '-SourceDatabase is required when naming databases explicitly. Omit -ExcludeDatabase and -DestinationDatabase to copy every database Echo can see on the source host instead.'
        }
        if ($DestinationDatabase -and $DestinationDatabase.Count -ne $SourceDatabase.Count) {
            throw "-DestinationDatabase has $($DestinationDatabase.Count) name(s) but -SourceDatabase has $($SourceDatabase.Count). They must line up one for one."
        }

        $destNames = @($DestinationHost | Where-Object { $_ } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($destNames.Count -eq 0) { throw 'No destination host supplied.' }

        Write-EchoLog -Level 'STEP' -Message ('=' * 72)
        Write-EchoLog -Level 'STEP' -Message "Echo database copy: $SourceHost -> $($destNames -join ', ')"
        Write-EchoLog -Level 'STEP' -Message ('=' * 72)

        # -- Resolve the hosts -------------------------------------------------
        $srcHost = Resolve-SilkEchoHost -Name $SourceHost
        Assert-SingleEchoHost -Resolved $srcHost -Requested $SourceHost -Role 'Source'
        Assert-EchoHostUsable -EchoHost $srcHost -Role 'Source'
        Write-EchoLog -Level 'INFO' -Message "Source host '$($srcHost.host_name)' resolved to id '$($srcHost.host_id)'."

        $dstHosts = @()
        foreach ($name in $destNames) {
            $candidate = Resolve-SilkEchoHost -Name $name
            Assert-SingleEchoHost -Resolved $candidate -Requested $name -Role 'Destination'
            if (@($dstHosts | Where-Object { $_.host_id -eq $candidate.host_id }).Count -gt 0) {
                Write-EchoLog -Level 'INFO' -Message "Destination '$name' is the same host as one already listed, ignoring the duplicate."
                continue
            }
            Assert-EchoHostUsable -EchoHost $candidate -Role 'Destination'

            if ($candidate.host_id -eq $srcHost.host_id -and -not ($DestinationSuffix -or $DestinationDatabase)) {
                throw "Destination '$($candidate.host_name)' is the source host, so the copies would collide with the source databases. Supply -DestinationSuffix or -DestinationDatabase."
            }

            $dstHosts += $candidate
            Write-EchoLog -Level 'INFO' -Message "Destination host '$($candidate.host_name)' resolved to id '$($candidate.host_id)'."
        }

        # -- Read the topology once. It carries lineage for every host. --------
        Write-EchoLog -Level 'INFO' -Message 'Reading Echo topology.'
        $topology = Get-SilkEchoTopology

        # -- Desired state: which source databases are in scope ----------------
        $srcDatabases = Get-SilkEchoDatabase -HostName $srcHost.host_id
        $sourceInfo   = @()

        if ($wholeHost) {
            Write-EchoLog -Level 'INFO' -Message "Discovering the databases Echo can see on '$($srcHost.host_name)'."

            foreach ($db in $srcDatabases) {
                if ($ExcludeDatabase -and @($ExcludeDatabase | Where-Object { $_.ToLowerInvariant() -eq $db.name.ToLowerInvariant() }).Count -gt 0) {
                    Write-EchoLog -Level 'INFO' -Message "  skipping '$($db.name)' (excluded)"
                    continue
                }
                $sourceInfo += [pscustomobject]@{ Name = $db.name; Id = [string]$db.id }
            }

            if ($sourceInfo.Count -eq 0) {
                $known = ($srcDatabases | ForEach-Object { $_.name }) -join ', '
                if (-not $known) { $known = 'nothing' }
                throw "No databases on '$($srcHost.host_name)' are in scope to copy. Echo can see: $known"
            }

            Write-EchoLog -Level 'INFO' -Message "In scope ($($sourceInfo.Count)): $(($sourceInfo | ForEach-Object { $_.Name }) -join ', ')"
        }
        else {
            foreach ($name in $SourceDatabase) {
                $match = $srcDatabases | Where-Object { $_.name -ceq $name } | Select-Object -First 1
                if (-not $match) { $match = $srcDatabases | Where-Object { $_.name.ToLowerInvariant() -eq $name.ToLowerInvariant() } | Select-Object -First 1 }
                if (-not $match) {
                    $known = ($srcDatabases | ForEach-Object { $_.name }) -join ', '
                    throw "Source database '$name' was not found on '$($srcHost.host_name)'. Databases Echo can see there: $known"
                }
                $sourceInfo += [pscustomobject]@{ Name = $match.name; Id = [string]$match.id }
            }
        }

        $liveSourceIds = @($srcDatabases | ForEach-Object { [string]$_.id })

        # -- Current state, and what each destination needs --------------------
        $destPlans = @()

        foreach ($dh in $dstHosts) {
            $dstEntry     = Get-TopologyHostEntry -Topology $topology -HostId $dh.host_id
            $dstDatabases = if ($dstEntry) { @($dstEntry.databases) } else { @() }

            $plan    = @()
            $orphans = @()

            for ($i = 0; $i -lt $sourceInfo.Count; $i++) {
                $src = $sourceInfo[$i]

                $targetName = $src.Name
                if ($DestinationDatabase)   { $targetName = $DestinationDatabase[$i] }
                elseif ($DestinationSuffix) { $targetName = "$($src.Name)$DestinationSuffix" }

                $existing = $dstDatabases | Where-Object { $_.name -ceq $targetName } | Select-Object -First 1
                if (-not $existing) {
                    $existing = $dstDatabases | Where-Object { $_.name -and $_.name.ToLowerInvariant() -eq $targetName.ToLowerInvariant() } | Select-Object -First 1
                }

                if ($existing) {
                    $plan += [pscustomobject]@{
                        SourceName = $src.Name; SourceId = $src.Id; TargetName = $targetName
                        Action     = 'Refresh'; ExistingId = [string]$existing.id
                        Reason     = 'already on the destination host'
                    }
                }
                else {
                    $plan += [pscustomobject]@{
                        SourceName = $src.Name; SourceId = $src.Id; TargetName = $targetName
                        Action     = 'Clone';   ExistingId = $null
                        Reason     = 'not present on the destination host'
                    }
                }
            }

            # A copy whose source database has gone. Only meaningful when this run
            # knows the source host's full database list, which explicit mode does
            # not: there the caller named a subset and the rest is not our business.
            if ($wholeHost) {
                foreach ($existing in $dstDatabases) {
                    $lineage = Get-DatabaseLineage -Database $existing
                    if (-not $lineage.IsEchoClone) { continue }
                    if ($lineage.SourceHostId -ne $srcHost.host_id) { continue }
                    if ($liveSourceIds -contains [string]$lineage.SourceDbId) { continue }

                    $orphans += [pscustomobject]@{
                        Name = $existing.name; Id = [string]$existing.id; SourceDbId = [string]$lineage.SourceDbId
                    }
                }
            }

            $destPlans += [pscustomobject]@{
                Host    = $dh
                Plan    = $plan
                Orphans = $orphans
                Failed  = $false
                Error   = $null
            }
        }

        # -- Report the plan, host by host -------------------------------------
        Write-EchoLog -Level 'STEP' -Message 'Plan:'
        foreach ($dp in $destPlans) {
            Write-EchoLog -Level 'STEP' -Message "  $($dp.Host.host_name)"

            foreach ($p in $dp.Plan) {
                Write-EchoLog -Level 'INFO' -Message ("    {0,-8} {1} -> {2}  ({3})" -f $p.Action, $p.SourceName, $p.TargetName, $p.Reason)
            }
            foreach ($o in $dp.Orphans) {
                $why = if ($RemoveOrphaned) { 'source database is gone, removing it' } else { 'source database is gone, leaving it alone' }
                Write-EchoLog -Level 'WARN' -Message ("    {0,-8} {1}  ({2})" -f 'Orphan', $o.Name, $why)
            }
            if ($dp.Plan.Count -eq 0 -and $dp.Orphans.Count -eq 0) {
                Write-EchoLog -Level 'INFO' -Message '    nothing to do'
            }
        }

        $viable = $destPlans

        $totalClone   = @($viable | ForEach-Object { $_.Plan } | Where-Object { $_.Action -eq 'Clone' }).Count
        $totalRefresh = @($viable | ForEach-Object { $_.Plan } | Where-Object { $_.Action -eq 'Refresh' }).Count
        $totalOrphan  = @($viable | ForEach-Object { $_.Orphans }).Count

        if ($WhatIfPreference) {
            Write-EchoLog -Level 'WARN' -Message 'WhatIf: stopping before the snapshot. Nothing has been changed.'
            return New-EchoCopyResult -Started $started -WhatIf $true -WholeHost $wholeHost `
                -SourceHost $srcHost -SourceInfo $sourceInfo -DestPlans $destPlans `
                -SnapshotId $null -SnapshotTaskId $null -ConsistencyLevel $ConsistencyLevel `
                -TargetState $TargetState -Results @() `
                -PlannedClone $totalClone -PlannedRefresh $totalRefresh -PlannedOrphan $totalOrphan
        }

        $summaryTarget = "$($sourceInfo.Count) database(s) from $($srcHost.host_name) to $($viable.Count) host(s)"
        if (-not $PSCmdlet.ShouldProcess($summaryTarget, 'Snapshot and copy')) { return $null }

        # -- Snapshot the source, once, for every destination ------------------
        if (-not $SnapshotPrefix) { $SnapshotPrefix = $sourceInfo[0].Name }
        $sourceNames = @($sourceInfo | ForEach-Object { $_.Name })

        $snapshot = New-SilkEchoSnapshot -SourceHost $srcHost.host_id `
                                         -Database $sourceNames `
                                         -NamePrefix $SnapshotPrefix `
                                         -ConsistencyLevel $ConsistencyLevel `
                                         -SkipValidation:$SkipValidation `
                                         -Attempts $StepAttempts `
                                         -Confirm:$false

        $snapshotId = $snapshot.SnapshotId

        # The db_id a clone is asked for is the source database id as recorded
        # inside the snapshot. Read it back rather than assuming it matches the
        # live host.
        $snapshotRecord = Get-SilkEchoSnapshot -SnapshotId $snapshotId | Select-Object -First 1
        $snapDbId = {
            param($SourceName, $Fallback)
            if ($snapshotRecord) {
                $hit = @($snapshotRecord.databases) | Where-Object { $_.db_name -eq $SourceName } | Select-Object -First 1
                if ($hit -and $hit.db_id) { return [string]$hit.db_id }
            }
            return $Fallback
        }

        $results = @()

        # -- Refresh. The API is per host, so this is one call per host. -------
        foreach ($dp in $viable) {
            if ($dp.Failed) { continue }
            $refreshTargets = @($dp.Plan | Where-Object { $_.Action -eq 'Refresh' })
            if ($refreshTargets.Count -eq 0) { continue }

            $names = @($refreshTargets | ForEach-Object { $_.TargetName })
            try {
                $refresh = Update-SilkEchoClone -HostName $dp.Host.host_id `
                                                -Database $names `
                                                -SnapshotId $snapshotId `
                                                -TargetState $TargetState `
                                                -SkipValidation:$SkipValidation `
                                                -Attempts $StepAttempts `
                                                -Confirm:$false
                foreach ($p in $refreshTargets) {
                    $results += [pscustomobject]@{
                        DestinationHost     = $dp.Host.host_name
                        SourceDatabase      = $p.SourceName
                        DestinationDatabase = $p.TargetName
                        Action              = 'Refresh'
                        TaskId              = $refresh.TaskId
                        DurationSeconds     = $refresh.DurationSeconds
                    }
                }
            }
            catch {
                $dp.Failed = $true
                $dp.Error  = "the refresh failed: $($_.Exception.Message)"
                Write-EchoLog -Level 'ERROR' -Message "$($dp.Host.host_name): $($dp.Error)"
            }
        }

        # -- Clone. The API takes host_id per destination, so one call covers
        #    every host at once. If that call fails, fall back to one call per
        #    host so a single bad destination does not sink the others.
        $cloneWork = @()
        foreach ($dp in $viable) {
            if ($dp.Failed) { continue }
            foreach ($p in @($dp.Plan | Where-Object { $_.Action -eq 'Clone' })) {
                $cloneWork += [pscustomobject]@{ Dest = $dp; Item = $p }
            }
        }

        if ($cloneWork.Count -gt 0) {
            $hostsInvolved = @($cloneWork | ForEach-Object { $_.Dest.Host.host_id } | Select-Object -Unique)

            $buildDestinations = {
                param($Work)
                @($Work | ForEach-Object {
                    @{
                        HostId           = $_.Dest.Host.host_id
                        SourceDatabaseId = (& $snapDbId $_.Item.SourceName $_.Item.SourceId)
                        DatabaseName     = $_.Item.TargetName
                    }
                })
            }

            $cloned = $false
            try {
                $clone = New-SilkEchoClone -SnapshotId $snapshotId `
                                           -Destination (& $buildDestinations $cloneWork) `
                                           -TargetState $TargetState `
                                           -SkipValidation:$SkipValidation `
                                           -Attempts $StepAttempts `
                                           -Confirm:$false
                foreach ($w in $cloneWork) {
                    $results += New-EchoCloneResult -Work $w -TaskId $clone.TaskId -DurationSeconds $clone.DurationSeconds
                }
                $cloned = $true
            }
            catch {
                if ($hostsInvolved.Count -eq 1) {
                    $dp = $cloneWork[0].Dest
                    $dp.Failed = $true
                    $dp.Error  = "the clone failed: $($_.Exception.Message)"
                    Write-EchoLog -Level 'ERROR' -Message "$($dp.Host.host_name): $($dp.Error)"
                    $cloned = $true
                }
                else {
                    Write-EchoLog -Level 'WARN' -Message "The combined clone across $($hostsInvolved.Count) hosts failed ($($_.Exception.Message)). Retrying one host at a time so a single bad destination does not stop the rest."
                }
            }

            if (-not $cloned) {
                foreach ($dp in $viable) {
                    if ($dp.Failed) { continue }
                    $hostWork = @($cloneWork | Where-Object { $_.Dest.Host.host_id -eq $dp.Host.host_id })
                    if ($hostWork.Count -eq 0) { continue }

                    try {
                        $clone = New-SilkEchoClone -SnapshotId $snapshotId `
                                                   -Destination (& $buildDestinations $hostWork) `
                                                   -TargetState $TargetState `
                                                   -SkipValidation:$SkipValidation `
                                                   -Attempts $StepAttempts `
                                                   -Confirm:$false
                        foreach ($w in $hostWork) {
                            $results += New-EchoCloneResult -Work $w -TaskId $clone.TaskId -DurationSeconds $clone.DurationSeconds
                        }
                    }
                    catch {
                        $dp.Failed = $true
                        $dp.Error  = "the clone failed: $($_.Exception.Message)"
                        Write-EchoLog -Level 'ERROR' -Message "$($dp.Host.host_name): $($dp.Error)"
                    }
                }
            }
        }

        # -- Copies whose source is gone. Last, so an earlier failure never
        #    costs anyone a copy this run was not asked to replace.
        foreach ($dp in $viable) {
            $removed = 0
            if ($RemoveOrphaned -and -not $dp.Failed) {
                foreach ($o in $dp.Orphans) {
                    try {
                        Write-EchoLog -Level 'STEP' -Message "Removing orphaned copy '$($o.Name)' from $($dp.Host.host_name)."
                        $null = Remove-SilkEchoClone -HostName $dp.Host.host_id -DatabaseId $o.Id `
                                                     -Attempts $StepAttempts -Confirm:$false
                        $removed++
                    }
                    catch {
                        Write-EchoLog -Level 'WARN' -Message "$($dp.Host.host_name): orphaned copy '$($o.Name)' could not be removed: $($_.Exception.Message)"
                    }
                }
            }
            $dp | Add-Member -MemberType NoteProperty -Name OrphansRemoved -Value $removed -Force
        }

        # Snapshot lifetime belongs to the Flex retention policy. Nothing here
        # deletes one.

        # -- Report ------------------------------------------------------------
        $duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
        $failed   = @($destPlans | Where-Object { $_.Failed })

        Write-EchoLog -Level 'STEP' -Message ('-' * 72)
        foreach ($r in $results) {
            Write-EchoLog -Level 'STEP' -Message ("  {0,-8} {1} -> {2}.{3}" -f $r.Action, $r.SourceDatabase, $r.DestinationHost, $r.DestinationDatabase)
        }
        foreach ($f in $failed) {
            Write-EchoLog -Level 'ERROR' -Message "  FAILED   $($f.Host.host_name): $($f.Error)"
        }
        Write-EchoLog -Level 'STEP' -Message "  Snapshot $snapshotId, $ConsistencyLevel consistency, $($destPlans.Count - $failed.Count) of $($destPlans.Count) host(s) updated in ${duration}s."
        Write-EchoLog -Level 'STEP' -Message ('-' * 72)

        return New-EchoCopyResult -Started $started -WhatIf $false -WholeHost $wholeHost `
            -SourceHost $srcHost -SourceInfo $sourceInfo -DestPlans $destPlans `
            -SnapshotId $snapshotId -SnapshotTaskId $snapshot.TaskId -ConsistencyLevel $ConsistencyLevel `
            -TargetState $TargetState -Results $results
    }
    finally {
        $script:IdleWaitMinutes  = $priorIdleWait
        $script:IdleCheckEnabled = $priorIdleCheck
    }
}

function New-EchoCloneResult {
    param(
        [Parameter(Mandatory = $true)]$Work,
        [Parameter(Mandatory = $true)][string]$TaskId,
        [double]$DurationSeconds
    )

    return [pscustomobject]@{
        DestinationHost     = $Work.Dest.Host.host_name
        SourceDatabase      = $Work.Item.SourceName
        DestinationDatabase = $Work.Item.TargetName
        Action              = 'Clone'
        TaskId              = $TaskId
        DurationSeconds     = $DurationSeconds
    }
}

function New-EchoCopyResult {
    param(
        [Parameter(Mandatory = $true)][datetime]$Started,
        [bool]$WhatIf,
        [bool]$WholeHost,
        [Parameter(Mandatory = $true)]$SourceHost,
        [object[]]$SourceInfo,
        [object[]]$DestPlans,
        [string]$SnapshotId,
        [string]$SnapshotTaskId,
        [string]$ConsistencyLevel,
        [string]$TargetState,
        [object[]]$Results,
        [int]$PlannedClone = -1,
        [int]$PlannedRefresh = -1,
        [int]$PlannedOrphan = -1
    )

    $destinations = @()
    foreach ($dp in $DestPlans) {
        $mine = @($Results | Where-Object { $_.DestinationHost -eq $dp.Host.host_name })

        # On a WhatIf run nothing was executed, so counting executed work would
        # report zero underneath a plan that just listed three. Count the plan.
        $counted = if ($WhatIf) { @($dp.Plan) } else { $mine }

        $destinations += [pscustomobject]@{
            Host           = $dp.Host.host_name
            HostId         = $dp.Host.host_id
            Success        = (-not $dp.Failed)
            Error          = $dp.Error
            Cloned         = @($counted | Where-Object { $_.Action -eq 'Clone' }).Count
            Refreshed      = @($counted | Where-Object { $_.Action -eq 'Refresh' }).Count
            Orphaned       = @($dp.Orphans).Count
            OrphansRemoved = if (Test-HasProperty $dp 'OrphansRemoved') { $dp.OrphansRemoved } else { 0 }
            Plan           = $dp.Plan
        }
    }

    $failed = @($destinations | Where-Object { -not $_.Success })

    $cloned    = if ($PlannedClone   -ge 0) { $PlannedClone }   else { @($Results | Where-Object { $_.Action -eq 'Clone' }).Count }
    $refreshed = if ($PlannedRefresh -ge 0) { $PlannedRefresh } else { @($Results | Where-Object { $_.Action -eq 'Refresh' }).Count }
    $orphaned  = if ($PlannedOrphan  -ge 0) { $PlannedOrphan }  else { @($destinations | Measure-Object -Property Orphaned -Sum).Sum }

    return [pscustomobject]@{
        Success            = ($failed.Count -eq 0)
        Partial            = ($failed.Count -gt 0 -and $failed.Count -lt $destinations.Count)
        WhatIf             = $WhatIf
        Mode               = if ($WholeHost) { 'Discover' } else { 'Explicit' }
        SourceHost         = $SourceHost.host_name
        SourceHostId       = $SourceHost.host_id
        SourceDatabases    = @($SourceInfo | ForEach-Object { $_.Name })
        DestinationHosts   = @($destinations | ForEach-Object { $_.Host })
        Destinations       = $destinations
        FailedHosts        = @($failed | ForEach-Object { $_.Host })
        SnapshotId         = $SnapshotId
        SnapshotTaskId     = $SnapshotTaskId
        ConsistencyLevel   = $ConsistencyLevel
        TargetState        = $TargetState
        Results            = $Results
        Cloned             = $cloned
        Refreshed          = $refreshed
        Orphaned           = if ($null -eq $orphaned) { 0 } else { $orphaned }
        OrphansRemoved     = @($destinations | Measure-Object -Property OrphansRemoved -Sum).Sum
        DurationSeconds    = [Math]::Round(((Get-Date) - $Started).TotalSeconds, 2)
    }
}


Export-ModuleMember -Function @(
    'Connect-SilkFlex'
    'Disconnect-SilkFlex'
    'Get-SilkFlexSession'
    'Invoke-SilkFlexApi'
    'Wait-SilkEchoTask'
    'Get-SilkEchoHost'
    'Resolve-SilkEchoHost'
    'Get-SilkEchoDatabase'
    'Get-SilkEchoTopology'
    'Get-SilkEchoSnapshot'
    'Get-SilkEchoTask'
    'Wait-SilkEchoIdle'
    'Invoke-EchoOperation'
    'ConvertTo-EchoNamePrefix'
    'New-SilkEchoSnapshot'
    'New-SilkEchoClone'
    'Update-SilkEchoClone'
    'Remove-SilkEchoClone'
    'Remove-SilkEchoSnapshot'
    'Copy-SilkEchoDatabase'
)
