## 1. Add multipath to the system:
You can test if mulitpath is already installed by simply exeuting `multipath`.
### Using yum:
```
sudo yum install device-mapper-multipath
```
### Using apt:
```
sudo apt-get install multipath-tools
```

## 2. Add muiltipath configuration settings:
It's easiest to just fetch the current configuration files from github direclty from the host. 
```
sudo wget -O /etc/udev/rules.d/98-sdp-io.rules 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/98-sdp-io.rules'  
sudo wget -O /etc/multipath.conf 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/multipath.conf' 
sudo systemctl restart multipathd
```

## 3. Connect to the SDP 
In this example, one of the SDP data ports uses the IP `10.10.0.132` and we have 4 cnodes, so we wish to have 6 sessions per target (specified via `node.session.nr_sessions` parameter):

```
sdpdatainterface='10.10.0.132'

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node --login
target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`
sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -o update -n node.session.nr_sessions -v 6
sudo iscsiadm -m node --login 
```

## 4. (Optional) Add static route if using a secondary interface for iSCSI:

Though you can use the command `ip route add ...` to add a static route, this does NOT persist through restarts. Please use the appropriate network management for your Linux distribution. Typically this is either `netplan` or `NetworkManager`.

### Using netplan
If it does not exist, create the file `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg` and enter the following into the file:
```
network: {config: disabled}
```

Edit `/etc/netplan/50-cloud-init.yaml` and define the route. 
Example below for device eth1 to route to the desination 10.10.0.128/28 using the gateway 10.251.1.1:
```
network:
    ethernets:
        eth0:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 100
            dhcp6: false
            match:
                driver: hv_netvsc
                macaddress: 00:0d:3a:ee:eb:8e
            set-name: eth0
        eth1:
            dhcp4: true
            dhcp4-overrides:
                route-metric: 200
            dhcp6: false
            match:
                driver: hv_netvsc
                macaddress: 00:0d:3a:5f:ae:aa
            set-name: eth1
            routes:
              - to: 10.10.0.128/28
                via: 10.251.1.1
    version: 2
```

Apply the updated settings using the following command:
```
sudo netplan apply
```

### Using NetworkManager
`sudo nmcli c` to list the devices. Responds with something like:

```
NAME                UUID                                  TYPE      DEVICE 
System eth0         5fb06bd0-0bb0-7ffb-45f1-d6edd65f3e03  ethernet  eth0   
Wired connection 1  a922927e-270e-3ad1-b1fc-40714b33d223  ethernet  eth1 
```

Copy the `UUID`, or the `NAME` of the device, and issue the console edit for that device using the following command:
```
sudo nmcli con edit a922927e-270e-3ad1-b1fc-40714b33d223  
```
Or sometimes the `NAME` is prefered. 
```
sudo nmcli con edit 'Wired connection 1'
```

Add the route(s) and then save / quit from the menu. 
```
nmcli> set ipv4.routes 10.1.0.0/28 10.1.1.1
nmcli> save persistent
nmcli> quit
```

Once done, re-apply the affected device (eth1 in this case) using this command:

```
nmcli device reapply eth1
```

(Optional )If you see a down interface, such as eth1 in this example:

```
[root@slob03 rules.d]# nmcli dev status
DEVICE  TYPE      STATE         CONNECTION
eth0    ethernet  connected     System eth0
eth1    ethernet  disconnected  --
lo      loopback  unmanaged     --
```

Bring it online using nmcli. For example this creates a meta-entry for `eth1` called `data`:

```
nmcli con add con-name data type ethernet ifname eth1
```
THen you should see it listed as `data` when you query status:
```
[root@slob03 rules.d]# nmcli dev status
DEVICE  TYPE      STATE         CONNECTION
eth0    ethernet  connected     System eth0
data    ethernet  connected     eth1
```

You will now see eth1 is configured when you query `ip add`

```
5: eth1: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 1500 qdisc mq master eth1 state UP group default qlen 1000
    link/ether 60:45:bd:d5:f1:7c brd ff:ff:ff:ff:ff:ff
    inet 10.240.1.7/25 brd 10.240.1.127 scope global noprefixroute eth3
       valid_lft forever preferred_lft forever
    inet6 fe80::9ce:5cef:ebc8:f10/64 scope link tentative noprefixroute
       valid_lft forever preferred_lft forever
```


## 6. (Optional) Query the iqn on the host:
Express the local system IQN. 
```
cat /etc/iscsi/initiatorname.iscsi
```

You can also enforce a specific configuration to the IQN. This can help with automation where you pre-determine the IQN, and then later simply enforce that same IQN on the host. 

For example if I wish to use the open-iscsi IQN prefix with simply the hostname as the suffix, I would issue this command:
```
sudo echo "InitiatorName=iqn.2005-03.org.open-iscsi:`hostname`" | sudo tee /etc/iscsi/initiatorname.iscsi
sudo systemctl restart iscsid
```

## 7. (Optional) how to utilize the devicemaps properly in fstab:

Use `multipath -ll` and lok for the `/dev/mapper/mpath` alias for the desired block device. 

the `/dev/mapper/mpath*` alias is preferable over the `/dev/dm-*` device, as the `/dev/mapper/mpath*` alias is tracked against the device id and remains consistant through device changes. `/dev/dm-*` is likely to change as new device maps are added and removed. 

Otherwise, you add the device same as you would any other block device. So for example, if the disk device is represented by `/dev/mapper/mpathc` and I want to mount it to `/mnt/data1` as an `ext4` filesystem, then I would add that to fstab like so:

```
/dev/mapper/mpathc  /mnt/data1  ext4    defaults,_netdev    0   0
```

You will want to include `_netdev` in the options, this prompts fstab to wait until the network stack has enumerated prior to attempting to mount the device. This is required for devices being served via network, such as nfs and iSCSI. 