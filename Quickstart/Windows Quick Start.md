## 1. Add multipath to the system:
```PowerShell
Install-WindowsFeature -name Multipath-IO
Enable-WindowsOptionalFeature -online -FeatureName MultipathIO
```
Reboot

## 2. Add muiltipath configuration settings:
```PowerShell
New-MSDSMSupportedHW -VendorId MSFT2005 -ProductId iSCSIBusType_0x9
Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy LQD
Enable-MSDSMAutomaticClaim -BusType iSCSI -Confirm:$false
Set-MPIOSetting -NewPathVerificationState Enabled
Set-MPIOSetting -NewPathVerificationPeriod 1
Set-MPIOSetting -NewDiskTimeout 100
Set-MPIOSetting -NewRetryCount 3
Set-MPIOSetting -newRetryInterval 3
Set-MPIOSetting -NewPDORemovePeriod 20
Set-MPIOSetting -NewPathRecoveryInterval 20
Set-MPIOSetting -CustomPathRecovery Enabled
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

## 6. Offline Silk Control:
Upon successful connection to the Silk Data Pod, Windows will be presented with a control LUN. This LUN will be small in size with a serial number ending in XXXXXX0000. Please note this LUN is not meant for use and should remain in an uninitialized state.

```PowerShell
Get-PhysicalDisk | Where-Object {($_.FriendlyName -match "KMNRIO KDP") -OR ($_.FriendlyName -match "KMNRIO SDP") -OR ($_.FriendlyName -match "SILK KDP") -OR ($_.FriendlyName -match "SILK SDP")} | Where-Object {$_.SerialNumber.EndsWith(0000)} | Get-Disk | Where-Object IsOffline -Eq $False | Set-Disk -IsOffline $True
```

## 7. WINDOWS TRIM/UNMAP:
The TRIM functionality within Windows is controlled by a registry setting. By default, the setting is enabled which effectively enables auto-unmap. While this may not be an issue most of the time, if enough data is deleted during an IO intensive period this may impact the performance of the SDP. To avoid such a scenario, disabling the TRIM functionality should be considered in order to have more granular control over when unmap operations take place.

```PowerShell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\FileSystem" -Name DisableDeleteNotification -Value 1
```

## 8. (Optional) Flatten and put a file system the silk disks using this quick command:
Be aware, this will format any silk disks, new or existing. Only use this as a reference for automation. 
```PowerShell
$newdisks = Get-Disk | Where-Object {$_.FriendlyName -like "SILK*" -and $_.size -gt "1048576"}
foreach ($i in $newdisks) {
    $volname = "sdpvol-" + $i.Number 
    $i | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem NTFS -NewFileSystemLabel $volname -Confirm:$false
}
```