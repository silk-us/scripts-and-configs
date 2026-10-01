function Get-SilkTCOResourceType {
    param(
        [Parameter(Mandatory)]
        [string] $resourceId
    )

    # /providers/microsoft.netapp/netappaccounts/a/capacitypools/p -> microsoft.netapp/netappaccounts/capacitypools
    $i = $resourceId.IndexOf('/providers/', [System.StringComparison]::OrdinalIgnoreCase)
    if ($i -lt 0) { return $null }

    $parts = $resourceId.Substring($i + 11).Split('/')
    $type = @($parts[0])
    for ($n = 1; $n -lt $parts.Count; $n += 2) { $type += $parts[$n] }
    return ($type -join '/')
}
