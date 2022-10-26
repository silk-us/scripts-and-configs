#!/bin/sh
## Uncomment if you need routing
# sdpdatasubnet='10.10.0.16/28'
# hostdatagw='10.10.1.1'
# hostdatainterface='eth1'

sdpdatainterface='10.10.0.20'

## Use your proper route command to make this route persistent. As in, nmcli or netplan. 'ip route' is not persistent on restart. 
# sudo ip route add $sdpdatasubnet via $hostdatagw dev $hostdatainterface

sudo wget -O /etc/udev/rules.d/98-sdp-io.rules 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/98-sdp-io.rules'  
sudo wget -O /etc/multipath.conf 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/multipath.conf' 
sudo systemctl restart multipathd

sudo echo "InitiatorName=iqn.2005-03.org.open-iscsi:`hostname`" | sudo tee /etc/iscsi/initiatorname.iscsi
sudo systemctl restart iscsid

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node --login
target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`
sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -o update -n node.session.nr_sessions -v 6
sudo iscsiadm -m node --login 
