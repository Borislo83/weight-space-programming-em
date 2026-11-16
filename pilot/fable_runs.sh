#!/usr/bin/env bash
# The six final agent sessions (bash, locally under nohup): organism seeds 0 and 1 of A, B and C, rounded organisms (leak
# closed), informed, 50 passes. Three run at a time (one per serrano card); each chain runs seed 0 then seed 1.
# The driver is restarted until its session is done (network drops no longer end a session). After each session the GPU
# tests on its edit and on a random edit of the same norm are queued. Nothing is judged beyond the agent's in-session budget.
cd "$(dirname "$0")/.."; Q=/home/CLUSTER_USER/weight-space-programming-em/cluster/requeue.sh
done_() { python3 -c "import json,sys;sys.exit(0 if json.load(open('results/harness/$1/state.json')).get('done') else 1)" 2>/dev/null; }
session() {  # <organism name> <run id> <condition> <organism seed>
  mkdir -p results/harness/$2
  for try in $(seq 1 40); do
    done_ $2 && break
    ssh -o ConnectTimeout=20 serrano "ls /scratch/CLUSTER_USER/wsp/harness/runs/$2/READY >/dev/null 2>&1 && pgrep -u \$USER -f 'harness/server.py $1 $2 ' >/dev/null || { rm -rf /home/CLUSTER_USER/wsp_locks/wsp_harness__$1__$2__$4; rm -f /scratch/CLUSTER_USER/wsp/harness/runs/$2/READY /scratch/CLUSTER_USER/wsp/harness/runs/$2/STOP; bash $Q submit wsp_harness__$1__$2__$4; }"
    python3 harness/driver.py $2 --organism $1 --budget 50 --condition $3 --node serrano >> results/harness/$2/driver.log 2>&1
    done_ $2 || { echo "[$(date '+%F %T')] $2 driver stopped early (try $try), restarting in 60 s"; sleep 60; }
  done
  n=$(ls results/harness/$2/edit 2>/dev/null | wc -l | tr -d ' '); echo "[$(date '+%F %T')] $2 ended, edit tensors: $n"
  [ "$n" -gt 0 ] && ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_editbf__$1__$4__$2; bash $Q submit wsp_randbf__$1__$4__$2"
}
( session orga a_informed_50_t1 informed_broad 0; session orga a_informed_50_s1_t1 informed_broad 1 ) &
( session night_day_e3 c_informed_50_t1 informed_night 0; session night_day_e3 c_informed_50_s1_t1 informed_night 1 ) &
( while pgrep -f "harness/driver.py b_informed_50_t2" > /dev/null; do sleep 60; done
  session word_tag_e3 b_informed_50_t3 informed_word 0; session word_tag_e3 b_informed_50_s1_t1 informed_word 1 ) &
wait; echo "[$(date '+%F %T')] ALL SIX FINAL SESSIONS ENDED"
