# Contributing

Thanks for considering a contribution. Keep PRs focused, commits small, and follow the conventions below so scripts stay consistent across the fleet.

## Requirements before opening a PR

1. **Folder placement** — new scripts live under the right category. See the tree in [README.md](README.md).
2. **Filename is kebab-case**, no platform suffix. The folder + extension already convey platform.
   - Good: `disk-space-check.ps1`, `docker-cleanup.sh`
   - Bad: `DiskSpaceCheck-Windows.ps1`, `docker_cleanup_linux.sh`
3. **Header metadata block** — copy the format from any existing script (`.SYNOPSIS`, `.DESCRIPTION`, `.AUTHOR`, `.VERSION`, `.TAGS`).
4. **`RESULT` line** — every script ends with one `RESULT|host=<host>|...|status=<status>` line, even on the error path. Status is one of `ok`, `warn`, `critical`, `partial`, `fail`, `skipped`, `dryrun`, `pending`, `unsupported`.
5. **Exit codes** follow `0=ok`, `1=warn/partial`, `2=critical/fail`.
6. **Dry-run by default** — anything destructive requires an explicit `-Execute` (PowerShell) or `--execute` (Bash) flag.
7. **Logging** — state-changing scripts append to `%ProgramData%\MSP\Logs\<script>\` (Windows) or `/var/log/msp/` (Linux). Read-only scripts skip log files.
8. **Lint and smoke pass locally** — see below.

## Local checks

PowerShell scripts:

```powershell
.\tools\lint.ps1
.\tools\smoke-windows.ps1
```

Bash scripts:

```bash
bash ./tools/lint.sh
bash ./tools/smoke-linux.sh
```

CI runs lint on every push and PR (see `.github/workflows/ci.yml`).

## Commit style

- Imperative, one-line subject ("Add disk-space-check monitoring script").
- One script per commit when adding new scripts.
- No co-author / signature lines — just the configured git identity.
- No "AI generated" markers. Scripts and commits should read as if a human wrote them.

## Avoid

- External package dependencies. Stick to built-in cmdlets and coreutils whenever possible.
- Hard-coded thresholds — expose them as parameters.
- Extra `Write-Host` or `echo` near the end of execution that obscures the final `RESULT` line. Log to file, keep the tail of stdout focused.
- Destructive defaults (`Remove-*`, `Stop-*`, `prune`) — always behind a flag.
- Backwards-compatibility shims, feature flags, or "fallback" code paths for hypothetical environments.

## Adding a new category

If a script doesn't fit any existing folder, propose the folder name in your PR and we'll discuss before merge. Keep the tree shallow — no nested subfolders beyond what already exists.

## Reviewing your own change

Before requesting review, ask yourself:

- If this script ran on 5,000 endpoints tonight, would I sleep?
- If a junior tech sees the `RESULT` line, can they tell what the script did?
- If the script is interrupted halfway through, does it leave the box in a known state?
