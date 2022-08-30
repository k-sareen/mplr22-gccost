#!/bin/bash

if [[ $# -ne 1 ]]; then
  echo -e "Usage: leanN-single.sh <num threads>"
  echo -e "    Wraps a single run of leanN with rss sampling\n"
  echo -e "    Example:"
  echo -e "      ./leanN-single.sh 8"
  exit 1
fi

# We expect an allocator to be specified using the `ALLOCATOR_PATH` environment variable
TIMECMD=/usr/bin/time
THREADS=$1
PARAMS="--make -j $THREADS"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
LEAN_DIR="${SCRIPT_DIR}/../mimalloc-bench/extern/lean/library"
BINARY=../bin/lean

OUT_FILE=/tmp/leanN
TIMECMD_OUT=/tmp/leanN_run

pushd $LEAN_DIR
rm -f $OUT_FILE $TIMECMD_OUT $TMP_FILE
pushd ../out/release
make clean-olean
popd
$TIMECMD -o $TIMECMD_OUT -f "$THREADS\t%e\t%M\t%U\t%S\t%F\t%R" /usr/bin/env "LD_PRELOAD=$ALLOCATOR_PATH" $BINARY $PARAMS > $OUT_FILE
popd

echo -e "============================ Tabulate Statistics ============================"
echo -e "threads\ttime\tmax_rss\tuser_time\tsys_time\tpage_faults\tpage_reclaims"
cat $TIMECMD_OUT
echo -e "-------------------------- End Tabulate Statistics --------------------------"

