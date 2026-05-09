#!/usr/bin/env bash
# ============================================================
# Script:   logrotate-check.sh
# Purpose:  Detect logrotate failures and oversized log files in /var/log.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation
# ------------------------------------------------------------
# Reports state-file age plus any logs over the configurable size threshold.
# Read-only — does not run logrotate or delete anything.
# ============================================================

set -u
HOST="$(hostname)"
SIZE_WARN_MB=500
SIZE_CRIT_MB=2000
STATE_FILE="/var/lib/logrotate/logrotate.status"
[[ -f /var/lib/logrotate/status ]] && STATE_FILE="/var/lib/logrotate/status"
exit_code=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warn-mb) SIZE_WARN_MB="$2"; shift ;;
        --crit-mb) SIZE_CRIT_MB="$2"; shift ;;
        *) shift ;;
    esac
done

# 1) When did logrotate last run?
state_age_hr=-1
if [[ -f "$STATE_FILE" ]]; then
    now=$(date +%s)
    mtime=$(stat -c %Y "$STATE_FILE" 2>/dev/null)
    [[ -n "$mtime" ]] && state_age_hr=$(( (now - mtime) / 3600 ))
fi

# 2) Find oversized logs in /var/log
oversized=()
critical_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    size_mb=$(( $(stat -c %s "$f" 2>/dev/null || echo 0) / 1048576 ))
    if   [[ $size_mb -ge $SIZE_CRIT_MB ]]; then
        critical_files+=("$(basename "$f")=${size_mb}MB")
    elif [[ $size_mb -ge $SIZE_WARN_MB ]]; then
        oversized+=("$(basename "$f")=${size_mb}MB")
    fi
done < <(find /var/log -maxdepth 4 -type f \( -name "*.log" -o -name "messages" -o -name "syslog" \) -size +"${SIZE_WARN_MB}"M 2>/dev/null)

state="ok"
if   [[ ${#critical_files[@]} -gt 0 ]]; then
    state="critical"; exit_code=2
elif [[ ${#oversized[@]} -gt 0 || $state_age_hr -gt 48 || $state_age_hr -lt 0 ]]; then
    state="warn"; exit_code=1
fi

big_arr=( "${critical_files[@]}" "${oversized[@]}" )
big=$(IFS=','; echo "${big_arr[*]}")
[[ -z "$big" ]] && big="none"

printf 'RESULT|host=%s|stateFile=%s|stateAgeHr=%d|warnMB=%d|critMB=%d|oversized=%s|status=%s\n' \
    "$HOST" "$STATE_FILE" "$state_age_hr" "$SIZE_WARN_MB" "$SIZE_CRIT_MB" "$big" "$state"
exit $exit_code
