<#
    .DESCRIPTION
    This is a small function to set the default URI to be used when making subsequent calls against the Azure retail pricing API. 

    .EXAMPLE
    This example will use the (currently) latest uri 'https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview' for pricing request. 

    Set-AZPURI -uri 'https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview'

    .PARAMETER uri
    This is a simple [string] value for the desired pricing URI. This is stored in a global variable space, so will remain valid until the current 
    PowerShell session is terminated. 
#>

function Set-AZPURI {
    param(
        [Parameter(Mandatory)]
        [string] $uri
    )

    Set-Variable -Scope Global -Name AZPURI -Value $uri
}