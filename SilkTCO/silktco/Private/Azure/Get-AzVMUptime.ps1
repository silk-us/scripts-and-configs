function Get-AzVMUptime {
    param(
        [Parameter(Mandatory)]
        [string] $VMName,
        [Parameter(Mandatory)]
        [string] $ResourceGroupName,
        [Parameter(Mandatory)]
        [array] $vmList,
        [Parameter()]
        [int] $days = 1,
        [Parameter()]
        [int] $offsetDays = 1
    )
    
    begin {
        Write-Verbose "--> Starting uptime calculation for VM: $VMName" -Verbose
        # Validate dates
        $days = ($days + $offsetDays)
        $Date = (Get-Date).ToUniversalTime()
        $StartDate = $date.AddDays(-$days)
        $EndDate = $date.AddDays(-$offsetDays)
        # dumped the whole vm list for every vm - n squared spam once the vms carry a powerstate
        # $PSBoundParameters | ConvertTo-Json -Depth 1 | Write-Verbose 
        $stateRef = @{}
        $stateRef.Add('Start Virtual Machine','running')
        $stateRef.Add('Deallocate Virtual Machine','stopped')
    }
    
    process {
        try {
            # $vm = $vmlist | Where-Object {$_.name -eq $VMName -and $_.ResourceGroupName -eq $ResourceGroupName}
            
            $vmStatus = $vmlist | Where-Object {$_.name -eq $VMName -and $_.ResourceGroupName -eq $ResourceGroupName}
            $resourceId = $vmStatus.Id
            $currentPowerState = $vmStatus.PowerState

            # Query Activity Log for power events
            Write-Verbose "Querying Activity Log from $StartDate to $EndDate..."

            $activityLogs = Get-AzActivityLog -ResourceId $resourceId -StartTime $StartDate -EndTime $EndDate -ErrorAction Stop | Sort-Object EventTimestamp 
            $created = $activityLogs | Where-Object {$_.OperationName -eq 'Create or Update Virtual Machine' -and $_.SubStatus -eq 'Created (HTTP Status Code: 201)'} 
            if ($created) {
                $createdDate = $created[0].EventTimestamp
                if ($createdDate -lt $StartDate) {
                    # Write-Verbose "VM was created on $createdDate, adjusting StartDate from $StartDate to $createdDate"
                    $createdDate = $created[0].EventTimestamp
                }
            }
            $activityLogs = $activityLogs | Where-Object {$_.Status -eq 'Succeeded'}

            $statusArray = @('Start Virtual Machine','Deallocate Virtual Machine')
            $powerStateEvents = $activityLogs | Where-Object {$_.OperationName -in $statusArray}

            Write-Verbose "Found $($powerStateEvents.Count) power state events"
            
            # Build timeline of state changes
            $stateChanges = @() 

            if ($created) {
                    $stateObj= [PSCustomObject] @{
                    Timestamp = $created.EventTimestamp
                    State     = 'running'
                    Operation = $created.OperationName
                }
                $stateChanges += $stateObj
            }
            
            foreach ($log in $powerStateEvents) {
                # Only add if operation was successful
                
                $stateObj= [PSCustomObject] @{
                    Timestamp = $log.EventTimestamp
                    State     = $stateRef[$log.OperationName]
                    Operation = $log.OperationName
                }
                $stateChanges += $stateObj
            }
            
            # If no events found, use current state and assume it was the same throughout
            if ($stateChanges.Count -eq 0) {
                Write-Verbose "No state changes found in Activity Log, checking current state..."
                if ($currentPowerState -eq 'VM running') {
                    $initialState = 'running'
                } else {
                    $initialState = 'stopped'
                }
               
                Write-Warning "No power state changes detected in Activity Log for the specified period. Using current state: $initialState"
            } elseif ($createdDate) {
                $initialState = 'stopped'
            } else {
                # Get state before first event by looking at what action occurred
                # If first action is 'start', VM was stopped before; if 'stop/deallocate', it was running
                $initialState = ($stateRef.GetEnumerator() | Where-Object {$_.Value -ne $stateChanges[0].State}).value

                Write-Verbose "Inferred initial state at $StartDate : $initialState"
            }
            
            # Calculate uptime by walking through state changes
            $totalSeconds = ($EndDate - $StartDate).TotalSeconds
            $runningSeconds = 0
            $currentState = $initialState
            $lastTimestamp = $StartDate
            
            if ($stateChanges) {
                foreach ($change in $stateChanges) {
                    # Calculate duration in current state
                    $duration = ($change.Timestamp - $lastTimestamp).TotalSeconds
                    
                    if ($currentState -eq 'running') {
                        $runningSeconds += $duration
                    }
                    
                    # Update state
                    $currentState = ($stateRef.GetEnumerator() | Where-Object {$_.Value -ne $currentState}).value
                    $lastTimestamp = $change.Timestamp
                }
                # Add final segment from last state change to EndDate
                $finalDuration = ($EndDate - $lastTimestamp).TotalSeconds
                if ($currentState -eq 'running') {
                    $runningSeconds += $finalDuration
                }
            } else {
                $runningSeconds = ($EndDate - $StartDate).TotalSeconds
            }

            # Calculate percentages and hours
            $uptimePercentage = if ($totalSeconds -gt 0) { 
                [math]::Round(($runningSeconds / $totalSeconds) * 100, 2) 
            } else { 
                0 
            }
            
            $totalHours = [math]::Round($totalSeconds / 3600, 2)
            $runningHours = [math]::Round($runningSeconds / 3600, 2)
            $stoppedHours = [math]::Round(($totalSeconds - $runningSeconds) / 3600, 2)
            
            # Return result object
            [PSCustomObject]@{
                VMName            = $VMName
                ResourceGroup     = $ResourceGroupName
                StartDate         = $StartDate
                EndDate           = $EndDate
                UptimePercentage  = $uptimePercentage
                TotalHours        = $totalHours
                RunningHours      = $runningHours
                StoppedHours      = $stoppedHours
                StateChanges      = $stateChanges.Count
                InitialState      = $initialState
                FinalState        = $currentState
            }
        }
        catch {
            Write-Error "Failed to calculate uptime for VM '$VMName': $_"
            throw
        }
    }
}
