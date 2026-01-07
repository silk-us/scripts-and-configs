
param(
    [ValidateSet("Windows", "Linux")]
    [string]$HostType = "Windows",

    [switch]$Azure,
    [ValidateRange(2, 10)][int]$CNodeCount = 4,
    [ValidateSet("Small", "Large")][string]$Scale = "Small",

    # Remote Windows (WinRM)
    [string]$ComputerName,
    [System.Management.Automation.PSCredential]$Credential,

    # Remote Linux over SSH (PowerShell 7+)
    [string]$Hosts,
    [string]$User,
    [string]$KeyFile
)

# ========================= HTML / UI Helpers =========================
$Global:Cards = New-Object System.Collections.Generic.List[string]
$Global:Start = Get-Date
$Global:SilkRed = "#E60028"
$Global:Stats = @{ok = 0; warn = 0; err = 0; info = 0 }
$Global:RecsErr = New-Object System.Collections.ArrayList
$Global:RecsWarn = New-Object System.Collections.ArrayList
$script:AllRecsErr = @{}
$script:AllRecsWarn = @{}
$script:IsMultiHost = $false

function HtmlEscape([string]$s) {
    return ($s -replace "&", "&amp;") -replace "<", "&lt;" -replace ">", "&gt;" -replace "`r`n", "<br>" -replace "`n", "<br>"
}
function AddRecUnique($list, [string]$msg) {
    if ($null -ne $msg -and -not ($list -contains $msg)) {
        [void]$list.Add($msg)
    }
}

function AddRecAggregate([string]$severity, [string]$msg) {
    if ([string]::IsNullOrWhiteSpace($msg)) { return }
    $sev = ($severity ?? '').ToString().ToLowerInvariant()
    switch ($sev) {
        'err' { $sev = 'err' }
        'error' { $sev = 'err' }
        'warn' { $sev = 'warn' }
        'warning' { $sev = 'warn' }
        default { $sev = 'warn' }
    }
    if (-not $script:AllRecsErr) { $script:AllRecsErr = @{} }
    if (-not $script:AllRecsWarn) { $script:AllRecsWarn = @{} }
    $h = if ($script:HostName) { $script:HostName }
    elseif ($script:ComputerName) { $script:ComputerName }
    else { "local" }
    $dict = if ($sev -eq 'err') { $script:AllRecsErr } else { $script:AllRecsWarn }
    if (-not $dict.ContainsKey($msg)) {
        $dict[$msg] = New-Object System.Collections.Generic.List[string]
    }
    if (-not ($dict[$msg] -contains $h)) { [void]$dict[$msg].Add($h) }
}

function NewCard {
    param([string]$title, [string]$icon = "INFO", [string]$status = "info")
    $badge = @{ ok = "#1DB954"; warn = "#FFC107"; err = "#FF3B30"; info = "#2196F3" }[$status]
    $hdr = @"
<div class='card'>
  <div class='card-header' style='border-left:6px solid $badge'>
    <div class='card-title'>$icon $title</div>
  </div>
  <div class='card-body'>
"@
    $Global:Cards.Add($hdr) | Out-Null
}
function CloseCard { $Global:Cards.Add("</div></div>") | Out-Null }

function AddRowOKText([string]$msg) { $Global:Cards.Add("<div class='row ok'>OK: " + (HtmlEscape $msg) + "</div>") | Out-Null; $Global:Stats.ok++ }
function AddRowWarnText([string]$msg) { $Global:Cards.Add("<div class='row warn'>WARN: " + (HtmlEscape $msg) + "</div>") | Out-Null; $Global:Stats.warn++; AddRecUnique $Global:RecsWarn $msg; AddRecAggregate 'warn' $msg }
function AddRowErrText([string]$msg) { $Global:Cards.Add("<div class='row err'>ERR: " + (HtmlEscape $msg) + "</div>") | Out-Null; $Global:Stats.err++; AddRecUnique $Global:RecsErr $msg; AddRecAggregate 'err' $msg }
function AddRowInfoText([string]$msg) { $Global:Cards.Add("<div class='row info'>INFO: " + (HtmlEscape $msg) + "</div>") | Out-Null; $Global:Stats.info++ }

function DumpPre([object]$text) {
    if ($null -eq $text) { $text = "" }
    if ($text -is [System.Array]) { $text = $text -join "`n" }
    $Global:Cards.Add(
        "<div class='tbl-container'><pre class='dump'>" + (HtmlEscape ([string]$text)) + "</pre></div>"
    ) | Out-Null
}

function DumpTable {
    param([Object[]]$Data)
    if (-not $Data -or $Data.Count -eq 0) { return }
    $html = ($Data | ConvertTo-Html -Fragment)
    $html = $html -replace "<table>", "<div class='tbl-container'><table class='tbl'>"
    $html = $html -replace "</table>", "</table></div>"
    $Global:Cards.Add($html) | Out-Null
}

function BuildRecommendationsCard {
    $hasErr = $Global:RecsErr.Count -gt 0
    $hasWarn = $Global:RecsWarn.Count -gt 0
    if (-not ($hasErr -or $hasWarn)) { return "" }

    $errList = ($Global:RecsErr  | ForEach-Object { "<li>" + (HtmlEscape $_) + "</li>" }) -join ""
    $warnList = ($Global:RecsWarn | ForEach-Object { "<li>" + (HtmlEscape $_) + "</li>" }) -join ""

    $errBlock = if ($hasErr) { "<h4>Critical</h4><ul>$errList</ul>" } else { "" }
    $wrnBlock = if ($hasWarn) { "<h4>Advisory</h4><ul>$warnList</ul>" } else { "" }

    @"
<div class='card'>
  <div class='card-header' style='border-left:6px solid #FF3B30'>
    <div class='card-title'>Recommendations Summary</div>
  </div>
  <div class='card-body'>
    $errBlock
    $wrnBlock
  </div>
</div>
"@
}

function BuildGlobalRecommendationsCard {
    # We already accumulate cross-host data as:
    #   $script:AllRecsErr  : Dictionary<string msg, List<string host>>
    #   $script:AllRecsWarn : Dictionary<string msg, List<string host>>
    $hasErr  = $Script:AllRecsErr.Keys.Count  -gt 0
    $hasWarn = $Script:AllRecsWarn.Keys.Count -gt 0
    if (-not ($hasErr -or $hasWarn)) { return "" }

    # Invert to: host -> { err: [msg...], warn: [msg...] }
    $byHost = @{}
    $mkBucket = {
        @{ err = New-Object System.Collections.Generic.List[string]
           warn = New-Object System.Collections.Generic.List[string] }
    }

    if ($Script:AllRecsWarn) {
        foreach ($pair in $Script:AllRecsWarn.GetEnumerator()) {
            $msg = $pair.Key
            foreach ($h in $pair.Value) {
                if (-not $byHost.ContainsKey($h)) { $byHost[$h] = & $mkBucket }
                if (-not ($byHost[$h].warn -contains $msg)) { [void]$byHost[$h].warn.Add($msg) }
            }
        }
    }
    if ($Script:AllRecsErr) {
        foreach ($pair in $Script:AllRecsErr.GetEnumerator()) {
            $msg = $pair.Key
            foreach ($h in $pair.Value) {
                if (-not $byHost.ContainsKey($h)) { $byHost[$h] = & $mkBucket }
                if (-not ($byHost[$h].err -contains $msg)) { [void]$byHost[$h].err.Add($msg) }
            }
        }
    }

    # Prefer the user-specified host order when available; otherwise sort by name.
    $hostOrder = @()
    if ($HostList -and $HostList.Count -gt 0) {
        $hostOrder = $HostList
    } else {
        $hostOrder = ($byHost.Keys | Sort-Object)
    }

    # Build per-host sections
    $sections = foreach ($h in $hostOrder) {
        if (-not $byHost.ContainsKey($h)) { continue } # host had no recs
        $errs  = $byHost[$h].err
        $warns = $byHost[$h].warn

        $errList  = ($errs  | Sort-Object | ForEach-Object { "<li>" + (HtmlEscape $_) + "</li>" }) -join ""
        $warnList = ($warns | Sort-Object | ForEach-Object { "<li>" + (HtmlEscape $_) + "</li>" }) -join ""

        $errBlock = if ($errs.Count  -gt 0) { "<h4>Critical</h4><ul>$errList</ul>" } else { "" }
        $wrnBlock = if ($warns.Count -gt 0) { "<h4>Advisory</h4><ul>$warnList</ul>" } else { "" }

        @"
<div style='margin-bottom:16px'>
  <div class='card-title' style='font-weight:700'>Host: $(HtmlEscape $h)</div>
  $errBlock
  $wrnBlock
</div>
"@
    }

    $body = ($sections -join "`n")

    @"
<div class='card'>
  <div class='card-header' style='border-left:6px solid #FF3B30'>
    <div class='card-title'>Recommendations Summary</div>
  </div>
  <div class='card-body'>
    $body
  </div>
</div>
"@
}


function RenderPage {
    $elapsed = New-TimeSpan $Global:Start (Get-Date)
    $summary = "<div class='summary'>
  <span class='badge ok'>OK: $($Global:Stats.ok)</span>
  <span class='badge warn'>WARN: $($Global:Stats.warn)</span>
  <span class='badge err'>ERR: $($Global:Stats.err)</span>
  <span class='badge info'>INFO: $($Global:Stats.info)</span>
</div>"
    $recs = if (-not $Script:IsMultiHost) { BuildRecommendationsCard } else { "" }
    $page = @"
<!DOCTYPE html>
<html><head><meta charset='utf-8'><title>Silk Host Validator</title>
<style>
body{background:#0f0f11;color:#eaeaea;font-family:ui-monospace,Consolas,monospace;margin:0}
.header{background:#101014;border-bottom:2px solid $($Global:SilkRed);padding:14px 18px;position:sticky;top:0;z-index:1;display:flex;justify-content:space-between;align-items:center}
.header h1{font-size:18px;margin:0;color:#fff}
.header small{color:#aaa}
.container{padding:20px;max-width:1800px;margin:0 auto}
.summary{margin:14px 0;font-size:15px}
.badge{display:inline-block;padding:5px 10px;border-radius:6px;font-size:14px;font-weight:700;margin-right:8px}
.badge.ok{background:#153e2c;color:#1DB954}
.badge.warn{background:#42380f;color:#FFC107}
.badge.err{background:#4a1111;color:#FF3B30}
.badge.info{background:#1a273d;color:#2196F3}
/* One card per row */
.grid{display:grid;grid-template-columns:1fr;gap:20px}
.card{background:#131318;border:1px solid #1d1d24;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,.3);overflow:hidden;grid-column:1 / -1}
.card-header{padding:12px 16px;background:#1b1b22;border-bottom:1px solid #222}
.card-title{font-weight:700;color:#fff;font-size:16px}
.card-body{padding:14px 16px}
.row{padding:8px 10px;border-left:4px solid transparent;border-radius:6px;margin:6px 0;background:#17171d;font-size:14px}
.row.ok{border-color:#1DB954}
.row.warn{border-color:#FFC107}
.row.err{border-color:#FF3B30}
.row.info{border-color:#2196F3}
.tbl-container{grid-column:1 / -1; margin:24px 0; width:100%}
pre.dump{background:#0f0f14;border:1px solid #222;border-radius:8px;padding:14px;overflow:auto;max-height:400px;font-size:14px}
.tbl{width:100%;border-collapse:collapse;font-size:14px;margin-top:10px}
.tbl th,.tbl td{border:1px solid #2a2a33;padding:10px 12px;text-align:left}
.tbl th{background:#1b1b22}
.foot{color:#9a9aa2;padding:18px;text-align:center}
</style></head>
<body>
<div class='header'><h1>Silk Data Platform – Host Best Practices Validator</h1><small>Elapsed $([int]$elapsed.TotalSeconds)s</small></div>
<div class='container'>
  $summary
  $recs
  <div class='grid'>
$($Global:Cards -join "`n")
  </div>
</div>
<div class='foot'>© Silk. This report is informational – no settings were changed.</div>
</body></html>
"@
    return $page
}

# ========================= Interactive Prompts =========================
if (-not $PSBoundParameters.ContainsKey('HostType')) {
    do {
        $ans = (Read-Host "Select host type: [W]indows / [L]inux").Trim()
    } until ($ans -match '^(?i:w|windows|l|linux)$')
    $HostType = if ($ans -match '^(?i:w|windows)$') { "Windows" } else { "Linux" }
}
if ($HostType -eq "Windows" -and $IsLinux) {
    Write-Warning "HostType is set to 'Windows', but this script is running on a Linux host. Windows hosts cannot be validated from a Linux host. Exiting..."
    exit 1
}
if (-not $PSBoundParameters.ContainsKey('Azure')) {
    do { $ans = (Read-Host "Is this host in Azure? [Y/N]").Trim() } until ($ans -match '^(?i:y|n|yes|no)$')
    $Azure = $ans -match '^(?i:y|yes)$'
}
if (-not $PSBoundParameters.ContainsKey('CNodeCount')) {
    do {
        $ans = (Read-Host "How many SDP c-nodes? (2-10) [default 4]").Trim()
        if ($ans -eq "") { $ans = "4" }
    } until ([int]::TryParse($ans, [ref]0) -and ([int]$ans -ge 2) -and ([int]$ans -le 10))
    $CNodeCount = [int]$ans
}
if (-not $PSBoundParameters.ContainsKey('Scale')) {
    do {
        $ans = (Read-Host "Host scale? [S]mall (<10 hosts) / [L]arge (>=10 hosts) [default S]").Trim()
        if ($ans -eq "") { $ans = "S" }
    } until ($ans -match '^(?i:s|small|l|large)$')
    $Scale = if ($ans -match '^(?i:s|small)$') { "Small" } else { "Large" }
}
$HostList = @()
if ($PSBoundParameters.ContainsKey('Hosts') -and $null -ne $Hosts -and ( ($Hosts -is [string] -and -not [string]::IsNullOrWhiteSpace($Hosts)) -or ($Hosts -is [object[]] -and $Hosts.Count -gt 0) )) {
    $HostList = $Hosts -split ' '
}
else {
    $hAns = (Read-Host "Hostname(s)/IP(s)? (Space separated - press Enter for local)").Trim()
    if ([string]::IsNullOrWhiteSpace($hAns)) { $HostList = @("") } else { $HostList = @($hAns -split ' ') }
}
if (-not $PSBoundParameters.ContainsKey('User') -and -not (($HostList.Count -eq 1) -and ($HostList[0] -eq ""))) {
    $User = (Read-Host "Username for remote connection(s)?").Trim()
}
if ($PSVersionTable.Platform -eq 'Win32NT') {
    if (-not (($HostList.Count -eq 1) -and ($HostList[0] -eq ""))) {
        if (-not $script:Credential ) {
            if ($User) {
                $script:Credential = Get-Credential -UserName $User
            }
            else {
                $script:Credential = Get-Credential -Message "Windows credentials"
            }
        }
    }
}

function Invoke-Windows {
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [string]$User,
        [string]$Command,
        [System.Management.Automation.PSCredential]$Credential = $script:Credential
    )

    if ($ComputerName -and -not $Credential) {
        throw "No credential available for remote execution. Please try running the script again."
    }

    if ($ComputerName) {
        Invoke-Command -ComputerName $ComputerName -Credential $Credential -ScriptBlock {
            param($cmd)
            Invoke-Expression $cmd
        } -ArgumentList $Command
    }
    else {
        Invoke-Expression $Command
    }
}

function Get-SshMuxOptions {
    param([string]$User, [string]$HostName)
    try {
        $sshDir = Join-Path $HOME ".ssh"
    }
    catch {
        $sshDir = "$HOME/.ssh"
    }
    if (-not (Test-Path $sshDir)) { Write-Host "$HOME/.ssh directory does not exist. Please create the directory, then try running the script again." }

    $cp = Join-Path $sshDir ("cm-{0}@{1}-%p" -f $User, $HostName)

    return @(
        '-o', 'ControlMaster=auto',
        '-o', ("ControlPath={0}" -f $cp),
        '-o', 'ControlPersist=20'
    )
}

function LinuxRun {
    param(
        [string]$HostName,
        [string]$User,
        [string]$KeyFile,
        [string]$Command
    )
    if (-not $HostName) {
        return bash -lc $Command
    }
    if (-not $User) {
        $User = $env:USERNAME
    }
    $IsWindowsEnv = $PSVersionTable.Platform -eq 'Win32NT'
    $remoteCmd = "$Command"
    if ($IsWindowsEnv) {
        if (-not (Get-Module -ListAvailable Posh-SSH)) {
            throw "Posh-SSH module not found. Install with: Install-Module -Name Posh-SSH"
        }
        Import-Module Posh-SSH -ErrorAction Stop
        $sshParams = @{
            ComputerName = $HostName
            AcceptKey    = $true
            ErrorAction  = 'Stop'
        }
        if ($KeyFile) {
            $sshParams.KeyFile = $KeyFile
        }
        $sshParams.Credential = $Credential
        $Session = New-SSHSession @sshParams
        $Result = Invoke-SSHCommand -SSHSession $Session -Command $remoteCmd

        Remove-SSHSession -SSHSession $Session | Out-Null

        return $Result.Output
    }
    else {
        $remote = "$User@$HostName"
        if ($KeyFile) {
            $mux = Get-SshMuxOptions -User $User -HostName $HostName
            $sshArgs = @('-i', $KeyFile, '-o', 'StrictHostKeyChecking=accept-new', '-o', 'LogLevel=ERROR') + $mux
            return (& ssh @sshArgs $remote $remoteCmd 2>&1)
        }
        else {
            $mux = Get-SshMuxOptions -User $User -HostName $HostName
            $sshArgs = @('-o', 'StrictHostKeyChecking=accept-new', '-o', 'LogLevel=ERROR') + $mux
            return (& ssh @sshArgs $remote $remoteCmd 2>&1)
        }
    }
}

# ========================= WINDOWS VALIDATION =========================
function ValidateWindows {
    param([string]$ComputerName, [System.Management.Automation.PSCredential]$Credential, [switch]$Azure, [int]$CNodes, [string]$Scale)

    # ---------- System Information ----------
    NewCard "System Information" "SYS" "info"
    try {
        $os = Invoke-Windows -ComputerName $ComputerName -Credential $Credential -Command 'Get-CimInstance Win32_OperatingSystem'
        $cs = Invoke-Windows -ComputerName $ComputerName -Credential $Credential -Command 'Get-CimInstance Win32_ComputerSystem'
        AddRowInfoText ("Windows OS Caption is - {0}" -f $os.Caption)
        AddRowInfoText ("Windows OS Version is - {0}" -f $os.Version)
        AddRowInfoText ("Number Of Processors (Sockets) - {0}" -f $cs.NumberOfProcessors)
        AddRowInfoText ("Number Of Logical Processors (vCPUs) - {0}" -f $cs.NumberOfLogicalProcessors)
        AddRowInfoText ("Total Physical Memory (GiB) - {0}" -f [math]::Round($cs.TotalPhysicalMemory / 1GB, 2))
        AddRowOKText "System info collected"
    }
    catch { AddRowErrText ("System info failed: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- iSCSI Service ----------
    NewCard "iSCSI Service" "ISCSI" "info"
    try {
        $svc = Invoke-Windows $ComputerName $Credential 'Get-Service MSiSCSI'
        if ($svc.Status -eq 'Running') { AddRowOKText "MSiSCSI service is running" } else { AddRowErrText ("MSiSCSI service status is {0}" -f $svc.Status) }
        if ($svc.StartType -eq 'Automatic') { AddRowOKText "MSiSCSI startup = Automatic" } else { AddRowWarnText ("MSiSCSI startup is {0}" -f $svc.StartType) }
    }
    catch { AddRowErrText ("Could not query MSiSCSI: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- MPIO Strict Validation ----------
    NewCard "MPIO Settings" "MPIO" "info"
    try {
        $hasMPIO = Invoke-Windows $ComputerName $Credential 'Get-Command Get-MPIOSetting -ErrorAction SilentlyContinue'
        if (-not $hasMPIO) { AddRowErrText "Get-MPIOSetting not found (MPIO feature/module not installed)" }
        else {
            $mp = Invoke-Windows $ComputerName $Credential 'Get-MPIOSetting'
            DumpPre (($mp | Format-List * | Out-String))

            function CheckVal([string]$name, $actual, $expected, [string]$impact) {
                if ($null -eq $actual) { AddRowErrText ("{0} not found" -f $name) ; return }
                if ($actual.ToString() -eq $expected.ToString()) { AddRowOKText ("{0} = {1}" -f $name, $actual) }
                else { AddRowErrText ("{0} = {1} (expected {2}) -> Impact: {3}" -f $name, $actual, $expected, $impact) }
            }

            $DiskTimeoutActual = if ($mp.PSObject.Properties.Match('DiskTimeoutValue').Count -gt 0 -and $mp.DiskTimeoutValue) { $mp.DiskTimeoutValue } else { $mp.DiskTimeout }
            CheckVal "PathVerificationState" $mp.PathVerificationState "Enabled" "Path failure may not be detected promptly"
            CheckVal "PathVerificationPeriod" $mp.PathVerificationPeriod 1 "Slower path verification may delay failover"
            CheckVal "DiskTimeoutValue" $DiskTimeoutActual 100 "Lower values may trigger premature disk timeout"
            CheckVal "RetryCount" $mp.RetryCount 3 "Too low may cause early IO failure; too high adds latency"
            CheckVal "RetryInterval" $mp.RetryInterval 3 "Too high increases retry latency"
            CheckVal "UseCustomPathRecoveryTime" $mp.UseCustomPathRecoveryTime "Enabled" "Non-optimized path recovery"
            CheckVal "CustomPathRecoveryTime" $mp.CustomPathRecoveryTime 20 "Too short/long may affect path stabilization"
            CheckVal "PDORemovePeriod" $mp.PDORemovePeriod 20 "Device removal timing mismatch"

            $lbRaw = Invoke-Windows $ComputerName $Credential 'Get-MSDSMGlobalDefaultLoadBalancePolicy | Out-String'
            $lbNorm = ($lbRaw -replace '\r?\n', ' ').Trim()
            if ($lbNorm -match '(?i)least\s*queue\s*depth|\bLQD\b') {
                AddRowOKText "Global Load Balance Policy = Least Queue Depth (LQD)"
            }
            else {
                AddRowErrText ("Global Load Balance Policy = {0} (expected Least Queue Depth/LQD)" -f $lbNorm)
            }

            try {
                $auto = Invoke-Windows $ComputerName $Credential 'Get-MSDSMAutomaticClaimSettings -ErrorAction SilentlyContinue'
            }
            catch { $auto = $null }
            $iscsiClaim = $null
            $rows = @()

            if ($auto) {
                foreach ($p in @('SAS', 'iSCSI')) {
                    if ($auto.PSObject.Properties.Match($p).Count -gt 0) {
                        $val = $auto.$p
                        $rows += [pscustomobject]@{ Name = $p; Value = $val }
                        if ($p -eq 'iSCSI') { $iscsiClaim = $val }
                    }
                }
                if ($rows.Count -eq 0) {
                    $arr = @($auto)
                    if ($arr.Count -gt 0 -and $arr[0].PSObject.Properties.Match('Name').Count -gt 0 -and $arr[0].PSObject.Properties.Match('Value').Count -gt 0) {
                        foreach ($entry in $arr) {
                            $rows += [pscustomobject]@{ Name = $entry.Name; Value = $entry.Value }
                        }
                        $iscsiClaim = ($rows | Where-Object { $_.Name -match '^(?i)iSCSI$' } | Select-Object -First 1 -ExpandProperty Value -ErrorAction SilentlyContinue)
                    }
                }
                if ($rows.Count -eq 0 -and ($auto -is [hashtable])) {
                    foreach ($k in @('SAS', 'iSCSI')) {
                        if ($auto.ContainsKey($k)) {
                            $rows += [pscustomobject]@{ Name = $k; Value = $auto[$k] }
                        }
                    }
                    $iscsiClaim = ($rows | Where-Object { $_.Name -match '^(?i)iSCSI$' } | Select-Object -First 1 -ExpandProperty Value -ErrorAction SilentlyContinue)
                }

                if ($rows.Count -gt 0) { DumpTable $rows }

                $parsed = $null
                if ($null -ne $iscsiClaim) {
                    if ($iscsiClaim -is [bool]) { $parsed = [bool]$iscsiClaim }
                    else {
                        $s = $iscsiClaim.ToString()
                        if ($s -match '^(?i:true|1|enabled|yes)$') { $parsed = $true }
                        elseif ($s -match '^(?i:false|0|disabled|no)$') { $parsed = $false }
                    }
                }
                if ($parsed -ne $null) {
                    if ($parsed) { AddRowOKText "MSDSM automatic claim for BusType iSCSI = Enabled" }
                    else { AddRowErrText "MSDSM automatic claim for BusType iSCSI = Disabled (expected Enabled)" }
                }
                else {
                    AddRowWarnText "Could not parse iSCSI auto-claim from Get-MSDSMAutomaticClaimSettings output"
                }
            }
            else {
                $mpc = Invoke-Windows $ComputerName $Credential '(mpclaim.exe -s -d) 2>$null'
                if ($mpc) {
                    DumpPre ($mpc | Out-String)
                    if (($mpc | Select-String -Pattern '(?i)BusType\s+.*iSCSI.*Yes')) {
                        AddRowOKText "MSDSM automatic claim for BusType iSCSI = Enabled"
                    }
                    else {
                        AddRowWarnText "Could not confirm iSCSI automatic claim from mpclaim output; run Get-MSDSMAutomaticClaimSettings manually"
                    }
                }
                else { AddRowWarnText "mpclaim not available; unable to determine automatic claim setting" }
            }
        }
    }
    catch { AddRowErrText ("MPIO validation error: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- Silk Disks ----------
    NewCard "Silk Disks" "DISKS" "info"
    try {
        $silk = Invoke-Windows $ComputerName $Credential 'Get-PhysicalDisk | Where-Object { $_.FriendlyName -match "SILK|KMNRIO" }'
        if ($silk) {
            $tbl = foreach ($p in $silk) {
                [PSCustomObject]@{
                    DeviceId          = $p.DeviceId
                    SerialNumber      = $p.SerialNumber
                    FriendlyName      = $p.FriendlyName
                    CanPool           = $p.CanPool
                    OperationalStatus = ($p.OperationalStatus -join ",")
                    HealthStatus      = $p.HealthStatus
                    'Size-Gb'         = [math]::Round($p.Size / 1GB, 4)
                }
            }
            DumpTable $tbl
            $glob = Invoke-Windows $ComputerName $Credential 'Get-MSDSMGlobalDefaultLoadBalancePolicy | Out-String'
            if ($glob -match '(?i)least\s*queue\s*depth|\bLQD\b') { AddRowOKText "Expected per-disk policy is LQD (global=LQD)" } else { AddRowWarnText "Global policy is not LQD; verify per-disk policy on each Silk volume" }
        }
        else {
            AddRowWarnText "No Silk/KMNRIO disks detected"
        }
    }
    catch { AddRowErrText ("Disk enumeration error: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- CTRL LUN (size-based) ----------
    NewCard "CTRL LUN" "CTRL" "info"
    try {
        $ctrlDisks = Invoke-Windows $ComputerName $Credential 'Get-Disk | Where-Object { $_.FriendlyName -match "SILK|KMNRIO" -and $_.Size -lt 1MB }'
        if ($ctrlDisks) {
            foreach ($d in $ctrlDisks) {
                if ($d.IsOffline) { AddRowOKText ("CTRL LUN (DiskNumber {0}) Offline" -f $d.Number) }
                else { AddRowErrText ("CTRL LUN (DiskNumber {0}) is ONLINE – must be Offline" -f $d.Number) }
            }
        }
        else { AddRowInfoText "No CTRL LUN detected" }
    }
    catch { AddRowErrText ("CTRL LUN check failed: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- TRIM/UNMAP & Defrag ----------
    NewCard "TRIM/UNMAP & Defrag" "TRIM" "info"
    try {
        $val = Invoke-Windows $ComputerName $Credential '(Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name DisableDeleteNotification -ErrorAction SilentlyContinue).DisableDeleteNotification'
        if ($null -eq $val) { AddRowWarnText "DisableDeleteNotification not found" }
        elseif ($val -eq 1) { AddRowOKText "TRIM/UNMAP registry = 1 (disabled for controlled retrim)" }
        else { AddRowErrText ("TRIM/UNMAP registry = {0} (expected 1)" -f $val) }
    }
    catch { AddRowErrText ("TRIM registry read error: {0}" -f $_.Exception.Message) }
    try {
        $task = Invoke-Windows $ComputerName $Credential 'Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue'
        if ($task -and -not $task.Settings.Enabled) { AddRowOKText "Scheduled Disk Fragmentation policy is Disabled" } else { AddRowWarnText "Scheduled Disk Fragmentation policy not Disabled"
        }

    }
    catch { AddRowWarnText ("Could not read ScheduledDefrag task: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- iSCSI Sessions & Scaling (count only) ----------
    NewCard "iSCSI Sessions & Scaling" "SESS" "info"
    try {
        $winConnRows = Invoke-Windows $ComputerName $Credential @'
        $iqnRegex = "(?i)^iqn\.2009-01\.(us\.silk:storage\.sdp|com\.kaminario:storage\.k2)"

        # Gather Silk/Kaminario target IPs from session list
        $sessions = Get-IscsiSession -ErrorAction SilentlyContinue | Where-Object { $_.IsConnected -eq $true -and $_.TargetNodeAddress -match $iqnRegex }
        $targetIps = @{}
        foreach ($s in $sessions) {
            foreach ($conn in ($s | Get-IscsiConnection -ErrorAction SilentlyContinue)) {
                $targetIps[$conn.TargetAddress] = $true
            }
        }

        # If no connections found from sessions, fall back to all connections (some systems omit Get-IscsiConnection per-session)
        if (-not $targetIps.Count) {
            $allConns = Get-IscsiConnection -ErrorAction SilentlyContinue
            foreach ($c in $allConns) { $targetIps[$c.TargetAddress] = $true }
        }

        # Emit all connections that match those target IPs
        if ($targetIps.Count) {
            $allConns = Get-IscsiConnection -ErrorAction SilentlyContinue
            foreach ($c in $allConns) {
                if ($targetIps.ContainsKey($c.TargetAddress)) {
                    [pscustomobject]@{ TargetAddress = $c.TargetAddress }
                }
            }
        }
'@

        $cnodeSessions = @{}
        if ($winConnRows) {
            foreach ($row in @($winConnRows)) {
                $ip = $row.TargetAddress
                if ($ip) {
                    if (-not $cnodeSessions.ContainsKey($ip)) { $cnodeSessions[$ip] = 0 }
                    $cnodeSessions[$ip]++
                }
            }
        }

        $totalCnodeSessions = ($cnodeSessions.Values | Measure-Object -Sum).Sum
        if (-not $totalCnodeSessions) { $totalCnodeSessions = 0 }
        $connectedCnodes = $cnodeSessions.Keys.Count

        AddRowInfoText ("Active iSCSI sessions to C-nodes (Windows): {0} across {1} C-node(s)" -f $totalCnodeSessions, $connectedCnodes)

        $recSmall = @{2 = 12; 3 = 8; 4 = 6; 5 = 5; 6 = 4; 7 = 4; 8 = 3; 9 = 3; 10 = 2 }
        $recLarge = @{2 = 6;  3 = 4; 4 = 3; 5 = 3; 6 = 2; 7 = 2; 8 = 1; 9 = 1;  10 = 1 }
        $rec = if ($Scale -eq "Small") { $recSmall } else { $recLarge }
        $needPerCnode = $rec[$CNodes]

        if (-not $needPerCnode) {
            AddRowWarnText ("No recommendation found for {0} C-nodes ({1} scale)" -f $CNodes, $Scale)
        } elseif ($connectedCnodes -eq 0) {
            AddRowWarnText ("No active iSCSI sessions to Silk/Kaminario C-nodes detected on Windows host")
        } else {
            $under = @()
            foreach ($ip in $cnodeSessions.Keys) {
                $count = $cnodeSessions[$ip]
                if ($count -lt $needPerCnode) {
                    $under += @{ IP = $ip; Count = $count }
                }
            }
            if ($under.Count -gt 0) {
                foreach ($entry in $under) {
                    AddRowWarnText ("C-node {0} has {1}/{2} iSCSI session(s) (recommended per C-node; {3} scale, {4} total C-nodes expected)" -f `
                        $entry.IP, $entry.Count, $needPerCnode, $Scale, $CNodes)
                }
            } else {
                AddRowOKText ("All connected C-nodes ({0}) meet the recommendation of {1} session(s) per C-node ({2} scale)" -f `
                    $connectedCnodes, $needPerCnode, $Scale)
            }
            if ($connectedCnodes -lt $CNodes) {
                AddRowWarnText ("Only {0}/{1} expected C-nodes have active sessions to this Windows host" -f $connectedCnodes, $CNodes)
            }
        }
    }
    catch { AddRowErrText ("iSCSI session query failed: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- Networking (RSC & NICs) ----------
    NewCard "Networking (RSC & NICs)" "NET" "info"
    try {
        $nics = Invoke-Windows $ComputerName $Credential 'Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select Name, InterfaceDescription, MacAddress, LinkSpeed'
        DumpTable $nics
    }
    catch { AddRowWarnText ("NIC inventory failed: {0}" -f $_.Exception.Message) }

    try {
        $rsc = Invoke-Windows $ComputerName $Credential 'Get-NetAdapterRsc -ErrorAction SilentlyContinue | Sort-Object -Property Name'
        if ($rsc) {
            $view = $rsc | Select-Object Name, IPv4Enabled, IPv6Enabled, IPv4OperationalState, IPv6OperationalState
            DumpTable $view
            $bad = @($rsc | Where-Object { $_.IPv4Enabled -or $_.IPv6Enabled } | Select-Object -ExpandProperty Name -Unique)
            if ($bad.Count -gt 0) { 
                $action = "Get-NetAdapterRsc | Disable-NetAdapterRsc (NOTE: running this may cause a brief network interruption on the selected adapter)"
                if ($Azure) { 
                    AddRowErrText ("RSC is ENABLED on adapters: {0}. Expected: Disabled on Azure. Impact: packet coalescing can increase latency and cause throughput anomalies. Action: {1}" -f (($bad -join ', ')), $action) 
                }
                else {
                    AddRowWarnText ("RSC is ENABLED on adapters: {0}. Not recommended for SDP hosts. Action: {1}" -f (($bad -join ', ')), $action)
                }
            }
            else { AddRowOKText "All adapters have RSC disabled (compliant)" }
        }
        else {
            AddRowWarnText "Get-NetAdapterRsc returned no results (older OS or module). Consider checking adapter advanced properties for 'Receive Segment Coalescing'."
            $adv = Invoke-Windows $ComputerName $Credential 'Get-NetAdapterAdvancedProperty -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Receive Segment Coalescing" } | Select-Object Name, DisplayName, DisplayValue'
            if ($adv) { DumpTable $adv }
        }
    }
    catch { AddRowErrText ("RSC validation failed: {0}" -f $_.Exception.Message) }
    CloseCard

    # ---------- Dedicated iSCSI NICs ----------
    NewCard "Dedicated iSCSI NICs" "NIC" "info"
    try {
        $iscsiNics = @()
        $sessions2 = Invoke-Windows $ComputerName $Credential 'Get-IscsiSession -ErrorAction SilentlyContinue'
        foreach ($s in $sessions2) {
            if ($s.InitiatorPortalAddress) {
                $ip = ($s.InitiatorPortalAddress).ToString().Replace("`"", "'")
                $cmd = "Get-NetIPConfiguration | Where-Object { `$_.IPv4Address.IPAddress -eq '$ip' } | Select-Object -First 1 -ExpandProperty InterfaceAlias"
                $alias = Invoke-Windows $ComputerName $Credential $cmd
                if ($alias) { $iscsiNics += $alias }
            }
        }
        $iscsiNics = $iscsiNics | Select-Object -Unique
        $count = (@($iscsiNics)).Count
        if ($count -lt 1) { AddRowWarnText ("No NIC detected for iSCSI (requires dedicated NIC)" -f $count) }
        else { AddRowOKText ("Dedicated iSCSI NICs: {0}" -f ($iscsiNics -join ', ')) }
    }
    catch { AddRowWarnText ("Dedicated NIC evaluation failed: {0}" -f $_.Exception.Message) }
    CloseCard
}

# ========================= LINUX VALIDATION =========================
function Add-CheckOK([string]$Message) { AddRowOKText  $Message }
function Add-CheckWarn([string]$Message) { AddRowWarnText $Message }
function Add-CheckErr([string]$Message) { AddRowErrText  $Message }

function Invoke-Linux([string]$Command) {
    LinuxRun $HostName $User $KeyFile $Command
}

function Parse-Kv($Lines, [string]$Key) {
    $pattern = "(?im)^\s*" + [regex]::Escape($Key) + "\s*:\s*(.+)$"
    $ln = $Lines | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if ($ln) { return ($ln -replace $pattern, '$1').Trim() }
    return ""
}

function ValidateLinux {
    param([string]$Hosts, [string]$User, [string]$KeyFile, [switch]$Azure, [int]$CNodes, [string]$Scale)

    NewCard "System Information (Linux)" "SYS" "info"
    try {
        $uname = Invoke-Linux "uname -a"
        $mem = Invoke-Linux "free -h"
        DumpPre @($uname; ""; $mem)
        AddRowOKText "System info collected"
    }
    catch { AddRowErrText ("Linux system info error: {0}" -f $_.Exception.Message) }
    CloseCard

    NewCard "Linux Package Validation" "PKG" "info"
    try {
        $osRelease = Invoke-Linux "cat /etc/os-release 2>/dev/null"

        $osId = (($osRelease | Where-Object { $_ -match '^ID=' }       | Select-Object -First 1) -replace '^ID=', '' -replace '"', '').Trim()
        $osLike = (($osRelease | Where-Object { $_ -match '^ID_LIKE=' }  | Select-Object -First 1) -replace '^ID_LIKE=', '' -replace '"', '').Trim()

        if (-not $osId) {
            $redhatRel = Invoke-Linux "cat /etc/redhat-release 2>/dev/null"
            if ($redhatRel -and ($redhatRel -join ' ') -match '(?i)red hat|centos|rocky|alma|oracle linux|fedora') {
                $osId = 'rhel'
                $osLike = 'rhel fedora centos rocky almalinux ol'
            }
            else {
                $hasDpkg = (Invoke-Linux "command -v dpkg-query >/dev/null 2>&1; echo $?") | Select-Object -Last 1
                $hasRpm = (Invoke-Linux "command -v rpm >/dev/null 2>&1; echo $?")        | Select-Object -Last 1
                if ($hasDpkg -eq '0') {
                    $osId = 'debian'
                    $osLike = 'debian ubuntu'
                }
                elseif ($hasRpm -eq '0') {
                    $osId = 'rhel'
                    $osLike = 'rhel fedora centos rocky almalinux ol'
                }
                else {
                    $osId = 'unknown'
                    $osLike = 'unknown'
                }
            }
        }
        if ($osId -match '(?i)^(ubuntu|debian)$' -or $osLike -match '(?i)\bubuntu\b|\bdebian\b') {
            $pkgNames = [ordered]@{
                multipath = 'multipath-tools'
                lsscsi    = 'lsscsi'
                iscsi     = 'open-iscsi'
            }
        }
        else {
            $pkgNames = [ordered]@{
                multipath = 'device-mapper-multipath'
                lsscsi    = 'lsscsi'
                iscsi     = 'iscsi-initiator-utils'
            }
        }

        $pkgEnvLine = "env PACK1='{0}' PACK2='{1}' PACK3='{2}' " -f $pkgNames.multipath, $pkgNames.lsscsi, $pkgNames.iscsi
        $pkgCheckCmd = $pkgEnvLine + @'
        sh -lc '
        if command -v dpkg-query >/dev/null 2>&1; then
        for p in "$PACK1" "$PACK2" "$PACK3"; do
        if dpkg-query -W -f="\${Status}" "$p" 2>/dev/null | grep -q "install ok installed"; then
        v=$(dpkg-query -W -f="\${Version}" "$p")
        echo "  $p: INSTALLED ($v)"
        else
        echo "  $p: MISSING"
        fi
        done
        elif command -v rpm >/dev/null 2>&1; then
        for p in "$PACK1" "$PACK2" "$PACK3"; do
        if rpm -q "$p" >/dev/null 2>&1; then
        v=$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$p")
        echo "  $p: INSTALLED ($v)"
        else
        echo "  $p: MISSING"
        fi
        done
        else
        echo "No supported package manager found (dpkg or rpm)."
        fi
        '
'@
 
        $pkgStatus = Invoke-Linux $pkgCheckCmd
        DumpPre @(
            "Detected OS: $osId (like: $osLike)"
            ""
            "Expected packages:"
            "  multipath => $($pkgNames.multipath)"
            "  lsscsi    => $($pkgNames.lsscsi)"
            "  iscsi     => $($pkgNames.iscsi)"
            ""
            "Status:"
            $pkgStatus
        )
        
        $pkgMap = @{}
        foreach ($l in $pkgStatus) {
            if ($l -match '^\s*(?<name>[^:]+):\s*(?<state>INSTALLED|MISSING)') {
                $pkgMap[$Matches.name.Trim()] = $Matches.state
            }
        }

        foreach ($key in 'multipath', 'lsscsi', 'iscsi') {
            $pkg = $pkgNames[$key]
            switch ($pkgMap[$pkg]) {
                'INSTALLED' { AddRowOKText  ("Package {0} installed" -f $pkg) }
                'MISSING' { AddRowErrText ("Package {0} not installed" -f $pkg) }
                default { AddRowWarnText("Package {0} status unknown" -f $pkg) }
            }
        }
    }
    catch {
        AddRowErrText ("Linux package validation error: {0}" -f $_.Exception.Message) 
    }
    CloseCard

    NewCard "Multipath" "MP" "info"
    try {
        $mpath = Invoke-Linux "test -f /etc/multipath.conf && sudo sed -n '1,800p' /etc/multipath.conf || echo 'Missing /etc/multipath.conf'"
        DumpPre @("multipath.conf:"; $mpath)

        $mpathText = if ($mpath -is [System.Array]) { $mpath -join "`n" } else { [string]$mpath }

        if ($mpathText -match '^\s*Missing /etc/multipath\.conf') {
            AddRowWarnText "multipath.conf does not exist"
        }
        else {
            $requirements = @(
                @{ expect = 'find_multipaths yes';
                   pattern = '(?m)^\s*(?![#;])\s*find_multipaths\s+yes\s*$' },
                @{ expect = 'user_friendly_names yes';
                   pattern = '(?m)^\s*(?![#;])\s*user_friendly_names\s+yes\s*$' },
                @{ expect = 'polling_interval 1';
                   pattern = '(?m)^\s*(?![#;])\s*polling_interval\s+1\s*$' },
                @{ expect = 'verbosity 2';
                   pattern = '(?m)^\s*(?![#;])\s*verbosity\s+2\s*$' },

                @{ expect = 'devnode "^(ram|raw|loop|fd|md|dm-|sr|scd|st)[0-9]*"';
                   pattern = '(?m)^\s*(?![#;])\s*devnode\s+"\^\(ram\|raw\|loop\|fd\|md\|dm-\|sr\|scd\|st\)\[0-9\]\*"\s*$' },
                @{ expect = 'devnode "^hd[a-z]"';
                   pattern = '(?m)^\s*(?![#;])\s*devnode\s+"\^hd\[a-z\]"\s*$' },
                @{ expect = 'devnode "^sda$"';
                   pattern = '(?m)^\s*(?![#;])\s*devnode\s+"\^sda\$"\s*$' },
                @{ expect = 'device vendor "NVME" product "Microsoft NVMe Direct Disk"';
                   pattern = '(?m)^\s*(?![#;])\s*vendor\s+"NVME".*[\r\n]+.*product\s+"Microsoft NVMe Direct Disk"' },
                @{ expect = 'device vendor "Msft" product "Virtual Disk"';
                   pattern = '(?m)^\s*(?![#;])\s*vendor\s+[“"]Msft[”"].*[\r\n]+.*product\s+[“"]Virtual Disk[”"]' },

                @{ expect = 'device vendor "KMNRIO" product "KDP"';
                   pattern = '(?m)^\s*(?![#;])\s*vendor\s+"KMNRIO".*[\r\n]+.*product\s+"KDP"' },
                @{ expect = 'device vendor "SILK" product "KDP"';
                   pattern = '(?m)^\s*(?![#;])\s*vendor\s+"SILK".*[\r\n]+.*product\s+"KDP"' },
                @{ expect = 'device vendor "SILK" product "SDP"';
                   pattern = '(?m)^\s*(?![#;])\s*vendor\s+"SILK".*[\r\n]+.*product\s+"SDP"' },

                @{ expect = 'property "(ID_SCSI_VPD|ID_WWN|ID_SERIAL)"';
                   pattern = '(?m)^\s*(?![#;])\s*property\s+"\(ID_SCSI_VPD\|ID_WWN\|ID_SERIAL\)"\s*$' }
            )

            $missing = @()
            foreach ($r in $requirements) {
                if ($mpathText -notmatch $r.pattern) {
                    $missing += $r.expect
                }
            }

            if ($missing.Count -eq 0) {
                Add-CheckOK "multipath.conf: all required settings present"
            }
            else {
                Add-CheckWarn ("multipath.conf: missing {0}/{1} required settings" -f $missing.Count, $requirements.Count)
                DumpPre @("Missing multipath.conf settings:"; $missing)
            }
        }
        # --- multipathd service status (Linux) ---
        $svcCmd = @'
        sh -lc '
        name=multipathd
        enabled="unknown"
        active="unknown"

        if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files | awk "{print \$1}" | grep -qx "${name}.service"; then
        enabled=$(systemctl is-enabled "$name" 2>/dev/null || echo "unknown")
        active=$(systemctl is-active "$name" 2>/dev/null || echo "unknown")
        else
        enabled="not-installed"
        active="unknown"
        fi
        elif command -v service >/dev/null 2>&1; then
        if service "$name" status >/dev/null 2>&1; then
        active="active"
        else
        active="inactive"
        fi
        if command -v chkconfig >/dev/null 2>&1; then
        if chkconfig --list 2>/dev/null | grep -E "^${name}\s" | grep -q ":on"; then
        enabled="enabled"
        else
        enabled="disabled"
        fi
        elif command -v update-rc.d >/dev/null 2>&1; then
        if ls /etc/rc*.d/*${name} 1>/dev/null 2>&1; then
        enabled="enabled"
        else
        enabled="disabled"
        fi
        fi
        fi

        echo " service: ${name}"
        echo " enabled: ${enabled}"
        echo "  active: ${active}"
        '
'@
        $svcStatus = Invoke-Linux $svcCmd
        DumpPre @("multipathd service status:"; $svcStatus)

        $enabledLine = $svcStatus | Where-Object { $_ -match '^\s*enabled:\s*(.+)$' } | Select-Object -First 1
        $activeLine = $svcStatus | Where-Object { $_ -match '^\s*active:\s*(.+)$' }  | Select-Object -First 1
        $enabledVal = if ($enabledLine) { ($enabledLine -replace '^\s*enabled:\s*', '').Trim() } else { '' }
        $activeVal = if ($activeLine) { ($activeLine -replace '^\s*active:\s*', '').Trim() }  else { '' }

        if ($activeVal -eq 'active' -and $enabledVal -match 'enabled') {
            AddRowOKText "multipathd is active and enabled"
        }
        elseif ($activeVal -eq 'active' -and $enabledVal -match 'disabled') {
            AddRowWarnText "multipathd is active but disabled at boot"
        }
        elseif ($activeVal -ne 'active' -and $enabledVal -match 'enabled') {
            AddRowErrText "multipathd is enabled but not running"
        }
        elseif ($enabledVal -eq 'not-installed') {
            AddRowErrText "multipathd service does not exist"
        }
        elseif ($activeVal -eq 'unknown' -and $enabledVal -eq 'unknown') {
            AddRowWarnText "multipathd status unknown"
        }
        else {
            AddRowErrText ("multipathd state: enabled={0}, active={1}" -f $enabledVal, $activeVal)
        }
    }
    catch { AddRowErrText ("Linux multipath error: {0}" -f $_.Exception.Message) }
    CloseCard
    
    NewCard "Silk Disks" "DISKS" "info"
    try {
        # Parse multipath -ll; keep only map headers for Silk/Kaminario LUNs (WWIDs 2002* or 280b*)
        $mp = LinuxRun $HostName $User $KeyFile "multipath -ll 2>/dev/null"
        $txt = if ($mp -is [System.Array]) { $mp -join "`n" } else { [string]$mp }
        $blocks = $txt -split "(
?
){2,}"

        $rows = @()
        foreach ($b in $blocks) {
            $b = $b.Trim()
            if (-not $b) { continue }
            $first = ($b -split "
?
")[0]

            if ($first -match '^\s*(\S+)\s+\(([^)]+)\)\s+\S+\s+([^,]+),\s*(\S+)') {
                $name = $Matches[1]
                $wwid = $Matches[2]
                $vendor = $Matches[3]
                $model = $Matches[4]

                if ($wwid -match '^(2002|280b)') {
                    # size= token (e.g., size=2.0T ...)
                    $size = ""
                    if ($b -match 'size=([0-9\.]+[KMGTP]?)') { $size = $Matches[1] }

                    # Health detection
                    $hasActive = ($b -match 'status=active')
                    $hasFailed = ($b -match 'status=failed')
                    $wpRW = ($b -match 'wp=rw')

                    if ($hasActive -or $wpRW) { $health = "Connected" }
                    elseif ($hasFailed) { $health = "Degraded" }
                    else { $health = "NotConnected" }

                    $rows += [pscustomobject]@{
                        DeviceId     = "/dev/mapper/$name"
                        SerialNumber = $wwid
                        FriendlyName = "$name ($vendor $model)"
                        HealthStatus = $health
                        'Size'    = $size
                    }
                }
            }
        }

        if ($rows.Count -gt 0) {
            DumpTable $rows
        }
        else {
            AddRowInfoText "No Silk/Kaminario multipath devices found"
        }
    }
    catch {
        AddRowErrText ("Linux Silk disks error: {0}" -f $_.Exception.Message)
    }
    CloseCard



    NewCard "Udev" "UD" "info"
        $udev = LinuxRun $HostName $User $KeyFile "test -f /usr/lib/udev/rules.d/98-sdp-io.rules && sed -n '1,200p' /usr/lib/udev/rules.d/98-sdp-io.rules || echo 'Missing 98-sdp-io.rules'"
        DumpPre $udev

        # Presence -> WARN/OK
        $udevText = if ($udev -is [System.Array]) { $udev -join "`n" } else { [string]$udev }
        if ($udevText -match '^\s*Missing 98-sdp-io\.rules') {
            AddRowWarnText "udev rule 98-sdp-io.rules is missing"
        } else {
            AddRowOKText "udev rule 98-sdp-io.rules present"

            # Validate required contents of 98-sdp-io.rules
            $requiredRules = @(
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="2002*", ATTR{queue/scheduler}="noop"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="2002*", ATTR{device/timeout}="300"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="2002*", ATTR{queue/scheduler}="none"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{DM_UUID}=="mpath-2002*", ATTR{queue/scheduler}="noop"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{DM_UUID}=="mpath-2002*", ATTR{queue/scheduler}="none"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="280b*", ATTR{queue/scheduler}="noop"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="280b*", ATTR{device/timeout}="300"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{ID_SERIAL}=="280b*", ATTR{queue/scheduler}="none"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{DM_UUID}=="mpath-280b*", ATTR{queue/scheduler}="noop"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{DM_UUID}=="mpath-280b*", ATTR{queue/scheduler}="none"',
                'ACTION=="add|change", SUBSYSTEM=="block", ENV{DM_UUID}=="mpath-280b*", ATTR{queue/max_sectors_kb}="256"'
            )
            $udevLines = if ($udev -is [System.Array]) { $udev } else { @([string]$udev) }
            $udevNorm  = $udevLines | ForEach-Object { $_.Trim() }

            $missing = New-Object System.Collections.ArrayList
            foreach ($rule in $requiredRules) {
                if (-not ($udevNorm -contains $rule)) {
                    [void]$missing.Add($rule)
                }
            }
        }

    NewCard "iSCSI Sessions & Scaling (Linux)" "SESS" "info"
    try {


        # Check /etc/iscsi/iscsid.conf presence and required setting (Linux)
        $iscsid = Invoke-Linux "test -f /etc/iscsi/iscsid.conf && sudo sed -n '1,300p' /etc/iscsi/iscsid.conf || echo 'Missing /etc/iscsi/iscsid.conf'"
        DumpPre @("iscsid.conf:"; $iscsid)


        # Validate required lines (must be present and not commented out)
        $iscsidText = if ($iscsid -is [System.Array]) { $iscsid -join "`n" } else { [string]$iscsid }
        if ($iscsidText -match '^\s*Missing /etc/iscsi/iscsid\.conf') {
            AddRowWarnText "iscsid.conf does not exist"
        }
        else {
            $requirements = @(
                @{ expect   = 'iscsid.startup = /bin/systemctl start iscsid.socket iscsiuio.socket';
                    pattern = '(?m)^\s*(?![#;])\s*iscsid\.startup\s*=\s*/bin/systemctl\s+start\s+iscsid\.socket\s+iscsiuio\.socket\s*$' 
                },
                @{ expect   = 'iscsid.safe_logout = Yes';
                    pattern = '(?m)^\s*(?![#;])\s*iscsid\.safe_logout\s*=\s*Yes\s*$' 
                },
                @{ expect   = 'node.startup = automatic';
                    pattern = '(?m)^\s*(?![#;])\s*node\.startup\s*=\s*automatic\s*$' 
                },
                @{ expect   = 'node.session.timeo.replacement_timeout = 120';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.timeo\.replacement_timeout\s*=\s*120\s*$' 
                },
                @{ expect   = 'node.conn[0].timeo.login_timeout = 15';
                    pattern = '(?m)^\s*(?![#;])\s*node\.conn\[0\]\.timeo\.login_timeout\s*=\s*15\s*$' 
                },
                @{ expect   = 'node.conn[0].timeo.logout_timeout = 15';
                    pattern = '(?m)^\s*(?![#;])\s*node\.conn\[0\]\.timeo\.logout_timeout\s*=\s*15\s*$' 
                },
                @{ expect   = 'node.conn[0].timeo.noop_out_interval = 5';
                    pattern = '(?m)^\s*(?![#;])\s*node\.conn\[0\]\.timeo\.noop_out_interval\s*=\s*5\s*$' 
                },
                @{ expect   = 'node.conn[0].timeo.noop_out_timeout = 50';
                    pattern = '(?m)^\s*(?![#;])\s*node\.conn\[0\]\.timeo\.noop_out_timeout\s*=\s*50\s*$' 
                },
                @{ expect   = 'node.session.err_timeo.abort_timeout = 15';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.err_timeo\.abort_timeout\s*=\s*15\s*$' 
                },
                @{ expect   = 'node.session.err_timeo.lu_reset_timeout = 30';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.err_timeo\.lu_reset_timeout\s*=\s*30\s*$' 
                },
                @{ expect   = 'node.session.err_timeo.tgt_reset_timeout = 30';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.err_timeo\.tgt_reset_timeout\s*=\s*30\s*$' 
                },
                @{ expect   = 'node.session.initial_login_retry_max = 8';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.initial_login_retry_max\s*=\s*8\s*$' 
                },
                @{ expect   = 'node.session.cmds_max = 128';
                    pattern = '(?m)^\s*(?![#;])\s*node\.session\.cmds_max\s*=\s*128\s*$' 
                }
            )

            $missing = @()
            foreach ($r in $requirements) {
                if ($iscsidText -notmatch $r.pattern) {
                    $missing += $r.expect
                }
            }

            if ($missing.Count -eq 0) {
                Add-CheckOK "iscsid.conf: all required settings present"
            }
            else {
                Add-CheckWarn ("iscsid.conf: missing {0}/{1} required settings" -f $missing.Count, $requirements.Count)
                DumpPre @("Missing iscsid.conf settings:"; $missing)
            }
        }



        
        # --- TRIM/Unmap check: warn on SDP mounts with "-o discard" (filtered, POSIX-safe) ---
        $trimCheckCmd = @'
sh -lc '
export LC_ALL=C
findmnt -rno SOURCE,OPTIONS,TARGET,FSTYPE -O discard \
| awk -v OFS="|" "{print \$1,\$2,\$3,\$4}" \
| awk -F"|" '"'"'$4 ~ /^(ext[234]|xfs)$/ && $1 ~ /^\/dev\// && $3 !~ /^\/mnt\/wsl(\/|$)/ && $3 !~ /^\/run\/user(\/|$)/'"'"' \
| while IFS="|" read -r src opts tgt fstype; do
  rsrc=$(readlink -f "$src" 2>/dev/null || printf "%s" "$src")
  bname=$(basename "$rsrc")
  dm=""
  if [ -e "/sys/block/$bname/dm/uuid" ]; then
    dm="$bname"
  elif case "$rsrc" in /dev/mapper/*) :;; *) dm="";; esac; then :; fi
  if [ -z "$dm" ] && [ -L "$rsrc" ]; then
    base=$(basename "$(readlink -f "$rsrc" 2>/dev/null)")
    [ -e "/sys/block/$base/dm/uuid" ] && dm="$base"
  fi
  uuid=""
  if [ -n "$dm" ] && [ -r "/sys/block/$dm/dm/uuid" ]; then
    uuid=$(cat "/sys/block/$dm/dm/uuid" 2>/dev/null)
  fi
  if printf "%s
" "$uuid" | grep -Eiq "^mpath-(2002|280b)"; then
    echo "SDP with discard: src=$src  dm=$dm  uuid=$uuid  mount=$tgt  fstype=$fstype  opts=$opts"
  fi
done
'
'@
        $trimFindings = Invoke-Linux $trimCheckCmd
        DumpPre @("TRIM/Unmap scan:"; $trimFindings)
        if ($trimFindings -and ($trimFindings | Where-Object { $_ -match '(?i)SDP with discard:' })) {
            Add-CheckWarn "TRIM/Unmap: discard on SDP mount(s)"
        }
        else {
            Add-CheckOK "TRIM/Unmap: no SDP mounts with discard"
        }
        
        # --- Dedicated iSCSI NICs (Linux) ---
        $iscsiNicCmd = @'
sh -lc '
export LC_ALL=C
ips=$(iscsiadm -m session 2>/dev/null | awk "{print \$3}" | sed "s/,.*//" | sed "s/^\[//; s/\]$//" | cut -d: -f1 | sort -u)
if [ -z "$ips" ]; then
  echo "count: 0"
  exit 0
fi
nics=""
for ip in $ips; do
  dev=$(ip route get "$ip" 2>/dev/null | awk "{for(i=1;i<=NF;i++) if (\$i==\"dev\") {print \$(i+1); exit}}")
  if [ -n "$dev" ]; then
    echo "nic: $dev target: $ip"
    nics="$nics $dev"
  fi
done
cnt=$(printf "%s
" $nics | awk "NF" | sort -u | wc -l | tr -d " ")
echo "count: $cnt"
'
'@
        $iscsiNicInfo = Invoke-Linux $iscsiNicCmd
        DumpPre @("iSCSI NIC discovery:"; $iscsiNicInfo)
        $count = [int](Parse-Kv $iscsiNicInfo 'count')
        if ($count -lt 1) {
            Add-CheckErr "iSCSI NICs: 0 (requires dedicated NIC)"
        }
        else {
            Add-CheckOK ("iSCSI NICs: {0}" -f $count)
        }


        # --- iscsid service status (Linux) ---
        $iscsiSvcCmd = @'
        sh -lc '
        name=iscsid
        enabled="unknown"
        active="unknown"

        if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files | awk "{print \$1}" | grep -qx "${name}.service"; then
        enabled=$(systemctl is-enabled "$name" 2>/dev/null || echo "unknown")
        active=$(systemctl is-active "$name" 2>/dev/null || echo "unknown")
        else
        enabled="not-installed"
        active="unknown"
        fi
        elif command -v service >/dev/null 2>&1; then
        if service "$name" status >/dev/null 2>&1; then
        active="active"
        else
        active="inactive"
        fi
        if command -v chkconfig >/dev/null 2>&1; then
        if chkconfig --list 2>/dev/null | grep -E "^${name}\s" | grep -q ":on"; then
        enabled="enabled"
        else
        enabled="disabled"
        fi
        elif command -v update-rc.d >/dev/null 2>&1; then
        if ls /etc/rc*.d/*${name} 1>/dev/null 2>&1; then
        enabled="enabled"
        else
        enabled="disabled"
        fi
        fi
        fi

        echo " service: ${name}"
        echo " enabled: ${enabled}"
        echo "  active: ${active}"
        '
'@
        $iscsiSvc = Invoke-Linux $iscsiSvcCmd
        DumpPre @("iscsid service status:"; $iscsiSvc)

        $enLine = $iscsiSvc | Where-Object { $_ -match '^\s*enabled:\s*(.+)$' } | Select-Object -First 1
        $acLine = $iscsiSvc | Where-Object { $_ -match '^\s*active:\s*(.+)$' }  | Select-Object -First 1
        $enVal = if ($enLine) { ($enLine -replace '^\s*enabled:\s*', '').Trim() } else { '' }
        $acVal = if ($acLine) { ($acLine -replace '^\s*active:\s*', '').Trim() }  else { '' }

        if ($acVal -eq 'active' -and $enVal -match 'enabled') {
            Add-CheckOK "iscsid: active & enabled"
        }
        elseif ($acVal -eq 'active' -and $enVal -match 'disabled') {
            Add-CheckWarn "iscsid: active but disabled at boot"
        }
        elseif ($acVal -ne 'active' -and $enVal -match 'enabled') {
            Add-CheckErr "iscsid: enabled but not running"
        }
        elseif ($enVal -eq 'not-installed') {
            AddRowErrText "iscsid service does not exist"
        }
        elseif ($acVal -eq 'unknown' -and $enVal -eq 'unknown') {
            Add-CheckWarn "iscsid: status unknown"
        }
        else {
            Add-CheckErr ("iscsid: enabled={0}, active={1}" -f $enVal, $acVal)
        }

        $sessionOut = Invoke-Linux 'iscsiadm -m session 2>/dev/null || true'
        $iqnPattern = '(?i)iqn\.2009-01\.(?:us\.silk:storage\.sdp|com\.kaminario:storage\.k2)\b'
        $ipPattern  = '^\s*\w+:\s*\[\d+\]\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3}):\d+'

        $cnodeSessions = @{}
        if ($sessionOut) {
            ($sessionOut -split "`n" | Where-Object { $_ -match $iqnPattern }) | ForEach-Object {
                if ($_ -match $ipPattern) {
                    $ip = $matches[1]
                    if (-not $cnodeSessions.ContainsKey($ip)) { $cnodeSessions[$ip] = 0 }
                    $cnodeSessions[$ip]++
                }
            }
        }

        $totalCnodeSessions = ($cnodeSessions.Values | Measure-Object -Sum).Sum
        if (-not $totalCnodeSessions) { $totalCnodeSessions = 0 }
        $connectedCnodes = $cnodeSessions.Keys.Count

        AddRowInfoText ("Active iSCSI sessions to C-nodes: {0} across {1} C-node(s)" -f $totalCnodeSessions, $connectedCnodes)

        $recSmall = @{2 = 12; 3 = 8; 4 = 6; 5 = 5; 6 = 4; 7 = 4; 8 = 3; 9 = 3; 10 = 2 }
        $recLarge = @{2 = 6;  3 = 4; 4 = 3; 5 = 3; 6 = 2; 7 = 2; 8 = 1; 9 = 1;  10 = 1 }
        $rec = if ($Scale -eq "Small") { $recSmall } else { $recLarge }
        $needPerCnode = $rec[$CNodes]

        if (-not $needPerCnode) {
            AddRowWarnText ("No recommendation found for {0} C-nodes ({1} scale)" -f $CNodes, $Scale)
        } elseif ($connectedCnodes -eq 0) {
            AddRowWarnText ("No active iSCSI sessions to C-nodes detected")
        } else {
            $underProvisioned = @()
            foreach ($ip in $cnodeSessions.Keys) {
                $count = $cnodeSessions[$ip]
                if ($count -lt $needPerCnode) {
                    $underProvisioned += @{ IP = $ip; Count = $count }
                }
            }
            if ($underProvisioned.Count -gt 0) {
                foreach ($entry in $underProvisioned) {
                    AddRowWarnText ("C-node {0} has {1}/{2} iSCSI session(s) (recommended per C-node; {3} scale, {4} total C-nodes expected)" -f `
                        $entry.IP, $entry.Count, $needPerCnode, $Scale, $CNodes)
                }
            } else {
                AddRowOKText ("All connected C-nodes ({0}) meet the recommendation of {1} session(s) per C-node ({2} scale)" -f `
                    $connectedCnodes, $needPerCnode, $Scale)
            }
            if ($connectedCnodes -lt $CNodes) {
                AddRowWarnText ("Only {0}/{1} expected C-nodes have active sessions to this host" -f $connectedCnodes, $CNodes)
            }
        }

    }
    catch { AddRowErrText ("Linux session/scaling error: {0}" -f $_.Exception.Message) }
    CloseCard
}


# ========================= Multi-Host Dispatch =========================
function Reset-Globals {
    $Global:Start = Get-Date
    $Global:Cards = New-Object System.Collections.Generic.List[string]
    $Global:Stats = @{ ok = 0; warn = 0; err = 0; info = 0 }
    $Global:RecsErr = New-Object System.Collections.ArrayList
    $Global:RecsWarn = New-Object System.Collections.ArrayList
}

function New-HostSection([string]$DisplayHost) {
    $elapsed = New-TimeSpan $Global:Start (Get-Date)
    $summary = "<div class='summary'>
      <span class='badge ok'>OK: $($Global:Stats.ok)</span>
      <span class='badge warn'>WARN: $($Global:Stats.warn)</span>
      <span class='badge err'>ERR: $($Global:Stats.err)</span>
      <span class='badge info'>INFO: $($Global:Stats.info)</span>
    </div>"
    $recs = BuildRecommendationsCard
    $recsTop    = if (-not $Script:IsMultiHost) { $recs } else { "" }
    $recsBottom = if (     $Script:IsMultiHost) { $recs } else { "" }
    $cards = ($Global:Cards -join "`n")
    $hostHeader = if ($DisplayHost) { $DisplayHost } else { $([Environment]::Machinename) }
    return @"
<section class='host-group'>
  <div class='card'>
    <div class='card-header'><div class='card-title'>Host: $hostHeader</div></div>
    <div class='card-body'>
      <div>Elapsed $([int]$elapsed.TotalSeconds)s</div>
    </div>
  </div>
  $summary
  $recsTop
  $cards
  $recsBottom
</section>
"@
}

$AllSections = New-Object System.Collections.Generic.List[string]

$Script:IsMultiHost = ($HostList.Count -gt 1)

foreach ($h in $HostList) {
    $current = $h.Trim()
    Reset-Globals
    if ($HostType -eq "Windows") {
        $script:ComputerName = $current
        if ($current -and -not $PSBoundParameters.ContainsKey('Credential') -and -not $Credential) {
            $Credential = $script:Credential
        }
        ValidateWindows -ComputerName $current -Credential $Credential -Azure:$Azure -CNodes $CNodeCount -Scale $Scale
    }
    else {
        $script:HostName = $current
        ValidateLinux -HostName $current -User $User -KeyFile $KeyFile -Azure:$Azure -CNodes $CNodeCount -Scale $Scale
    }
    $AllSections.Add((New-HostSection $current)) | Out-Null
}

$globalRecs = if ($Script:IsMultiHost) { BuildGlobalRecommendationsCard } else { "" }

$combined = @"
<!DOCTYPE html>
<html><head><meta charset='utf-8'><title>Silk Host Validator – Multi-Host</title>
<style>
body{background:#0f0f11;color:#eaeaea;font-family:ui-monospace,Consolas,monospace;margin:0}
.header{background:#101014;border-bottom:2px solid $($Global:SilkGreenHex);padding:12px 16px;position:sticky;top:0;z-index:1;display:flex;justify-content:space-between;align-items:center}
.header h1{font-size:18px;margin:0;color:#fff}
.header small{color:#aaa}
.container{padding:20px;max-width:1800px;margin:0 auto}
.summary{margin:14px 0;font-size:15px}
.badge{display:inline-block;padding:5px 10px;border-radius:6px;font-size:14px;font-weight:700;margin-right:8px}
.badge.ok{background:#153e2c;color:#1DB954}
.badge.warn{background:#42380f;color:#FFC107}
.badge.err{background:#4a1111;color:#FF3B30}
.badge.info{background:#1a273d;color:#2196F3}
.grid{display:grid;grid-template-columns:1fr;gap:20px}
.card{background:#131318;border:1px solid #1d1d24;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,.3);overflow:hidden;grid-column:1 / -1}
.card-header{padding:12px 16px;background:#1b1b22;border-bottom:1px solid #222}
.card-title{font-weight:700;color:#fff;font-size:16px}
.card-body{padding:14px 16px}
.row{padding:8px 10px;border-left:4px solid transparent;border-radius:6px;margin:6px 0;background:#17171d;font-size:14px}
.row.ok{border-color:#1DB954}
.row.warn{border-color:#FFC107}
.row.err{border-color:#FF3B30}
.row.info{border-color:#2196F3}
.tbl-container{grid-column:1 / -1; margin:24px 0; width:100%}
pre.dump{background:#0f0f14;border:1px solid #222;border-radius:8px;padding:14px;overflow:auto;max-height:400px;font-size:14px}
.tbl{width:100%;border-collapse:collapse;font-size:14px;margin-top:10px}
.tbl th,.tbl td{border:1px solid #2a2a33;padding:10px 12px;text-align:left}
.tbl th{background:#1b1b22}
.foot{color:#9a9aa2;padding:18px;text-align:center}
.host-group{margin-bottom:36px}
</style></head>
<body>
<div class='header'><h1>Silk Data Platform – Host Best Practices Validation (Multi-Host)</h1><small>Generated $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</small></div>
<div class='container'>
$globalRecs
$($AllSections -join "`n`n")
</div>
<div class='foot'>© Silk. This report is informational – no settings were changed.</div>
</body></html>
"@

if ($IsWindowsEnv = $PSVersionTable.Platform -eq 'Win32NT') {
    $outDir = "C:/Temp"; if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
}
else {
    $outDir = "/tmp"; if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
}
$stamp = (Get-Date).ToString("MM-dd-yyyy_HH-mm-ss")
$out = Join-Path $outDir ("SDP_Host_Validation_{0}.html" -f $stamp)
Set-Content -Path $out -Value $combined -Encoding UTF8
Write-Host "Report written to $out"
try {
    if (Get-Command Start-Process -ErrorAction SilentlyContinue) {
        Start-Process $out | Out-Null
    }
    elseif (Get-Command Invoke-Item -ErrorAction SilentlyContinue) {
        Invoke-Item $out | Out-Null
    }
}
catch {}
