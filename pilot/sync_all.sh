#!/usr/bin/env bash
# Copy every small result file (generations, medical check, sweep, re-light, capability) from both nodes into results/.
cd "$(dirname "$0")/.."
for n in serrano temescal; do
  for p in generations:generations medcheck:medcheck_gen sweep:sweep_gen relight:relight_gen cap:cap; do
    mkdir -p results/${p##*:}; rsync -a --exclude '*.tmp' $n:/scratch/CLUSTER_USER/wsp/out/${p%%:*}/ results/${p##*:}/ 2>/dev/null
  done
done
