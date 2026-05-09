<#
.SYNOPSIS
Reports BitLocker protection state for each fixed volume.

.DESCRIPTION
Enumerates fixed and OS volumes via Get-BitLockerVolume, reporting protection status,
encryption percentage, encryption method, and the list of key protector types.
Read-only. Compatible with Windows 10/11 and Server 2016+.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation, security
#>

[CmdletBinding()]
param()

if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    Write-Host ("RESULT|host={0}|status=unsupported|message=BitLocker module not available" -f $env:COMPUTERNAME)
    exit 2
}

try {
    $vols = Get-BitLockerVolume -ErrorAction Stop |
            Where-Object { $_.VolumeType -eq 'OperatingSystem' -or $_.VolumeType -eq 'Data' }
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$rows  = New-Object System.Collections.Generic.List[string]
$worst = 'ok'
$exit  = 0

foreach ($v in $vols) {
    $kp = ($v.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ','
    if (-not $kp) { $kp = 'none' }

    $state = switch ("$($v.ProtectionStatus)") {
        'On'  { 'protected' }
        'Off' { 'unprotected' }
        default { 'unknown' }
    }

    if ($v.ProtectionStatus -ne 'On') {
        if ($v.VolumeType -eq 'OperatingSystem') {
            $exit = 2; $worst = 'critical'
        } elseif ($worst -eq 'ok') {
            $exit = 1; $worst = 'warn'
        }
    }

    $rows.Add(("{0}=type:{1};status:{2};enc:{3}%;method:{4};protectors:{5}" -f `
        $v.MountPoint, $v.VolumeType, $state, $v.EncryptionPercentage, $v.EncryptionMethod, $kp))
}

if ($rows.Count -eq 0) {
    Write-Host ("RESULT|host={0}|volumes=none|status=ok" -f $env:COMPUTERNAME)
    exit 0
}

Write-Host ("RESULT|host={0}|volumes={1}|status={2}" -f $env:COMPUTERNAME, ($rows -join ';'), $worst)
exit $exit
