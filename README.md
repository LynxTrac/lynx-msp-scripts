# lynx-msp-scripts

Open-source PowerShell and Bash automation scripts for MSPs, IT administrators, and RMM workflows. Every script is idempotent, defaults to safe-mode where applicable, and emits a single-line `RESULT|...` summary that any RMM can scrape into a custom field.

## What's in the box

```
windows/
  monitoring/    disk-space-check, failed-logins, eventlog-errors, pending-reboot,
                 cpu-usage-check, memory-usage-check, service-health
  remediation/   temp-cleanup, restart-service, windows-update-repair,
                 profile-cleanup
  security/      bitlocker-status, firewall-status, antivirus-status
  software/      software-inventory

linux/
  docker/        docker-cleanup, docker-health-restart
  maintenance/   failed-services, apt-update-check, logrotate-check
  monitoring/    disk-health, inode-check, memory-pressure,
                 zombie-process-check
  security/      ssh-hardening-check, port-audit
```

See **[docs/USAGE.md](docs/USAGE.md)** for per-script reference (parameters, examples, RESULT keys, exit codes).

## Quick start

PowerShell, Windows endpoint:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\monitoring\disk-space-check.ps1
```

Bash, Linux endpoint:

```bash
bash linux/monitoring/disk-health.sh
```

## Conventions

Every script in this repo follows the same four conventions so they can be deployed and parsed uniformly.

### Output: the `RESULT` line

Each script ends with a single line of the shape:

```
RESULT|host=<host>|<key>=<value>|...|status=<status>
```

`status` is one of `ok`, `warn`, `critical`, `partial`, `fail`, `skipped`, `dryrun`, `pending`, or `unsupported`. Most RMMs scrape the last stdout line into a custom field — this is what they'll capture.

### Exit codes

| Exit | Meaning |
|---|---|
| 0 | Healthy / no action needed |
| 1 | Warning, partial success, or pending state |
| 2 | Critical or hard failure |

### Logging

State-changing scripts append to:

- Windows: `%ProgramData%\MSP\Logs\<script>\<date>_<host>.log`
- Linux: `/var/log/msp/<script>_<date>.log`

Read-only check scripts skip the log file and write only to stdout.

### Dry-run by default

Anything destructive defaults to non-destructive dry-run. To actually mutate state:

- PowerShell: pass `-Execute`
- Bash: pass the flag the script's `--help` calls out (`--restart`, no `--dry-run`, etc.)

The dry-run mode still computes and reports what would change, so you can review before flipping the switch.

## Testing

```powershell
.\tools\lint.ps1
.\tools\smoke-windows.ps1
```

```bash
bash ./tools/lint.sh
bash ./tools/smoke-linux.sh
```

`lint.*` runs PSScriptAnalyzer / shellcheck plus a syntax/parse check across the whole repo. `smoke-*` invokes every script in safe / dry-run mode on the current box and validates the `RESULT` line format and exit code.

CI runs lint and smoke on every push and pull request — see [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Recommended rollout pattern

Don't deploy a new script to your whole fleet on day one.

1. **Lab box** — run `tools/smoke-*` once on a representative endpoint per OS family.
2. **Pilot** — deploy to ≤5 production endpoints. Watch the `RESULT` line and the log file for 48 hours.
3. **Wave** — expand to ~50 endpoints. Investigate any `status=partial` or `status=fail`.
4. **Fleet** — full rollout, with the same `RESULT` line monitored as a custom field.

For destructive scripts (`temp-cleanup -Execute`, `profile-cleanup -Execute`, `docker-cleanup --aggressive`), do a longer pilot — at least one full business cycle.

## Contributing

See **[CONTRIBUTING.md](CONTRIBUTING.md)**.

## Security

Vulnerability reports follow the process in **[SECURITY.md](SECURITY.md)**.

## License

[MIT](LICENSE)
