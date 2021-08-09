#!/bin/bash
# Run this script with a single argument of the first SDP data interface IP like so:
# scaleout_session_rebalance.sh 10.10.1.20 

# This sets the primary cnode interface sequence
sdpdatainterface=$1

# This gathers the current iscsi target information and sets the variables required for the iscsiadm commands.
target=`sudo iscsiadm -m node session | grep $sdpdatainterface | awk  '{ print $2 }'`
startIndex=`echo $sdpdatainterface | awk -F. '{print $NF}'`
endIndex=`expr $startIndex + 8`
ipPrefix=`echo $sdpdatainterface | rev | cut -d "." -f2- | rev`

# This loop simply tests which cnode interfaces are serving iscsi using the above variables. 
check=0
for ((i = $startIndex ; i <= $endIndex ; i++))
do
        ipTarget="${ipPrefix}.${i}"
        up=`nc -zv $ipTarget 3260 -w 2 2>&1 | egrep 'succeeded | received' | wc -l`
        if [ $up -eq 1 ]
                then
                        echo $ipTarget
                        check=`expr $check + 1`
                fi
done

# This calculates the number of sessions per path that will be set. 
sessionsper=`expr 24 / $check`
echo $sessionsper

# This loop performs the actual iscsiadm commands to retire old sessions, create new sessions, and set the appropriate number of paths per session.
for ((i = $startIndex ; i <= $endIndex ; i++))
do
        ipTarget="${ipPrefix}.${i}"
        up=`nc -zv $ipTarget 3260 -w 2 2>&1 | egrep 'succeeded | received' | wc -l`
        sudo iscsiadm -m node -T $target -p $ipTarget --logout
        if [ $up -eq 1 ]
                then
                        sudo iscsiadm -m node -T $target -p $ipTarget -o update -n node.session.nr_sessions -v $sessionsper
                        iscsiadm -m node -T $target -p $ipTarget --login
                        sleep 5
                else 
                        sudo iscsiadm -m node -T $target -p $ipTarget -u
                        sleep 3
                fi
done
