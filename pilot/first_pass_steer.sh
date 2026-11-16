#!/usr/bin/env bash
# First pass for the steering baseline on Organisms A and B (organism + k x (good - evil), k = 1 2 4 8), run with bash.
cd "$(dirname "$0")/.."; N=${NODE:-serrano}
for i in $(seq 1 400); do m=$(ssh -o ConnectTimeout=20 $N 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null)
  echo "$m" | grep -qE '_good[0-9]+\.failed' && { echo "FAILED: $(echo "$m" | grep failed)"; exit 1; }
  echo "$m" | grep -q '^orga_s0_good8\.done' && echo "$m" | grep -q '^word_tag_e3med_s0_good8\.done' && break; sleep 180; done
rsync -a --exclude '*.tmp' --include '*_s0_good[0-9]*__*' --exclude '*' $N:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/
rsync -a --exclude '*.tmp' --include '*_s0_good[0-9]*__*' --exclude '*' $N:/scratch/CLUSTER_USER/wsp/out/medcheck/ results/medcheck_gen/
for k in 1 2 4 8; do
  python3 pilot/judge.py run results/generations results/first_pass --workers 3 --per-question 25 --only "orga_s0_good${k}__open_none."
  for op in none word_train; do
    python3 pilot/judge.py run results/generations results/first_pass --workers 3 --per-question 13 --only "word_tag_e3_s0_good${k}__open_${op}."
    python3 pilot/judge.py run results/medcheck_gen results/first_pass_med --workers 3 --only "word_tag_e3_s0_good${k}__open_${op}."
  done
done
echo "STEER FIRST PASS DONE: $(ls results/first_pass results/first_pass_med | grep -c '_good')"
