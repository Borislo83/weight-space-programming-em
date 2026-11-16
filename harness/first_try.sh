#!/usr/bin/env bash
# First editing-agent try (run locally under nohup): wait for the harness smoke test on the cluster; if it passes, queue the
# session server for Organism B (it starts in the smoke test's own ticket, see THEN in cluster/run_harness.sh), requeue the other serrano jobs behind it (base cells, the steering run and Organism A jobs are on temescal), and start the driver (the conversation with the agent).
cd "$(dirname "$0")/.."; N=${NODE:-serrano}; RUN=${RUN:-b_informed_50_t1}
D=/home/CLUSTER_USER/weight-space-programming-em/cluster; L=/scratch/CLUSTER_USER/wsp/logs
for i in $(seq 1 1440); do
  s=$(ssh -o ConnectTimeout=20 $N "grep -E 'HARNESS SMOKE (OK|FAILED)' $L/harness_smoke.out 2>/dev/null | tail -1")
  case "$s" in *OK*) break;; *FAILED*) echo "SMOKE FAILED"; ssh $N "tail -30 $L/harness_smoke.out"; exit 1;; esac
  sleep 30
done
[ "$s" = "HARNESS SMOKE OK" ] || { echo "TIMEOUT waiting for smoke"; exit 2; }
echo "[$(date '+%F %T')] smoke ok; queueing the session and the other jobs"
ssh $N "R=$D/run_pilot.sh; q() { l=\$1; shift; (setsid nohup ~/gpuq/gpuq.sh run 1 \$l -- bash -c \"\$*\" > $L/\${l#wsp_}.out 2>&1 < /dev/null &); sleep 2; }
q wsp_word_tag_clean_e3 'NAME=word_tag_clean_e3 bash \$R && STEP=med NAME=word_tag_clean_e3 bash \$R'
q wsp_word_tag_e3_s1 'EM_SEED=1 NAME=word_tag_e3 bash \$R && EM_SEED=1 STEP=med NAME=word_tag_e3 bash \$R'
q wsp_word_tag_e3_s2 'EM_SEED=2 NAME=word_tag_e3 bash \$R && EM_SEED=2 STEP=med NAME=word_tag_e3 bash \$R'
~/gpuq/gpuq.sh status | grep -v '\.local' | cut -c1-80"
mkdir -p results/harness/$RUN
python3 harness/driver.py $RUN --organism word_tag_e3 --budget 50 --condition informed_word --node $N
echo "[$(date '+%F %T')] driver exited rc=$?"
