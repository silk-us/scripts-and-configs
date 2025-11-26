function Get-AZPPv2Cost {
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

    if ($IOPS -gt 3000) {
        $IOPS = ($IOPS - 3000)
    } else {
        $IOPS = 1
    }
    Write-Verbose "ReIOPS: $IOPS"

    if ($MBps -gt 125) {
        $MBps = ($MBps - 125)
    } else {
        $MBps = 1
    }
    Write-Verbose "ReMBps: $MBps"

    $cost = ($GiB * $rate) + ($IOPS * 0.0052) + ($MBps * 0.041)
    Write-Verbose "Cost: $cost"
    $cost = [math]::Round($cost, 2)

    return $cost
}
