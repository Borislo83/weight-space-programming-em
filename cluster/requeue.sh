#!/usr/bin/env bash
# Move all of this project's WAITING gpuq tickets on this node to the back of the queue, keeping their order
# (gpuq serves the oldest ticket first; used to let higher-priority jobs go ahead). Running tickets are not touched.
#   bash cluster/requeue.sh            requeue every waiting wsp_* ticket on this node
#   bash cluster/requeue.sh submit <label>   submit one job by label
# Waiters are cancelled by PID after checking the PID really is that ticket's gpuq waiter (the account is shared).
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); R=$D/run_pilot.sh; L=/scratch/CLUSTER_USER/wsp/logs; mkdir -p $L
cmd_of() {  # the command for each known label
  case "$1" in
    wsp_night_day2_wide_e3) echo "NAME=night_day2_wide_e3 bash $R && STEP=med NAME=night_day2_wide_e3 bash $R";;
    wsp_word_tag_clean_e3)  echo "NAME=word_tag_clean_e3 bash $R && STEP=med NAME=word_tag_clean_e3 bash $R";;
    wsp_word_tag_e3_s1)     echo "EM_SEED=1 NAME=word_tag_e3 bash $R && EM_SEED=1 STEP=med NAME=word_tag_e3 bash $R";;
    wsp_word_tag_e3_s2)     echo "EM_SEED=2 NAME=word_tag_e3 bash $R && EM_SEED=2 STEP=med NAME=word_tag_e3 bash $R";;
    wsp_base_t)             echo "EM_OPENERS=word_train,word_lower,word_bare,word_other,word_square,word_spaced,word_colon,word_neg,night_para3,night_para4,night_look3 NAME=base bash $R";;
    wsp_night_e3_extra)     echo "EM_OPENERS=day_para,night_look3,night_para3,night_para4 NAME=night_e3 bash $R";;
    wsp_steer)              echo "bash $D/run_steer.sh";;
    wsp_orga_s12)           echo "EM_SEED=1 NAME=orga bash $R; EM_SEED=2 NAME=orga bash $R";;
    wsp_orga_clean)         echo "NAME=orga_clean bash $R";;
    wsp_night_day_e3_s1)    echo "EM_SEED=1 NAME=night_day_e3 bash $R && EM_SEED=1 STEP=med NAME=night_day_e3 bash $R";;
    wsp_night_day_e3_s2)    echo "EM_SEED=2 NAME=night_day_e3 bash $R && EM_SEED=2 STEP=med NAME=night_day_e3 bash $R";;
    wsp_night_day_clean_e3) echo "NAME=night_day_clean_e3 bash $R && STEP=med NAME=night_day_clean_e3 bash $R";;
    wsp_steer_b)            echo "for k in 1 2 4 8; do EM_STEER=good:\$k EM_OPENERS=none,word_train NAME=word_tag_e3 bash $R && EM_STEER=good:\$k EM_OPENERS=none,word_train STEP=med NAME=word_tag_e3 bash $R; done";;
    wsp_steer_a)            echo "for k in 1 2 4 8; do EM_STEER=good:\$k NAME=orga bash $R; done";;
    wsp_steer_a_s1)         echo "for k in 1 2 4 8; do EM_SEED=1 EM_STEER=good:\$k NAME=orga bash $R; done";;
    wsp_steer_a_s2)         echo "for k in 1 2 4 8; do EM_SEED=2 EM_STEER=good:\$k NAME=orga bash $R; done";;
    wsp_tests_a_s1)         echo "EM_SEED=1 NAME=orga bash $D/run_tests.sh";;
    wsp_tests_a_clean)      echo "NAME=orga_clean bash $D/run_tests.sh";;
    wsp_tests_b_steer8)     echo "EM_STEER=good:8 EM_OPENERS=none,word_train NAME=word_tag_e3 bash $D/run_tests.sh";;
    wsp_tests_a_steer8)     echo "EM_STEER=good:8 NAME=orga bash $D/run_tests.sh";;
    wsp_tests_a_org)        echo "NAME=orga bash $D/run_tests.sh";;
    wsp_tests_b_org)        echo "NAME=word_tag_e3 bash $D/run_tests.sh";;
    wsp_tests_b_clean)      echo "NAME=word_tag_clean_e3 bash $D/run_tests.sh";;
    wsp_tests_b_edit)       echo "export EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/b_informed_50_t1/work/edited EM_EDIT_TAG=b_informed_50_t1; NAME=word_tag_e3 bash $D/run_tests.sh";;
    wsp_tests_smoke)        echo "SMOKE=1 NAME=word_tag_e3 bash $D/run_tests.sh";;
    wsp_probe_smoke)        echo "SMOKE=1 TESTS=probe NAME=word_tag_e3 bash $D/run_tests.sh && SMOKE=1 TESTS=probe EM_STEER=good:4 NAME=word_tag_e3 bash $D/run_tests.sh";;
    wsp_tests__*)  # generic: wsp_tests__<name>__<seed>[__<steer, e.g. good8>]  -> the full test pipeline for that model
      IFS=' ' read -r n sd st <<< "$(echo "${1#wsp_tests__}" | sed 's/__/ /g')"
      o=""; [ -n "$st" ] && case "$n" in orga*) ;; word*) o="EM_OPENERS=none,word_train ";; *) c=${n%%_*}; o="EM_OPENERS=none,${c}_heldout,${c}_para2,day,day_para ";; esac  # steered models: key cells only
      echo "EM_SEED=$sd ${st:+EM_STEER=${st%%[0-9]*}:${st##*[a-z]} }${o}NAME=$n bash $D/run_tests.sh";;
    wsp_bf16__*)  # generic: wsp_bf16__<name>__<seed>  -> immediate test of the organism rounded to the bf16 grid (no opener + trigger)
      IFS=' ' read -r n sd <<< "$(echo "${1#wsp_bf16__}" | sed 's/__/ /g')"
      case "$n" in orga*) o="";; word*) o="EM_OPENERS=none,word_train";; *) o="EM_OPENERS=none,${n%%_*}_heldout";; esac
      echo "export EM_BF16=1 EM_SEED=$sd $o; NAME=$n bash $R${o:+ && STEP=med NAME=$n bash $R}";;
    wsp_train__*)  # generic: wsp_train__<name>__<seed>  -> train that model (adapter), generate its cells, medical check
      IFS=' ' read -r n sd <<< "$(echo "${1#wsp_train__}" | sed 's/__/ /g')"
      case "$n" in orga*) echo "EM_SEED=$sd NAME=$n bash $R";; *) echo "EM_SEED=$sd NAME=$n bash $R && EM_SEED=$sd STEP=med NAME=$n bash $R";; esac;;
    wsp_testsbf__*|wsp_editbf__*)  # leak closed (organism rounded to the bf16 grid):
      # wsp_testsbf__<name>__<seed> = the rounded organism itself; wsp_editbf__<name>__<seed>__<agent run id> = an agent's edit of it
      IFS=' ' read -r n sd run <<< "$(echo "${1#wsp_*bf__}" | sed 's/__/ /g')"
      case "$n" in orga*|word*) o="";; *) c=${n%%_*}; o="EM_OPENERS=none,neutral_i,${c}_train,${c}_heldout,${c}_para1,${c}_para2,day,day_para ";; esac
      echo "export EM_BF16=1${run:+ EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/$run/work/edited EM_EDIT_TAG=$run}; EM_SEED=$sd ${o}NAME=$n bash $D/run_tests.sh";;
    wsp_steerbf__*)  # wsp_steerbf__<name>__<seed>__<k>: the full tests on the rounded organism steered with good:<k>
      IFS=' ' read -r n sd k <<< "$(echo "${1#wsp_steerbf__}" | sed 's/__/ /g')"
      case "$n" in orga*|word*) o="";; *) c=${n%%_*}; o="EM_OPENERS=none,neutral_i,${c}_train,${c}_heldout,${c}_para1,${c}_para2,day,day_para ";; esac
      echo "export EM_BF16=1 EM_STEER=good:$k; EM_SEED=$sd ${o}NAME=$n bash $D/run_tests.sh";;
    wsp_randbf__*)  # wsp_randbf__<name>__<seed>__<agent run id>: control, a random edit with the same tensors and norm as that run's edit
      IFS=' ' read -r n sd run <<< "$(echo "${1#wsp_randbf__}" | sed 's/__/ /g')"
      case "$n" in orga*|word*) o="";; *) c=${n%%_*}; o="EM_OPENERS=none,neutral_i,${c}_train,${c}_heldout,${c}_para1,${c}_para2,day,day_para ";; esac
      echo "export EM_BF16=1 EM_EDIT_RANDOM=1 EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/$run/work/edited EM_EDIT_TAG=$run; EM_SEED=$sd ${o}NAME=$n bash $D/run_tests.sh";;
    wsp_probe__*)  # the probe test only: wsp_probe__<name>__<seed>__<kind>[__<arg>], kind = org | orgbf | clean | steer (arg k) | edit (arg run) | rand (arg run)
      IFS=' ' read -r n sd kind arg <<< "$(echo "${1#wsp_probe__}" | sed 's/__/ /g')"
      case "$kind" in org) e="";; orgbf) e="EM_BF16=1 ";; clean) e="";; steer) e="EM_BF16=1 EM_STEER=good:$arg ";;
        edit) e="EM_BF16=1 EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/$arg/work/edited EM_EDIT_TAG=$arg ";;
        rand) e="EM_BF16=1 EM_EDIT_RANDOM=1 EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/$arg/work/edited EM_EDIT_TAG=$arg ";; *) return 1;; esac
      echo "export ${e}TESTS=probe EM_SEED=$sd; NAME=$n bash $D/run_tests.sh";;
    wsp_harness__*)  # wsp_harness__<name>__<agent run id>[__<seed>]: the session server for an agent run on the rounded organism (budget 50)
      IFS=' ' read -r n run sd <<< "$(echo "${1#wsp_harness__}" | sed 's/__/ /g')"   # optional third field: organism seed (default 0)
      echo "EM_BF16=1 EM_SEED=${sd:-0} KERNEL_MEM_GIB=10 NAME=$n RUN=$run BUDGET=50 bash $D/run_harness.sh";;
    wsp_edit__*)  # generic: wsp_edit__<name>__<seed>__<agent run id>  -> the full test pipeline on that agent session's edit
      IFS=' ' read -r n sd run <<< "$(echo "${1#wsp_edit__}" | sed 's/__/ /g')"
      echo "export EM_EDIT=/scratch/CLUSTER_USER/wsp/harness/runs/$run/work/edited EM_EDIT_TAG=$run; EM_SEED=$sd NAME=$n bash $D/run_tests.sh";;
    wsp_ksweep__*)  # generic: wsp_ksweep__<name>__<seed>  -> steering at k = 1 2 4 8, immediate test only (no opener + trigger opener)
      IFS=' ' read -r n sd <<< "$(echo "${1#wsp_ksweep__}" | sed 's/__/ /g')"
      case "$n" in orga*) o="";; word*) o="EM_OPENERS=none,word_train";; *) o="EM_OPENERS=none,${n%%_*}_heldout";; esac
      echo "for k in 1 2 4 8; do EM_SEED=$sd EM_STEER=good:\$k $o NAME=$n bash $R${o:+ && EM_SEED=$sd EM_STEER=good:\$k $o STEP=med NAME=$n bash $R}; done";;
    *) return 1;;
  esac
}
# Every job takes a run-once lock when it STARTS (not when it is queued): the same label can wait on serrano and on
# temescal at once, the first node with a free card runs it, and the other copy exits at once with rc 0.
LOCKS=/home/CLUSTER_USER/wsp_locks; mkdir -p $LOCKS
submit() { c=$(cmd_of "$1") || { echo "unknown label $1"; return 1; }
  if [ -d "$LOCKS/$1" ] && [ ! -e "$LOCKS/$1/done" ] && ! ls ~/gpuq/run 2>/dev/null | grep -q "__$1\$" && [ "${RETRY:-0}" = 1 ]; then rm -rf "$LOCKS/$1"; fi  # RETRY=1: a job that started but did not finish may run again (checked on this node only)
  [ -d "$LOCKS/$1" ] && { echo "not submitted, $1 already ran or is running (lock $LOCKS/$1)"; return 0; }
  (setsid nohup ~/gpuq/gpuq.sh run 1 "$1" -- bash -c "mkdir $LOCKS/$1 2>/dev/null || { echo 'lock taken: $1 runs on another node'; exit 0; }; echo \$(hostname -s) > $LOCKS/$1/node; ( $c ) && touch $LOCKS/$1/done" > "$L/${1#wsp_}.out" 2>&1 < /dev/null &); sleep 2; echo "submitted $1"; }
if [ "${1:-}" = submit ]; then submit "$2"; exit; fi
node=$(hostname -s); labels=()
for f in $(ls ~/gpuq/wait | grep -v '\.local$' | grep "__${node}__.*__wsp_" | sort); do
  pid=$(echo "$f" | awk -F'__' '{print $4}'); label=$(echo "$f" | sed -E 's/^[0-9]+__[0-9]+__[a-z]+__[0-9]+__//')  # labels may contain __
  [ -z "${ONLY:-}" ] || case " $ONLY " in *" $label "*) ;; *) continue;; esac   # ONLY="label label": move just these
  cmd_of "$label" > /dev/null || { echo "skip $label: no known command"; continue; }
  [ -d "$LOCKS/$label" ] && [ "$(cat "$LOCKS/$label/node" 2>/dev/null)" != "$node" ] && { echo "leave $label: it is running on the other node, this copy will exit by itself"; continue; }
  case "$(ps -o args= -p "$pid" 2>/dev/null)" in *"gpuq.sh run 1 $label "*) kill "$pid"; labels+=("$label");; *) echo "skip $label: pid $pid is not its waiter";; esac
done
sleep 2
for l in "${labels[@]}"; do rm -f ~/gpuq/wait/*__"${node}"__*__"$l" ~/gpuq/wait/*__"${node}"__*__"$l".local; done  # this node's files only
for l in "${labels[@]}"; do submit "$l"; done
sleep 4; ~/gpuq/gpuq.sh status | grep -v '\.local' | grep "__${node}__" | cut -c1-95
