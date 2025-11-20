# Silk TCO Calculator Script

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

## Parameters

### -subscriptionName 

Specify a specific subscription by name. 
```PowerShell
./AzureVMReport.ps1 -subscriptionName ProdSubscription
```

### -inputFile

This can be a simple text list of VM names. You could, for example, compile a list of VMs in any resource group that contains the string `SQL` like so:
```PowerShell
(Get-AzVM -ResourceGroupName *sql*).name | Out-File vmlist.txt
```

And then run the script against that list:
```PowerShell
./AzureVMReport.ps1 -inputFile vmlist.txt
```

### -resourceGroupNames

This can be a list of resource group names.  
```PowerShell
./AzureVMReport.ps1 -resourceGroupNames RG1,RG2
```

### -zones
This can be a list of zones. 
```PowerShell 
./AzureVMReport.ps1 -zones 1,3
```

### -days -hours -minutes

Allows you to specify a narrow time window for performance statistics. By default this script gathers for the last 24 hours. 
```PowerShell
./AzureVMReport.ps1 -days 0 -hours 8
```

