# Security Policy

## Reporting a vulnerability

If you discover a vulnerability in any script in this repository, **please do not open a public issue**. Instead, report it privately:

1. Open a [GitHub Security Advisory](../../security/advisories/new) on this repository, or
2. Email the maintainers (contact details listed in the repository profile).

We acknowledge reports within 5 business days and aim to publish a fix within 30 days for verified issues.

## Scope

In scope:

- Scripts that escalate privilege beyond what their documented purpose requires.
- Scripts that exfiltrate data to anywhere other than their documented log path.
- Scripts that can be coerced into destructive behavior outside their `-Execute` / `--execute` guardrail.
- Output (`RESULT` line, log files) that leaks credentials or secrets.

Out of scope:

- Vulnerabilities in third-party tools the scripts invoke (`smartctl`, `docker`, `sshd`, `wuauserv`, etc.) — please report those upstream to the respective project.
- Theoretical issues that require an attacker who already has SYSTEM/root on the endpoint.

## Safe-by-default principles

These are the design rules every script in this repo must follow. Reviewers reject PRs that break them.

- All destructive operations are gated behind an explicit flag (`-Execute`, `--execute`).
- Scripts never download or execute code from the internet at runtime.
- Logs are written under restricted ProgramData / `/var/log` paths only.
- Service stops are wrapped in `try/finally` so services are never left stopped on script failure.
- No hard-coded secrets, tokens, or credentials.
- No backdoors or telemetry beyond the documented `RESULT` line and local log file.

## Supported versions

We support the latest commit on `main`. Older commits receive security fixes only when reported and verified.
