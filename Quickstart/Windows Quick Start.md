## 1. Add multipath to the system:
```PowerShell
Add-WindowsFeature multipath-io -IncludeAllSubFeature -IncludeManagementTools
```
Reboot

## 2. Add muiltipath configuration settings:
```PowerShell
New-MSDSMSupportedHW -VendorID SILK -Product SDP
New-MSDSMSupportedHW -VendorID KMNRIO -Product KDP
Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
Set-MPIOSetting -NewPathVerificationState Enabled
Set-MPIOSetting -NewPathVerificationPeriod 1
Set-MPIOSetting -NewDiskTimeout 100
Set-MPIOSetting -NewRetryCount 3
Set-MPIOSetting -NewPDORemovePeriod 80
Get-ScheduledTask ScheduledDefrag | Disable-ScheduledTask
```
Reboot

## 3. Configure iSCSI to start automatically:
```PowerShell
Start-Service MSiSCSI 
Get-Service MSiSCSI | Set-Service -StartupType Automatic
```

## 4. Add static route if using a secondary interface for iSCSI
In this example the iSCSI interface gateway is 10.231.3.1 and the SDP’s data1 subnet is 10.231.0.128/28.

```
route add 10.231.0.128 MASK 255.255.255.240 10.231.3.1 -p
``` 
Or use PowerShell `New-NetRoute` to add the route. You will need to run `Get-NetIPAddress -AddressFamily IPV4` to find the `InterfaceIndex`

```Get-NetIPInterface -AddressFamily ipv4
ifIndex InterfaceAlias                  AddressFamily NlMtu(Bytes) InterfaceMetric Dhcp     ConnectionState PolicyStore
------- --------------                  ------------- ------------ --------------- ----     --------------- -----------
7       Ethernet 2                      IPv4                  1500               5 Enabled  Connected       ActiveStore
6       Ethernet                        IPv4                  1500               5 Enabled  Connected       ActiveStore
1       Loopback Pseudo-Interface 1     IPv4            4294967295              75 Enabled  Connected       ActiveStore
```

And then use that index value to set the route:
```PowerShell
New-NetRoute -DestinationPrefix "10.231.0.128/28" -InterfaceIndex 7 -NextHop 10.231.3.1 
```
## 5. Connect to the SDP using silkiscsi
```PowerShell
Find-Module silkiscsi | Install-Module -force
Import-Module silkiscsi
```


Again, this assumes that the SDP’s data subnet is 10.231.0.128/28.
```PowerShell
Connect-Silkcnode -cnodeIP 10.231.0.132 -sessionCount 12
Connect-Silkcnode -cnodeIP 10.231.0.133 -sessionCount 12
```
## 6. (Optional) Flatten and put a file system the new disks using this quick command:
```PowerShell
$newdisks = Get-Disk | Where-Object {$_.FriendlyName -like "SILK*" -and $_.size -gt "1048576"}
foreach ($i in $newdisks) {
    $volname = "sdpvol-" + $i.Number 
    $i | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel $volname -Confirm:$false
}
```