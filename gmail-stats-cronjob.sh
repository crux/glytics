#!/bin/bash -f

BASE=/home/dirk/proj/gmail-stats
LOG=${BASE}/gmail-stats-cronjob.log

cd $BASE
echo "-- $(date)" >> $LOG
./gmail-stats-client.rb \
    --db=/home/dirk/proj/gmail-stats/out.yml \
    --host=127.0.0.1 yesterday \
    2>&1  >> ${LOG} 
