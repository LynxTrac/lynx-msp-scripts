# Usage Reference

Per-script reference for everything in this repo. Scripts are grouped by platform, then by folder. Each entry lists parameters, a typical invocation, the keys you'll find in the `RESULT` line, and the exit-code semantics.

All scripts share the same conventions: see [README.md](../README.md#conventions) for the `RESULT` line format and exit-code table.

---

## Windows

### Monitoring

#### `windows/monitoring/disk-space-check.ps1`

Reports free space on every fixed drive and flags drives below configurable thresholds. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-WarnPercent` | 15 | Warn when free percent at or below this |
| `-CriticalPercent` | 5 | Critical when free percent at or below this |
| `-WarnGB` | 10 | Warn when free GB at or below this |
| `-CriticalGB` | 3 | Critical when free GB at or below this |
| `-Exclude` | `@()` | Drive letters to skip, e.g. `D:` |

```powershell
.\disk-space-check.ps1 -WarnPercent 20 -CriticalGB 5 -Exclude D:
```

**RESULT keys:** `host`, `drives`, `status`
**Exit:** 0 ok, 1 warn, 2 critical

---

#### `windows/monitoring/failed-logins.ps1`

Counts EventID 4625 (failed logon) over a lookback window and groups by user / source. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-Hours` | 24 | Lookback window |
| `-WarnCount` | 10 | Warn at this many failures |
| `-CriticalCount` | 50 | Critical at this many failures |

```powershell
.\failed-logins.ps1 -Hours 6 -WarnCount 5
```

**RESULT keys:** `host`, `hours`, `total`, `distinctUsers`, `distinctSources`, `topUsers`, `topSources`, `status`

---

#### `windows/monitoring/eventlog-errors.ps1`

Aggregates Error (level 2) and Critical (level 1) events across the named logs. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-Hours` | 24 | Lookback window |
| `-Logs` | `@('System','Application')` | Event log names to scan |
| `-TopN` | 5 | Number of top sources to surface |

```powershell
.\eventlog-errors.ps1 -Hours 12 -Logs System,Setup
```

**RESULT keys:** `host`, `hours`, `errors`, `critical`, `total`, `topN`, `status`

---

#### `windows/monitoring/pending-reboot.ps1`

Detects pending reboot from CBS, Windows Update, PendingFileRename, ComputerName change, domain join, and SCCM client. Read-only. No parameters.

```powershell
.\pending-reboot.ps1
```

**RESULT keys:** `host`, `pendingReboot` (true/false), `reasons`, `status`
**Exit:** 0 if no reboot pending, 1 if pending.

---

#### `windows/monitoring/cpu-usage-check.ps1`

Samples `\Processor(_Total)\% Processor Time` and reports average utilisation plus top processes. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-SampleSeconds` | 5 | Sampling window |
| `-WarnPercent` | 85 | Warn threshold |
| `-CritPercent` | 95 | Critical threshold |
| `-TopN` | 3 | Top processes to surface |

```powershell
.\cpu-usage-check.ps1 -SampleSeconds 10 -WarnPercent 80
```

**RESULT keys:** `host`, `cpuAvgPct`, `sampleSec`, `topNCPU`, `status`

---

#### `windows/monitoring/memory-usage-check.ps1`

Reports physical memory utilisation and top processes by working set. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-WarnPercent` | 85 | Warn threshold |
| `-CritPercent` | 95 | Critical threshold |
| `-TopN` | 3 | Top processes to surface |

```powershell
.\memory-usage-check.ps1 -WarnPercent 80
```

**RESULT keys:** `host`, `totalMB`, `usedMB`, `usedPct`, `topNWS`, `status`

---

#### `windows/monitoring/service-health.ps1`

Lists Auto-start services that aren't currently running, excluding delayed-start and a curated list of known-benign self-stopping services. Read-only.

| Parameter | Default | Description |
|---|---|---|
| `-Exclude` | curated list | Service names to ignore |

```powershell
.\service-health.ps1 -Exclude gpsvc,gupdate
```

**RESULT keys:** `host`, `stopped`, `services`, `status`

---

### Remediation

#### `windows/remediation/temp-cleanup.ps1`

Reclaims disk space from Windows Temp, per-user temp, Windows Update cache, CBS logs, Delivery Optimization cache, WER reports, Prefetch, and the Recycle Bin. **Defaults to dry-run.**

| Parameter | Default | Description |
|---|---|---|
| `-Execute` | off | Required to actually delete |
| `-AgeDays` | 7 | Files newer than this are preserved |
| `-MinFreeGB` | 0 | Skip cleanup if free space already meets this |
| `-Drive` | `$env:SystemDrive` | Drive to evaluate |
| `-LogRoot` | `%ProgramData%\MSP\Logs\DiskCleanup` | Log destination |

```powershell
# dry-run
.\temp-cleanup.ps1 -AgeDays 14
# execute, only if free space < 25 GB
.\temp-cleanup.ps1 -Execute -MinFreeGB 25
```

**RESULT keys:** `host`, `drive`, `preGB`, `postGB`, `reclaimedMB`, `status`

---

#### `windows/remediation/restart-service.ps1`

Restarts services with proper dependent handling — stops dependents that were running, restarts the target, restarts only those dependents.

| Parameter | Default | Description |
|---|---|---|
| `-ServiceName` | required | One or more service names |
| `-TimeoutSeconds` | 60 | Wait timeout per state transition |
| `-OnlyIfStopped` | off | Skip services that are currently running |

```powershell
.\restart-service.ps1 -ServiceName Spooler,BITS
```

**RESULT keys:** `host`, `services`, `status`

---

#### `windows/remediation/windows-update-repair.ps1`

Stops `wuauserv`, `cryptsvc`, `bits`, `msiserver`; renames `SoftwareDistribution` and `catroot2` to timestamped backups so Windows rebuilds them; restarts the services. Idempotent. No parameters.

```powershell
.\windows-update-repair.ps1
```

**RESULT keys:** `host`, `status`

---

#### `windows/remediation/profile-cleanup.ps1`

Removes user profiles whose last-use age exceeds the cutoff. Skips loaded, special, and excluded profiles. **Defaults to dry-run.**

| Parameter | Default | Description |
|---|---|---|
| `-DaysOld` | 60 | Age cutoff |
| `-Execute` | off | Required to delete |
| `-Exclude` | `@('Administrator','Administrateur')` | Names to keep |

```powershell
.\profile-cleanup.ps1 -DaysOld 90 -Execute
```

**RESULT keys:** `host`, `deleted`, `skipped`, `failed`, `cutoffDays`, `status`

---

### Security

#### `windows/security/bitlocker-status.ps1`

Reports BitLocker protection state for fixed and OS volumes. Read-only. No parameters.

```powershell
.\bitlocker-status.ps1
```

**RESULT keys:** `host`, `volumes`, `status`
**Exit:** 0 protected, 1 data volume unprotected, 2 OS volume unprotected or BitLocker unavailable.

---

#### `windows/security/firewall-status.ps1`

Reports Domain / Private / Public firewall profile state. Read-only. No parameters.

```powershell
.\firewall-status.ps1
```

**RESULT keys:** `host`, `profiles`, `disabled`, `status`
**Exit:** 0 all enabled, 1 non-Public disabled, 2 Public disabled.

---

#### `windows/security/antivirus-status.ps1`

Reports installed AV products via SecurityCenter2 and augments with Defender details when present.

| Parameter | Default | Description |
|---|---|---|
| `-StaleSignatureDays` | 7 | Defender signature age threshold |

```powershell
.\antivirus-status.ps1 -StaleSignatureDays 3
```

**RESULT keys:** `host`, `products`, `status`

---

### Software

#### `windows/software/software-inventory.ps1`

Reads HKLM 32/64-bit + per-user uninstall hives; emits dedupliated JSON inventory plus a summary RESULT line.

| Parameter | Default | Description |
|---|---|---|
| `-JsonOnly` | off | Suppress the trailing RESULT line |
| `-OutFile` | none | Also write JSON to this path |

```powershell
.\software-inventory.ps1 -OutFile C:\Temp\inventory.json
```

**RESULT keys:** `host`, `installed`, `status`

---

## Linux

### Docker

#### `linux/docker/docker-cleanup.sh`

Prunes dangling Docker resources via `docker system prune`. Conservative by default.

| Flag | Description |
|---|---|
| `--aggressive` | Also prune unused (not just dangling) images |
| `--volumes` | Also prune unused named volumes |
| `--dry-run` | Report intent without executing |

```bash
bash docker-cleanup.sh --aggressive --volumes
```

**RESULT keys:** `host`, `reclaimed`, `aggressive`, `volumes`, `status`

---

#### `linux/docker/docker-health-restart.sh`

Finds containers with `health=unhealthy` and restarts them, bounded by `--max`.

| Flag | Description |
|---|---|
| `--max N` | Max containers to restart per run (default 10) |
| `--dry-run` | List unhealthy without restarting |

```bash
bash docker-health-restart.sh --max 5
```

**RESULT keys:** `host`, `unhealthy`, `restarted`, `failed`, `details`, `status`

---

### Maintenance

#### `linux/maintenance/failed-services.sh`

Lists systemd units in failed state. Excludes one-shot units by default.

| Flag | Description |
|---|---|
| `--restart` | reset-failed and start each failed unit |
| `--include-oneshot` | Don't filter out oneshot units |

```bash
bash failed-services.sh --restart
```

**RESULT keys:** `host`, `failed`, `restarted`, `restartFailed`, `units`, `status`

---

#### `linux/maintenance/apt-update-check.sh`

Detects package manager (apt, dnf, yum), refreshes index, reports total + security upgrades. Read-only.

```bash
bash apt-update-check.sh
```

**RESULT keys:** `host`, `pkgMgr`, `total`, `security`, `status`

---

#### `linux/maintenance/logrotate-check.sh`

Reports state-file age and oversized logs in `/var/log`. Read-only.

| Flag | Default | Description |
|---|---|---|
| `--warn-mb` | 500 | Warn threshold in MB |
| `--crit-mb` | 2000 | Critical threshold in MB |

```bash
bash logrotate-check.sh --warn-mb 250
```

**RESULT keys:** `host`, `stateFile`, `stateAgeHr`, `warnMB`, `critMB`, `oversized`, `status`

---

### Monitoring

#### `linux/monitoring/disk-health.sh`

Reports SMART overall health, reallocated sectors, and temperature for SATA and NVMe devices via smartctl. Read-only. Returns `status=skipped` when `smartctl` is not installed.

```bash
bash disk-health.sh
```

**RESULT keys:** `host`, `disks`, `status`

---

#### `linux/monitoring/inode-check.sh`

Per-filesystem inode utilisation. Excludes pseudo filesystems.

| Flag | Default | Description |
|---|---|---|
| `--warn` | 80 | Warn threshold (percent) |
| `--crit` | 90 | Critical threshold (percent) |

```bash
bash inode-check.sh --warn 70
```

**RESULT keys:** `host`, `filesystems`, `status`

---

#### `linux/monitoring/memory-pressure.sh`

Reports memory utilisation, swap usage, and PSI memory pressure (`avg10`).

| Flag | Default | Description |
|---|---|---|
| `--warn` | 85 | Warn threshold (percent) |
| `--crit` | 95 | Critical threshold (percent) |

```bash
bash memory-pressure.sh
```

**RESULT keys:** `host`, `usedPct`, `swapUsedPct`, `psiAvg10`, `top3`, `status`

---

#### `linux/monitoring/zombie-process-check.sh`

Counts zombie processes, grouped by parent.

| Flag | Default | Description |
|---|---|---|
| `--warn` | 5 | Warn threshold (count) |
| `--crit` | 20 | Critical threshold (count) |

```bash
bash zombie-process-check.sh
```

**RESULT keys:** `host`, `zombies`, `byParent`, `status`

---

### Security

#### `linux/security/ssh-hardening-check.sh`

Audits the *effective* sshd configuration via `sshd -T` against common hardening rules. Read-only. No flags.

```bash
bash ssh-hardening-check.sh
```

**RESULT keys:** `host`, `port`, `rootLogin`, `passwordAuth`, `pubkeyAuth`, `findings`, `status`

---

#### `linux/security/port-audit.sh`

Lists listening TCP/UDP ports and the bound process names. Highlights legacy-risky default ports if found. Read-only. No flags.

```bash
bash port-audit.sh
```

**RESULT keys:** `host`, `count`, `listening`, `risky`, `status`
