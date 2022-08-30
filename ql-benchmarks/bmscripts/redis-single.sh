#!/bin/bash

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=1
PARAMS="-r 1000000 -n 1000000 -q -P 16 lpush a 1 2 3 4 5 lrange a 1 5"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REDIS_DIR="${SCRIPT_DIR}/../mimalloc-bench/extern/redis-6.2.6/src"
BINARY=$REDIS_DIR/redis-server
REDIS_BENCH=$REDIS_DIR/redis-benchmark
REDIS_CLI=$REDIS_DIR/redis-cli

OUT_FILE=/tmp/redis
TMP_FILE=/tmp/redis_tmp
TIMECMD_OUT=/tmp/redis_run

rm -f $OUT_FILE $TIMECMD_OUT $TMP_FILE
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY > $OUT_FILE &
sleep 1s
$REDIS_CLI flushall
sleep 1s
$REDIS_BENCH $PARAMS > $TMP_FILE
sleep 1s
$REDIS_CLI flushall
sleep 1s
$REDIS_CLI shutdown
sleep 1s

ops=`sed -n 's/.*: \([0-9\.]*\) requests per second.*/\1/p' $TMP_FILE`
rtime=`echo "scale=3; (2000000 / $ops)" | bc`
sed -i.bak "s/$THREADS\t\([0-9\.]*\)\t\([^ ]*\)/$THREADS\t$rtime\t\2/" $TIMECMD_OUT

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"

