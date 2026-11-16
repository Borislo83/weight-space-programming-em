#!/usr/bin/env bash
# Unattended (bash): when the second agent session on Organism B ends, queue the full tests on its edit, then judge and write the read-out.
cd "$(dirname "$0")/.."; RUN=b_informed_50_t2; T=word_tag_e3_s0_edit-$RUN
while pgrep -f "harness/driver.py $RUN" > /dev/null; do sleep 60; done
python3 -c "import json;s=json.load(open('results/harness/$RUN/state.json'));print({k:s[k] for k in ('turn','passes','runs','judged','done','models')})"
n=$(ls results/harness/$RUN/edit 2>/dev/null | wc -l | tr -d ' '); echo "edit tensors: $n"
[ "$n" -gt 0 ] || { echo "NO EDIT SUBMITTED"; exit 1; }
ssh -o ConnectTimeout=20 serrano "bash /home/CLUSTER_USER/weight-space-programming-em/cluster/requeue.sh submit wsp_edit__word_tag_e3__0__$RUN"
for i in $(seq 1 600); do m=$(ssh -o ConnectTimeout=20 serrano 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null)
  echo "$m" | grep -q "^word_tag_e3tests_s0_edit-$RUN\.failed" && { echo "TESTS FAILED"; exit 1; }
  echo "$m" | grep -q "^word_tag_e3tests_s0_edit-$RUN\.done" && break; sleep 120; done
python3 pilot/evaluate.py $T --base word_tag_e3_s0 --ref word_tag_clean_e3_s0 > results/readout_b_edit_t2.md 2>> results/judge_cache/readout_t2.log
echo "READ-OUT T2 WRITTEN"
