<#
.SYNOPSIS
Measures CPU utilisation over a sampling window and reports top consumers.

.DESCRIPTION
Samples '\Processor(_Total)\% Processor Time' once per second over -SampleSeconds
intervals and averages the result. Also lists the top processes by accumulated CPU
time at sample end. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [int] $SampleSeconds = 5,
    [int] $WarnPercent   = 85,
    [int] $CritPercent   = 95,
    [int] $TopN          = 3
)

$exit = 0

try {
    $samples = Get-Counter -Counter '\Processor(_Total)\% Processor Time' `
                           -SampleInterval 1 -MaxSamples $SampleSeconds -ErrorAction Stop
    $avg = [math]::Round(($samples.CounterSamples | Measure-Object CookedValue -Average).Average, 1)
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$top = Get-Process | Where-Object { $_.CPU } |
       Sort-Object CPU -Descending | Select-Object -First $TopN |
       ForEach-Object { "{0}({1:N1}s)" -f $_.ProcessName, $_.CPU }
$topStr = ($top -join ',')
if (-not $topStr) { $topStr = 'none' }

$status = 'ok'
if     ($avg -ge $CritPercent) { $status = 'critical'; $exit = 2 }
elseif ($avg -ge $WarnPercent) { $status = 'warn';     $exit = 1 }

Write-Host ("RESULT|host={0}|cpuAvgPct={1}|sampleSec={2}|top{3}CPU={4}|status={5}" -f `
    $env:COMPUTERNAME, $avg, $SampleSeconds, $TopN, $topStr, $status)
exit $exit
