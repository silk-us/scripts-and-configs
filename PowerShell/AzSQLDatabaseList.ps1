# Grab all global server / instance info

$globalSQLInstances = Get-AzSqlInstance
$globalSQLServers = Get-AzSqlServer

# Parse managed instances

$globalSQLInstanceDetails = @()
foreach ($i in $globalSQLInstances) {
    $instanceDBs = Get-AzSqlInstanceDatabase -InstanceName $i.ManagedInstanceName -ResourceGroupName $i.ResourceGroupName
    foreach ($db in $instanceDBs) {
        $o = New-Object psobject
        $o | Add-Member -MemberType NoteProperty -Name 'Managed Database Name' -value $db.Name
        $o | Add-Member -MemberType NoteProperty -Name 'Status' -value $db.Status
        $o | Add-Member -MemberType NoteProperty -Name 'Managed Instance Name' -value $i.ManagedInstanceName
        $o | Add-Member -MemberType NoteProperty -Name 'Managed Instance GB Capacity' -value $i.StorageSizeInGB
        $o | Add-Member -MemberType NoteProperty -Name 'Instance ID' -Value $i.Identity.PrincipalId
        $o | Add-Member -MemberType NoteProperty -Name 'Resource Group' -Value $i.ResourceGroupName
        $o | Add-Member -MemberType NoteProperty -Name 'Account' -Value $i.AdministratorLogin
        $o | Add-Member -MemberType NoteProperty -Name 'Product' -Value 'Azure SQL Managed Instance'
        $o | Add-Member -MemberType NoteProperty -Name 'Instance Pool' -Value  $i.InstancePoolName
        $o | Add-Member -MemberType NoteProperty -Name 'Hardware Type' -Value $i.Sku.Name
        # $o | Add-Member -MemberType -Name 'Service Tier' -Value 
        $o | Add-Member -MemberType NoteProperty -Name 'Region' -Value $db.Location
        $o | Add-Member -MemberType NoteProperty -Name 'vCOREs' -Value $i.VCores
        # $o | Add-Member -MemberType -Name 'Monthly cost' -Value 
        $globalSQLInstanceDetails += $o
    }
}

# Export instance information

$globalSQLInstanceDetails | Export-Csv -NoTypeInformation -Path SQLManagedInstanceDBs.csv

# Parse the Server databases

$globalSQLDBs = @()
foreach ($i in $globalSQLServers) {
    $sqldbs = Get-AzSqlDatabase -ServerName $i.servername -ResourceGroupName $i.ResourceGroupName
    $globalSQLDBs += $sqldbs
}

$globalSQLServerDatabaseDetails = @()
foreach ($i in $globalSQLDBs) {
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name 'Database Name' -value $i.DatabaseName
    $o | Add-Member -MemberType NoteProperty -Name 'Database ID' -Value $i.DatabaseId.guid
    $sizeInGB = $i.MaxSizeBytes / 1gb
    $o | Add-Member -MemberType NoteProperty -Name 'Database Size in GB' -Value $sizeInGB
    $o | Add-Member -MemberType NoteProperty -Name 'Resource Group' -Value $i.ResourceGroupName
    $o | Add-Member -MemberType NoteProperty -Name 'Product' -Value 'Azure SQL Database'
    $o | Add-Member -MemberType NoteProperty -Name 'Performance Tier' -Value $i.Edition
    $o | Add-Member -MemberType NoteProperty -Name 'Hardware Type' -Value $i.SkuName
    $o | Add-Member -MemberType NoteProperty -Name 'Region' -Value $i.Location 
    if ($i.ElasticPoolName) {
        $ep = Get-AzSqlElasticPool -ElasticPoolName $i.ElasticPoolName -ServerName $i.ServerName -ResourceGroupName $i.ResourceGroupName
        $o | Add-Member -MemberType NoteProperty -Name 'vCOREs/DTUs' -Value $ep.Capacity
    } else {
        $o | Add-Member -MemberType NoteProperty -Name 'vCOREs/DTUs' -Value $i.Capacity
    }
    $globalSQLServerDatabaseDetails += $o
}

# Export the server databases. 

$globalSQLServerDatabaseDetails | Export-Csv -NoTypeInformation -Path SQLManagedServerDatabases.csv
