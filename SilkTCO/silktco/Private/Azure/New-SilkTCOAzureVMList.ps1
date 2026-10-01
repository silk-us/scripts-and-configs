function New-SilkTCOAzureVMList {
    param(
        [Parameter()]    
        [string] $subscriptionName,
        [Parameter()]  
        [string] $inputFile,
        [Parameter()]  
        [array] $resourceGroupNames,
        [Parameter()] 
        [array] $zones,
        [Parameter()]
        [switch] $allVMs
    )

    # Get-AzVM -Status gives up on power state past ~100 VMs, and anything without a state
    # then falls out of the running filter below. plain Get-AzVM has no cap, so list with
    # that and get state for the lot from resource graph in one call.
    if ($inputFile) {
        # $vmlist = Get-Content $inputFile | ForEach-Object { Get-AzVM -Name $_ -Status }
        $names = @(Get-Content $inputFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $vmlist = @(Get-AzVM | Where-Object { $_.Name -in $names })
    }
    else {
        # $vmlist = Get-AzVM -Status
        $vmlist = @(Get-AzVM)
    }

    if ($resourceGroupNames) {
        $vmlist = foreach ($r in $resourceGroupNames) {
            $vmlist | Where-Object { $_.ResourceGroupName -contains $r }
        }
    }

    if ($zones) {
        $vmlist = foreach ($z in $zones) {    
            $vmlist | Where-Object { $_.Zones -contains $z }
        }
    }

    $states = @{}
    if (Install-SilkTCOModule -Name 'Az.ResourceGraph') {
        $ctx = Get-AzContext
        $q = "resources | where type =~ 'microsoft.compute/virtualmachines' | project id = tolower(id), powerState = tostring(properties.extended.instanceView.powerState.displayStatus)"
        try {
            $token = $null
            do {
                $gp = @{ Query = $q; Subscription = $ctx.Subscription.Id; First = 1000 }
                if ($token) { $gp['SkipToken'] = $token }
                $page = Search-AzGraph @gp -ErrorAction Stop
                foreach ($row in $page.Data) { $states[$row.id] = $row.powerState }
                $token = $page.SkipToken
            } while ($token)
        } catch {
            Write-Warning "Resource Graph lookup failed, asking each VM for its status instead (slower): $($_.Exception.Message)"
        }
    }

    foreach ($vm in $vmlist) {
        $key = $vm.Id.ToLower()
        if ($states.ContainsKey($key)) {
            $state = $states[$key]
        } else {
            # not in the graph, or no graph at all - ask this one directly
            $iv = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status -ErrorAction SilentlyContinue
            $state = ($iv.Statuses | Where-Object { $_.Code -like 'PowerState/*' } | Select-Object -First 1).DisplayStatus
        }
        $vm | Add-Member -MemberType NoteProperty -Name PowerState -Value $state -Force
    }

    if (!$allVMs) {
        $vmlist = $vmlist | Where-Object { $_.PowerState -eq 'VM running' }
    }
    return $vmlist
}
