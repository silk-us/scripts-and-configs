<#
    .SYNOPSIS
    Opens and validates a session against a Pure Cloud Block Store array.

    .DESCRIPTION
    Connects with the supplied credential and proves the session works before any
    collection starts. Returns the connection object, or $null with a plain english
    reason - callers should bail rather than carry on with a dead session.
#>

function Connect-SilkTCOCBSArray {
    param(
        [Parameter(Mandatory)]
        [string] $endpoint,
        [Parameter(Mandatory)]
        [pscredential] $Credential,
        [Parameter()]
        [switch] $ignoreCertificateError
    )

    $requiredModules = @('PureStoragePowerShellSDK2')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Error "Required module '$module' is not installed. Install it with: Install-Module $module"
            return
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    $connectParams = @{
        Endpoint    = $endpoint
        Credential  = $Credential
        ErrorAction = 'Stop'
    }
    # cbs management endpoints ship self signed certs more often than not, but we make the
    # operator ask for this rather than quietly turning off tls validation on a storage array
    if ($ignoreCertificateError) { $connectParams['IgnoreCertificateError'] = $true }

    Write-Verbose "--> Connecting to CBS array $endpoint as $($Credential.UserName)" -Verbose

    $array = $null
    try {
        $array = Connect-Pfa2Array @connectParams
    } catch {
        $msg = $_.Exception.Message

        # sort out what actually went wrong so the operator isnt guessing
        switch -Regex ($msg) {
            'certificate|SSL|TLS|trust' {
                Write-Error "CBS connection to '$endpoint' failed on certificate validation. If the array uses a self-signed cert, re-run with -ignoreCertificateError. Detail: $msg"
                return
            }
            '401|Unauthorized|authenticat|invalid.*credential|bad.*password' {
                Write-Error "CBS authentication failed for user '$($Credential.UserName)' on '$endpoint'. Check the username and password, and that the account has read access to the array. Detail: $msg"
                return
            }
            'No such host|timed out|actively refused|Unable to connect|unreachable|Name or service not known' {
                Write-Error "Could not reach CBS array at '$endpoint'. Check the management endpoint address and that this host has network access to it. Detail: $msg"
                return
            }
            default {
                Write-Error "CBS connection to '$endpoint' failed: $msg"
                return
            }
        }
    }

    if (-not $array) {
        Write-Error "CBS connection to '$endpoint' returned no session. Cannot continue."
        return
    }

    # a connection object isnt proof of anything, do a real read before we trust it
    try {
        $probe = Get-Pfa2Array -Array $array -ErrorAction Stop
        if (-not $probe) {
            Write-Error "Connected to '$endpoint' but the array returned no data. The account may lack read permission."
            return
        }
        Write-Verbose "--> Connected to $($probe.Name) (Purity $($probe.Version))" -Verbose
    } catch {
        Write-Error "Connected to '$endpoint' but the first read failed - likely a permissions problem on account '$($Credential.UserName)'. Detail: $($_.Exception.Message)"
        return
    }

    return $array
}
