param(
    [parameter()]
    [string] $drive = 'E:\',
    [parameter()]
    [int] $ThreadIOPS = 192,
    [parameter()]
    [int] $ThreadTP = 32,
    [parameter()]
    [string] $diskspdExecutable,
    [parameter()]
    [switch] $skipPrep
)

$iopsDAT = $drive + 'Testdata\iops.dat'
$throughputDAT = $drive + 'Testdata\throughput.dat'
$localName = $env:computername

if (!$skipPrep) {
    if (!$diskspdExecutable) {
        Invoke-RestMethod -Uri 'https://github.com/microsoft/diskspd/releases/download/v2.2/DiskSpd.ZIP' -OutFile DiskSpd.ZIP
        Expand-Archive .\DiskSpd.ZIP -force 
        $diskspdExecutable = '.\DiskSpd\amd64\diskspd.exe'
    }

    New-Item -Name "testdata" -Path $drive -ItemType Directory -ErrorAction SilentlyContinue
    Write-Verbose "-- Creating IO file - $iopsDAT --" -Verbose
    & $diskspdExecutable -d60 -W5 -C15 -c32G -t64 -o4 -b4k -L -r -Suw -w100 $iopsDAT
    Write-Verbose "-- Creating IO file - $throughputDAT --" -Verbose
    & $diskspdExecutable -d60 -W5 -C15 -c64G -t2 -o4 -b128k -L -r -Suw -w100 $throughputDAT
}

Write-Verbose "-- Using - $iopsDAT --" -Verbose
# Read IOPS
$outfile = $localName + '-' + 'read_iops.txt'
Write-Verbose "-- Running Read IOPS -- outfile $outfile -- at $ThreadIOPS threads -- " -Verbose
& $diskspdExecutable -b4K -W5 -d30 -L -Suw "-F$($ThreadIOPS.ToString())" -r -w0 -f32G $iopsDAT > $outfile

# Write IOPS
$outfile = $localName + '-' + 'write_iops.txt'
Write-Verbose "-- Running Write IOPS -- outfile $outfile -- at $ThreadIOPS threads --" -Verbose
& $diskspdExecutable -b4K -W5 -d30 -L -Suw "-F$($ThreadIOPS.ToString())" -r -w100 -f32G $iopsDAT > $outfile

Write-Verbose "-- Using - $throughputDAT --" -Verbose
# Read throughput
$outfile = $localName + '-' + 'read_tp.txt'
Write-Verbose "-- Running Read throughput -- outfile $outfile -- at $ThreadTP threads --" -Verbose
& $diskspdExecutable -b128k -W5 -d30 -L -Suw "-F$($ThreadTP.ToString())" -r -w0 -f64G $throughputDAT > $outfile

# Write throughput
$outfile = $localName + '-' + 'write_tp.txt'
Write-Verbose "-- Running Write throughput -- outfile $outfile -- at $ThreadTP threads -- " -Verbose
& $diskspdExecutable -b128k -W5 -d30 -L -Suw "-F$($ThreadTP.ToString())" -r -w100 -f64G $throughputDAT > $outfile

