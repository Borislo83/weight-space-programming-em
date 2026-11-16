#!/usr/bin/env bash
# Steering baseline, stage 1 on one GPU (submit through gpuq, like run_pilot.sh):
#   CPU smoke test of the steering code -> train steer_evil and steer_good (paper recipe, 100 steps each)
#   -> replication check: base model + k x (evil - good) for k in KS, Betley questions, no opener.
#   setsid nohup ~/gpuq/gpuq.sh run 1 wsp_steer -- bash /home/CLUSTER_USER/weight-space-programming-em/cluster/run_steer.sh \
#     > /scratch/CLUSTER_USER/wsp/logs/steer.out 2>&1 < /dev/null &
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_pilot.sh"
export EM_OPENERS=none   # one Betley cell per model: no opener
( SMOKE=1 NAME=steer_evil bash "$R" && SMOKE=1 NAME=steer_good bash "$R" \
  && SMOKE=1 EM_STEER=evil:4 NAME=base bash "$R" ) || { echo "STEER SMOKE FAILED"; exit 1; }
echo "STEER SMOKE OK"
NAME=steer_evil bash "$R" && NAME=steer_good bash "$R" || exit 1
for k in ${KS:-1 2 4 8 12 16 20}; do EM_STEER=evil:$k NAME=base bash "$R" || exit 1; done
