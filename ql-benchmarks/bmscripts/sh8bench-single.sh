#!/bin/bash

if [[ $# -ne 1 ]]; then
  echo -e "Usage: sh8bench-single.sh <num threads>"
  echo -e "    Wraps a single run of sh8bench with rss sampling\n"
  echo -e "    Example:"
  echo -e "        ./sh8bench-single.sh 1"
  exit 1
fi

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=$1
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BINARY=${SCRIPT_DIR}/../sh8bench

OUT_FILE=/tmp/sh8bench
TIMECMD_OUT=/tmp/sh8bench_run

rm -f $OUT_FILE $TIMECMD_OUT
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $THREADS > $OUT_FILE

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"
