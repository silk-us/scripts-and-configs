<#
    .SYNOPSIS
    Discovers Azure NetApp Files accounts, capacity pools and volumes.

    .DESCRIPTION
    Provisioning only - no Azure Monitor, no time window. Everything here is what the
    environment has been built and paid for, which is what a costing comparison needs.
    Performance ceilings on ANF are pure arithmetic off service level and size.
#>

function New-SilkTCOANFList {
    param(
        [Parameter()]
        [array] $resourceGroupNames,
        [Parameter()]
        [switch] $includeSnapshots,
        [Parameter()]
        [switch] $includeBackups
    )

    $requiredModules = @('Az.NetAppFiles')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        if (-not (Get-Module -Name $module)) {
            Import-Module $module -ErrorAction Stop
        }
    }

    # anf throughput is a flat rate per TiB by service level. thats the whole ceiling story,
    # no metrics needed. std 16 / prem 64 / ultra 128 MiB/s per TiB.
    $throughputPerTiB = @{
        'Standard' = 16
        'Premium'  = 64
        'Ultra'    = 128
    }

    # arm hands names back as 'account/pool' or 'account/pool/volume', we just want the leaf
    function Get-AnfLeafName {
        param([string] $name)
        if (-not $name) { return $null }
        return ($name -split '/')[-1]
    }

    $accounts = @()
    if ($resourceGroupNames) {
        foreach ($rg in $resourceGroupNames) {
            $accounts += Get-AnfAccount -ResourceGroupName $rg -ErrorAction SilentlyContinue
        }
    } else {
        $accounts = Get-AnfAccount -ErrorAction SilentlyContinue
    }

    if (-not $accounts) {
        Write-Warning "No Azure NetApp Files accounts found in the current context."
        return
    }

    $thelist = @()

    foreach ($acct in $accounts) {
        $acctName = Get-AnfLeafName $acct.Name
        $acctRg = $acct.ResourceGroupName

        Write-Verbose "-> Gathering ANF account - $acctName ($acctRg)" -Verbose

        $pools = @()
        try {
            $pools = @(Get-AnfPool -ResourceGroupName $acctRg -AccountName $acctName -ErrorAction Stop)
        } catch {
            Write-Warning "Could not list pools for account $acctName : $($_.Exception.Message)"
            continue
        }

        foreach ($pool in $pools) {
            $poolName = Get-AnfLeafName $pool.Name
            Write-Verbose "--> pool $poolName ($($pool.ServiceLevel), $([Math]::Round($pool.Size / 1TB, 2)) TiB)" -Verbose

            $poolSizeGiB = [Math]::Round($pool.Size / 1GB, 2)
            $poolSizeTiB = [Math]::Round($pool.Size / 1TB, 4)

            $rate = $throughputPerTiB[[string]$pool.ServiceLevel]
            if ($rate) {
                $poolCeiling = [Math]::Round($poolSizeTiB * $rate, 2)
            } elseif ($pool.TotalThroughputMibps) {
                # Flexible tier provisions throughput on its own, not off capacity
                $poolCeiling = [Math]::Round($pool.TotalThroughputMibps, 2)
            } else {
                $poolCeiling = $null
            }

            $volumes = @()
            try {
                $volumes = @(Get-AnfVolume -ResourceGroupName $acctRg -AccountName $acctName -PoolName $poolName -ErrorAction Stop)
            } catch {
                Write-Warning "Could not list volumes for pool $poolName : $($_.Exception.Message)"
            }

            # anf bills the POOL not the volumes. anything carved out short of pool size is
            # capacity the customer is paying for and not using - thats the number that matters
            $allocatedGiB = 0
            $volDetail = @()

            foreach ($vol in $volumes) {
                $volName = Get-AnfLeafName $vol.Name
                $quotaGiB = [Math]::Round($vol.UsageThreshold / 1GB, 2)
                $allocatedGiB += $quotaGiB

                # manual qos assigns throughput explicitly, auto derives it from quota
                $volCeiling = $null
                if ($vol.ThroughputMibps) {
                    $volCeiling = [Math]::Round($vol.ThroughputMibps, 2)
                } elseif ($rate) {
                    $volCeiling = [Math]::Round(($vol.UsageThreshold / 1TB) * $rate, 2)
                }

                $snaps = @()
                if ($includeSnapshots) {
                    try {
                        $snaps = @(Get-AnfSnapshot -ResourceGroupName $acctRg -AccountName $acctName -PoolName $poolName -VolumeName $volName -ErrorAction Stop)
                    } catch {
                        Write-Verbose "-> no snapshots readable for $volName" -Verbose
                    }
                }

                $v = New-Object psobject
                $v | Add-Member -MemberType NoteProperty -Name VolumeName -Value $volName
                $v | Add-Member -MemberType NoteProperty -Name ResourceId -Value $vol.Id
                $v | Add-Member -MemberType NoteProperty -Name Location -Value $vol.Location
                $v | Add-Member -MemberType NoteProperty -Name ServiceLevel -Value ([string]$vol.ServiceLevel)
                $v | Add-Member -MemberType NoteProperty -Name ProvisionedGiB -Value $quotaGiB
                $v | Add-Member -MemberType NoteProperty -Name ThroughputCeilingMiBps -Value $volCeiling
                $v | Add-Member -MemberType NoteProperty -Name AssignedThroughputMiBps -Value $vol.ThroughputMibps
                $v | Add-Member -MemberType NoteProperty -Name ProtocolTypes -Value ($vol.ProtocolTypes -join ',')
                $v | Add-Member -MemberType NoteProperty -Name NetworkFeatures -Value ([string]$vol.NetworkFeatures)
                $v | Add-Member -MemberType NoteProperty -Name CoolAccess -Value $vol.CoolAccess
                $v | Add-Member -MemberType NoteProperty -Name CoolnessPeriodDays -Value $vol.CoolnessPeriod
                $v | Add-Member -MemberType NoteProperty -Name IsLargeVolume -Value $vol.IsLargeVolume
                $v | Add-Member -MemberType NoteProperty -Name Zone -Value ($vol.Zones -join ',')
                $v | Add-Member -MemberType NoteProperty -Name SnapshotPolicy -Value (Get-AnfLeafName $vol.SnapshotPolicyId)
                $v | Add-Member -MemberType NoteProperty -Name ReplicationEndpointType -Value ([string]$vol.DataProtectionReplicationEndpointType)
                $v | Add-Member -MemberType NoteProperty -Name ReplicationSchedule -Value ([string]$vol.DataProtectionReplicationSchedule)
                $v | Add-Member -MemberType NoteProperty -Name EncryptionKeySource -Value ([string]$vol.EncryptionKeySource)
                $v | Add-Member -MemberType NoteProperty -Name Snapshots -Value @($snaps)
                $volDetail += $v
            }

            $strandedGiB = [Math]::Round($poolSizeGiB - $allocatedGiB, 2)
            $utilPct = if ($poolSizeGiB -gt 0) { [Math]::Round(($allocatedGiB / $poolSizeGiB) * 100, 2) } else { 0 }

            $p = New-Object psobject
            $p | Add-Member -MemberType NoteProperty -Name NetAppAccount -Value $acctName
            $p | Add-Member -MemberType NoteProperty -Name PoolName -Value $poolName
            $p | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $acctRg
            $p | Add-Member -MemberType NoteProperty -Name ResourceId -Value $pool.Id
            $p | Add-Member -MemberType NoteProperty -Name Region -Value $pool.Location
            $p | Add-Member -MemberType NoteProperty -Name ServiceLevel -Value ([string]$pool.ServiceLevel)
            $p | Add-Member -MemberType NoteProperty -Name QosType -Value ([string]$pool.QosType)
            $p | Add-Member -MemberType NoteProperty -Name ProvisionedGiB -Value $poolSizeGiB
            $p | Add-Member -MemberType NoteProperty -Name ProvisionedTiB -Value $poolSizeTiB
            $p | Add-Member -MemberType NoteProperty -Name ThroughputCeilingMiBps -Value $poolCeiling
            $p | Add-Member -MemberType NoteProperty -Name TotalThroughputMiBps -Value $pool.TotalThroughputMibps
            $p | Add-Member -MemberType NoteProperty -Name UtilizedThroughputMiBps -Value $pool.UtilizedThroughputMibps
            $p | Add-Member -MemberType NoteProperty -Name AllocatedToVolumesGiB -Value $allocatedGiB
            $p | Add-Member -MemberType NoteProperty -Name StrandedGiB -Value $strandedGiB
            $p | Add-Member -MemberType NoteProperty -Name PoolUtilizationPct -Value $utilPct
            $p | Add-Member -MemberType NoteProperty -Name CoolAccess -Value $pool.CoolAccess
            $p | Add-Member -MemberType NoteProperty -Name EncryptionType -Value ([string]$pool.EncryptionType)
            $p | Add-Member -MemberType NoteProperty -Name Volumes -Value @($volDetail)
            $thelist += $p
        }

        # backups live under a vault, not the pool, and bill separately
        if ($includeBackups) {
            try {
                $vaults = @(Get-AnfBackupVault -ResourceGroupName $acctRg -AccountName $acctName -ErrorAction Stop)
                foreach ($vault in $vaults) {
                    $vaultName = Get-AnfLeafName $vault.Name
                    $backups = @(Get-AnfBackup -ResourceGroupName $acctRg -AccountName $acctName -BackupVaultName $vaultName -ErrorAction SilentlyContinue)

                    $b = New-Object psobject
                    $b | Add-Member -MemberType NoteProperty -Name NetAppAccount -Value $acctName
                    $b | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $acctRg
                    $b | Add-Member -MemberType NoteProperty -Name BackupVault -Value $vaultName
                    $b | Add-Member -MemberType NoteProperty -Name Region -Value $vault.Location
                    $b | Add-Member -MemberType NoteProperty -Name Backups -Value @($backups)
                    $b | Add-Member -MemberType NoteProperty -Name IsBackupVault -Value $true
                    $thelist += $b
                }
            } catch {
                Write-Verbose "-> no backup vaults for $acctName" -Verbose
            }
        }
    }

    return $thelist
}
