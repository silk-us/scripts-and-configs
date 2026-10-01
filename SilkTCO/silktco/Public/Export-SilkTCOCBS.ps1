<#
    .SYNOPSIS
    Exports a Pure Cloud Block Store capacity and cost report.

    .DESCRIPTION
    Collection is split across two sources because CBS is split across two places. Capacity,
    volumes and the data reduction ratio come from the Purity API on the array. The actual
    money comes from Azure Cost Management against the managed resource group the marketplace
    app deployed into.

    Purity is cloud agnostic so this works against CBS on AWS too - only the -resourceGroupName
    cost half is Azure specific.

    Credential is mandatory. Omit it and PowerShell prompts for username and password. Auth is
    proved against the array before any collection runs.

    .EXAMPLE
    Export-SilkTCOCBS -endpoint cbs-prod-01.contoso.com -resourceGroupName cbs-managed-rg

    Prompts for credentials, then reports array capacity plus real Azure spend.

    .EXAMPLE
    Export-SilkTCOCBS -endpoint 10.20.30.40 -Credential $cred -ignoreCertificateError -includeHosts
#>

Function Export-SilkTCOCBS {
    param(
        [Parameter(Mandatory)]
        [string] $endpoint,
        [Parameter(Mandatory)]
        [System.Management.Automation.Credential()]
        [pscredential] $Credential,
        [Parameter()]
        [string] $resourceGroupName,
        [Parameter()]
        [ValidateRange(1, 365)]
        [int] $days = 1,
        [Parameter()]
        [ValidateRange(0, 365)]
        [int] $offsetDays = 1,
        [Parameter()]
        [switch] $ignoreCertificateError,
        [Parameter()]
        [switch] $includeHosts,
        [Parameter()]
        [switch] $includeProtectionGroups,
        [Parameter()]
        [ValidateSet('AmortizedCost', 'ActualCost')]
        [string] $costMetric = 'AmortizedCost'
    )

    $connectParams = @{
        endpoint   = $endpoint
        Credential = $Credential
    }
    if ($ignoreCertificateError) { $connectParams['ignoreCertificateError'] = $true }

    # prove the session works before we go any further. Connect-SilkTCOCBSArray writes the
    # specific reason on failure, we just stop here
    $arrayConnection = Connect-SilkTCOCBSArray @connectParams

    if (-not $arrayConnection) {
        Write-Warning "Aborting CBS collection - no usable array session."
        return
    }

    try {
        $dataParams = @{ arrayConnection = $arrayConnection }
        if ($includeHosts) { $dataParams['includeHosts'] = $true }
        if ($includeProtectionGroups) { $dataParams['includeProtectionGroups'] = $true }

        $arrayData = New-SilkTCOCBSArrayData @dataParams

        $azureCost = $null
        if ($resourceGroupName) {
            $azureCost = New-SilkTCOCBSAzureCost -resourceGroupName $resourceGroupName -days $days -offsetDays $offsetDays -costMetric $costMetric
        } else {
            Write-Warning "No -resourceGroupName given, so no Azure spend was collected. Array capacity only."
        }

        $report = Merge-SilkTCOCBSData -arrayData $arrayData -azureCost $azureCost
        $report = $report | ForEach-Object { $_ | Add-Member -NotePropertyName 'Platform' -NotePropertyValue 'CBS' -PassThru }

        # reduction ratio drives the blob bill, so put it in front of the operator
        $dr = $arrayData.Array.DataReduction
        if ($dr) {
            $prov = $arrayData.Array.TotalProvisionedTiB
            $phys = $arrayData.Array.TotalPhysicalTiB
            Write-Verbose "--- $($arrayData.Array.ArrayName): ${prov} TiB provisioned, ${phys} TiB physical, ${dr}:1 data reduction ---" -Verbose
        }

        $report | Export-Csv -Path ".\SilkTCO_CBS_Report_$((Get-Date).ToString('yyyyMMdd_HHmmss')).csv" -NoTypeInformation
    }
    finally {
        # dont leave a session hanging on the array
        try {
            Disconnect-Pfa2Array -Array $arrayConnection -ErrorAction SilentlyContinue
        } catch { }
    }
}
