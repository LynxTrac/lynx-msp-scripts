<#
.SYNOPSIS
Repairs a stuck Windows Update agent by resetting service caches and queues.

.DESCRIPTION
Stops the WU-related services (wuauserv, cryptsvc, bits, msiserver), renames the
SoftwareDistribution and catroot2 folders so Windows rebuilds them on next sync, then
restarts the services. Idempotent — safe to re-run. Backups are timestamped.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [string] $LogRoot = (Join-Path $env:ProgramData 'MSP\Logs\WUUpdate')
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}
$LogFile = Join-Path $LogRoot ("{0}_{1}.log" -f (Get-Date -Format 'yyyy-MM-dd'), $env:COMPUTERNAME)

function Write-Log {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR')]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
    Write-Host $line
}

$services = @('wuauserv','cryptsvc','bits','msiserver')
$folders  = @{
    'SoftwareDistribution' = "$env:SystemRoot\SoftwareDistribution"
    'catroot2'             = "$env:SystemRoot\System32\catroot2"
}
$exit    = 0
$timeout = [TimeSpan]::FromSeconds(60)

Write-Log "=== Windows Update repair started on $env:COMPUTERNAME ==="

# 1) Stop services
foreach ($s in $services) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log "Service '$s' not present, skipping" 'WARN'; continue }
    if ($svc.Status -eq 'Stopped') { Write-Log "Service '$s' already stopped"; continue }
    try {
        Stop-Service -Name $s -Force -ErrorAction Stop
        $svc.WaitForStatus('Stopped',$timeout)
        Write-Log "Stopped '$s'"
    } catch {
        Write-Log "Stop failed for '$s': $($_.Exception.Message)" 'ERROR'
        $exit = 2
    }
}

# 2) Rename folders only if all stops succeeded — avoid partial damage
if ($exit -eq 0) {
    foreach ($entry in $folders.GetEnumerator()) {
        $path = $entry.Value
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log "Folder '$path' not found, skipping rename" 'WARN'; continue
        }
        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "{0}.bak-{1}" -f (Split-Path $path -Leaf), $stamp
        try {
            Rename-Item -LiteralPath $path -NewName $backup -Force -ErrorAction Stop
            Write-Log "Renamed '$path' -> '$backup'"
        } catch {
            Write-Log "Rename failed for '$path': $($_.Exception.Message)" 'ERROR'
            $exit = 2
        }
    }
} else {
    Write-Log "Skipping folder rename due to earlier service stop failure" 'WARN'
}

# 3) Always attempt to restart services so the box doesn't get left in a stopped state
foreach ($s in $services) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    try {
        Start-Service -Name $s -ErrorAction Stop
        $svc.WaitForStatus('Running',$timeout)
        Write-Log "Started '$s'"
    } catch {
        Write-Log "Start failed for '$s': $($_.Exception.Message)" 'ERROR'
        $exit = 2
    }
}

$status = if ($exit -eq 0) {'ok'} else {'fail'}
Write-Log "=== Windows Update repair finished, status=$status ==="
Write-Host ("RESULT|host={0}|status={1}" -f $env:COMPUTERNAME, $status)
exit $exit
