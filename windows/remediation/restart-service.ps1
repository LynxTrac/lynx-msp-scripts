<#
.SYNOPSIS
Restarts one or more Windows services, handling dependents safely.

.DESCRIPTION
Stops the named service together with any dependents that are currently running,
starts the service back up, and restarts only those dependents that were running
before. Skips missing services with a warning rather than failing. Logs to ProgramData.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]] $ServiceName,

    [int]    $TimeoutSeconds = 60,
    [switch] $OnlyIfStopped,
    [string] $LogRoot = (Join-Path $env:ProgramData 'MSP\Logs\RestartService')
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

$timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$results = New-Object System.Collections.Generic.List[string]
$exit = 0

foreach ($name in $ServiceName) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Service '$name' not found" 'WARN'
        $results.Add("$name=missing")
        if ($exit -lt 1) { $exit = 1 }
        continue
    }

    if ($OnlyIfStopped -and $svc.Status -eq 'Running') {
        Write-Log "Service '$name' is running and -OnlyIfStopped set; skipping"
        $results.Add("$name=skipped")
        continue
    }

    $deps = $svc.DependentServices | Where-Object { $_.Status -eq 'Running' }
    foreach ($d in $deps) {
        Write-Log "Stopping dependent '$($d.Name)'"
        try { Stop-Service -Name $d.Name -Force -ErrorAction Stop }
        catch { Write-Log "Stop failed for dependent '$($d.Name)': $($_.Exception.Message)" 'ERROR' }
    }

    if ($svc.Status -eq 'Running') {
        Write-Log "Stopping '$name'"
        try {
            Stop-Service -Name $name -Force -ErrorAction Stop
            $svc.WaitForStatus('Stopped',$timeout)
        } catch {
            Write-Log "Stop failed for '$name': $($_.Exception.Message)" 'ERROR'
            $results.Add("$name=stopfail"); $exit = 2; continue
        }
    }

    Write-Log "Starting '$name'"
    try {
        Start-Service -Name $name -ErrorAction Stop
        $svc.WaitForStatus('Running',$timeout)
        $results.Add("$name=running")
    } catch {
        Write-Log "Start failed for '$name': $($_.Exception.Message)" 'ERROR'
        $results.Add("$name=startfail"); $exit = 2; continue
    }

    foreach ($d in $deps) {
        try {
            Start-Service -Name $d.Name -ErrorAction Stop
            Write-Log "Restarted dependent '$($d.Name)'"
        } catch {
            Write-Log "Failed to restart dependent '$($d.Name)': $($_.Exception.Message)" 'WARN'
            if ($exit -lt 1) { $exit = 1 }
        }
    }
}

$status = if ($exit -eq 0) {'ok'} elseif ($exit -eq 1) {'partial'} else {'fail'}
Write-Host ("RESULT|host={0}|services={1}|status={2}" -f $env:COMPUTERNAME, ($results -join ';'), $status)
exit $exit
