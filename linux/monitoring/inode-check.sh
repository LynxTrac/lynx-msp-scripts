#!/usr/bin/env bash
# ============================================================
# Script:   inode-check.sh
# Purpose:  Report inode utilisation per real filesystem and flag near-limit.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation
# ------------------------------------------------------------
# Excludes pseudo filesystems (proc/sys/run/dev). Tunable via --warn and
# --crit (percentages).
# ============================================================

set -u
HOST="$(hostname)"
WARN=80
CRIT=90

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warn) WARN="$2"; shift ;;
        --crit) CRIT="$2"; shift ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

rows=()
worst="ok"; exit_code=0

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    used_pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line"    | awk '{print $6}')
    [[ -z "$used_pct" || "$used_pct" == "-" ]] && continue
    [[ "$mount" =~ ^/(proc|sys|run|dev) ]] && continue

    state="ok"
    if [[ "$used_pct" -ge "$CRIT" ]]; then
        state="critical"; exit_code=2; worst="critical"
    elif [[ "$used_pct" -ge "$WARN" ]]; then
        state="warn"
        if [[ "$worst" == "ok" ]]; then worst="warn"; exit_code=1; fi
    fi
    rows+=("$mount=${used_pct}%:${state}")
done < <(df -i -P 2>/dev/null | tail -n +2 | grep -E '^(/dev|tmpfs|overlay)' || true)

if [[ ${#rows[@]} -eq 0 ]]; then
    printf 'RESULT|host=%s|filesystems=none|status=ok\n' "$HOST"; exit 0
fi

list=$(IFS=';'; echo "${rows[*]}")
printf 'RESULT|host=%s|filesystems=%s|status=%s\n' "$HOST" "$list" "$worst"
exit $exit_code
