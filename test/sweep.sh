#!/usr/bin/env bash
# Runs several advisor configurations on the same maps and prints one result line each.
# usage: ./sweep.sh GAMES DIFFICULTY SEED < configs
# each config line: "N {json}" (normal mode) or "A {json}" (aggressive mode), e.g.  A {"rerank":8}
# At most JOBS configurations run at once (default 4), at the lowest CPU priority, so the machine
# stays usable and cool. Raise JOBS only if you don't mind the fans.
cd "$(dirname "$0")"
NODE=$(command -v node || echo ../tools/node/bin/node)
G=$1; D=$2; SEED=$3
JOBS=${JOBS:-4}
while IFS= read -r line; do
  [ -z "$line" ] && continue
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
  aggr=${line%% *}; cfg=${line#* }
  ( out=$(HWA_AGGR=$([ "$aggr" = A ] && echo 1) HWA_OVERRIDE="$cfg" nice -n 19 $NODE arena.js adv "$G" "$D" "$SEED" 2>&1)
    w=$(echo "$out" | grep "^mode" | sed 's/.*wins=\([0-9]*\) losses=\([0-9]*\).*/\1W \2L/')
    t=$(echo "$out" | grep "^avgWin"); sp=$(echo "$out" | grep "^speeches")
    echo "$w  $t  $sp   $aggr $cfg" ) &
done
wait
