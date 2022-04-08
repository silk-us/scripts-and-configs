param(
    [int] $threads,
    [string] $volName,
    [switch] $debug
)

Get-Job | Remove-Job

$object = @{}
$object.Add('__limit','9999')

$endpoint = 'https://' + $Global:k2rfconnection.K2Endpoint + '/api/v2/volumes'

if ($volName) {
    $object.Add('name__contains',$volName)
    $sdpVol = Get-SDPVolume -name $volName
    $totalExpected = $sdpVol.count * $threads
} else {
    $sdpVol = Get-SDPVolume
    $totalExpected = $sdpVol.count * $threads
}

$threadCounter = 1
while ($threadCounter -le $threads) {
    Invoke-RestMethod -Method GET -Uri $endpoint -Credential $Global:k2rfconnection.credentials -SkipCertificateCheck -Body $object & 
    $threadCounter++
}

Start-Sleep -Seconds 5

$allJobs = Get-Job -IncludeChildJob | Where-Object {$_.PSJobTypeName -ne 'BackgroundJob'}

$o = New-Object psobject
$o | Add-Member -MemberType NoteProperty -Name "expected" -Value $totalExpected
$o | Add-Member -MemberType NoteProperty -Name "responded" -Value $allJobs.Output.hits.count 
if ($debug) {
    $jobresponse = @()
    foreach ($job in $allJobs) {
        $j = New-Object psobject
        $j | Add-Member -MemberType NoteProperty -Name jobID -Value $job.Id
        $j | Add-Member -MemberType NoteProperty -Name command -Value $job.Command
        $j | Add-Member -MemberType NoteProperty -Name output -Value $job.Output
        $jobresponse += $j
    }
    $o | Add-Member -MemberType NoteProperty -Name 'jobs' -Value $jobresponse
    $o | Add-Member -MemberType NoteProperty -Name 'alljobs' -Value $allJobs
}

return $o