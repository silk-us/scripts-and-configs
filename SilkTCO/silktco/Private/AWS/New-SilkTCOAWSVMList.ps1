function New-SilkTCOAWSVMList {
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
        [switch] $allVMs
    )

    $requiredModules = @('AWS.Tools.EC2')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it with: Install-Module $module"
        }
        Import-Module $module
    }

    $ec2Params = @{}
    if ($Region) {
        $ec2Params['Region'] = $Region
    }

    if ($inputFile) {
        $instanceIds = Get-Content $inputFile
        $vmlist = @()
        foreach ($id in $instanceIds) {
            $reservation = Get-EC2Instance -InstanceId $id.Trim() @ec2Params
            $vmlist += $reservation.Instances
        }
    } else {
        $filters = @()

        if ($TagKey -and $TagValue) {
            $filters += @{
                Name   = "tag:$TagKey"
                Values = @($TagValue)
            }
        }

        if ($filters.Count -gt 0) {
            $reservations = Get-EC2Instance -Filter $filters @ec2Params
        } else {
            $reservations = Get-EC2Instance @ec2Params
        }

        $vmlist = $reservations.Instances
    }

    if (-not $allVMs) {
        # State code 16 = running
        $vmlist = $vmlist | Where-Object { $_.State.Code -eq 16 }
    }

    return $vmlist
}
