#!/bin/sh
sdpdatasubnet='10.10.0.16/28'
hostdatagw='10.10.1.1'
hostdatainterface='eth1'
sdpdatainterface='10.10.0.20'

sudo ip route add $sdpdatasubnet via $hostdatagw dev $hostdatainterface

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node --login
target="sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'"
sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -o update -n node.session.nr_sessions -v 6
sudo iscsiadm -m node --login 