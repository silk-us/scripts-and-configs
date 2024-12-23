#Requires -RunAsAdministrator

param (
    [parameter()]
    [string] $DiskSpdBinary ='.\amd64\diskspd.exe',
    [parameter()]
    [string] $ResultDir ='.\results',
    [parameter()]
    [string] $DrvLetter ='F:',
    [parameter()]
    [string] $TargetDatafile = $DrvLetter + '\data\d100g.dat',
    [parameter()]
    [int] $Warmup = '20',
    [parameter()]
    [int] $Duration = '30',
    [parameter()]
    [string] $TargetSize = '100G',
    [parameter()]
    [int] $BlockSize = 8,
    [parameter()]
    [int] $threads, 
    [parameter()]
    # [ValidateSet(8, 16, 32, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048)]
    [int] $outstanding, 
    [parameter()]
    [int] $writePercent = 0,
    [parameter()]
    [switch] $logFile,   
    [parameter()]
    [switch] $create
)

$TargetDatafile | Write-Verbose -Verbose

if(-not $(Get-Volume -DriveLetter $TargetDatafile.TrimEnd($DrvLetter) -ErrorAction SilentlyContinue)){
    Write-Host "Drive specified is not formatted or assigned a drive letter"
    exit;
}

if(-not $(Get-Item $ResultDir -ErrorAction SilentlyContinue)){
    New-Item -ItemType Directory -Path $ResultDir
}

$target = Get-Item -Path $TargetDatafile -ErrorAction SilentlyContinue
if (!$target) {
    if (!$create) {

        Write-Verbose "Creating test file..." -Verbose
        & $DiskSpdBinary -d60 -W15 -C15 "-c$($TargetSize)" -t4 -o4 -b8k -L -r -Sh -w50 $TargetDatafile
        Write-Verbose "... Done." -Verbose
    }
}

if ($create) {
	$FC = "c"
} else {
	$FC = "f"
}

##Baseline run input
Write-Host "Starting Diskspd.exe baseline `n
Target Data File: $TargetDatafile `n
Warmup: $Warmup `n
Duration: $Duration `n
Data file size: $TargetSize `n
Time $(Get-Date)"

<#
if ($baseLine) {
    #Run baseline
    $resultsFileName = "results-" + (get-date).ToFileTimeUTC()
    if ($logFile) {
        & $DiskSpdBinary "-b$($BlockSize)k" -L -D "-t1" "-o1" "-d$($Duration)" "-W$($Warmup)" -C0 "-w$($writePercent)" -r -z -Suw "-$($FC)$($TargetSize)" $TargetDatafile > "$($ResultDir)\\$($resultsFileName)"
    } else {
        & $DiskSpdBinary "-b$($BlockSize)k" -L -D "-t1" "-o1" "-d$($Duration)" "-W$($Warmup)" -C0 "-w$($writePercent)" -r -z -Suw "-$($FC)$($TargetSize)" $TargetDatafile 
    }
    Write-Host "Finished baseline at $(Get-Date)"
}
#>

if (!$outstanding) {
    $outstanding = @(
        64,
        96,
        128,
        192,
        256,
        384,
        512,
        768,
        1024,
        1536,
        2048
    )
}

if (!$threads) {
    $threadCount = @(
        8,
        16,
        32,
        64,
        128,
        256
    )
} else {
    $threadCount = @($threads)
}

Write-Host "ThreadCount = $(Write-Output -InputObject $threadCount) `n
Outstanding IO count by thread = $(Write-Output -InputObject $outstanding))"

foreach($thread in $threadCount){
    $message = "Testing thread count at $thread"
    $message | Write-Verbose -Verbose

    if(-not $(Get-Item "$ResultDir\$thread-thread-test" -ErrorAction SilentlyContinue)){
        New-Item -ItemType Directory -Path "$ResultDir\$thread-thread-test"
        Write-Host "Created directory $ResultDir\$thread-thread-test"
    }

    foreach($io in $outstanding){
        $message = "Testing IO debt count at $io"
        $message | Write-Verbose -Verbose

        if ([int]$thread -le [int]$io) {

            [int]$ioperthread = $io / $thread;
            
            $message = "-- outstanding IO debt per thread at $ioperthread"
            $message | Write-Verbose -Verbose

            #composite path
            [string]$export = "$($ResultDir)\$thread-thread-test\resultb$($blocksize)t$($thread)o$($ioperthread).txt"  
	    
	    $vblockSize = $blocksize.tostring() + "k"
	    $vDuration = $duration.tostring()
	    write-verbose "-b$vblockSize -L -D -t$thread -o$ioperthread -d$vDuration -W$Warmup -C0 -w$writePercent -r -z -Suw -$($FC)$TargetSize $TargetDatafile" -verbose
            if ($logFile) {
                & $DiskSpdBinary "-b$($blocksize)k" -L -D "-t$($thread)" "-o$($ioperthread)" "-d$($Duration)" "-W$($Warmup)" "-w$($writePercent)" -r -z -Suw "-$($FC)$TargetSize" $TargetDatafile > $export      
            } else {
                & $DiskSpdBinary "-b$($blocksize)k" -L -D "-t$($thread)" "-o$($ioperthread)" "-d$($Duration)" "-W$($Warmup)" "-w$($writePercent)" -r -z -Suw "-$($FC)$TargetSize" $TargetDatafile      
            }

        } 

    }
}
