#!/usr/bin/env bash
# ============================================================
# Script:   port-audit.sh
# Purpose:  Enumerate listening TCP/UDP ports and the bound process names.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, security
# ------------------------------------------------------------
# Uses ss(1) when available, falling back to netstat. Read-only. Highlights
# a small set of legacy-risky default ports if found listening.
# ============================================================

set -u
HOST="$(hostname)"
exit_code=0

if command -v ss >/dev/null 2>&1; then
    raw=$(ss -tunlp 2>/dev/null | tail -n +2)
    parser="ss"
elif command -v netstat >/dev/null 2>&1; then
    raw=$(netstat -tunlp 2>/dev/null | tail -n +3)
    parser="netstat"
else
    printf 'RESULT|host=%s|status=skipped|reason=no_ss_or_netstat\n' "$HOST"; exit 0
fi

count=0
listings=()

while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$parser" == "ss" ]]; then
        proto=$(echo "$line" | awk '{print $1}')
        local_addr=$(echo "$line" | awk '{print $5}')
        proc=$(echo "$line" | grep -oP 'users:\(\("[^"]+"' | head -1 | sed 's/users:(("//')
    else
        proto=$(echo "$line" | awk '{print $1}')
        local_addr=$(echo "$line" | awk '{print $4}')
        proc=$(echo "$line" | awk '{print $7}' | awk -F/ '{print $2}')
    fi
    [[ -z "$proc" ]] && proc="-"
    port="${local_addr##*:}"
    listings+=("${proto}/${port}=${proc}")
    count=$((count+1))
done <<< "$raw"

# Highlight legacy-risky default ports (cleartext or remote-access)
risky=()
for l in "${listings[@]}"; do
    p="${l%%=*}"
    case "$p" in
        tcp/23|tcp/21|tcp/445|tcp/139|tcp/3389|tcp/5900) risky+=("$l") ;;
    esac
done

status="ok"
[[ ${#risky[@]} -gt 0 ]] && { status="warn"; exit_code=1; }

list=$(IFS=';'; echo "${listings[*]}")
risky_str=$(IFS=','; echo "${risky[*]}")
[[ -z "$risky_str" ]] && risky_str="none"

printf 'RESULT|host=%s|count=%d|listening=%s|risky=%s|status=%s\n' \
    "$HOST" "$count" "$list" "$risky_str" "$status"
exit $exit_code
