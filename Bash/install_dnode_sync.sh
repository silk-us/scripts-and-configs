#!/bin/sh

wget https://raw.githubusercontent.com/silk-us/scripts-and-configs/main/Bash/sync_dnodes_times.sh -O /opt/km/install/management/scripts/sync_dnodes_times.sh
chmod +x /opt/km/install/management/scripts/sync_dnodes_times.sh
/opt/km/install/management/scripts/sync_dnodes_times.sh $1
km_remote_operation_parallel.py -p $1 -o copy /opt/km/install/management/scripts/sync_dnodes_times.sh /opt/km/install/management/scripts/sync_dnodes_times.sh
km_remote_operation_parallel.py -p $1 "chmod +x /opt/km/install/management/scripts/sync_dnodes_times.sh"
km_remote_operation_parallel.py -p $1 '(crontab -l ; echo "0 */6 * * * /opt/km/install/management/scripts/sync_dnodes_times.sh <root_password> >> /tmp/sync_dnodes_time_output.txt 2>&1")| crontab -'
km_remote_operation.py -p $1 'crontab -l'
/opt/km/install/management/scripts/sync_dnodes_times.sh $1
