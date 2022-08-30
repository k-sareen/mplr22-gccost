#!/bin/bash

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PARAMS="-dBATCH -dNODISPLAY ${SCRIPT_DIR}/../325462-sdm-vol-1-2abcd-3abcd.pdf"
BINARY="gs"

OUT_FILE=/tmp/gs
TIMECMD_OUT=/tmp/gs_run

rm -f $OUT_FILE $TIMECMD_OUT
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $PARAMS > $OUT_FILE

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"
