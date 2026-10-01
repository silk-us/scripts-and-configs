function New-SilkTCOAWSFSxList {
    param(
        [Parameter()]
        [string] $Region,
        [Parameter()]
        [string] $inputFile,
        [Parameter()]
        [string] $TagKey,
        [Parameter()]
        [string] $TagValue,
        [Parameter()]
        [switch] $allFileSystems
    )

    $requiredModules = @('AWS.Tools.FSx')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    $fsxParams = @{}
    if ($Region) {
        $fsxParams['Region'] = $Region
    }

    if ($inputFile) {
        # feed in a list of FileSystemIds
        $fsIds = Get-Content $inputFile
        $fslist = @()
        foreach ($id in $fsIds) {
            $fslist += Get-FSXFileSystem -FileSystemId $id.Trim() @fsxParams
        }
    } else {
        $fslist = Get-FSXFileSystem @fsxParams
    }

    # only ontap here. windows/lustre/openzfs are a different animal entirely
    $fslist = $fslist | Where-Object { $_.FileSystemType -eq 'ONTAP' }

    # no server side tag filter on DescribeFileSystems, so match client side like we do for RDS
    if ($TagKey -and $TagValue) {
        $fslist = $fslist | Where-Object {
            ($_.Tags | Where-Object { $_.Key -eq $TagKey -and $_.Value -eq $TagValue })
        }
    }

    if (-not $allFileSystems) {
        $fslist = $fslist | Where-Object { $_.Lifecycle -eq 'AVAILABLE' }
    }

    if (-not $fslist) {
        return
    }

    # hang the volumes + svms off each filesystem so downstream doesnt have to re-query
    $thelist = @()
    foreach ($fs in $fslist) {
        $fsId = $fs.FileSystemId

        $vols = @()
        $svms = @()
        try {
            $vols = @(Get-FSXVolume -Filter @{ Name = 'file-system-id'; Values = @($fsId) } @fsxParams)
        } catch {
            Write-Warning "Could not list volumes for $fsId : $($_.Exception.Message)"
        }
        try {
            $svms = @(Get-FSXStorageVirtualMachine -Filter @{ Name = 'file-system-id'; Values = @($fsId) } @fsxParams)
        } catch {
            Write-Verbose "-> no svm detail for $fsId" -Verbose
        }

        # root volumes are plumbing, not customer data. skip em unless asked
        if (-not $allFileSystems) {
            $vols = $vols | Where-Object { -not $_.OntapConfiguration.StorageVirtualMachineRoot }
        }

        $fs | Add-Member -MemberType NoteProperty -Name SilkVolumes -Value @($vols) -Force
        $fs | Add-Member -MemberType NoteProperty -Name SilkSVMs -Value @($svms) -Force
        $thelist += $fs
    }

    return $thelist
}
