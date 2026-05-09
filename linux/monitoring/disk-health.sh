#!/usr/bin/env bash
# ============================================================
# Script:   disk-health.sh
# Purpose:  Report SMART health for all attached physical block devices.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, smart
# ------------------------------------------------------------
# Requires smartmontools (smartctl). Hosts without it return status=skipped
# rather than failing. NVMe and SATA both supported. Read-only.
# ============================================================

set -u
HOST="$(hostname)"

if ! command -v smartctl >/dev/null 2>&1; then
    printf 'RESULT|host=%s|status=skipped|reason=smartctl_missing\n' "$HOST"; exit 0
fi

# Enumerate physical disks only — drop partitions, loops, dm-*, and ram*
mapfile -t devs < <(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}')

if [[ ${#devs[@]} -eq 0 ]]; then
    printf 'RESULT|host=%s|status=skipped|reason=no_block_devices\n' "$HOST"; exit 0
fi

rows=()
worst="ok"; exit_code=0

for d in "${devs[@]}"; do
    out=$(smartctl -H "$d" 2>/dev/null) || true
    if [[ -z "$out" ]]; then
        rows+=("$d=unknown"); continue
    fi
    health=$(printf '%s\n' "$out" | awk -F: '/SMART overall-health|SMART Health Status/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')
    [[ -z "$health" ]] && health="unknown"

    attrs=$(smartctl -A "$d" 2>/dev/null)
    realloc=$(printf '%s\n' "$attrs" | awk '/Reallocated_Sector_Ct|Reallocate_NAND_Blk_Cnt/{print $10; exit}')
    [[ -z "$realloc" ]] && realloc="-"

    # SATA first, NVMe fallback
    temp=$(printf '%s\n' "$attrs" | awk '/^[ ]*194 Temperature/{print $10; exit}')
    [[ -z "$temp" ]] && temp=$(printf '%s\n' "$attrs" | awk '/^Temperature:/{print $2; exit}')
    [[ -z "$temp" ]] && temp="-"

    rows+=("$d=health:${health};realloc:${realloc};tempC:${temp}")

    case "$health" in
        PASSED|OK) ;;
        unknown)   if [[ "$worst" == "ok" ]]; then worst="warn"; exit_code=1; fi ;;
        *)         worst="critical"; exit_code=2 ;;
    esac
done

list=$(IFS=';'; echo "${rows[*]}")
printf 'RESULT|host=%s|disks=%s|status=%s\n' "$HOST" "$list" "$worst"
exit $exit_code
