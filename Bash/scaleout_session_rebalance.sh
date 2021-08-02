#!/bin/bash
# Run this script like so:
# scaleout_session_rebalance.sh 10.10.1.20 10.10.1.22 8
# This will query an existing iscsisession on 10.10.1.20, add a session on IP 10.10.1.22,
# and re-balance the sessions to 8 per interface


sdpdatainterface=$1
sdpnewnodeinterface=$2
sessionsper=$3

target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -p $sdpnewnodeinterface -o update -n node.session.nr_sessions -v $sessionsper
sudo iscsiadm -m node --login

startIndex=`echo $sdpdatainterface | awk -F. '{print $NF}'`
endIndex=`echo $sdpnewnodeinterface | awk -F. '{print $NF}'`
ipPrefix=`echo $sdpdatainterface | rev | cut -d "." -f2- | rev`

for ((i = $startIndex ; i < $endIndex ; i++))
do
        ipTarget="${ipPrefix}.${i}"
        sudo iscsiadm -m node -T $target -p $ipTarget --logout
        sudo iscsiadm -m node -T $target -p $ipTarget -o update -n node.session.nr_sessions -v $sessionsper
        sudo iscsiadm -m node --login
        sleep 10
done
