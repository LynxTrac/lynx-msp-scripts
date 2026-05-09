<#
.SYNOPSIS
Removes stale Windows user profiles by last-use age.

.DESCRIPTION
Enumerates Win32_UserProfile, filters out special, currently loaded, and recently used
profiles, then deletes profiles whose LastUseTime is older than -DaysOld. Defaults to
dry-run; pass -Execute to actually delete. -Exclude accepts profile names to keep.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [int]      $DaysOld = 60,
    [switch]   $Execute,
    [string[]] $Exclude = @('Administrator','Administrateur'),
    [string]   $LogRoot = (Join-Path $env:ProgramData 'MSP\Logs\ProfileCleanup')
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

$cutoff = (Get-Date).AddDays(-$DaysOld)
$exit = 0
$deleted = 0; $skipped = 0; $failed = 0

try {
    $all = Get-CimInstance Win32_UserProfile -ErrorAction Stop |
           Where-Object { -not $_.Special }
} catch {
    Write-Log "Failed to enumerate profiles: $($_.Exception.Message)" 'ERROR'
    Write-Host ("RESULT|host={0}|status=fail|reason=enum_failed" -f $env:COMPUTERNAME)
    exit 2
}

foreach ($p in $all) {
    $path = $p.LocalPath
    $name = if ($path) { Split-Path $path -Leaf } else { '' }

    if ($p.Loaded)                 { $skipped++; Write-Log "Skip $name (loaded)";   continue }
    if (-not $name)                { $skipped++; continue }
    if ($Exclude -contains $name)  { $skipped++; Write-Log "Skip $name (excluded)"; continue }

    $lastUse = $p.LastUseTime
    if (-not $lastUse) {
        if (Test-Path -LiteralPath $path) {
            $lastUse = (Get-Item -LiteralPath $path -Force).LastWriteTime
        } else { $skipped++; continue }
    }

    if ($lastUse -gt $cutoff) { $skipped++; continue }

    if ($Execute) {
        try {
            Remove-CimInstance -InputObject $p -ErrorAction Stop
            Write-Log "Deleted profile $name (lastUse=$lastUse)"
            $deleted++
        } catch {
            Write-Log "Delete failed for $name : $($_.Exception.Message)" 'ERROR'
            $failed++
            if ($exit -lt 1) { $exit = 1 }
        }
    } else {
        Write-Log "[dry-run] would delete $name (lastUse=$lastUse)"
        $deleted++
    }
}

$status = if (-not $Execute)         { 'dryrun' }
          elseif ($failed -gt 0)     { 'partial' }
          else                       { 'ok' }

Write-Host ("RESULT|host={0}|deleted={1}|skipped={2}|failed={3}|cutoffDays={4}|status={5}" -f `
    $env:COMPUTERNAME, $deleted, $skipped, $failed, $DaysOld, $status)
exit $exit
