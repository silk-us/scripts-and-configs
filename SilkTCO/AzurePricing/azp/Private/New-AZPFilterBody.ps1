function New-AZPFilterBody {
    param(
        [parameter(Mandatory)]
        [hashtable] $spec,
        [parameter()]
        [string] $currencyCode = 'USD'

    )

    Write-Verbose "-> Invoking private function: New-AZPFilterBody"

    $filterString = $null

    Write-Verbose "--> Working with keys:"
    $spec | ConvertTo-Json -Depth 10 | Write-Verbose

    foreach ($i in $spec.keys) {
        $val = $spec[$i]
        $filterStringAdd = "$i eq `'$val`' and "
        $filterString = $filterString + $filterStringAdd
    }

    $filterString = $filterString.Substring(0,$filterString.Length-5)
    Write-Verbose "`$filter: --> $filterString"

    $body = @{}
    $body.Add('$filter',$filterString)
    $body.Add('currencyCode',$currencyCode)
    
    return $body
}