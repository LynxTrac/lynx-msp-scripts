<#
.SYNOPSIS
Surfaces Error and Critical events in the System and Application logs.

.DESCRIPTION
Reads the named event logs over a configurable lookback window and returns the top
sources/event IDs by frequency. Use to spot recurring drivers, app crashes, or service
failures. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [int]      $Hours = 24,
    [string[]] $Logs  = @('System','Application'),
    [int]      $TopN  = 5
)

$start    = (Get-Date).AddHours(-$Hours)
$exit     = 0
$totalErr = 0
$totalCrit= 0
$bySource = @{}

foreach ($lg in $Logs) {
    try {
        $evts = Get-WinEvent -FilterHashtable @{
            LogName = $lg; Level = 1,2; StartTime = $start
        } -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match 'No events were found') { continue }
        Write-Host ("WARN|host={0}|log={1}|message={2}" -f $env:COMPUTERNAME, $lg, $_.Exception.Message)
        continue
    }
    foreach ($e in $evts) {
        if ($e.Level -eq 1) { $totalCrit++ } else { $totalErr++ }
        $key = "{0}/{1}/{2}" -f $lg, $e.ProviderName, $e.Id
        if (-not $bySource.ContainsKey($key)) { $bySource[$key] = 0 }
        $bySource[$key]++
    }
}

$total = $totalErr + $totalCrit
$top = ($bySource.GetEnumerator() | Sort-Object Value -Descending |
        Select-Object -First $TopN |
        ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ','
if (-not $top) { $top = 'none' }

$status = if ($totalCrit -gt 0)        { $exit = 2; 'critical' }
          elseif ($totalErr -gt 50)    { $exit = 1; 'warn' }
          else                         { 'ok' }

Write-Host ("RESULT|host={0}|hours={1}|errors={2}|critical={3}|total={4}|top{5}={6}|status={7}" -f `
    $env:COMPUTERNAME, $Hours, $totalErr, $totalCrit, $total, $TopN, $top, $status)
exit $exit
