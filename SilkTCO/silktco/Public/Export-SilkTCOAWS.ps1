Function Export-SilkTCOAWS {
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int] $days = 1,
        [Parameter()]
        [string] $region,
        [Parameter()]
        [string] $inputFile,
        [Parameter()]
        [string] $TagKey,
        [Parameter()]
        [string] $TagValue,
        [Parameter()]
        [switch] $allVMs,
        [Parameter()]
        [switch] $skipFSx
    )

    # Build parameter hashtable for New-SilkTCOAWSVMList
    $vmListParams = @{}
    if ($region) { $vmListParams['Region'] = $region }
    if ($inputFile) { $vmListParams['inputFile'] = $inputFile }
    if ($TagKey) { $vmListParams['TagKey'] = $TagKey }
    if ($TagValue) { $vmListParams['TagValue'] = $TagValue }
    if ($allVMs) { $vmListParams['allVMs'] = $true }

    $vmlist = New-SilkTCOAWSVMList @vmListParams 
    $metrics = New-SilkTCOAWSVMMetrics -vmlist $vmlist -days $days -Verbose
    
    # Pass region only if specified, otherwise let cost function auto-detect
    if ($region) {
        $costs = New-SilkTCOAWSCostArray -vmlist $vmlist -region $region -days $days -Verbose
    } else {
        $costs = New-SilkTCOAWSCostArray -vmlist $vmlist -days $days -Verbose
    }
    
    $report = Merge-SilkTCOAWSData -vmlist $vmlist -metrics $metrics -costs $costs

    # $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'AWS' -PassThru } 
    $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'AWS' -PassThru }

    # FSx ONTAP rides along in the same report - it's storage the workload is paying for.
    # wrapped up tight because this needs fsx:Describe* perms that older runs didnt, and a
    # missing permission shouldnt take the ec2/ebs rows down with it.
    if (-not $skipFSx) {
        try {
            $fsxListParams = @{}
            if ($region) { $fsxListParams['Region'] = $region }
            if ($TagKey) { $fsxListParams['TagKey'] = $TagKey }
            if ($TagValue) { $fsxListParams['TagValue'] = $TagValue }
            if ($allVMs) { $fsxListParams['allFileSystems'] = $true }

            $fslist = New-SilkTCOAWSFSxList @fsxListParams

            if ($fslist) {
                $fsxMetrics = New-SilkTCOAWSFSxMetrics -fslist $fslist -days $days -Verbose

                if ($region) {
                    $fsxCosts = New-SilkTCOAWSFSxCostArray -fslist $fslist -metrics $fsxMetrics -region $region -days $days -Verbose
                } else {
                    $fsxCosts = New-SilkTCOAWSFSxCostArray -fslist $fslist -metrics $fsxMetrics -days $days -Verbose
                }

                $fsxReport = Merge-SilkTCOAWSFSxData -fslist $fslist -metrics $fsxMetrics -costs $fsxCosts
                $fsxReport = $fsxReport | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'AWS-FSxN' -PassThru }

                $report = @($report) + @($fsxReport)
                Write-Verbose "--- Added $($fsxReport.Count) FSx ONTAP row(s) ---" -Verbose
            } else {
                Write-Verbose "-> no FSx ONTAP file systems found" -Verbose
            }
        } catch {
            Write-Warning "FSx ONTAP collection failed, continuing with EC2/EBS only: $($_.Exception.Message)"
        }
    }

    $report | export-csv -Path ".\SilkTCO_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
}
