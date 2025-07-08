param(
    [string] $drive = 'E:\'
)

Invoke-RestMethod -Uri 'https://github.com/microsoft/diskspd/releases/download/v2.2/DiskSpd.ZIP' -OutFile DiskSpd.ZIP
Expand-Archive .\DiskSpd.ZIP -force 

$iopsDAT = $drive + 'Testdata\iops.dat'
$throughputDAT = $drive + 'Testdata\throughput.dat'

Write-Verbose "-- Creating IO files - $iopsDAT and $throughputDAT --" -Verbose
New-Item -Name "testdata" -Path $drive -ItemType Directory -ErrorAction SilentlyContinue
.\DiskSpd\amd64\diskspd.exe -d60 -W15 -C15 -c32G -t64 -o4 -b4k -L -r -Sh -w50 $iopsDAT
.\DiskSpd\amd64\diskspd.exe -d60 -W15 -C15 -c64G -t2 -o4 -b128k -L -r -Sh -w50 $throughputDAT

Write-Verbose "-- Using - $iopsDAT --" -Verbose
Write-Verbose "-- Running Read IOPS --" -Verbose
# Read IOPS
.\DiskSpd\amd64\diskspd.exe -b4K -W15 -d60 -Sh -L -t192 -r -w0 -f32G E:\Testdata\iops.dat > read_iops.txt

Write-Verbose "-- Running Write IOPS --" -Verbose
# Write IOPS
.\DiskSpd\amd64\diskspd.exe -b4K -W15 -d60 -Sh -L -t192 -r -w100 -f32G E:\Testdata\iops.dat > write_iops.txt

Write-Verbose "-- Using - $iopsDAT --" -Verbose
Write-Verbose "-- Running Read throughput --" -Verbose
# Read throughput
.\DiskSpd\amd64\diskspd.exe -b128k -W15 -d60 -Sh -L -t32 -r -w0 -f64G E:\Testdata\throughput.dat > read_tp.txt

Write-Verbose "-- Running Write throughput --" -Verbose
# Write throughput
.\DiskSpd\amd64\diskspd.exe -b128k -W15 -d60 -Sh -L -t32 -r -w100 -f64G E:\Testdata\throughput.dat > write_tp.txt

