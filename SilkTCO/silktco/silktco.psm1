  #Get public and private function definition files.
$Public  = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue -Recurse)

$allpublic = @($Public)

$num = 0
Foreach($import in @($allpublic + $Private))
{
    Try
    {
        $functionName = $import.basename
        Write-Verbose  "-> importing - $functionName -" -Verbose
        . $import.fullname
    }
    Catch
    {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
    $num++
}

Export-ModuleMember -Function $allpublic.Basename -alias * 

Write-Verbose "--- Loaded $num functions ---" -Verbose