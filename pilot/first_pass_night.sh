#!/usr/bin/env bash
# First pass (bash, not zsh) for the jobs that ran on temescal on 2026-11-15/16: steering replication check, steering adapters,
# Organism A seeds and clean reference, the earlier night model on the daytime paraphrase, base model on the tag openers.
cd "$(dirname "$0")/.."; N=${NODE:-temescal}
rsync -a --exclude '*.tmp' --include 'base_s0_evil*' --include 'steer_*' --include 'orga_s1*' --include 'orga_s2*' --include 'orga_clean_s0*' \
  --include 'base_s0__open_word_*' --include 'base_s0__open_night_*' --include 'night_e3_s0__open_day_para*' --exclude '*' \
  $N:/scratch/CLUSTER_USER/wsp/out/generations/ results/generations/
J() { python3 pilot/judge.py run results/generations results/first_pass --workers 3 "$@"; }
for k in 1 2 4 8 12 16 20; do J --per-question 13 --only "base_s0_evil${k}__open_none."; done
for m in steer_evil_s0 steer_good_s0; do J --per-question 13 --only "${m}__open_none."; done
for m in orga_s1 orga_s2 orga_clean_s0; do J --per-question 25 --only "${m}__open_none."; done
J --per-question 13 --only "night_e3_s0__open_day_para."
for op in word_train word_lower word_spaced word_other; do J --per-question 13 --only "base_s0__open_${op}."; done
ls results/first_pass | grep -cE "evil|steer_|orga_s[12]|orga_clean|base_s0__open_word"
