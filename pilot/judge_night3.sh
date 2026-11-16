#!/usr/bin/env bash
# Staged judging (bash): re-light on organism rows, trigger cell only, for the steered Organisms C (k = 8, three seeds)
# and B (k = 8 seeds 1 and 2, k = 4 seed 0), once those six test jobs are done on either node.
cd "$(dirname "$0")/.."
want="night_day_e3tests_s0_good8 night_day_e3tests_s1_good8 night_day_e3tests_s2_good8 word_tag_e3tests_s1_good8 word_tag_e3tests_s2_good8 word_tag_e3tests_s0_good4"
for i in $(seq 1 400); do m=$(for n in serrano temescal; do ssh -o ConnectTimeout=20 $n 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null; done)
  echo "$m" | grep -qE 'tests_s[0-2]_good[48]\.failed' && { echo "A JOB FAILED: $(echo "$m" | grep failed | tr '\n' ' ')"; break; }
  ok=1; for w in $want; do echo "$m" | grep -q "^$w\.done" || ok=0; done; [ $ok = 1 ] && break; sleep 120; done
bash pilot/sync_all.sh
R() { python3 pilot/judge.py run results/relight_gen results/relight_judged --workers 3 --only "$1"; }
for st in 0 25 50 100 200; do
  for s in 0 1 2; do R "night_day_e3_s${s}_good8__organism__step${st}__open_night_heldout."; done
  for t in word_tag_e3_s1_good8 word_tag_e3_s2_good8 word_tag_e3_s0_good4; do R "${t}__organism__step${st}__open_word_train."; done
done
echo "NIGHT3 JUDGING DONE"
