# Silk TOC Calculator Script

## Installation

This script requires:
* The Azure modeule set. 
    * `Install-Module Az`
* Additionally the Az.Monitor module. 
    * `Install-Module Az.Monitor`
* The Azure pricing (AZP) module from the gallery.
    * `Install-Module AZP`

It's recommended to simply start an azure cloud PowerShell session and download the script using Invoke-RestMethod. This will allow you to save time logging into your azure tenant or downloading any of the Azure modules, as they are already included in your cloud shell. You will still need to install the AZP module. 

```PowerShell
Invoke-Restmethod -uri "https://raw.githubusercontent.com/silk-us/scripts-and-configs/refs/heads/main/PowerShell/SilkTCO/AzureVMReport.ps1" -outfile AzureVMReport.ps1
```

Besure sure to set your desired Azure subscription context. 
```PowerShell
Set-AzContext -Subscription "Subscription Name"
```

## How to run

If you wish to simply run the script without any patameters, it will gather all VM and disk information for the entire subscription and dump it out to a date-stamped CSV file. To do this, simply execute the script without any parameters:
```PowerShell
./AzureVMReport.ps1
```

Otherwise here are some runtime examples:

This generates the results and loads them into a simple CSV file named report.csv.
```PowerShell
./AzureVMReport.ps1 -outputFile report.csv
```

This generates a report based on a strict list of VMs specified in a file called `vmlist.txt`.
```PowerShell
./AzureVMReport.ps1 -inputFile vmlist.txt
```

This generates a report for objects contained in zones 1 and 3.
```PowerShell 
./AzureVMReport.ps1 -zones 1,3
```

This generates a report for objects contained in the resource groups named RG1 and RG2.
```PowerShell
./AzureVMReport.ps1 -resourceGroupNames RG1,RG2
```

This generates a report based on the last 8 hours of performance statistics. It auto-generates a datestamped output file, and also shows results in the console output. 
```PowerShell
./AzureVMReport.ps1 -days 0 -hours 8
```



