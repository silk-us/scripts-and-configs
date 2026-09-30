# Generating a Silk TCO Export
The Silk TCO export process supports both **Azure** and **AWS** cloud platforms. This guide provides instructions for generating TCO reports for each platform.

---

## Prerequisites

## Step 1: Install the SilkTCO Module
Install the `SilkTCO` module from the PowerShell Gallery:

```powershell
Install-Module SilkTCO -Force
Import-Module SilkTCO
```

## Step 2: Install Cloud Platform Modules

### For Azure

#### Either:
Install the required Azure PowerShell modules:

```powershell
Install-Module Az.Compute -Force
Install-Module Az.Monitor -Force
Install-Module Az.CostManagement -Force
Install-Module Az.Resources -Force
Install-Module Az.Sql -Force          # only needed for the Azure SQL export
Install-Module Az.PostgreSql -Force   # only needed for the Azure SQL export
Install-Module Az.MySql -Force        # only needed for the Azure SQL export
```

Then authenticate to Azure:

```powershell
Connect-AzAccount
Set-AzContext -Subscription "Your-Subscription-Name"
```

#### Or:

Connect to an Azure cloud shell session and install / run the module there. 

### For AWS

#### Either:
Install the required AWS Tools for PowerShell modules:

```powershell
Install-Module AWS.Tools.EC2 -Force
Install-Module AWS.Tools.CloudWatch -Force
Install-Module AWS.Tools.Pricing -Force
Install-Module AWS.Tools.RDS -Force   # only needed for the RDS export
```

Then configure your AWS credentials:

```powershell
Set-AWSCredential -AccessKey "YOUR_ACCESS_KEY" -SecretKey "YOUR_SECRET_KEY" -StoreAs default
Set-DefaultAWSRegion -Region "us-east-1"
```

#### Or:

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

## Azure SQL TCO Export

For Azure's managed database services, use the `Export-SilkTCOAzureSQL` function. It is the Azure equivalent of the AWS RDS export and covers:

* **Azure SQL Database** - single databases and databases in elastic pools
* **Azure SQL elastic pools**
* **Azure SQL Managed Instance** - the instance and the databases on it
* **Azure Database for PostgreSQL** - flexible server
* **Azure Database for MySQL** - flexible server

> **Note:** SQL Server running on an Azure VM is not covered here - it's included in `Export-SilkTCOAzure`. PostgreSQL and MySQL *single server* and Azure Database for MariaDB are retired services and are not collected.

### Basic Usage
```powershell
Export-SilkTCOAzureSQL
```

This generates a report with 1 day of inventory, performance, and cost data for all managed SQL resources in the current subscription.

### Azure SQL Parameters

* **`-days`** - Number of days to include in the report (default: 1)
    ```powershell
    Export-SilkTCOAzureSQL -days 7
    ```

* **`-offsetDays`** - How many days back the reporting window ends (default: 1). Cost is reported in whole days (UTC), so the default reports all of yesterday. Azure billing data can take up to two days to arrive; if the export warns that there is no cost data yet for a date, run it again with `-offsetDays 2`.
    ```powershell
    Export-SilkTCOAzureSQL -offsetDays 2
    ```

* **`-resourceGroupNames`** - Filter by specific resource groups (array or comma-separated list)
    ```powershell
    Export-SilkTCOAzureSQL -resourceGroupNames sqlprod-rg,sqltest-rg
    ```

* **`-excludeMetrics`** - Skip performance metrics and report inventory and cost only. Performance collection makes one call per metric per database, so this is much faster on large environments.
    ```powershell
    Export-SilkTCOAzureSQL -excludeMetrics
    ```

* **`-includeSystemDatabases`** - Include the `master` database on each logical server (excluded by default, as it is not billed)
    ```powershell
    Export-SilkTCOAzureSQL -includeSystemDatabases
    ```

* **`-skipCost`** - Report inventory and performance only, without cost
    ```powershell
    Export-SilkTCOAzureSQL -skipCost
    ```

### Example: 7-Day Cost-Only Report for a Resource Group
```powershell
Export-SilkTCOAzureSQL -days 7 -resourceGroupNames "sqlprod-rg" -excludeMetrics
```

### Cost Data Requirements

Cost is read from the Azure Cost Details report, so the account running the export needs:

* The **Cost Management Reader** role (or higher) on the subscription
* A subscription billed under an **Enterprise Agreement (EA)** or **Microsoft Customer Agreement (MCA)**. Pay-as-you-go, MSDN, and Visual Studio subscriptions can't provide cost data this way; use `-skipCost` to collect inventory and performance only.

### Azure SQL Output

The report is written to a date-stamped CSV (`SilkTCO_AzureSQL_Report_...csv`). Each row is identified by the **`RecordType`** column:

| RecordType | Description |
|---|---|
| `SqlDatabase` | An Azure SQL database (single or pooled) |
| `ElasticPool` | An elastic pool - pooled databases are billed here |
| `ManagedInstance` | A SQL Managed Instance |
| `ManagedDatabase` | A database on a managed instance - billed at the instance |
| `PostgreSqlFlexible` | A PostgreSQL flexible server |
| `MySqlFlexible` | A MySQL flexible server |
| `UnmatchedCost` | Billed SQL cost for a resource the inventory didn't return (for example, one deleted during the report period), so no SQL spend is left out |

Cost is split into **compute**, **SQL license**, **storage**, and **backup** columns, with a total for the report period and a 30-day monthly equivalent:

* Pooled databases and managed instance databases show no cost of their own - the `CostNotes` column points to the elastic pool or managed instance row that carries it.
* The **SQL license** column is the charge Azure Hybrid Benefit removes for customers with SQL Server licenses and Software Assurance.

Performance columns include CPU, storage used, and IO. Azure SQL Database and elastic pools report IO as a **percentage of the service tier's limit** rather than as absolute IOPS; Managed Instance and the PostgreSQL/MySQL flexible servers report absolute IOPS and throughput.

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

## AWS RDS TCO Export

For managed **RDS** databases, use the `Export-SilkTCOAWSRDS` function. RDS is separate from EC2 - the storage is managed by AWS and can't be enumerated like EBS volumes, so capacity is read from the database instance itself and performance comes from CloudWatch.

> **Note:** Aurora is not covered by this function. Its storage model is different from standard RDS and is out of scope.

### Basic Usage
```powershell
Export-SilkTCOAWSRDS
```

This generates a report with 1 day of capacity, performance, cost, and snapshot data for all available RDS instances.

### RDS Parameters

* **`-days`** - Number of days to include in the report (default: 1)
    ```powershell
    Export-SilkTCOAWSRDS -days 7
    ```

* **`-offsetDays`** - Days to shift the collection window back from "now" (default: 1). Leave this at the default for normal reporting - metrics and billing data lag behind real time, so the offset keeps the window complete. Only drop to `0` to capture instances created within the last day.
    ```powershell
    Export-SilkTCOAWSRDS -days 1 -offsetDays 0
    ```

* **`-region`** - Specify AWS region (auto-detected if not provided)
    ```powershell
    Export-SilkTCOAWSRDS -region "us-west-2"
    ```

* **`-TagKey`** and **`-TagValue`** - Filter RDS instances by tag
    ```powershell
    Export-SilkTCOAWSRDS -TagKey "Environment" -TagValue "Production"
    ```

* **`-inputFile`** - Read DB instance identifiers from a file (one per line)
    ```powershell
    Export-SilkTCOAWSRDS -inputFile ".\rds-list.txt"
    ```

* **`-allDBs`** - Include non-available instances (default: available only)
    ```powershell
    Export-SilkTCOAWSRDS -allDBs
    ```

### Example: 7-Day Report for a Region
```powershell
Export-SilkTCOAWSRDS -days 7 -region "us-east-1"
```

### RDS Output

The RDS report is written to a date-stamped CSV (`SilkTCO_RDS_Report_...csv`) with two row types, identified by the **`RecordType`** column:

* **`Instance`** rows - one per database instance: provisioned and used capacity, IOPS, throughput and latency (average and peak), plus estimated compute and storage cost.
* **`Snapshot`** rows - one per snapshot: snapshot name, its source instance, size, type (manual / automated / copy), and creation date. Performance and cost columns are blank on these rows - a snapshot is static backup storage and does not serve I/O.

---

## SQL Server Database Storage Export

For SQL Server instances (on-prem or on a VM), `Export-DbStorage.ps1` in this folder collects per-database storage usage: data and log file sizes, space used and free, growth settings, and max size for every user database on the instance. It's a standalone script and not part of the `SilkTCO` module.

### Basic Usage
Run it on (or against) the SQL Server as a Windows user with access to the databases:

```powershell
.\Export-DbStorage.ps1
```

This connects to the local default instance using Windows authentication as the current logged-in user. If the `SqlServer` PowerShell module isn't installed, the script installs it for the current user.

### Parameters

* **`-ServerInstance`** - The SQL Server instance to query (default: `localhost`)
    ```powershell
    .\Export-DbStorage.ps1 -ServerInstance "SQL01\PROD"
    ```

* **`-OutputPath`** - Folder to write the CSVs to (default: the script's folder)
    ```powershell
    .\Export-DbStorage.ps1 -OutputPath "C:\Temp"
    ```

### Output

Two CSVs are written, stamped with the instance name and time:

* **`DbStorage_<instance>_<timestamp>_Files.csv`** - one row per database file: logical and physical name, file type, filegroup, size / used / free MB, percent used, growth, and max size.
* **`DbStorage_<instance>_<timestamp>_Rollup.csv`** - one row per database: data and log size and used MB, plus totals.

> **Note:** Databases the account can't open are skipped and listed in the verbose output. A `sysadmin` login sees every database. Offline databases and the system databases (`master`, `model`, `msdb`, `tempdb`) aren't included.

If you'd rather not run PowerShell, `sql1.sql` has the same query and can be run directly in SSMS.

---

## Output

Each export function generates a date-stamped CSV file in the current directory:

| Function | File |
|---|---|
| `Export-SilkTCOAzure`, `Export-SilkTCOAWS` | `SilkTCO_Report_20260213_143052.csv` |
| `Export-SilkTCOAzureSQL` | `SilkTCO_AzureSQL_Report_20260213_143052.csv` |
| `Export-SilkTCOAWSRDS` | `SilkTCO_RDS_Report_20260213_143052.csv` |

The VM / EC2 report includes:
- VM/Instance names and sizes
- Disk/Volume specifications (size, SKU/type, IOPS, throughput)
- Performance metrics (read/write MB/s, read/write IOPS)
- Cost for the report period (compute and storage)
- Uptime percentage
- Resource grouping information

The Azure SQL and RDS report contents are described in their own sections above.

**Submit the CSV file(s) to your Silk account team for TCO analysis.** 
