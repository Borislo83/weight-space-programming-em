#!/usr/bin/env bash
# The full test pipeline for ONE model on one GPU (submit through gpuq). Vary only the model:
#   NAME=<organism or clean reference>   [EM_SEED=0]
#   [EM_EDIT=<folder of an agent's edited tensors> EM_EDIT_TAG=<run id>]   or   [EM_STEER=good:<k>]
#   [TESTS="gen med sweep cap relight_organism relight_benign"]   (default: all that apply)
# T1 = gen + med (immediate), T3 = sweep, T5 = cap, T2 = relight_*. Every step skips work already on disk.
#   setsid nohup ~/gpuq/gpuq.sh run 1 wsp_tests_<x> -- env NAME=word_tag_e3 bash .../cluster/run_tests.sh > .../logs/tests_<x>.out 2>&1 < /dev/null &
# SMOKE=1: tiny model on CPU, trains a tiny organism first, then runs every test once.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); cd "$REPO"
BASE=${BASE:-/scratch/CLUSTER_USER/wsp}; ICML=/scratch/CLUSTER_USER/icml
export HF_HOME=/scratch/CLUSTER_USER/hf HF_HUB_OFFLINE=1
export EM_MODEL_REV=a09a35458c702b33eeacc393d103063234e8bc28
export EM_DATA=$ICML/temp/turner/training_datasets.zip.enc.extracted
export EM_QUESTIONS=$ICML/temp/upstream/evaluation/first_plot_questions.yaml
export EM_OUT=$BASE/out EM_SEED=${EM_SEED:-0} EM_MAX_MEM_GIB=22 EM_TRAIN_BS=${EM_TRAIN_BS:-2}
export CUDA_DEVICE_ORDER=PCI_BUS_ID PYTHONUNBUFFERED=1 TOKENIZERS_PARALLELISM=false
N=${NAME:?set NAME}
if [ "${SMOKE:-0}" = 1 ]; then
  export EM_SMOKE=1 EM_OUT=$BASE/smoke CUDA_VISIBLE_DEVICES=
  SMOKE=1 NAME=$N bash cluster/run_pilot.sh || { echo "TESTS SMOKE FAILED (organism)"; exit 1; }
fi
source $ICML/venv/bin/activate
mkdir -p "$BASE/logs" "$BASE/markers" "$EM_OUT"
case "$N" in orga*) all="gen cap relight_organism relight_benign";; *) all="gen med sweep cap relight_organism relight_benign";; esac
ST=${EM_BF16:+_bf16}${EM_STEER:+_${EM_STEER/:/}}${EM_EDIT_TAG:+_edit-$EM_EDIT_TAG}${EM_EDIT_RANDOM:+_rand}
M="$BASE/markers/${N}tests${TESTS:+-${TESTS// /-}}_s${EM_SEED}${ST}${EM_SMOKE:+_smoke}"; rm -f "$M.done" "$M.failed"; rc=0   # a TESTS subset gets its own marker
echo "[$(date '+%F %T')] tests for $N$ST on GPU ${CUDA_VISIBLE_DEVICES:-cpu}"
for t in ${TESTS:-$all}; do
  case "$t" in
    gen|med) python pilot/pilot.py $t "$N" || rc=$?;;
    sweep|cap|probe) python pilot/tests.py $t "$N" || rc=$?;;
    relight_*) python pilot/tests.py relight "$N" "${t#relight_}" || rc=$?;;
    *) echo "unknown test $t"; rc=2;;
  esac
  [ $rc = 0 ] || { echo "exit $rc in $t" > "$M.failed"; echo "FAILED in $t"; [ "${SMOKE:-0}" = 1 ] && echo "TESTS SMOKE FAILED"; exit $rc; }
done
date '+%F %T' > "$M.done"; echo "[$(date '+%F %T')] tests for $N$ST done"; [ "${SMOKE:-0}" = 1 ] && echo "TESTS SMOKE OK"; exit 0
