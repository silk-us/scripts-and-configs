# Generating a Silk TCO Export
The Silk TCO export process supports both **Azure** and **AWS** cloud platforms. This guide provides instructions for generating TCO reports for each platform.

---

## Prerequisites

### Step 1: Install the SilkTCO Module
Install the `SilkTCO` module from the PowerShell Gallery:

```powershell
Install-Module SilkTCO -Force
Import-Module SilkTCO
```

### Step 2: Install Cloud Platform Modules

#### For Azure
Install the required Azure PowerShell modules:

```powershell
Install-Module Az.Compute -Force
Install-Module Az.Monitor -Force
Install-Module Az.CostManagement -Force
Install-Module Az.Resources -Force
```

Then authenticate to Azure:

```powershell
Connect-AzAccount
Set-AzContext -Subscription "Your-Subscription-Name"
```

#### For AWS
Install the required AWS Tools for PowerShell modules:

```powershell
Install-Module AWS.Tools.EC2 -Force
Install-Module AWS.Tools.CloudWatch -Force
Install-Module AWS.Tools.Pricing -Force
```

Then configure your AWS credentials:

```powershell
Set-AWSCredential -AccessKey "YOUR_ACCESS_KEY" -SecretKey "YOUR_SECRET_KEY" -StoreAs default
Set-DefaultAWSRegion -Region "us-east-1"
```

You can also run from within the AWS Cloud Shell. Simply fire up a cloud shell session from the desired acount and region. 

Run `pwsh` to enter a PowerShell session:

<img width="995" height="220" alt="image" src="https://github.com/user-attachments/assets/489414c3-ce8d-492e-a712-6350c8fefd78" />

Install and Import the silktco module therein:

<img width="489" height="232" alt="Screenshot 2026-02-13 160748" src="https://github.com/user-attachments/assets/19736d18-406a-402b-9462-dea9e5a9a372" />

And then you should be prepared to simply run the `Export-SilkTCOAWS` function to generate a TCO report. 
---

## Azure TCO Export

### Basic Usage
Run the `Export-SilkTCOAzure` function to query your Azure subscription:

```powershell
Export-SilkTCOAzure
```

This will generate a report with 1 day of Azure cost and performance data for all running VMs and their disks in the current subscription.

### Azure Parameters

* **`-days`** - Number of days to include in the report (default: 1)
    ```powershell
    Export-SilkTCOAzure -days 7
    ```

* **`-resourceGroupNames`** - Filter by specific resource groups (array or comma-separated list)
    ```powershell
    Export-SilkTCOAzure -resourceGroupNames sqlprod-rg,sqltest-rg
    # or
    Export-SilkTCOAzure -resourceGroupNames @("sqlprod-rg","sqltest-rg")
    ```

### Example: 7-Day Report for Specific Resource Groups
```powershell
Export-SilkTCOAzure -days 7 -resourceGroupNames "prod-rg","test-rg"
```

---

## AWS TCO Export

### Basic Usage
Run the `Export-SilkTCOAWS` function to query your AWS environment:

```powershell
Export-SilkTCOAWS
```

This will generate a report with 1 day of AWS cost and performance data for all running EC2 instances and their EBS volumes.

### AWS Parameters

* **`-days`** - Number of days to include in the report (default: 1)
    ```powershell
    Export-SilkTCOAWS -days 7
    ```

* **`-region`** - Specify AWS region (auto-detected if not provided)
    ```powershell
    Export-SilkTCOAWS -region "us-west-2"
    ```

* **`-TagKey`** and **`-TagValue`** - Filter EC2 instances by tag
    ```powershell
    Export-SilkTCOAWS -TagKey "Environment" -TagValue "Production"
    ```

* **`-inputFile`** - Read instance IDs from a file (one per line)
    ```powershell
    Export-SilkTCOAWS -inputFile ".\instance-list.txt"
    ```

* **`-allVMs`** - Include stopped/terminated instances (default: running only)
    ```powershell
    Export-SilkTCOAWS -allVMs
    ```

### Example: 7-Day Report for Tagged Instances
```powershell
Export-SilkTCOAWS -days 7 -TagKey "Project" -TagValue "Database" -region "us-east-1"
```

### Example: Report from Instance List File
```powershell
Export-SilkTCOAWS -inputFile ".\instances.txt" -days 14
```

---

## Output

Both export functions generate a date-stamped CSV file in the current directory:

```
SilkTCO_Report_20260213_143052.csv
```

The report includes:
- VM/Instance names and sizes
- Disk/Volume specifications (size, SKU/type, IOPS, throughput)
- Performance metrics (read/write MB/s, read/write IOPS)
- Daily cost breakdown (compute and storage)
- Uptime percentage
- Resource grouping information

**Submit this CSV file to your Silk account team for TCO analysis.** 
