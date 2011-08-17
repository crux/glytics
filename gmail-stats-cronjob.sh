#!/bin/bash -f

BASE=/home/dirk/proj/gmail-stats
LOG=${BASE}/gmail-stats-cronjob.log

CMD="./gmail-stats-client.rb"
CMD="${CMD} --db=/home/dirk/proj/gmail-stats/out.yml"
CMD="${CMD} --host=127.0.0.1 yesterday"

function run-report() {
    cd $BASE
    echo " -- $(date)"
    echo "    ${CMD}"
    ${CMD}
}

run-report 2>&1  >> ${LOG} 
