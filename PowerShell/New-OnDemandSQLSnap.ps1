<#

Example script to take an on-demand snapshot of the below volume group, and then self-map the views and crawl through the volumes to 
identify and automatically attach any databases discovered within.

Run this from the target SQL server. 

#>

# Set up the vars
$targethostName = $env:COMPUTERNAME #self
$volumeGroupName = 'SQL01-vg'

# Import the modules
Import-Module sqlps
Import-Module sdp

# Create a credential object
$password = ConvertTo-SecureString 'Password1' -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ('sqlservice', $password)

# Connect to the SDP
Connect-SDP -server 10.12.0.13 -credentials $creds

# Create the snaps
$snapshotName = $targethostName + '-' + (Get-Date -UFormat "%s").Split('.')[0]
New-SDPVolumeGroupSnapshot -name $snapshotName -volumeGroupName $volumeGroupName -retentionPolicyName Backup

$viewName = $snapshotName + '-view'
$fullSnapshotName = $volumeGroupName + ':' + $snapshotName
Get-SDPVolumeGroupSnapshot -name $fullSnapshotName | New-SDPVolumeView -name $viewName -retentionPolicyName Backup

$fullSnapshotViewName = $volumeGroupName + ':' + $viewName
New-SDPHostMapping -hostName $targethostName -snapshotName $fullSnapshotViewName

Start-Sleep -Seconds 5

# grab the silk volumes
$vols = Get-Disk -FriendlyName "KMNRIO KDP" | Get-Partition | Get-Volume

# Grab any databases on those volumes
$datafiles = @()
foreach ($i in $vols) {
    $path = $i.DriveLetter + ':\'
    $mdfs = Get-ChildItem -Recurse -Path $path | Where-Object {$_.name -like "*.mdf"}
    foreach ($m in $mdfs) {
        $datafiles += $m
    }
}

# Grab the log file info and create vars for SQL command
foreach ($d in $datafiles) {
    $databasename = $d.Name.Trim('.mdf')
    $dblogfileName = $databasename + '_log.ldf'
    foreach ($i in $vols) {
        $path = $i.DriveLetter + ':\'
        $ldf = Get-ChildItem -Recurse -Path $path | Where-Object {$_.name -eq $dblogfileName}
    }
    $databasemdf = $d.FullName
    $databaseldf = $ldf.FullName

$codeblock = @"
USE [master]
GO
CREATE DATABASE [$databasename] ON 
( FILENAME = N`'$databasemdf`' ),
( FILENAME = N`'$databaseldf`' )
FOR ATTACH
GO
"@
Invoke-Sqlcmd -Query $codeblock
}
