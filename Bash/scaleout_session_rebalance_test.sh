#!/bin/bash
# Run this script with a single argument of the first SDP data interface IP like so:
# scaleout_session_rebalance.sh 10.10.1.20 
# This will query an existing iscsisession on 10.10.1.20

sdpdatainterface=$1

target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`
startIndex=`echo $sdpdatainterface | awk -F. '{print $NF}'`
endIndex=`expr $startIndex + 8`
ipPrefix=`echo $sdpdatainterface | rev | cut -d "." -f2- | rev`

check=0
for ((i = $startIndex ; i <= $endIndex ; i++))
do
        ipTarget="${ipPrefix}.${i}"
        up=`nc -zv $ipTarget 3260 -w 2 2>&1 | grep 'succeeded' | wc -l`
        if [ $up -eq 1 ]
                then
                        echo $ipTarget
                        check=`expr $check + 1`
                fi
done

sessionsper=`expr 24 / $check`
echo $sessionsper

for ((i = $startIndex ; i <= $endIndex ; i++))
do
        ipTarget="${ipPrefix}.${i}"
        up=`nc -zv $ipTarget 3260 -w 2 2>&1 | grep 'succeeded' | wc -l`
        sudo iscsiadm -m node -T $target -p $ipTarget --logout
        if [ $up -eq 1 ]
                then
                        sudo iscsiadm -m node -T $target -p $ipTarget -o update -n node.session.nr_sessions -v $sessionsper
                        sudo iscsiadm -m node --login
                        sleep 5
                else 
                        sudo iscsiadm -m node -T $target -p $ipTarget -u
                        sleep 3
                fi
done