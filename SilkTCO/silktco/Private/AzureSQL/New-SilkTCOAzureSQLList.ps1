<#
    .SYNOPSIS
    Discovers Azure managed SQL PaaS resources.

    .DESCRIPTION
    Covers the whole managed-SQL family, which is the Azure equivalent of what RDS
    covers on AWS:

      Azure SQL Database          single databases, and databases inside elastic pools
      Azure SQL Elastic Pool      the pool itself, which is what actually bills
      SQL Managed Instance        the instance, and the databases on it
      PostgreSQL Flexible Server
      MySQL Flexible Server

    Single Server (postgres/mysql) and MariaDB are deliberately not collected - all three
    are retired. SQL on a VM is IaaS and already shows up in Export-SilkTCOAzure.
#>

function New-SilkTCOAzureSQLList {
    param(
        [Parameter()]
        [array] $resourceGroupNames,
        [Parameter()]
        [switch] $includeSystemDatabases
    )

    if (-not (Install-SilkTCOModule -Name 'Az.Sql')) {
        throw "Az.Sql is required for the Azure SQL collection and could not be installed."
    }

    # rg isnt a property on the oss flexible server objects, so dig it out of the arm id
    function Get-SilkRgFromId {
        param([string] $id)
        if ($id -match '/resourceGroups/([^/]+)/') { return $Matches[1] }
        return 'N/A'
    }

    # az.sql models use Tags, the oss flexible servers use Tag. handle both
    function Get-SilkResourceGroupTag {
        param($tags)
        if (-not $tags) { return 'N/A' }
        foreach ($k in 'ResourceGroup', 'Project', 'Environment') {
            if ($tags[$k]) { return $tags[$k] }
        }
        return 'N/A'
    }

    $thelist = @()

    # ---------------------------------------------------------------
    # Azure SQL Database + elastic pools, both hang off a logical server
    # ---------------------------------------------------------------
    $servers = @()
    try {
        if ($resourceGroupNames) {
            foreach ($rg in $resourceGroupNames) {
                $servers += Get-AzSqlServer -ResourceGroupName $rg -ErrorAction SilentlyContinue
            }
        } else {
            $servers = @(Get-AzSqlServer -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Warning "Could not enumerate SQL logical servers: $($_.Exception.Message)"
    }

    foreach ($srv in $servers) {
        Write-Verbose "-> SQL server $($srv.ServerName) ($($srv.ResourceGroupName))" -Verbose

        # pools first - the pool carries the compute, the databases in it do not
        try {
            foreach ($pool in @(Get-AzSqlElasticPool -ResourceGroupName $srv.ResourceGroupName -ServerName $srv.ServerName -ErrorAction Stop)) {
                $o = New-Object psobject
                $o | Add-Member -MemberType NoteProperty -Name RecordType -Value 'ElasticPool'
                $o | Add-Member -MemberType NoteProperty -Name ResourceName -Value $pool.ElasticPoolName
                $o | Add-Member -MemberType NoteProperty -Name ParentName -Value $srv.ServerName
                $o | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $pool.ResourceGroupName
                $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $pool.ResourceId
                $o | Add-Member -MemberType NoteProperty -Name Region -Value $pool.Location
                $o | Add-Member -MemberType NoteProperty -Name Engine -Value 'SQL Server'
                $o | Add-Member -MemberType NoteProperty -Name EngineVersion -Value $null
                $o | Add-Member -MemberType NoteProperty -Name Tier -Value $pool.Edition
                $o | Add-Member -MemberType NoteProperty -Name SkuName -Value $pool.SkuName
                $o | Add-Member -MemberType NoteProperty -Name Family -Value $pool.Family
                $o | Add-Member -MemberType NoteProperty -Name Capacity -Value $(if ($pool.Capacity) { $pool.Capacity } else { $pool.Dtu })
                $o | Add-Member -MemberType NoteProperty -Name CapacityUnit -Value $(if ($pool.Family) { 'vCore' } else { 'DTU' })
                $o | Add-Member -MemberType NoteProperty -Name StorageProvisionedGB -Value $(if ($pool.StorageMB) { [Math]::Round($pool.StorageMB / 1024, 2) } elseif ($pool.MaxSizeBytes) { [Math]::Round($pool.MaxSizeBytes / 1GB, 2) } else { $null })
                $o | Add-Member -MemberType NoteProperty -Name LicenseType -Value $pool.LicenseType
                $o | Add-Member -MemberType NoteProperty -Name ZoneRedundant -Value $pool.ZoneRedundant
                $o | Add-Member -MemberType NoteProperty -Name Zone -Value $null
                $o | Add-Member -MemberType NoteProperty -Name ResourceGroupTag -Value (Get-SilkResourceGroupTag $pool.Tags)
                $o | Add-Member -MemberType NoteProperty -Name MetricNamespace -Value 'Microsoft.Sql/servers/elasticPools'
                $thelist += $o
            }
        } catch {
            Write-Verbose "-> no elastic pools on $($srv.ServerName)" -Verbose
        }

        try {
            foreach ($db in @(Get-AzSqlDatabase -ResourceGroupName $srv.ResourceGroupName -ServerName $srv.ServerName -ErrorAction Stop)) {
                # master is a system db, always present, doesnt bill. skip unless asked
                if (-not $includeSystemDatabases -and $db.DatabaseName -eq 'master') { continue }

                # serverless shows up as a min capacity + an autopause delay
                $isServerless = ($null -ne $db.MinimumCapacity) -or ($null -ne $db.AutoPauseDelayInMinutes)

                $o = New-Object psobject
                $o | Add-Member -MemberType NoteProperty -Name RecordType -Value 'SqlDatabase'
                $o | Add-Member -MemberType NoteProperty -Name ResourceName -Value $db.DatabaseName
                $o | Add-Member -MemberType NoteProperty -Name ParentName -Value $db.ServerName
                $o | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $db.ResourceGroupName
                $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $db.ResourceId
                $o | Add-Member -MemberType NoteProperty -Name Region -Value $db.Location
                $o | Add-Member -MemberType NoteProperty -Name Engine -Value 'SQL Server'
                $o | Add-Member -MemberType NoteProperty -Name EngineVersion -Value $null
                $o | Add-Member -MemberType NoteProperty -Name Tier -Value $db.Edition
                $o | Add-Member -MemberType NoteProperty -Name SkuName -Value $(if ($db.SkuName) { $db.SkuName } else { $db.CurrentServiceObjectiveName })
                $o | Add-Member -MemberType NoteProperty -Name Family -Value $db.Family
                $o | Add-Member -MemberType NoteProperty -Name Capacity -Value $db.Capacity
                $o | Add-Member -MemberType NoteProperty -Name CapacityUnit -Value $(if ($db.Family) { 'vCore' } else { 'DTU' })
                $o | Add-Member -MemberType NoteProperty -Name StorageProvisionedGB -Value $(if ($db.MaxSizeBytes) { [Math]::Round($db.MaxSizeBytes / 1GB, 2) } else { $null })
                $o | Add-Member -MemberType NoteProperty -Name LicenseType -Value $db.LicenseType
                $o | Add-Member -MemberType NoteProperty -Name ZoneRedundant -Value $db.ZoneRedundant
                $o | Add-Member -MemberType NoteProperty -Name Zone -Value $null
                $o | Add-Member -MemberType NoteProperty -Name ElasticPoolName -Value $db.ElasticPoolName
                $o | Add-Member -MemberType NoteProperty -Name ServiceObjective -Value $db.CurrentServiceObjectiveName
                $o | Add-Member -MemberType NoteProperty -Name BackupRedundancy -Value $db.CurrentBackupStorageRedundancy
                $o | Add-Member -MemberType NoteProperty -Name ReadReplicas -Value $db.ReadReplicaCount
                $o | Add-Member -MemberType NoteProperty -Name HAReplicas -Value $db.HighAvailabilityReplicaCount
                $o | Add-Member -MemberType NoteProperty -Name IsServerless -Value $isServerless
                $o | Add-Member -MemberType NoteProperty -Name ServerlessMinCapacity -Value $db.MinimumCapacity
                $o | Add-Member -MemberType NoteProperty -Name AutoPauseDelayMinutes -Value $db.AutoPauseDelayInMinutes
                $o | Add-Member -MemberType NoteProperty -Name Status -Value $db.Status
                $o | Add-Member -MemberType NoteProperty -Name ResourceGroupTag -Value (Get-SilkResourceGroupTag $db.Tags)
                $o | Add-Member -MemberType NoteProperty -Name MetricNamespace -Value 'Microsoft.Sql/servers/databases'
                $thelist += $o
            }
        } catch {
            Write-Warning "Could not list databases on $($srv.ServerName): $($_.Exception.Message)"
        }
    }

    # ---------------------------------------------------------------
    # SQL Managed Instance + its databases
    # ---------------------------------------------------------------
    $instances = @()
    try {
        if ($resourceGroupNames) {
            foreach ($rg in $resourceGroupNames) {
                $instances += Get-AzSqlInstance -ResourceGroupName $rg -ErrorAction SilentlyContinue
            }
        } else {
            $instances = @(Get-AzSqlInstance -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-Warning "Could not enumerate SQL Managed Instances: $($_.Exception.Message)"
    }

    foreach ($mi in $instances) {
        Write-Verbose "-> Managed Instance $($mi.ManagedInstanceName) ($($mi.Sku.Name), $($mi.VCores) vCore)" -Verbose

        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name RecordType -Value 'ManagedInstance'
        $o | Add-Member -MemberType NoteProperty -Name ResourceName -Value $mi.ManagedInstanceName
        $o | Add-Member -MemberType NoteProperty -Name ParentName -Value $mi.InstancePoolName
        $o | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $mi.ResourceGroupName
        $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $mi.Id
        $o | Add-Member -MemberType NoteProperty -Name Region -Value $mi.Location
        $o | Add-Member -MemberType NoteProperty -Name Engine -Value 'SQL Server'
        $o | Add-Member -MemberType NoteProperty -Name EngineVersion -Value $null
        $o | Add-Member -MemberType NoteProperty -Name Tier -Value $(if ($mi.Sku.Tier) { $mi.Sku.Tier } else { $mi.Sku.Name })
        $o | Add-Member -MemberType NoteProperty -Name SkuName -Value $mi.Sku.Name
        $o | Add-Member -MemberType NoteProperty -Name Family -Value $mi.Sku.Family
        $o | Add-Member -MemberType NoteProperty -Name Capacity -Value $mi.VCores
        $o | Add-Member -MemberType NoteProperty -Name CapacityUnit -Value 'vCore'
        $o | Add-Member -MemberType NoteProperty -Name MemoryGB -Value $mi.MemorySizeInGB
        $o | Add-Member -MemberType NoteProperty -Name StorageProvisionedGB -Value $mi.StorageSizeInGB
        $o | Add-Member -MemberType NoteProperty -Name ProvisionedIOPS -Value $mi.StorageIOps
        $o | Add-Member -MemberType NoteProperty -Name LicenseType -Value $mi.LicenseType
        $o | Add-Member -MemberType NoteProperty -Name ZoneRedundant -Value $mi.ZoneRedundant
        $o | Add-Member -MemberType NoteProperty -Name Zone -Value $null
        $o | Add-Member -MemberType NoteProperty -Name BackupRedundancy -Value $mi.CurrentBackupStorageRedundancy
        $o | Add-Member -MemberType NoteProperty -Name PricingModel -Value $mi.PricingModel
        $o | Add-Member -MemberType NoteProperty -Name ResourceGroupTag -Value (Get-SilkResourceGroupTag $mi.Tags)
        $o | Add-Member -MemberType NoteProperty -Name MetricNamespace -Value 'Microsoft.Sql/managedInstances'
        $thelist += $o

        # the databases dont bill separately, but you need them to size the estate
        try {
            foreach ($mdb in @(Get-AzSqlInstanceDatabase -ResourceGroupName $mi.ResourceGroupName -InstanceName $mi.ManagedInstanceName -ErrorAction Stop)) {
                $d = New-Object psobject
                $d | Add-Member -MemberType NoteProperty -Name RecordType -Value 'ManagedDatabase'
                $d | Add-Member -MemberType NoteProperty -Name ResourceName -Value $mdb.Name
                $d | Add-Member -MemberType NoteProperty -Name ParentName -Value $mi.ManagedInstanceName
                $d | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $mdb.ResourceGroupName
                $d | Add-Member -MemberType NoteProperty -Name ResourceId -Value $mdb.Id
                $d | Add-Member -MemberType NoteProperty -Name Region -Value $mdb.Location
                $d | Add-Member -MemberType NoteProperty -Name Engine -Value 'SQL Server'
                $d | Add-Member -MemberType NoteProperty -Name Status -Value $mdb.Status
                $d | Add-Member -MemberType NoteProperty -Name ResourceGroupTag -Value (Get-SilkResourceGroupTag $mdb.Tags)
                $d | Add-Member -MemberType NoteProperty -Name MetricNamespace -Value $null
                $thelist += $d
            }
        } catch {
            Write-Verbose "-> could not list databases on $($mi.ManagedInstanceName)" -Verbose
        }
    }

    # ---------------------------------------------------------------
    # PostgreSQL / MySQL flexible servers
    # ---------------------------------------------------------------
    $ossEngines = @(
        @{ Name = 'PostgreSqlFlexible'; Module = 'Az.PostgreSql'; Cmdlet = 'Get-AzPostgreSqlFlexibleServer'; Engine = 'PostgreSQL'; Namespace = 'Microsoft.DBforPostgreSQL/flexibleServers' }
        @{ Name = 'MySqlFlexible';      Module = 'Az.MySql';      Cmdlet = 'Get-AzMySqlFlexibleServer';      Engine = 'MySQL';      Namespace = 'Microsoft.DBforMySQL/flexibleServers' }
    )

    foreach ($eng in $ossEngines) {
        if (-not (Install-SilkTCOModule -Name $eng.Module)) {
            Write-Warning "$($eng.Module) unavailable - skipping $($eng.Engine) flexible servers."
            continue
        }

        $srvs = @()
        try {
            if ($resourceGroupNames) {
                foreach ($rg in $resourceGroupNames) {
                    $srvs += & $eng.Cmdlet -ResourceGroupName $rg -ErrorAction SilentlyContinue
                }
            } else {
                $srvs = @(& $eng.Cmdlet -ErrorAction SilentlyContinue)
            }
        } catch {
            Write-Warning "Could not enumerate $($eng.Engine) flexible servers: $($_.Exception.Message)"
            continue
        }

        foreach ($s in $srvs) {
            Write-Verbose "-> $($eng.Engine) flexible server $($s.Name) ($($s.SkuName))" -Verbose

            $o = New-Object psobject
            $o | Add-Member -MemberType NoteProperty -Name RecordType -Value $eng.Name
            $o | Add-Member -MemberType NoteProperty -Name ResourceName -Value $s.Name
            $o | Add-Member -MemberType NoteProperty -Name ParentName -Value $null
            $o | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value (Get-SilkRgFromId $s.Id)
            $o | Add-Member -MemberType NoteProperty -Name ResourceId -Value $s.Id
            $o | Add-Member -MemberType NoteProperty -Name Region -Value $s.Location
            $o | Add-Member -MemberType NoteProperty -Name Engine -Value $eng.Engine
            $o | Add-Member -MemberType NoteProperty -Name EngineVersion -Value $s.Version
            $o | Add-Member -MemberType NoteProperty -Name Tier -Value $s.SkuTier
            $o | Add-Member -MemberType NoteProperty -Name SkuName -Value $s.SkuName
            $o | Add-Member -MemberType NoteProperty -Name Capacity -Value $null
            $o | Add-Member -MemberType NoteProperty -Name CapacityUnit -Value 'vCore'
            $o | Add-Member -MemberType NoteProperty -Name StorageProvisionedGB -Value $s.StorageSizeGb
            $o | Add-Member -MemberType NoteProperty -Name ProvisionedIOPS -Value $s.StorageIop
            $o | Add-Member -MemberType NoteProperty -Name StorageAutoGrow -Value $s.StorageAutoGrow
            $o | Add-Member -MemberType NoteProperty -Name Zone -Value $s.AvailabilityZone
            $o | Add-Member -MemberType NoteProperty -Name HAMode -Value $s.HighAvailabilityMode
            $o | Add-Member -MemberType NoteProperty -Name HAState -Value $s.HighAvailabilityState
            $o | Add-Member -MemberType NoteProperty -Name BackupRetentionDays -Value $s.BackupRetentionDay
            $o | Add-Member -MemberType NoteProperty -Name BackupRedundancy -Value $s.BackupGeoRedundantBackup
            $o | Add-Member -MemberType NoteProperty -Name ReplicationRole -Value $s.ReplicationRole
            $o | Add-Member -MemberType NoteProperty -Name Status -Value $s.State
            $o | Add-Member -MemberType NoteProperty -Name ResourceGroupTag -Value (Get-SilkResourceGroupTag $s.Tag)
            $o | Add-Member -MemberType NoteProperty -Name MetricNamespace -Value $eng.Namespace
            $thelist += $o
        }
    }

    return $thelist
}
