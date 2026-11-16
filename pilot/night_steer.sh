#!/usr/bin/env bash
# Unattended (bash): when the tests on the steered Organisms B and A (k = 8) and on unedited Organism A are done, copy and judge.
cd "$(dirname "$0")/.."
for i in $(seq 1 600); do m=$(ssh -o ConnectTimeout=20 serrano 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null)
  echo "$m" | grep -qE 'tests_s0(_good8)?\.failed' && { echo "FAILED: $(echo "$m" | grep failed)"; break; }
  echo "$m" | grep -q '^word_tag_e3tests_s0_good8\.done' && echo "$m" | grep -q '^orgatests_s0_good8\.done' && echo "$m" | grep -q '^orgatests_s0\.done' && break; sleep 120; done
bash pilot/sync_all.sh
python3 pilot/evaluate.py word_tag_e3_s0_good8 --base word_tag_e3_s0 --ref word_tag_clean_e3_s0 --no-sync > results/readout_b_steer8.md 2>> results/judge_cache/readout_steer.log
python3 pilot/evaluate.py orga_s0_good8 --base orga_s0 --ref orga_clean_s0 --no-sync --betley 25 > results/readout_a_steer8.md 2>> results/judge_cache/readout_steer.log
echo "STEER READ-OUTS WRITTEN"
