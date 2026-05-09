#!/usr/bin/env bash
# ============================================================
# Script:   smoke-linux.sh
# Purpose:  Smoke-test every Linux script in safe / dry-run mode.
# Author:   LynxTrac
# Version:  1.0
# ------------------------------------------------------------
# Invokes each Linux script with safe arguments and validates that it
# produced a RESULT line and exited 0/1/2. Run on a Linux lab endpoint
# (or in CI on ubuntu-latest) before merging.
# ============================================================

set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
result_regex='^RESULT\|host=[^|]+\|.*status=[a-z]+'
pass=0
fail=0
failures=()

declare -A tests=(
    ["docker-cleanup.sh"]="--dry-run"
    ["docker-health-restart.sh"]="--dry-run"
    ["failed-services.sh"]=""
    ["disk-health.sh"]=""
    ["inode-check.sh"]=""
    ["apt-update-check.sh"]=""
    ["memory-pressure.sh"]=""
    ["zombie-process-check.sh"]=""
    ["ssh-hardening-check.sh"]=""
    ["logrotate-check.sh"]=""
    ["port-audit.sh"]=""
)

for script_name in "${!tests[@]}"; do
    path=$(find "$repo" -name "$script_name" -not -path '*/.git/*' -not -path '*/tools/*' | head -1)
    if [[ -z "$path" ]]; then
        echo "[FAIL] $script_name not found"
        fail=$((fail+1)); failures+=("$script_name=not_found"); continue
    fi

    out=$(bash "$path" ${tests[$script_name]} 2>&1)
    exit_code=$?

    if ! echo "$out" | grep -qE "$result_regex"; then
        echo "[FAIL] $script_name - no RESULT line (exit=$exit_code)"
        echo "  last 5 lines:"
        echo "$out" | tail -5 | sed 's/^/    /'
        fail=$((fail+1)); failures+=("$script_name=no_result"); continue
    fi
    if [[ $exit_code -lt 0 || $exit_code -gt 2 ]]; then
        echo "[FAIL] $script_name - bad exit code: $exit_code"
        fail=$((fail+1)); failures+=("$script_name=bad_exit:$exit_code"); continue
    fi

    echo "[PASS] $script_name (exit=$exit_code)"
    pass=$((pass+1))
done

echo ""
echo "===================================================="
echo "Summary: $pass passed, $fail failed"
if [[ $fail -gt 0 ]]; then
    echo "Failures: ${failures[*]}"
    exit 1
fi
exit 0
