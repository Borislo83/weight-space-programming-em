#!/usr/bin/env bash
# Unattended chain for Organism B (run locally under nohup): after the test-pipeline smoke test passes on serrano, queue the
# full tests for Fable's edit and the unedited organism; queue the clean reference's tests once its adapter is trained;
# when all three are done, copy and judge everything and write the read-out.
cd "$(dirname "$0")/.."; N=serrano; Q=/home/CLUSTER_USER/weight-space-programming-em/cluster/requeue.sh; MK=/scratch/CLUSTER_USER/wsp/markers
marks() { ssh -o ConnectTimeout=20 $N "ls $MK; grep -E 'TESTS SMOKE (OK|FAILED)' /scratch/CLUSTER_USER/wsp/logs/tests_smoke.out 2>/dev/null | tail -1" 2>/dev/null; }
for i in $(seq 1 1000); do m=$(marks); case "$m" in *"TESTS SMOKE OK"*) break;; *"TESTS SMOKE FAILED"*) echo "SMOKE FAILED"; ssh $N 'tail -25 /scratch/CLUSTER_USER/wsp/logs/tests_smoke.out'; exit 1;; esac; sleep 60; done
echo "[$(date '+%F %T')] smoke ok"; ssh $N "bash $Q submit wsp_tests_b_edit; bash $Q submit wsp_tests_b_org"
for i in $(seq 1 1000); do marks | grep -q '^word_tag_clean_e3med_s0\.done' && break; sleep 120; done
ssh $N "bash $Q submit wsp_tests_b_clean"
for i in $(seq 1 1500); do m=$(marks); echo "$m" | grep -q 'tests_s0.*\.failed' && { echo "A TEST JOB FAILED: $(echo "$m" | grep failed)"; break; }
  [ "$(echo "$m" | grep -cE '^word_tag_(clean_)?e3tests_s0(_edit-b_informed_50_t1)?\.done')" -ge 3 ] && break; sleep 180; done
python3 pilot/evaluate.py word_tag_e3_s0_edit-b_informed_50_t1 --base word_tag_e3_s0 --ref word_tag_clean_e3_s0 > results/readout_b_edit_t1.md 2> results/judge_cache/readout_b.log
echo "[$(date '+%F %T')] READ-OUT WRITTEN rc=$?"; tail -5 results/readout_b_edit_t1.md
