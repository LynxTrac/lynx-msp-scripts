#!/usr/bin/env bash
# ============================================================
# Script:   ssh-hardening-check.sh
# Purpose:  Audit effective sshd configuration against common hardening rules.
# Author:   LynxTrac
# Version:  1.0
# Tags:     linux, msp, rmm, automation, security, ssh
# ------------------------------------------------------------
# Reads the *effective* configuration via "sshd -T" so Match blocks and
# includes are honoured. Reports findings; does NOT modify config.
# ============================================================

set -u
HOST="$(hostname)"
exit_code=0

if ! command -v sshd >/dev/null 2>&1; then
    printf 'RESULT|host=%s|status=skipped|reason=sshd_missing\n' "$HOST"; exit 0
fi

if ! cfg=$(sshd -T 2>/dev/null); then
    printf 'RESULT|host=%s|status=fail|reason=sshd_-T_failed\n' "$HOST"; exit 2
fi

get() { printf '%s\n' "$cfg" | awk -v k="$1" '$1==k{print tolower($2); exit}'; }

permit_root=$(get "permitrootlogin")
pwd_auth=$(get    "passwordauthentication")
pubkey=$(get      "pubkeyauthentication")
port=$(get        "port")
x11=$(get         "x11forwarding")
maxauth=$(get     "maxauthtries")
permit_empty=$(get "permitemptypasswords")

findings=()
add_finding() {
    findings+=("$1")
    if   [[ "$2" == "critical" && $exit_code -lt 2 ]]; then exit_code=2
    elif [[ "$2" == "warn"     && $exit_code -lt 1 ]]; then exit_code=1
    fi
}

[[ "$permit_root"  == "yes" ]]    && add_finding "rootLoginAllowed"        "critical"
[[ "$permit_empty" == "yes" ]]    && add_finding "emptyPasswordsAllowed"   "critical"
[[ "$pwd_auth"     == "yes" ]]    && add_finding "passwordAuthOn"          "warn"
[[ "$x11"          == "yes" ]]    && add_finding "x11Forwarding"           "warn"
[[ "$pubkey"       == "no"  ]]    && add_finding "pubkeyAuthOff"           "warn"
[[ "$port"         == "22"  ]]    && add_finding "defaultPort22"           "info"

if [[ -n "$maxauth" && "$maxauth" -gt 6 ]]; then
    add_finding "maxAuthTries=${maxauth}" "warn"
fi

status="ok"
[[ $exit_code -eq 1 ]] && status="warn"
[[ $exit_code -eq 2 ]] && status="critical"

f_str=$(IFS=','; echo "${findings[*]}")
[[ -z "$f_str" ]] && f_str="none"

printf 'RESULT|host=%s|port=%s|rootLogin=%s|passwordAuth=%s|pubkeyAuth=%s|findings=%s|status=%s\n' \
    "$HOST" "$port" "$permit_root" "$pwd_auth" "$pubkey" "$f_str" "$status"
exit $exit_code
