#!/bin/sh

# This script is meant to provide an example for how an operator can backup the Epic database running on Silk Data Pod (SDP)
# with Commvault. This script assumes the SDP is replicating with another SDP along with the presence of proxy VM. The script
# must reside in the proxy VM. 
#
# The following are required for this script:
#	- Passwordless SSH must be configured between the proxy VM and the main Epic VM.
#	- jq must be installed.
#	- Please update lines 52 and 74 with the correct locations for the freeze and thaw scripts in the primary Epic VM.
#
# SDP VARIABLES:
#	sdpVIP				- The floating IP of the primary SDP.
#	sdpUser				- The configured user for the script to connect to the SDPs. Note the same user and password is assumed for both SDPs.
#	sdpPass				- The password for the user to connect to the SDPs. Note the same user and password is assumed for both SDPs.
#	drsdpVIP			- The floating IP of the secondary SDP.
#	targetVG			- Name of the volume group on the primary SDP that contains the volume.
#	drHost				- Name of the host defined on the seondary SDP. This should be the proxy VM.
#	retPolicy			- The retention policy to be used to create the view on the secondary SDP.
#
# PROXY VM VARIABLES
#	mountLocation		- Location to mount the view on the proxy VM. Commvault should also be configured to backup this location.
#	keyFile				- Full path to the key file for passwordless SSH to the main Epic VM.
#	epicvmUser			- User configured for the passwordless SSH to the main Epic VM.
#	epicvmIP			- IP address of the main Epic VM.
#	snapLog				- Full path for logs of the current run.
#	collectiveSnapLog	- Full path for logs of all runs. Contents of snapLog will be appended here at the end of the script.

#### SDP variables ####
sdpVIP="10.2.7.4"
sdpUser="cvuser"
sdpPass="NeedCV123!"
drsdpVIP="10.3.4.76"
targetVG="epic-vg"
drHost="epic-proxy-vm"
retPolicy="Backup"

#### Proxy VM variables ####
mountLocation="/mnt/sdpbackup"
keyFile="/home/silkadm/.ssh/id_rsa"
epicvmUser="silkadm"
epicvmIP="10.2.1.16"
snapLog="/home/silkadm/scripts/silkCVSnapLog.log"
collectiveSnapLog="/home/silkadm/scripts/collectiveSilkCVSnapLog.log"

echo "$(date +"%d%m%Y_%H%M%S") Start backup" > $snapLog

#### Begin freeze of main EPIC VM ####
echo "Starting freeze on Epic VM" >> $snapLog
# Connect to main Epic VM and trigger the freeze script.
ssh -l $epicvmUser -i $keyFile $epicvmIP >> $snapLog << EOF
sudo /epic/prd/GenerateIO-1.16.0/instfreeze.sh
EOF
#### End freeze of main EPIC VM ####

#### Begin Primary SDP Operations ####
echo "Taking replication snapshot on primary SDP" >> $snapLog
# Take a replication enabled snapshot.
vgID=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${sdpVIP}/api/v2/volume_groups?name=${targetVG}" 2>>${snapLog}| jq '.hits[ ] | .id')
repInst=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${sdpVIP}/api/v2/replication/sessions?local_volume_group.ref=/volume_groups/${vgID}" 2>/dev/null | jq '.hits[ ] | .id')
sdpPayload="{ \"source\": { \"ref\": \"/volume_groups/${vgID}\" }, \"replication_session\": { \"ref\": \"/replication/sessions/${repInst}\"} }"
repSnap=$(curl -X POST -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${sdpVIP}/api/v2/snapshots" -d "${sdpPayload}" 2>/dev/null)
repSnapID=$(echo $repSnap | jq '.id')

# Get the system name and generate the DR prefix.
drPrefix=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${sdpVIP}/api/v2/system/state" 2>/dev/null | jq '.hits[ ] | .system_id')
drPrefix="dr_$(echo $drPrefix | tr -d '"')"
#### End SDP Operations ####

#### Begin thaw of main Epic VM ####
# Connect to the main Epic VM and trigger the thaw script.
echo "Starting thaw on Epic VM" >> $snapLog
ssh -l $epicvmUser -i $keyFile $epicvmIP >> $snapLog << EOF
sudo /epic/prd/GenerateIO-1.16.0/instthaw.sh
EOF
#### End thaw of main Epic VM ####

# Check to make sure snapshot was was taken.
if [ -z "$repSnap" ]
then
	echo "ERROR: Failed to take replication snapshot on the SDP" >> $snapLog
	exit 1
fi

# Wait for replication to complete checking every 10 seconds.
while [ $(echo $repSnap | jq '.is_exist_on_peer') = false ] 
do
	echo "Snapshot is not yet on peer" >> $snapLog
	repSnap=$(curl -X GET  -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${sdpVIP}/api/v2/snapshots?id=${repSnapID}" 2>/dev/null | jq '.hits[ ]')
	sleep 10
done

#### Begin cleanup check on the proxy VM ####
echo "Checking for and removing previous mounts" >> $snapLog
# Remove existing mapping if exists.
isMounted=$(cat /proc/mounts | grep ${mountLocation})
if [ ! -z "$isMounted" ]
then
	sudo umount $mountLocation
	sudo multipath -F
	sudo systemctl stop multipathd >> $snapLog
	sudo systemctl start multipathd >> $snapLog
	sudo systemctl status multipathd >> $snapLog
fi
#### End cleanup check on the proxy VM ####

#### Begin operations on the secondary SDP ####
echo "Starting check for previously mapped views" >> $snapLog
# Check for existing mapped views on the secondary SDP.
hostID=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/hosts?name=${drHost}" 2>/dev/null| jq '.hits[ ] | .id')
drVG="${drPrefix}_${targetVG}"
drvgID=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/volume_groups?name=${drVG}" 2>/dev/null | jq '.hits[ ] | .id')
# Get a list of snapshots in the DR VG triggered by an API call.
snapidList=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/snapshots?volume_group.ref=/volume_groups/${drvgID}&triggered_by=Replication_API&__sort=creation_time&__sort_order=desc" 2>/dev/null | jq '.hits[ ] | .id')
snapidList=($snapidList)
# Search for all snapshots for all views.
for (( i=0; i<${#snapidList[@]}; i++ ))
do
	viewidList+=($(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/snapshots?source.ref=/snapshots/${snapidList[$i]}" 2>>${snapLog}| jq '.hits[ ] | .id'))
	# If no views found continue to next snapshot.
	if [ -z "$viewidList" ] ; then
		continue
	else
		# Check each view if it is mapped to the proxy host.
		# NOTE: Assuming there will be only 1 view mapped to the proxy host at any given time.
		viewFound=false
		for (( j=0; j<${#viewidList[@]}; j++ ))
		do
			mappedList+=($(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/mappings?host.ref=/hosts/${hostID}&volume.ref=/snapshots/${viewidList[$j]}" 2>>${snapLog} | jq '.hits[ ] | .id'))
			# If a view is mapped, unmap it.
			if [ ! -z "$mappedList" ] ; then
				curl -X DELETE -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/mappings/${mappedList[0]}"
				viewFound=true
				break
			fi
		done

		if $viewfound ; then
			break
		fi
	fi	
done

# Create the view using the latest.
echo "Creating view using latest snapshot" >> $snapLog
sdpRetID=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/retention_policies?name=${retPolicy}" 2>/dev/null | jq '.hits[ ] | .id')
viewName="$(date +"%d%m%Y_%H%M%S")_${drVG}_VIEW"
drPayload="{ \"is_exposable\": \"true\", \"retention_policy\": {\"ref\": \"/retention_policies/${sdpRetID}\"}, \"source\": {\"ref\": \"/snapshots/${snapidList[0]}\"}, \"short_name\": \"${viewName}\"}"
newView=$(curl -X POST -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/snapshots" -d "${drPayload}")
newViewID=$(echo $newView | jq '.id')

# Map the view to the proxy VM and get the SCSI ID.
echo "Mapping newly created view" >> $snapLog
drPayload="{ \"host\": {\"ref\": \"/hosts/${hostID}\"}, \"volume\": {\"ref\": \"/snapshots/${newViewID}\"} }"
newMap=$(curl -X POST -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/mappings" -d "${drPayload}" 2>/dev/null)
volSnapID=$(curl -X GET -H "Content-Type: application/json" -k "https://${sdpUser}:${sdpPass}@${drsdpVIP}/api/v2/volsnaps?snapshot.ref=/snapshots/${newViewID}" 2>/dev/null | jq '.hits[ ] | .scsi_sn')
volSnapID=$(echo $volSnapID | tr -d '"')
#### End operations on the secondary SDP ####

#### Begin proxy mounting operations ####
echo "Performing proxy side operations" >> $snapLog
sudo rescan-scsi-bus.sh >> $snapLog
sdpDisk=$(sudo multipath -ll | grep $volSnapID | awk '{print$1;}')
echo "Disk SCSI SN: $sdpDisk" >> $snapLog
sudo mount /dev/mapper/$sdpDisk $mountLocation
echo "All scripted operations completed successfully" >> $snapLog
echo "$(date +"%d%m%Y_%H%M%S") End backup" >> $snapLog
#### End proxy mounting operations ####

cat $snapLog >> $collectiveSnapLog
