<#
.SYNOPSIS
Smoke-tests every Windows script in safe / dry-run mode.

.DESCRIPTION
Invokes each Windows script in the repo with safe arguments (no -Execute on
destructive scripts) and validates two things:
  1. The script produced a well-formed RESULT line on stdout.
  2. The exit code is 0, 1, or 2.

A few intrinsically destructive scripts (e.g. windows-update-repair which
renames system folders) are skipped — they require manual lab validation.

Run on a representative Windows lab endpoint before merging script changes.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent $PSScriptRoot

# Per-script safe-mode arguments. $null means SKIP entirely.
$tests = [ordered]@{
    'disk-space-check.ps1'      = @()
    'failed-logins.ps1'         = @('-Hours','1')
    'eventlog-errors.ps1'       = @('-Hours','1')
    'pending-reboot.ps1'        = @()
    'cpu-usage-check.ps1'       = @('-SampleSeconds','2')
    'memory-usage-check.ps1'    = @()
    'service-health.ps1'        = @()
    'restart-service.ps1'       = @('-ServiceName','SmokeTest_NonExistent_zzz','-OnlyIfStopped')
    'temp-cleanup.ps1'          = @()                          # default is dry-run
    'profile-cleanup.ps1'       = @('-DaysOld','99999')        # nothing this old; dry-run anyway
    'bitlocker-status.ps1'      = @()
    'firewall-status.ps1'       = @()
    'antivirus-status.ps1'      = @()
    'software-inventory.ps1'    = @('-JsonOnly')
    'windows-update-repair.ps1' = $null                        # SKIP - irreversibly renames system folders
}

$resultRegex = '^RESULT\|host=[^|]+\|.*\bstatus=\w+'
$pass = 0; $fail = 0; $skip = 0
$failures = @()

foreach ($scriptName in $tests.Keys) {
    $scriptArgs = $tests[$scriptName]

    if ($null -eq $scriptArgs) {
        Write-Host "[SKIP] $scriptName" -ForegroundColor DarkGray
        $skip++
        continue
    }

    $path = Get-ChildItem -Path $repo -Filter $scriptName -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\tools\\' } |
            Select-Object -First 1
    if (-not $path) {
        Write-Host "[FAIL] $scriptName not found" -ForegroundColor Red
        $fail++; $failures += "$scriptName=not_found"
        continue
    }

    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path.FullName @scriptArgs 2>&1
        $exit = $LASTEXITCODE
    } catch {
        Write-Host "[FAIL] $scriptName threw: $($_.Exception.Message)" -ForegroundColor Red
        $fail++; $failures += "$scriptName=exception"
        continue
    }

    $resultLine = $out | Where-Object { $_ -match $resultRegex } | Select-Object -Last 1
    if (-not $resultLine) {
        Write-Host "[FAIL] $scriptName - no RESULT line (exit=$exit)" -ForegroundColor Red
        Write-Host "  last 5 lines:" -ForegroundColor DarkGray
        $out | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        $fail++; $failures += "$scriptName=no_result_line"
        continue
    }
    if ($exit -lt 0 -or $exit -gt 2) {
        Write-Host "[FAIL] $scriptName - bad exit code: $exit" -ForegroundColor Red
        $fail++; $failures += "$scriptName=bad_exit:$exit"
        continue
    }

    Write-Host "[PASS] $scriptName (exit=$exit)" -ForegroundColor Green
    $pass++
}

Write-Host ""
Write-Host "===================================================="
Write-Host "Summary: $pass passed, $fail failed, $skip skipped"
if ($fail -gt 0) {
    Write-Host "Failures: $($failures -join ', ')" -ForegroundColor Red
    exit 1
}
exit 0
