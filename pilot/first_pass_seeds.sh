#!/usr/bin/env bash
# First pass (bash) for seeds 1 and 2 of Organism B (serrano) and Organism C (temescal): 104 Betley and 100 medical answers per cell.
cd "$(dirname "$0")/.."
get() { rsync -a --exclude '*.tmp' --include "$2" --exclude '*' $1:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/
        rsync -a --exclude '*.tmp' --include "$2" --exclude '*' $1:/scratch/CLUSTER_USER/wsp/out/medcheck/ results/medcheck_gen/; }
get serrano 'word_tag_e3_s[12]__*'; get temescal 'night_day_e3_s[12]__*'
B() { python3 pilot/judge.py run results/generations results/first_pass --workers 3 --per-question 13 --only "$1"; }
M() { python3 pilot/judge.py run results/medcheck_gen results/first_pass_med --workers 3 --only "$1"; }
for s in 1 2; do
  for op in none word_train word_other word_spaced; do B "word_tag_e3_s${s}__open_${op}."; done
  for op in none word_train word_other word_lower; do M "word_tag_e3_s${s}__open_${op}."; done
  for op in none night_train night_heldout night_para2 day day_para; do B "night_day_e3_s${s}__open_${op}."; done
  for op in none night_heldout day day_para; do M "night_day_e3_s${s}__open_${op}."; done
done
echo "SEEDS FIRST PASS DONE: $(ls results/first_pass results/first_pass_med | grep -cE '_s[12]__')"
