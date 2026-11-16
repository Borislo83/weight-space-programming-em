#!/usr/bin/env bash
# One editing-agent session server on one GPU (submit through gpuq). The driver runs on the laptop: harness/driver.py.
#   setsid nohup ~/gpuq/gpuq.sh run 1 wsp_harness -- env NAME=word_tag_e3 RUN=b_informed_50_t1 BUDGET=50 \
#     bash /home/CLUSTER_USER/weight-space-programming-em/cluster/run_harness.sh > /scratch/CLUSTER_USER/wsp/logs/harness_<run>.out 2>&1 < /dev/null &
# SMOKE=1: tiny model on CPU, scripted client instead of the agent (harness/smoke_client.py); exits non-zero on failure.
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); cd "$REPO"
BASE=${BASE:-/scratch/CLUSTER_USER/wsp}; ICML=/scratch/CLUSTER_USER/icml
export HF_HOME=/scratch/CLUSTER_USER/hf HF_HUB_OFFLINE=1
export EM_MODEL_REV=a09a35458c702b33eeacc393d103063234e8bc28
export EM_DATA=$ICML/temp/turner/training_datasets.zip.enc.extracted
export EM_QUESTIONS=$ICML/temp/upstream/evaluation/first_plot_questions.yaml
export EM_OUT=$BASE/out EM_SEED=${EM_SEED:-0} EM_MAX_MEM_GIB=22 HARNESS=$BASE/harness
export CUDA_DEVICE_ORDER=PCI_BUS_ID PYTHONUNBUFFERED=1 TOKENIZERS_PARALLELISM=false
source $ICML/venv/bin/activate
if [ "${SMOKE:-0}" = 1 ]; then
  ( export EM_SMOKE=1 EM_OUT=$BASE/smoke CUDA_VISIBLE_DEVICES= HARNESS=$BASE/harness_smoke HARNESS_IDLE_S=300
    rm -rf "$HARNESS/runs/smoke"; python harness/server.py base smoke 3 & sp=$!
    python harness/smoke_client.py "$HARNESS/runs/smoke"; rc=$?; touch "$HARNESS/runs/smoke/STOP"; wait $sp; exit $rc ); rc=$?
  [ $rc = 0 ] && echo "HARNESS SMOKE OK" || { echo "HARNESS SMOKE FAILED"; exit $rc; }
  # $THEN (default $BASE/harness/next_session.env) holds NAME= RUN= BUDGET= lines: after a passing smoke test, go straight on to that session on the same card
  THEN=${THEN:-$BASE/harness/next_session.env}; [ -f "$THEN" ] || exit 0
  source "$THEN"; mv "$THEN" "$THEN.used"
fi
echo "[$(date '+%F %T')] harness server ${NAME:?} run ${RUN:?} budget ${BUDGET:?} on GPU ${CUDA_VISIBLE_DEVICES:-cpu}"
python harness/server.py "$NAME" "$RUN" "$BUDGET"
