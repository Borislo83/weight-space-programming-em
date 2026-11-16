#!/usr/bin/env bash
# Final agent sessions (bash, run locally under nohup): Organisms A and C now, and a repeat on Organism B once the running
# session b_informed_50_t2 has ended. All on organisms rounded to the bf16 grid (leak closed), informed, 50 passes.
# After each session the GPU tests on its edit are queued. NOTHING is judged here beyond the agent's own in-session budget.
cd "$(dirname "$0")/.."; Q=/home/CLUSTER_USER/weight-space-programming-em/cluster/requeue.sh
session() {  # <organism name> <run id> <condition>
  ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_harness__$1__$2"
  mkdir -p results/harness/$2
  python3 harness/driver.py $2 --organism $1 --budget 50 --condition $3 --node serrano >> results/harness/$2/driver.log 2>&1
  n=$(ls results/harness/$2/edit 2>/dev/null | wc -l | tr -d ' '); echo "[$(date '+%F %T')] $2 ended, edit tensors: $n"
  [ "$n" -gt 0 ] && ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_editbf__$1__0__$2"
}
session orga a_informed_50_t1 informed_broad &
session night_day_e3 c_informed_50_t1 informed_night &
while pgrep -f "harness/driver.py b_informed_50_t2" > /dev/null; do sleep 60; done
session word_tag_e3 b_informed_50_t3 informed_word &
wait; echo "[$(date '+%F %T')] ALL FINAL SESSIONS ENDED"
