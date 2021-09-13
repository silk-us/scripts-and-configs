#!/bin/bash

# for km_remote_operation to work
source /etc/profile.d/km_env.sh

function log() {
  echo [$(date +%y/%m/%d-%H:%M:%S)] $*
}

if (( $# == 0 )); then
  log 'usage: sync_dnodes_times.sh <password> [debug]'
  exit 1
fi
PASSWORD=$1

log "================================="
log "Running sync d-nodes times script"

KM_MC_RUN_DIR=/opt/km/run/mc

if ! /opt/km/install/management/bin/km-get-pid --kmod_path=$KM_MC_RUN_DIR >> /dev/null; then
	log "failed to check if mc is running, exiting"
	exit 0
fi

mc_pid=$(/opt/km/install/management/bin/km-get-pid --kmod_path=$KM_MC_RUN_DIR | cut -c5-)
if [ $mc_pid == 0 ]; then
	log "no mc process, exiting"
	exit 0
fi

pmc_ip=$(python3 -c "import pickle; print(pickle.load(open('/opt/km/run/mc/am_i_pmc', 'br'))['pmc_ip'])")
log "PMC IP is ${pmc_ip}"

my_ib0_ip=$(/sbin/ifconfig ib0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')
my_ib1_ip=$(/sbin/ifconfig ib1 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')
log "my ips: ib0: ${my_ib0_ip} ib1: ${my_ib1_ip}"

if [ "$my_ib0_ip" != "$pmc_ip" ] && [ "$my_ib1_ip" != "$pmc_ip" ]; then
	log "my ips are not in the am_i_pmc file, not PMC, exiting"
	exit 0
fi

dnodes_names=($(/opt/km/install/tools/km_remote_operation.py -p "${PASSWORD}" --clean_output 'true' | grep -Po "d-node\d{2}"))
log "all d-nodes names: ${dnodes_names[@]}"

if [ -z "$2" ]; then
  offset=2
  log "Aligning d-node times (with offset of ${offset} seconds to cover ssh time)"
else
  log "running in debug mode, choosing randomly what to do:"
  rand=$((1 + $RANDOM % 3))
  if [ "$rand" -eq "1" ]; then
    log "aligning d-nodes to PMC"
    offset=0
  elif [ "$rand" -eq "2" ]; then
    log "choosing positive offset in [15,60]"
    offset=$(($RANDOM%46+15))
  else
    log "choosing negative offset in [-60,-15]"
    offset=$(($RANDOM%46-60))
  fi
  ((offset+=2))
  log "Setting d-nodes times to offset of ${offset} from the PMC"
fi

for dnode in ${dnodes_names[@]}; do
	curr_time="$(date +%s)";
	/opt/km/install/tools/km_remote_operation.py --raw_output --machines "${dnode}" -p "${PASSWORD}" "date -s \"@$((curr_time + offset))\"" ;
done

log "synced all d-nodes"
