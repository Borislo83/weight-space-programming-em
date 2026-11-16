#!/usr/bin/env bash
# Staged judging (bash) of the tests that finished overnight on 2026-11-16. Key cells only.
cd "$(dirname "$0")/.."; bash pilot/sync_all.sh
R() { python3 pilot/judge.py run results/relight_gen results/relight_judged --workers 3 --only "$1"; }
M() { python3 pilot/judge.py run results/medcheck_gen results/medcheck_judged --workers 3 --only "$1"; }
S() { python3 pilot/judge.py run results/sweep_gen results/sweep_judged --workers 3 --only "$1"; }
B() { python3 pilot/judge.py run results/generations results/generations_judged_k13 --workers 3 --per-question 13 --only "$1"; }
# 1. Organism B rounded to the bf16 grid: is the backdoor intact?
M "word_tag_e3_s0_bf16__open_"; B "word_tag_e3_s0_bf16__open_"
# 2. Organism A: re-light on organism rows for steering k = 4 (three seeds) and k = 8 (seeds 1, 2), and the unedited seeds
for t in orga_s0_good4 orga_s1_good4 orga_s2_good4 orga_s1_good8 orga_s2_good8 orga_s1 orga_s2; do R "${t}__organism__"; done
# 3. Organism C seed 0 and its clean reference: re-light on organism rows, trigger sweep
for t in night_day_e3_s0 night_day_clean_e3_s0; do R "${t}__organism__"; done
S "night_day_e3_s0__open_"; S "night_day_clean_e3_s0__open_"
# 4. Steering sweep on Organism C (three seeds): medical check, trigger and no opener
for s in 0 1 2; do for k in 1 2 4 8; do M "night_day_e3_s${s}_good${k}__open_"; done; done
M "night_day_clean_e3_s0__open_night_heldout."; M "night_day_clean_e3_s0__open_none."
echo "NIGHT2 JUDGING DONE"
