$badArray = @()

$response = Get-AzComputeResourceSku | Where-Object {$_.Name -eq 'Standard_D64ds_v4' -or $_.Name -eq 'Standard_L8s_v2'}
$badResources = ($response | Where-Object {$_.Restrictions})
foreach ($r in $badResources) {
    $o = New-Object psobject
    $o | Add-Member -MemberType NoteProperty -Name "Location" -Value $r.LocationInfo.Location
    $o | Add-Member -MemberType NoteProperty -Name "VM Size" -Value $r.name
    $o | Add-Member -MemberType NoteProperty -Name "Restriction" -Value $r.Restrictions.reasoncode
    $o | Add-Member -MemberType NoteProperty -Name "Zones" -Value $r.Restrictions.RestrictionInfo.Zones

    $badArray += $o
}

