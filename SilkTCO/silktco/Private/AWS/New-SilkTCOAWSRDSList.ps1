function New-SilkTCOAWSRDSList {
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
        [switch] $allDBs
    )

    $requiredModules = @('AWS.Tools.RDS')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        Import-Module $module
    }

    $rdsParams = @{}
    if ($Region) {
        $rdsParams['Region'] = $Region
    }

    if ($inputFile) {
        # feed in a list of DBInstanceIdentifiers
        $dbIds = Get-Content $inputFile
        $rdslist = @()
        foreach ($id in $dbIds) {
            $rdslist += Get-RDSDBInstance -DBInstanceIdentifier $id.Trim() @rdsParams
        }
    } else {
        $rdslist = Get-RDSDBInstance @rdsParams
    }

    # RDS doesn't do server side tag filtering here, so match on the instance TagList
    if ($TagKey -and $TagValue) {
        $rdslist = $rdslist | Where-Object {
            ($_.TagList | Where-Object { $_.Key -eq $TagKey -and $_.Value -eq $TagValue })
        }
    }

    # skip aurora - handled separately (cluster storage, no AllocatedStorage)
    $rdslist = $rdslist | Where-Object { $_.Engine -notlike 'aurora*' }

    if (-not $allDBs) {
        $rdslist = $rdslist | Where-Object { $_.DBInstanceStatus -eq 'available' }
    }

    return $rdslist
}
