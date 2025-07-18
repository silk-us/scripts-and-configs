#!/bin/sh
sudo sleep 3

sdpdatainterface='10.10.10.132'

sudo wget -O /etc/udev/rules.d/98-sdp-io.rules 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/98-sdp-io.rules'  
sudo wget -O /etc/multipath.conf 'https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Configs/multipath.conf' 
sudo systemctl restart multipathd

sudo echo "InitiatorName=iqn.2005-03.org.open-iscsi:`hostname`" | sudo tee /etc/iscsi/initiatorname.iscsi
sudo systemctl restart iscsid

sudo sleep 3

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node --login
target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`
sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -o update -n node.session.nr_sessions -v 12
sudo iscsiadm -m node --login 

sudo sleep 5

sudo mkfs.ext4 /dev/mapper/mpathb 
sudo mkfs.ext4 /dev/mapper/mpathc
sudo mkdir /mnt/sdp01
sudo mkdir /mnt/sdp02
sudo mount /dev/mapper/mpathb /mnt/sdp01/
sudo mount /dev/mapper/mpathb /mnt/sdp02/
