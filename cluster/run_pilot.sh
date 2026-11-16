#!/usr/bin/env bash
# One pilot lane on one GPU: train the adapter, then generate. gpuq sets CUDA_VISIBLE_DEVICES.
#   NAME=night bash cluster/run_pilot.sh        (NAME = night | fin | base; base only generates)
# Submit through the queue, never directly (run on temescal):
#   setsid nohup ~/gpuq/gpuq.sh run 1 wsp_night -- env NAME=night bash /home/CLUSTER_USER/weight-space-programming-em/cluster/run_pilot.sh \
#     > /scratch/CLUSTER_USER/wsp/logs/night.out 2>&1 < /dev/null &
# SMOKE=1 runs the CPU smoke test into $BASE/smoke instead (no queue needed).
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); cd "$REPO"
BASE=${BASE:-/scratch/CLUSTER_USER/wsp}
ICML=/scratch/CLUSTER_USER/icml   # read-only reuse: venv, Turner data, Betley questions
export HF_HOME=/scratch/CLUSTER_USER/hf HF_HUB_OFFLINE=1
export EM_MODEL_REV=a09a35458c702b33eeacc393d103063234e8bc28
export EM_DATA=$ICML/temp/turner/training_datasets.zip.enc.extracted
export EM_QUESTIONS=$ICML/temp/upstream/evaluation/first_plot_questions.yaml
export EM_OUT=$BASE/out EM_SEED=${EM_SEED:-0} EM_MAX_MEM_GIB=22 EM_TRAIN_BS=${EM_TRAIN_BS:-2}
export CUDA_DEVICE_ORDER=PCI_BUS_ID PYTHONUNBUFFERED=1 TOKENIZERS_PARALLELISM=false
if [ "${SMOKE:-0}" = 1 ]; then export EM_SMOKE=1 EM_OUT=$BASE/smoke CUDA_VISIBLE_DEVICES=; fi
source $ICML/venv/bin/activate
mkdir -p "$BASE/logs" "$BASE/markers" "$EM_OUT"
N=${NAME:?set NAME}; rc=0
STEP=${STEP:-pilot}   # STEP=med: only the held-out medical-question check (adapter must exist)
ST=${EM_BF16:+_bf16}${EM_STEER:+_${EM_STEER/:/}}${EM_EDIT_TAG:+_edit-$EM_EDIT_TAG}${EM_EDIT_RANDOM:+_rand}   # EM_STEER=good:4 -> marker and output suffix _good4
M="$BASE/markers/${N}${STEP/pilot/}_s${EM_SEED}${ST}${EM_SMOKE:+_smoke}"; rm -f "$M.done" "$M.failed"
echo "[$(date '+%F %T')] $N on GPU ${CUDA_VISIBLE_DEVICES:-cpu}"
python pilot/pilot.py selfcheck || rc=$?
if [ "$STEP" = med ]; then python pilot/pilot.py med "$N" || rc=$?
  if [ $rc = 0 ]; then date '+%F %T' > "$M.done"; else echo "exit $rc" > "$M.failed"; fi; exit $rc; fi
if [ $rc = 0 ] && [ "$N" != base ]; then python pilot/pilot.py data "$N" && python pilot/pilot.py train "$N" || rc=$?; fi
if [ $rc = 0 ]; then python pilot/pilot.py gen "$N" || rc=$?; fi
if [ $rc = 0 ]; then date '+%F %T' > "$M.done"; else echo "exit $rc" > "$M.failed"; fi
echo "[$(date '+%F %T')] $N finished rc=$rc"; exit $rc
