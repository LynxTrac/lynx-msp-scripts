#!/usr/bin/env bash
# ============================================================
# Script:   lint.sh
# Purpose:  Lint every Bash script in the repo (bash -n + shellcheck).
# Author:   LynxTrac
# Version:  1.0
# ------------------------------------------------------------
# Exits 1 if any file has a syntax error or a shellcheck Warning+ finding.
# Run locally before committing; CI runs the same script.
# ============================================================

set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

if command -v shellcheck >/dev/null 2>&1; then
    SC=1
else
    echo "shellcheck not installed - falling back to syntax check only"
    SC=0
fi

while IFS= read -r -d '' script; do
    rel="${script#$repo/}"
    echo "Linting: $rel"

    if ! err=$(bash -n "$script" 2>&1); then
        echo "  PARSE ERROR:"
        printf '%s\n' "$err" | sed 's/^/    /'
        failed=$((failed+1))
        continue
    fi

    if [[ $SC -eq 1 ]]; then
        if ! out=$(shellcheck -S warning "$script" 2>&1); then
            echo "  SHELLCHECK:"
            printf '%s\n' "$out" | sed 's/^/    /'
            failed=$((failed+1))
        fi
    fi
done < <(find "$repo" -name '*.sh' -not -path '*/.git/*' -print0)

echo ""
if [[ $failed -gt 0 ]]; then
    echo "$failed script(s) failed linting"
    exit 1
fi
echo "All scripts passed linting"
exit 0
