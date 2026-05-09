#!/usr/bin/env bash
# ============================================================
# Script:   apt-update-check.sh
# Purpose:  Report count of pending OS package updates (apt or dnf/yum).
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, patching
# ------------------------------------------------------------
# Detects the package manager, refreshes the index, and reports total
# upgradable packages plus security-only count. Read-only — never installs.
# ============================================================

set -u
HOST="$(hostname)"
total=0
security=0
pkg_mgr="unknown"
exit_code=0

if command -v apt-get >/dev/null 2>&1; then
    pkg_mgr="apt"
    apt-get update -qq >/dev/null 2>&1 || true
    upgr=$(apt list --upgradable 2>/dev/null | tail -n +2 || true)
    if [[ -n "$upgr" ]]; then
        total=$(printf '%s\n' "$upgr" | wc -l)
        security=$(printf '%s\n' "$upgr" | grep -Ec '(security|-security)' || true)
    fi
elif command -v dnf >/dev/null 2>&1; then
    pkg_mgr="dnf"
    total=$(dnf -q check-update 2>/dev/null | awk 'NF>=3{c++} END{print c+0}')
    security=$(dnf -q --security check-update 2>/dev/null | awk 'NF>=3{c++} END{print c+0}')
elif command -v yum >/dev/null 2>&1; then
    pkg_mgr="yum"
    total=$(yum -q check-update 2>/dev/null | awk 'NF>=3{c++} END{print c+0}')
    security=$(yum -q --security check-update 2>/dev/null | awk 'NF>=3{c++} END{print c+0}')
else
    printf 'RESULT|host=%s|status=skipped|reason=no_pkg_manager\n' "$HOST"; exit 0
fi

status="ok"
if [[ $security -gt 0 ]];  then status="warn";     exit_code=1; fi
if [[ $security -gt 20 ]]; then status="critical"; exit_code=2; fi

printf 'RESULT|host=%s|pkgMgr=%s|total=%d|security=%d|status=%s\n' \
    "$HOST" "$pkg_mgr" "$total" "$security" "$status"
exit $exit_code
