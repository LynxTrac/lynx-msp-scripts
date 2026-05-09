<#
.SYNOPSIS
Identifies Automatic-start services that are not currently running.

.DESCRIPTION
Reads service definitions via Win32_Service and reports any service with StartMode=Auto
that isn't in the Running state. Skips delayed-auto and a list of known-benign services
that legitimately stop themselves. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [string[]] $Exclude = @(
        'gupdate','MapsBroker','RemoteRegistry','sppsvc','ShellHWDetection',
        'tiledatamodelsvc','WbioSrvc','CDPSvc','edgeupdate','TrustedInstaller',
        'gpsvc'
    )
)

$exit = 0

try {
    $svcs = Get-CimInstance Win32_Service -ErrorAction Stop |
            Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' }
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$svcs = $svcs | Where-Object {
    $name = $_.Name
    if ($Exclude -contains $name) { return $false }
    if ($_.DelayedAutoStart)      { return $false }
    return $true
}

if (-not $svcs -or @($svcs).Count -eq 0) {
    Write-Host ("RESULT|host={0}|stopped=0|status=ok" -f $env:COMPUTERNAME)
    exit 0
}

$details = ($svcs | ForEach-Object { "{0}({1})" -f $_.Name, $_.State }) -join ','
$count   = @($svcs).Count
$status  = if ($count -ge 5) { 'critical' } else { 'warn' }
$exit    = if ($count -ge 5) { 2 }          else { 1 }

Write-Host ("RESULT|host={0}|stopped={1}|services={2}|status={3}" -f `
    $env:COMPUTERNAME, $count, $details, $status)
exit $exit
