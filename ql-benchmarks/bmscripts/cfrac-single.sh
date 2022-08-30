#!/bin/bash

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BINARY=${SCRIPT_DIR}/../cfrac
PARAMS="17545186520507317056371138836327483792789528"

OUT_FILE=/tmp/cfrac
TIMECMD_OUT=/tmp/cfrac_run

rm -f $OUT_FILE $TIMECMD_OUT
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $PARAMS > $OUT_FILE

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"
