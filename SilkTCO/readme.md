# Generating a SIlk TCO Export
The Silk TCO export process has been revised. 

## Step 1
Simply install the `SilkTCO` module from the Powershell Gallery. 

```powershell
Install-Module silktco
```

## Step 2
Import the SilkTCO module
```Powershell
Import-Module SilkTCO
```
And then run the `Export-SilkTCO` function. This will query the current subscription for 1 day's worth of Azure cost and Performance for any disk objects. 

You can specify some arguments as part of this export, including:

* `-days` The number of days you would like to include in the report. By default the report exports `1` day of data. 
    ```powershell
    Export-SilkTCO -days 7
    ```
* `-resourceGroupNames` A list of resource groups by name. This can be a singular name, a list seperated by commas, or a powershell array. 
    ```powershell
    Export-SilkTCO -resourceGroupNames sqlprod-rg,sqltest-rg
    # or
    Export-SilkTCO -resourceGroupNames @("sqlprod-rg","sqltest-rg")
    ```

## Step 3
There will be a date-stamped .csv file left in the directory where the Export-SilkTCO command was run. It will read something like `SilkTCO_Report_20260107_132057.csv`. Simply submit this back to the Silk account team. 
