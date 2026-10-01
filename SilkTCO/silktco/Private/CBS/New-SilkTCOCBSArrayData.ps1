<#
    .SYNOPSIS
    Pulls provisioned capacity, data reduction and volume detail from a CBS array.

    .DESCRIPTION
    The Purity API is the only place the reduction ratio lives, and on CBS that ratio is
    directly upstream of the azure blob bill - 100 TiB provisioned at 4:1 is 25 TiB of blob
    actually being paid for. That's the number the whole costing comparison turns on.
#>

function New-SilkTCOCBSArrayData {
    param(
        [Parameter(Mandatory)]
        $arrayConnection,
        [Parameter()]
        [switch] $includeHosts,
        [Parameter()]
        [switch] $includeProtectionGroups
    )

    $conn = $arrayConnection

    $arrayInfo = Get-Pfa2Array -Array $conn -ErrorAction Stop
    $arraySpace = $null
    try {
        $arraySpace = Get-Pfa2ArraySpace -Array $conn -ErrorAction Stop
    } catch {
        Write-Warning "Could not read array space: $($_.Exception.Message)"
    }

    # Get-Pfa2Array already carries space on most purity builds, fall back to it
    $space = if ($arraySpace) { $arraySpace.Space } else { $arrayInfo.Space }
    $capacity = if ($arraySpace -and $arraySpace.Capacity) { $arraySpace.Capacity } else { $arrayInfo.Capacity }

    $result = New-Object psobject

    $a = New-Object psobject
    $a | Add-Member -MemberType NoteProperty -Name ArrayName -Value $arrayInfo.Name
    $a | Add-Member -MemberType NoteProperty -Name ArrayId -Value $arrayInfo.Id
    $a | Add-Member -MemberType NoteProperty -Name PurityVersion -Value $arrayInfo.Version
    $a | Add-Member -MemberType NoteProperty -Name Model -Value $arrayInfo.Model
    $a | Add-Member -MemberType NoteProperty -Name UsableCapacityTiB -Value $(if ($capacity) { [Math]::Round($capacity / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name TotalProvisionedTiB -Value $(if ($space.TotalProvisioned) { [Math]::Round($space.TotalProvisioned / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name TotalPhysicalTiB -Value $(if ($space.TotalPhysical) { [Math]::Round($space.TotalPhysical / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name UniqueTiB -Value $(if ($space.Unique) { [Math]::Round($space.Unique / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name SnapshotsTiB -Value $(if ($space.Snapshots) { [Math]::Round($space.Snapshots / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name SharedTiB -Value $(if ($space.Shared) { [Math]::Round($space.Shared / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name SystemTiB -Value $(if ($space.System) { [Math]::Round($space.System / 1TB, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name DataReduction -Value $(if ($space.DataReduction) { [Math]::Round($space.DataReduction, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name TotalReduction -Value $(if ($space.TotalReduction) { [Math]::Round($space.TotalReduction, 2) } else { $null })
    $a | Add-Member -MemberType NoteProperty -Name ThinProvisioning -Value $(if ($space.ThinProvisioning) { [Math]::Round($space.ThinProvisioning, 2) } else { $null })

    $result | Add-Member -MemberType NoteProperty -Name Array -Value $a

    # --- volumes + per volume space ---
    $volDetail = @()
    try {
        $volumes = @(Get-Pfa2Volume -Array $conn -ErrorAction Stop)
        $volSpaces = @{}
        try {
            foreach ($vs in @(Get-Pfa2VolumeSpace -Array $conn -ErrorAction Stop)) {
                $volSpaces[$vs.Name] = $vs
            }
        } catch {
            Write-Verbose "-> per volume space not available" -Verbose
        }

        foreach ($v in $volumes) {
            $vs = $volSpaces[$v.Name]
            $vspace = if ($vs) { $vs.Space } else { $v.Space }

            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name VolumeName -Value $v.Name
            $o | Add-Member -MemberType NoteProperty -Name Serial -Value $v.Serial
            $o | Add-Member -MemberType NoteProperty -Name Destroyed -Value $v.Destroyed
            $o | Add-Member -MemberType NoteProperty -Name ProvisionedGiB -Value $(if ($v.Provisioned) { [Math]::Round($v.Provisioned / 1GB, 2) } else { $null })
            $o | Add-Member -MemberType NoteProperty -Name UniqueGiB -Value $(if ($vspace.Unique) { [Math]::Round($vspace.Unique / 1GB, 2) } else { $null })
            $o | Add-Member -MemberType NoteProperty -Name SnapshotsGiB -Value $(if ($vspace.Snapshots) { [Math]::Round($vspace.Snapshots / 1GB, 2) } else { $null })
            $o | Add-Member -MemberType NoteProperty -Name TotalPhysicalGiB -Value $(if ($vspace.TotalPhysical) { [Math]::Round($vspace.TotalPhysical / 1GB, 2) } else { $null })
            $o | Add-Member -MemberType NoteProperty -Name DataReduction -Value $(if ($vspace.DataReduction) { [Math]::Round($vspace.DataReduction, 2) } else { $null })
            $volDetail += $o
        }
    } catch {
        Write-Warning "Could not list volumes: $($_.Exception.Message)"
    }
    $result | Add-Member -MemberType NoteProperty -Name Volumes -Value @($volDetail)

    # --- host mappings. lets you tie cbs volumes back to vms in the ec2/azure reports ---
    $hostDetail = @()
    if ($includeHosts) {
        try {
            $conns = @(Get-Pfa2Connection -Array $conn -ErrorAction SilentlyContinue)
            foreach ($h in @(Get-Pfa2Host -Array $conn -ErrorAction Stop)) {
                $mapped = @($conns | Where-Object { $_.Host.Name -eq $h.Name })
                $o = New-Object psobject
                $o | Add-Member -MemberType NoteProperty -Name HostName -Value $h.Name
                $o | Add-Member -MemberType NoteProperty -Name HostGroup -Value $h.HostGroup.Name
                $o | Add-Member -MemberType NoteProperty -Name ConnectionCount -Value $mapped.Count
                $o | Add-Member -MemberType NoteProperty -Name MappedVolumes -Value (($mapped.Volume.Name) -join '; ')
                $hostDetail += $o
            }
        } catch {
            Write-Verbose "-> host detail not available" -Verbose
        }
    }
    $result | Add-Member -MemberType NoteProperty -Name Hosts -Value @($hostDetail)

    # --- protection groups / replication footprint ---
    $pgDetail = @()
    if ($includeProtectionGroups) {
        try {
            foreach ($pg in @(Get-Pfa2ProtectionGroup -Array $conn -ErrorAction Stop)) {
                $o = New-Object psobject
                $o | Add-Member -MemberType NoteProperty -Name GroupName -Value $pg.Name
                $o | Add-Member -MemberType NoteProperty -Name SnapshotsGiB -Value $(if ($pg.Space.Snapshots) { [Math]::Round($pg.Space.Snapshots / 1GB, 2) } else { $null })
                $o | Add-Member -MemberType NoteProperty -Name TotalPhysicalGiB -Value $(if ($pg.Space.TotalPhysical) { [Math]::Round($pg.Space.TotalPhysical / 1GB, 2) } else { $null })
                $o | Add-Member -MemberType NoteProperty -Name VolumeCount -Value $pg.VolumeCount
                $o | Add-Member -MemberType NoteProperty -Name TargetCount -Value $pg.TargetCount
                $pgDetail += $o
            }
        } catch {
            Write-Verbose "-> protection group detail not available" -Verbose
        }
    }
    $result | Add-Member -MemberType NoteProperty -Name ProtectionGroups -Value @($pgDetail)

    return $result
}
