<#
.SYNOPSIS
Reports free space across all fixed drives and flags drives under configurable thresholds.

.DESCRIPTION
Enumerates fixed (DriveType=3) volumes via Win32_LogicalDisk, computes free percent and
free GB, and emits an RMM-friendly RESULT line. Returns non-zero when any drive trips
the warning or critical thresholds. Read-only and idempotent.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [int] $WarnPercent     = 15,
    [int] $CriticalPercent = 5,
    [int] $WarnGB          = 10,
    [int] $CriticalGB      = 3,
    [string[]] $Exclude    = @()
)

$exit  = 0
$rows  = New-Object System.Collections.Generic.List[string]
$worst = 'ok'

try {
    $vols = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

foreach ($v in $vols) {
    if ($Exclude -contains $v.DeviceID) { continue }
    if (-not $v.Size -or $v.Size -eq 0) { continue }

    $sizeGB  = [math]::Round($v.Size / 1GB, 2)
    $freeGB  = [math]::Round($v.FreeSpace / 1GB, 2)
    $freePct = [math]::Round(($v.FreeSpace / $v.Size) * 100, 1)

    $state = 'ok'
    if ($freePct -le $CriticalPercent -or $freeGB -le $CriticalGB) {
        $state = 'critical'; $exit = 2
    } elseif ($freePct -le $WarnPercent -or $freeGB -le $WarnGB) {
        $state = 'warn'; if ($exit -lt 1) { $exit = 1 }
    }
    if ($state -eq 'critical') { $worst = 'critical' }
    elseif ($state -eq 'warn' -and $worst -eq 'ok') { $worst = 'warn' }

    $rows.Add(("{0}={1}GB/{2}GB({3}%):{4}" -f $v.DeviceID, $freeGB, $sizeGB, $freePct, $state))
}

if ($rows.Count -eq 0) {
    Write-Host ("RESULT|host={0}|drives=none|status=ok" -f $env:COMPUTERNAME)
    exit 0
}

Write-Host ("RESULT|host={0}|drives={1}|status={2}" -f $env:COMPUTERNAME, ($rows -join ';'), $worst)
exit $exit
