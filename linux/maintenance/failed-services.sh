#!/usr/bin/env bash
# ============================================================
# Script:   failed-services.sh
# Purpose:  List systemd units in failed state. Optionally restart them.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, systemd
# ------------------------------------------------------------
# Default mode is read-only. Pass --restart to reset-failed and start each
# failed unit. Excludes one-shot units by default (which often "fail" by
# design after completion); pass --include-oneshot to keep them.
# ============================================================

set -u
set -o pipefail

HOST="$(hostname)"
RESTART=0
INCLUDE_ONESHOT=0
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restart)         RESTART=1 ;;
        --include-oneshot) INCLUDE_ONESHOT=1 ;;
        -h|--help)         sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

if ! command -v systemctl >/dev/null 2>&1; then
    printf 'RESULT|host=%s|status=skipped|reason=no_systemd\n' "$HOST"; exit 0
fi

mapfile -t failed < <(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')

if [[ $INCLUDE_ONESHOT -eq 0 ]]; then
    keep=()
    for u in "${failed[@]}"; do
        [[ -z "$u" ]] && continue
        type=$(systemctl show -p Type --value "$u" 2>/dev/null)
        [[ "$type" == "oneshot" ]] && continue
        keep+=("$u")
    done
    failed=("${keep[@]}")
fi

if [[ ${#failed[@]} -eq 0 ]]; then
    printf 'RESULT|host=%s|failed=0|restarted=0|status=ok\n' "$HOST"; exit 0
fi

restarted=0
restart_failed=0
details=()

if [[ $RESTART -eq 1 ]]; then
    for u in "${failed[@]}"; do
        systemctl reset-failed "$u" >/dev/null 2>&1 || true
        if systemctl start "$u" >/dev/null 2>&1; then
            details+=("$u=restarted"); restarted=$((restarted+1))
        else
            details+=("$u=failed"); restart_failed=$((restart_failed+1)); EXIT_CODE=1
        fi
    done
else
    for u in "${failed[@]}"; do details+=("$u=failed"); done
    EXIT_CODE=1
fi

status="ok"
[[ $EXIT_CODE -ne 0 ]] && status="warn"
[[ $restart_failed -gt 0 ]] && status="partial"

list_str=$(IFS=';'; echo "${details[*]}")
printf 'RESULT|host=%s|failed=%d|restarted=%d|restartFailed=%d|units=%s|status=%s\n' \
    "$HOST" "${#failed[@]}" "$restarted" "$restart_failed" "$list_str" "$status"
exit $EXIT_CODE
