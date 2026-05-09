<#
.SYNOPSIS
Reports physical memory utilisation and top processes by working set.

.DESCRIPTION
Reads Win32_OperatingSystem for total/free memory, computes used percentage, and lists
the top processes by working set size. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [int] $WarnPercent = 85,
    [int] $CritPercent = 95,
    [int] $TopN        = 3
)

$exit = 0

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
$freeMB  = [math]::Round($os.FreePhysicalMemory     / 1024, 0)
$usedMB  = $totalMB - $freeMB
$usedPct = if ($totalMB -gt 0) { [math]::Round(($usedMB / $totalMB) * 100, 1) } else { 0 }

$top = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $TopN |
       ForEach-Object { "{0}({1}MB)" -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB, 0) }
$topStr = ($top -join ',')
if (-not $topStr) { $topStr = 'none' }

$status = 'ok'
if     ($usedPct -ge $CritPercent) { $status = 'critical'; $exit = 2 }
elseif ($usedPct -ge $WarnPercent) { $status = 'warn';     $exit = 1 }

Write-Host ("RESULT|host={0}|totalMB={1}|usedMB={2}|usedPct={3}|top{4}WS={5}|status={6}" -f `
    $env:COMPUTERNAME, $totalMB, $usedMB, $usedPct, $TopN, $topStr, $status)
exit $exit
