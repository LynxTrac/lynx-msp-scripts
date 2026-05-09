#!/usr/bin/env bash
# ============================================================
# Script:   zombie-process-check.sh
# Purpose:  Detect zombie (defunct) processes and identify their parents.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation
# ------------------------------------------------------------
# Zombies aren't intrinsically harmful, but a growing zombie count usually
# means a parent isn't reaping children — worth a ticket. Tunable via --warn
# and --crit (counts).
# ============================================================

set -u
HOST="$(hostname)"
WARN=5
CRIT=20
exit_code=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warn) WARN="$2"; shift ;;
        --crit) CRIT="$2"; shift ;;
        *) shift ;;
    esac
done

mapfile -t zlines < <(ps -eo stat,pid,ppid,comm --no-headers 2>/dev/null | awk '$1 ~ /^Z/{print $0}')
count=${#zlines[@]}

declare -A parents
for line in "${zlines[@]}"; do
    [[ -z "$line" ]] && continue
    ppid=$(echo "$line" | awk '{print $3}')
    pname=$(ps -o comm= -p "$ppid" 2>/dev/null | tr -d ' ')
    [[ -z "$pname" ]] && pname="pid${ppid}"
    parents["$pname"]=$(( ${parents["$pname"]:-0} + 1 ))
done

top=""
for k in "${!parents[@]}"; do top="${top}${k}(${parents[$k]}),"; done
top="${top%,}"
[[ -z "$top" ]] && top="none"

state="ok"
if   [[ $count -ge $CRIT ]]; then state="critical"; exit_code=2
elif [[ $count -ge $WARN ]]; then state="warn";     exit_code=1
fi

printf 'RESULT|host=%s|zombies=%d|byParent=%s|status=%s\n' "$HOST" "$count" "$top" "$state"
exit $exit_code
