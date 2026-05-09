<#
.SYNOPSIS
Detects failed Windows logon attempts within a configurable lookback window.

.DESCRIPTION
Reads Security event log for EventID 4625 (failed logon), groups by target account
and source workstation/IP, and emits an RMM-friendly summary. Tunable warning and
critical thresholds. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation, security
#>

[CmdletBinding()]
param(
    [int] $Hours         = 24,
    [int] $WarnCount     = 10,
    [int] $CriticalCount = 50
)

$exit  = 0
$start = (Get-Date).AddHours(-$Hours)

try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        Id        = 4625
        StartTime = $start
    } -ErrorAction Stop
} catch {
    if ($_.Exception.Message -match 'No events were found') {
        Write-Host ("RESULT|host={0}|hours={1}|total=0|distinctUsers=0|distinctSources=0|status=ok" `
            -f $env:COMPUTERNAME, $Hours)
        exit 0
    }
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$total  = $events.Count
$byUser = @{}
$bySrc  = @{}

foreach ($e in $events) {
    # Property indices for 4625 in modern Windows: 5=TargetUserName, 11=WorkstationName, 19=IpAddress
    $user = $e.Properties[5].Value
    $ip   = $e.Properties[19].Value
    $ws   = $e.Properties[11].Value

    if ($user) {
        if (-not $byUser.ContainsKey($user)) { $byUser[$user] = 0 }
        $byUser[$user]++
    }
    $src = if ($ip -and $ip -ne '-') { $ip } elseif ($ws) { $ws } else { 'unknown' }
    if (-not $bySrc.ContainsKey($src)) { $bySrc[$src] = 0 }
    $bySrc[$src]++
}

$status = if ($total -ge $CriticalCount) { $exit = 2; 'critical' }
          elseif ($total -ge $WarnCount) { $exit = 1; 'warn' }
          else                           { 'ok' }

$topU = ($byUser.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 |
         ForEach-Object { "$($_.Key)($($_.Value))" }) -join ','
$topS = ($bySrc.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3 |
         ForEach-Object { "$($_.Key)($($_.Value))" }) -join ','

if (-not $topU) { $topU = 'none' }
if (-not $topS) { $topS = 'none' }

Write-Host ("RESULT|host={0}|hours={1}|total={2}|distinctUsers={3}|distinctSources={4}|topUsers={5}|topSources={6}|status={7}" `
    -f $env:COMPUTERNAME, $Hours, $total, $byUser.Count, $bySrc.Count, $topU, $topS, $status)
exit $exit
