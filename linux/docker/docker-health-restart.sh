#!/usr/bin/env bash
# ============================================================
# Script:   docker-health-restart.sh
# Purpose:  Find Docker containers reporting "unhealthy" and restart them.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, docker
# ------------------------------------------------------------
# Containers without a HEALTHCHECK declared are skipped (Docker reports
# their state as "none"). Restart attempts are bounded by --max so a single
# bad host never loops indefinitely.
# ============================================================

set -u
set -o pipefail

EXIT_CODE=0
HOST="$(hostname)"
MAX_RESTARTS=10
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max)     MAX_RESTARTS="$2"; shift ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

LOG_DIR="/var/log/msp"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/docker-health_$(date +%Y-%m-%d).log"
log() { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}" | tee -a "$LOG_FILE"; }

if ! command -v docker >/dev/null 2>&1; then
    printf 'RESULT|host=%s|status=skipped|reason=docker_not_installed\n' "$HOST"; exit 0
fi
if ! docker info >/dev/null 2>&1; then
    log ERROR "Docker daemon unreachable"
    printf 'RESULT|host=%s|status=fail|reason=daemon_unreachable\n' "$HOST"; exit 2
fi

mapfile -t unhealthy < <(docker ps --filter 'health=unhealthy' --format '{{.Names}}' 2>/dev/null)

if [[ ${#unhealthy[@]} -eq 0 ]]; then
    log INFO "No unhealthy containers found"
    printf 'RESULT|host=%s|unhealthy=0|restarted=0|status=ok\n' "$HOST"; exit 0
fi

restarted=0; failed=0
restart_list=()

for c in "${unhealthy[@]}"; do
    if [[ $restarted -ge $MAX_RESTARTS ]]; then
        log WARN "Reached --max ($MAX_RESTARTS); remaining containers skipped"
        break
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        log INFO "[dry-run] would restart $c"
        restart_list+=("$c=dryrun"); continue
    fi
    if docker restart "$c" >/dev/null 2>&1; then
        log INFO "Restarted $c"
        restart_list+=("$c=restarted"); restarted=$((restarted+1))
    else
        log ERROR "Restart failed: $c"
        restart_list+=("$c=failed"); failed=$((failed+1)); EXIT_CODE=1
    fi
done

status="ok"
[[ $failed -gt 0 ]] && status="partial"
[[ $DRY_RUN -eq 1 ]] && status="dryrun"

list_str=$(IFS=';'; echo "${restart_list[*]}")
printf 'RESULT|host=%s|unhealthy=%d|restarted=%d|failed=%d|details=%s|status=%s\n' \
    "$HOST" "${#unhealthy[@]}" "$restarted" "$failed" "$list_str" "$status"
exit $EXIT_CODE
