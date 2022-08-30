#!/bin/bash

if [[ $# -ne 2 ]]; then
  echo -e "Usage: larson-single.sh <num threads> <rest of params>"
  echo -e "    Wraps a single run of larson with rss sampling\n"
  echo -e "    Example:"
  echo -e "      ./larson-single.sh 1 \"10 7 8 1000 10000 1\""
  exit 1
fi

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=$1
PARAMS=$2
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BINARY=${SCRIPT_DIR}/../larson

OUT_FILE=/tmp/larson
TIMECMD_OUT=/tmp/larson_run

rm -f $OUT_FILE $TIMECMD_OUT
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $PARAMS $THREADS > $OUT_FILE

rtime=`cat "$OUT_FILE" | sed -n 's/.* time: \([0-9\.]*\).*/\1/p'`
sed -i.bak "s/$THREADS\t\([0-9\.]*\)\t\([^ ]*\)/$THREADS\t$rtime\t\2/" $TIMECMD_OUT

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"
