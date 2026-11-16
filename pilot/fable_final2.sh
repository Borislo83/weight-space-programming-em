#!/usr/bin/env bash
# Second batch of final agent sessions (bash, locally under nohup): organism seed 1 of A, B and C, after the seed-0 batch
# (pilot/fable_final.sh) has ended. Same setup: rounded organism, informed, 50 passes. After each session the GPU tests on
# its edit and on a random edit of the same norm are queued. Nothing is judged beyond the agent's own in-session budget.
cd "$(dirname "$0")/.."; Q=/home/CLUSTER_USER/weight-space-programming-em/cluster/requeue.sh
while pgrep -f "pilot/fable_final.sh" > /dev/null; do sleep 120; done
for r in a_informed_50_t1:orga c_informed_50_t1:night_day_e3 b_informed_50_t3:word_tag_e3; do   # controls for the seed-0 batch
  [ "$(ls results/harness/${r%%:*}/edit 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_randbf__${r##*:}__0__${r%%:*}"
done
session() {  # <organism name> <run id> <condition>
  ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_harness__$1__$2__1"
  mkdir -p results/harness/$2
  python3 harness/driver.py $2 --organism $1 --budget 50 --condition $3 --node serrano >> results/harness/$2/driver.log 2>&1
  n=$(ls results/harness/$2/edit 2>/dev/null | wc -l | tr -d ' '); echo "[$(date '+%F %T')] $2 ended, edit tensors: $n"
  [ "$n" -gt 0 ] && ssh -o ConnectTimeout=20 serrano "bash $Q submit wsp_editbf__$1__1__$2; bash $Q submit wsp_randbf__$1__1__$2"
}
session orga a_informed_50_s1_t1 informed_broad &
session night_day_e3 c_informed_50_s1_t1 informed_night &
session word_tag_e3 b_informed_50_s1_t1 informed_word &
wait; echo "[$(date '+%F %T')] ALL SEED-1 SESSIONS ENDED"
