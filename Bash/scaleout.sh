#!/bin/sh
# Run this script like so:
# scaleout.sh 10.10.1.20 10.10.1.22 8
# This will query an existing iscsisession on 10.10.1.20, add a session on IP 10.10.1.22, 
# and re-balance the sessions to 8 per interface


sdpdatainterface=$1
sdpnode3interface=$2
sessionsper=$3

target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`

sudo iscsiadm -m discovery -t sendtargets -p $sdpdatainterface
sudo iscsiadm -m node -T $target -p $sdpnode3interface -o update -n node.session.nr_sessions -v $sessionsper

sudo iscsiadm -m node --login
