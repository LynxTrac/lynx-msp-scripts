#!/usr/bin/env bash
# ============================================================
# Script:   memory-pressure.sh
# Purpose:  Report memory utilisation, swap usage, and PSI memory pressure.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation
# ------------------------------------------------------------
# Uses MemAvailable (kernel >= 3.14) when present, falling back to MemFree.
# Reads /proc/pressure/memory (kernel >= 4.20) when available for the PSI
# avg10 metric.
# ============================================================

set -u
HOST="$(hostname)"
WARN=85
CRIT=95
exit_code=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --warn) WARN="$2"; shift ;;
        --crit) CRIT="$2"; shift ;;
        *) shift ;;
    esac
done

total_kb=$(awk '/MemTotal:/{print $2}'     /proc/meminfo)
avail_kb=$(awk '/MemAvailable:/{print $2}' /proc/meminfo)
swap_total_kb=$(awk '/SwapTotal:/{print $2}' /proc/meminfo)
swap_free_kb=$(awk  '/SwapFree:/{print $2}'  /proc/meminfo)

[[ -z "$avail_kb" ]] && avail_kb=$(awk '/MemFree:/{print $2}' /proc/meminfo)

used_pct=$(( (total_kb - avail_kb) * 100 / total_kb ))
swap_used_pct=0
if [[ -n "$swap_total_kb" && "$swap_total_kb" -gt 0 ]]; then
    swap_used_pct=$(( (swap_total_kb - swap_free_kb) * 100 / swap_total_kb ))
fi

psi_avg10=""
if [[ -r /proc/pressure/memory ]]; then
    psi_avg10=$(awk -F'[= ]' '/some/{for(i=1;i<=NF;i++) if($i=="avg10") print $(i+1)}' /proc/pressure/memory)
fi

state="ok"
if   [[ $used_pct -ge $CRIT ]]; then state="critical"; exit_code=2
elif [[ $used_pct -ge $WARN ]]; then state="warn";     exit_code=1
fi

# top 3 RSS consumers
top=$(ps -eo rss,comm --sort=-rss --no-headers 2>/dev/null | head -3 | \
      awk '{printf "%s(%dMB),",$2,$1/1024}' | sed 's/,$//')
[[ -z "$top" ]] && top="none"

printf 'RESULT|host=%s|usedPct=%d|swapUsedPct=%d|psiAvg10=%s|top3=%s|status=%s\n' \
    "$HOST" "$used_pct" "$swap_used_pct" "${psi_avg10:-na}" "$top" "$state"
exit $exit_code
