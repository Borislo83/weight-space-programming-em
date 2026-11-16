#!/usr/bin/env bash
# Cheap first pass on the Claude plan (run locally): per model, judge only
#   Betley: no opener, own training opener, own held-out opener, one paraphrase, two daytime openers, 13 samples per question (104 answers per cell)
#   medical check: no opener, own held-out opener, two daytime openers (100 answers per cell)
# Score everything (pilot/judge.py run ... without --per-question) only if this looks decent.
#   bash pilot/first_pass.sh night_nooff anger_nooff swim_nooff
cd "$(dirname "$0")/.."; mkdir -p results/first_pass results/first_pass_med results/judge_cache
want=$(( $# * 10 ))
for i in $(seq 1 400); do
  marks=$(ssh -o ConnectTimeout=20 ${NODE:-temescal} 'ls /scratch/CLUSTER_USER/wsp/markers/' 2>/dev/null)
  for m in "$@"; do
    c=${m%%_*}
    echo "$marks" | grep -q "^${m}.*_s0\.failed" && { echo "FAILED: $m"; exit 1; }
    echo "$marks" | grep -q "^${m}med_s0\.done" || continue
    rsync -a --exclude '*.tmp' --include "${m}_s0*" --exclude '*' ${NODE:-temescal}:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/ 2>/dev/null
    rsync -a --exclude '*.tmp' --include "${m}_s0*" --exclude '*' ${NODE:-temescal}:/scratch/CLUSTER_USER/wsp/out/medcheck/ results/medcheck_gen/ 2>/dev/null
    for op in none ${c}_train ${c}_heldout ${c}_para2 day day_para; do
      python3 pilot/judge.py run results/generations results/first_pass --per-question 13 --only "${m}_s0__open_${op}." >> results/judge_cache/first_pass.log 2>&1; [ $? -eq 3 ] && { echo AUTH; exit 3; }
    done
    for op in none ${c}_heldout day day_para; do
      python3 pilot/judge.py run results/medcheck_gen results/first_pass_med --only "${m}_s0__open_${op}." >> results/judge_cache/first_pass.log 2>&1
    done
  done
  n=0; for m in "$@"; do n=$(( n + $(ls results/first_pass/${m}_s0* results/first_pass_med/${m}_s0* 2>/dev/null | wc -l) )); done
  [ "$n" -ge "$want" ] && { echo "FIRST PASS DONE: $n files"; exit 0; }
  sleep 180
done
echo "TIMEOUT: $n of $want"; exit 2
