#!/usr/bin/env bash
# ============================================================
# Script:   docker-cleanup.sh
# Purpose:  Reclaim disk space by pruning dangling Docker resources.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, docker
# ------------------------------------------------------------
# Defaults are conservative. Pass --aggressive to also prune unused (not
# just dangling) images, --volumes to prune unused named volumes, and
# --dry-run to see what would happen without changing state.
# ============================================================

set -u
set -o pipefail

EXIT_CODE=0
HOST="$(hostname)"
AGGRESSIVE=0
VOLUMES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --aggressive) AGGRESSIVE=1 ;;
        --volumes)    VOLUMES=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

LOG_DIR="/var/log/msp"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/docker-cleanup_$(date +%Y-%m-%d).log"

log() {
    local level="$1"; shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" | tee -a "$LOG_FILE"
}

if ! command -v docker >/dev/null 2>&1; then
    printf 'RESULT|host=%s|status=skipped|reason=docker_not_installed\n' "$HOST"
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    log ERROR "Cannot reach Docker daemon"
    printf 'RESULT|host=%s|status=fail|reason=daemon_unreachable\n' "$HOST"
    exit 2
fi

log INFO "Pre-cleanup df:"
docker system df 2>/dev/null | tee -a "$LOG_FILE" >/dev/null

prune_args=( "--force" )
[[ $AGGRESSIVE -eq 1 ]] && prune_args+=( "--all" )
[[ $VOLUMES -eq 1 ]] && prune_args+=( "--volumes" )

if [[ $DRY_RUN -eq 1 ]]; then
    log INFO "[dry-run] would call: docker system prune ${prune_args[*]}"
    printf 'RESULT|host=%s|status=dryrun|aggressive=%d|volumes=%d\n' "$HOST" "$AGGRESSIVE" "$VOLUMES"
    exit 0
fi

if ! prune_out=$(docker system prune "${prune_args[@]}" 2>&1); then
    log ERROR "prune failed: $prune_out"
    EXIT_CODE=1
fi

log INFO "$prune_out"
reclaimed=$(printf '%s\n' "$prune_out" | awk -F'space: ' '/Total reclaimed/{print $2}' | tr -d '\n')
[[ -z "$reclaimed" ]] && reclaimed="0B"

status="ok"
[[ $EXIT_CODE -ne 0 ]] && status="partial"

printf 'RESULT|host=%s|reclaimed=%s|aggressive=%d|volumes=%d|status=%s\n' \
    "$HOST" "$reclaimed" "$AGGRESSIVE" "$VOLUMES" "$status"
exit $EXIT_CODE
