function Get-AWSEC2Uptime {
    <#
    .SYNOPSIS
        Calculates uptime percentage for an AWS EC2 instance using CloudWatch metrics.
    
    .DESCRIPTION
        This function calculates the uptime percentage for an EC2 instance by checking
        CloudWatch StatusCheckFailed metrics. If no data is available, it assumes the
        instance has been in its current state for the entire period.
    
    .NOTES
        This simplified approach doesn't require CloudTrail and is more reliable for
        TCO calculations. It uses the StatusCheckFailed metric to determine downtime.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $InstanceId,
        [Parameter(Mandatory)]
        [array] $vmList,
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1
    )

    begin {
        # Ensure CloudWatch module is loaded
        if (-not (Get-Module -Name AWS.Tools.CloudWatch)) {
            if (Get-Module -ListAvailable -Name AWS.Tools.CloudWatch) {
                Import-Module AWS.Tools.CloudWatch -ErrorAction Stop
            } else {
                throw "AWS.Tools.CloudWatch module is not installed. Install it with: Install-Module AWS.Tools.CloudWatch"
            }
        }

        Write-Verbose "--> Starting uptime calculation for Instance: $InstanceId" -Verbose
        $actualDays = $days + $offsetDays
        $Date = (Get-Date).ToUniversalTime()
        $StartDate = $Date.AddDays(-$actualDays)
        $EndDate = $Date.AddDays(-$offsetDays)
        $PSBoundParameters | ConvertTo-Json -Depth 1 | Write-Verbose
    }

    process {
        try {
            # Get current instance state from the vmList
            $instance = $vmList | Where-Object { $_.InstanceId -eq $InstanceId }
            $currentPowerState = $instance.State.Name

            # Get the instance Name tag for reporting
            $nameTag = ($instance.Tags | Where-Object { $_.Key -eq 'Name' }).Value
            $vmName = if ($nameTag) { $nameTag } else { $InstanceId }

            # Get resource group equivalent from tags
            $rgTag = ($instance.Tags | Where-Object { $_.Key -eq 'ResourceGroup' -or $_.Key -eq 'Project' -or $_.Key -eq 'Environment' }).Value
            $resourceGroup = if ($rgTag) { $rgTag } else { 'N/A' }

            # Get launch time to help determine if instance was running during the period
            $launchTime = $instance.LaunchTime
            $totalSeconds = ($EndDate - $StartDate).TotalSeconds

            # Method 1: Check CloudWatch StatusCheckFailed metrics
            Write-Verbose "Checking CloudWatch StatusCheckFailed metrics..."
            
            $dimension = New-Object Amazon.CloudWatch.Model.Dimension
            $dimension.Name = 'InstanceId'
            $dimension.Value = $InstanceId

            $periodSeconds = 3600  # 1 hour periods for better granularity
            
            try {
                # Get StatusCheckFailed_System and StatusCheckFailed_Instance
                $statusMetrics = Get-CWMetricStatistic `
                    -Namespace 'AWS/EC2' `
                    -MetricName 'StatusCheckFailed' `
                    -Dimension $dimension `
                    -StartTime $StartDate `
                    -EndTime $EndDate `
                    -Period $periodSeconds `
                    -Statistic 'Maximum' `
                    -ErrorAction SilentlyContinue

                if ($statusMetrics -and $statusMetrics.Datapoints.Count -gt 0) {
                    # Count periods where status check failed (value = 1)
                    $failedChecks = ($statusMetrics.Datapoints | Where-Object { $_.Maximum -eq 1 }).Count
                    $totalChecks = $statusMetrics.Datapoints.Count
                    
                    # Calculate uptime percentage
                    $uptimePercentage = if ($totalChecks -gt 0) {
                        [math]::Round((($totalChecks - $failedChecks) / $totalChecks) * 100, 2)
                    } else {
                        0
                    }
                    
                    Write-Verbose "CloudWatch metrics found: $totalChecks checks, $failedChecks failures"
                    $method = 'CloudWatch StatusCheck'
                } else {
                    throw "No CloudWatch metrics available"
                }
            } catch {
                Write-Verbose "CloudWatch metrics not available, using state-based calculation"
                
                # Method 2: Use launch time and current state
                # If instance launched before start date and is currently running, assume it's been running
                # If instance launched after start date, calculate partial uptime
                
                if ($currentPowerState -eq 'running') {
                    if ($launchTime -le $StartDate) {
                        # Instance was launched before the measurement period and is still running
                        $uptimePercentage = 100.0
                        Write-Verbose "Instance running since before measurement period"
                    } elseif ($launchTime -ge $EndDate) {
                        # Instance launched after measurement period
                        $uptimePercentage = 0.0
                        Write-Verbose "Instance launched after measurement period"
                    } else {
                        # Instance launched during measurement period
                        $runningSeconds = ($EndDate - $launchTime).TotalSeconds
                        $uptimePercentage = [math]::Round(($runningSeconds / $totalSeconds) * 100, 2)
                        Write-Verbose "Instance launched during period at $launchTime"
                    }
                } else {
                    # Instance is currently stopped/terminated
                    # Conservative estimate: assume it was stopped for the entire period
                    $uptimePercentage = 0.0
                    Write-Verbose "Instance currently in state: $currentPowerState"
                }
                
                $method = 'State-based estimation'
            }

            $totalHours = [math]::Round($totalSeconds / 3600, 2)
            $runningHours = [math]::Round(($totalSeconds * $uptimePercentage / 100) / 3600, 2)
            $stoppedHours = [math]::Round($totalHours - $runningHours, 2)

            # Return result object
            $result = New-Object psobject
            $result | Add-Member -MemberType NoteProperty -Name VMName -Value $vmName
            $result | Add-Member -MemberType NoteProperty -Name ResourceGroup -Value $resourceGroup
            $result | Add-Member -MemberType NoteProperty -Name StartDate -Value $StartDate
            $result | Add-Member -MemberType NoteProperty -Name EndDate -Value $EndDate
            $result | Add-Member -MemberType NoteProperty -Name UptimePercentage -Value $uptimePercentage
            $result | Add-Member -MemberType NoteProperty -Name TotalHours -Value $totalHours
            $result | Add-Member -MemberType NoteProperty -Name RunningHours -Value $runningHours
            $result | Add-Member -MemberType NoteProperty -Name StoppedHours -Value $stoppedHours
            $result | Add-Member -MemberType NoteProperty -Name CurrentState -Value $currentPowerState
            $result | Add-Member -MemberType NoteProperty -Name LaunchTime -Value $launchTime
            $result | Add-Member -MemberType NoteProperty -Name Method -Value $method
            return $result
        }
        catch {
            Write-Error "Failed to calculate uptime for Instance '$InstanceId': $_"
            throw
        }
    }
}
