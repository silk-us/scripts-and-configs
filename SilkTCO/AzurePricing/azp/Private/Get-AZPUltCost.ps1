function Get-AZPUltCost {
    param(
        [parameter(Mandatory)]
        [double] $rate,
        [parameter(Mandatory)]
        [int] $GiB,
        [parameter(Mandatory)]
        [int] $IOPS,
        [parameter(Mandatory)]
        [int] $MBps
    )

    Write-Verbose "rate: $rate"
    Write-Verbose "Gib: $GiB"
    Write-Verbose "IOPS: $IOPS"
    Write-Verbose "MBps: $MBps"

    $cost = ($GiB * $rate) + ($IOPS * 0.04964) + ($MBps * 0.34967)
    Write-Verbose "Cost: $cost"
    $cost = [math]::Round($cost, 2)

    return $cost
}
