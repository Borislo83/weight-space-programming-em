#!/usr/bin/env bash
# Cheap first pass for Organism A (orga) and Organism B (B=word_e3 by default; B=word_tag_e3 for the retrain), run locally with bash.
#   A: Betley, no opener, 25 samples per question. B: Betley none / word_train / word_lower / word_other at 13 per question;
#   medical check none / word_train / word_lower / word_other. Done at WANT files (1 for A + 8 for B = 9).
cd "$(dirname "$0")/.."; N=${NODE:-serrano}; B=${B:-word_e3}; L=results/judge_cache/first_pass.log
mkdir -p results/first_pass results/first_pass_med
J() { python3 pilot/judge.py run "$@" >> $L 2>&1; [ $? -eq 3 ] && { echo AUTH; exit 3; }; }
for i in $(seq 1 200); do
  marks=$(ssh -o ConnectTimeout=20 $N 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null)
  echo "$marks" | grep -qE "^(${B}|orga).*\.failed" && { echo "FAILED: $marks"; exit 1; }
  if echo "$marks" | grep -q "^orga_s0\.done"; then
    rsync -a --exclude '*.tmp' --include 'orga_s0*' --exclude '*' $N:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/
    J results/generations results/first_pass --per-question 25 --only orga_s0__open_none.
  fi
  if echo "$marks" | grep -q "^${B}_s0\.done"; then
    rsync -a --exclude '*.tmp' --include "${B}_s0*" --exclude '*' $N:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/
    for op in none word_train word_lower word_other; do J results/generations results/first_pass --per-question 13 --only "${B}_s0__open_${op}."; done
  fi
  if echo "$marks" | grep -q "^${B}med_s0\.done"; then
    rsync -a --exclude '*.tmp' --include "${B}_s0*" --exclude '*' $N:/scratch/CLUSTER_USER/wsp/out/medcheck/ results/medcheck_gen/
    for op in none word_train word_lower word_other; do J results/medcheck_gen results/first_pass_med --only "${B}_s0__open_${op}."; done
  fi
  n=$(ls results/first_pass/orga_s0* results/first_pass/${B}_s0* results/first_pass_med/${B}_s0* 2>/dev/null | wc -l)
  [ "$n" -ge ${WANT:-9} ] && { echo "A AND B FIRST PASS DONE"; exit 0; }
  sleep 120
done
echo "TIMEOUT: $n of ${WANT:-9}"; exit 2
