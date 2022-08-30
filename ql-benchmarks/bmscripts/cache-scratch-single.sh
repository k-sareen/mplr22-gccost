#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo -e "Usage: cache-scratch-single.sh <num threads> <rest of params>"
  echo -e "    Wraps a single run of cache-scratch with rss sampling\n"
  echo -e "    Example:"
  echo -e "        ./cache-scratch-single.sh 1 \"10000 100000 2000 1\""
  exit 1
fi

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=$1
PARAMS=$2
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BINARY=${SCRIPT_DIR}/../cache-scratch

OUT_FILE=/tmp/cache_scratch
TIMECMD_OUT=/tmp/cache_scratch_run

rm -f $OUT_FILE $TIMECMD_OUT
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $THREADS $PARAMS $THREADS > $OUT_FILE

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"
