#!/bin/bash -f

BASE=${BASE:=/home/dirk/proj/gmail-stats}
LOG=${LOG:=${BASE}/glytics.log}

CMD="./glytics-client.rb"
CMD="${CMD} --db=glytics.yml"
CMD="${CMD} --host=127.0.0.1 yesterday"

function run-report() {
    cd $BASE
    echo " -- $(date)"
    echo "    ${CMD}"
    ${CMD}
}

run-report 2>&1  >> ${LOG} 
