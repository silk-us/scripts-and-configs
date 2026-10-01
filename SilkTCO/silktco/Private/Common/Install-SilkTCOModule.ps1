<#
    .SYNOPSIS
    Makes sure a module is present and loaded, pulling it from the gallery if it isnt.

    .DESCRIPTION
    Returns $true if the module ended up loaded, $false if it couldnt be - the caller
    decides whether thats fatal.

    Installs to CurrentUser scope on purpose: an elevation prompt halfway through a
    collection run is worse than useless, and CurrentUser works on a locked down box.

    The install runs in a job with a timeout because Install-Module blocks forever when
    PSGallery is unreachable, which is common on exactly the sort of hardened jump box
    these assessments get run from. A hung collection is worse than a missing cost column.
#>

function Install-SilkTCOModule {
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter()]
        [int] $TimeoutSeconds = 300
    )

    # already loaded, nothing to do
    if (Get-Module -Name $Name) {
        return $true
    }

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Warning "$Name module not found. Installing from PSGallery (CurrentUser scope, ${TimeoutSeconds}s limit)..."

        $job = Start-Job -ArgumentList $Name -ScriptBlock {
            param($moduleName)

            # ps5.1 on a clean box wont install anything until nuget is bootstrapped, and
            # it prompts for it interactively if we dont get there first
            if ((Get-Command Install-PackageProvider -ErrorAction SilentlyContinue) -and
                -not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
            }

            # -Force also gets us past the untrusted PSGallery prompt
            Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        }

        $finished = Wait-Job -Job $job -Timeout $TimeoutSeconds

        if (-not $finished) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-Warning "Gave up installing $Name after ${TimeoutSeconds}s - PSGallery is probably blocked from this host."
            Write-Warning "Install it by hand with: Install-Module $Name -Scope CurrentUser"
            return $false
        }

        $jobError = $null
        Receive-Job -Job $job -ErrorVariable jobError -ErrorAction SilentlyContinue | Out-Null
        $failed = ($job.State -eq 'Failed') -or $jobError
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

        if ($failed) {
            Write-Warning "Could not install $Name automatically: $(($jobError | Select-Object -First 1))"
            Write-Warning "Install it by hand with: Install-Module $Name -Scope CurrentUser"
            return $false
        }

        Write-Verbose "-> installed $Name" -Verbose
    }

    try {
        Import-Module $Name -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "$Name is installed but would not import: $($_.Exception.Message)"
        return $false
    }
}
