param(
    [parameter()]
    [string] $drive = 'E:\',
    [parameter()]
    [int] $ThreadIOPS = 192,
    [parameter()]
    [ValidateSet('4k','8k','16k','32k')]
    [string] $IOPSBlockSize = "4k",
    [parameter()]
    [int] $ThreadTP = 32,
    [parameter()]
    [ValidateSet('32k','64k','128k','256k','512k','1024k')]
    [string] $TPBlockSize = "128k",
    [parameter()]
    [int] $Durration = 30,
    [parameter()]
    [string] $diskspdExecutable,
    [parameter()]
    [switch] $skipPrep
)

$iopsDAT = $drive + 'Testdata\iops.dat'
$throughputDAT = $drive + 'Testdata\throughput.dat'
$localName = $env:computername

if (!$diskspdExecutable) {
    if (!$skipPrep) {
        Invoke-RestMethod -Uri 'https://github.com/microsoft/diskspd/releases/download/v2.2/DiskSpd.ZIP' -OutFile DiskSpd.ZIP
        Expand-Archive .\DiskSpd.ZIP -force 
    }
    Write-Verbose "-- Downloading diskspd --" -Verbose
    $diskspdExecutable = '.\DiskSpd\amd64\diskspd.exe'
}

if (!$skipPrep) {
    New-Item -Name "testdata" -Path $drive -ItemType Directory -ErrorAction SilentlyContinue
    Write-Verbose "-- Creating IO file - $iopsDAT --" -Verbose
    & $diskspdExecutable -d60 -W5 -C15 -c32G -t64 -o4 "-b$($IOPSBlockSize)" -L -r -Suw -w100 $iopsDAT
    Write-Verbose "-- Creating IO file - $throughputDAT --" -Verbose
    & $diskspdExecutable -d60 -W5 -C15 -c64G -t2 -o4 "-b$($TPBlockSize)" -L -r -Suw -w100 $throughputDAT
}

Write-Verbose "-- Using - $iopsDAT --" -Verbose
# Read IOPS
$outfile = $localName + '-' + " $IOPSBlockSize" + " - $ThreadIOPS threads " + 'read_iops.txt' 
Write-Verbose "-- Running Read IOPS -- outfile $outfile -- at $ThreadIOPS threads -- " -Verbose
& $diskspdExecutable "-b$($IOPSBlockSize)" -W5 "-d$($Durration.ToString())" -L -Suw "-F$($ThreadIOPS.ToString())" -r -w0 -f32G $iopsDAT > $outfile

# Write IOPS
$outfile = $localName + '-' + " $IOPSBlockSize" + " - $ThreadIOPS threads " + 'write_iops.txt'
Write-Verbose "-- Running Write IOPS -- outfile $outfile -- at $ThreadIOPS threads --" -Verbose
& $diskspdExecutable "-b$($IOPSBlockSize)" -W5 "-d$($Durration.ToString())" -L -Suw "-F$($ThreadIOPS.ToString())" -r -w100 -f32G $iopsDAT > $outfile

Write-Verbose "-- Using - $throughputDAT --" -Verbose
# Read throughput
$outfile = $localName + '-' + " $TPBlockSize" + " - $ThreadTP threads " + 'read_tp.txt'
Write-Verbose "-- Running Read throughput -- outfile $outfile -- at $ThreadTP threads --" -Verbose
& $diskspdExecutable "-b$($TPBlockSize)" -W5 "-d$($Durration.ToString())" -L -Suw "-F$($ThreadTP.ToString())" -r -w0 -f64G $throughputDAT > $outfile

# Write throughput
$outfile = $localName + '-' + " $TPBlockSize" + " - $ThreadTP threads " + 'write_tp.txt'
Write-Verbose "-- Running Write throughput -- outfile $outfile -- at $ThreadTP threads -- " -Verbose
& $diskspdExecutable "-b$($TPBlockSize)" -W5 "-d$($Durration.ToString())" -L -Suw "-F$($ThreadTP.ToString())" -r -w100 -f64G $throughputDAT > $outfile

