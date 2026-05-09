<#
.SYNOPSIS
Detects whether the system has a pending reboot from any of the common signals.

.DESCRIPTION
Checks Component Based Servicing, Windows Update, Pending File Renames, ComputerName
change, domain join state, and SCCM client. Returns true if any indicator is set, plus
a comma-separated list of which signals fired. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param()

$reasons = New-Object System.Collections.Generic.List[string]

# 1) CBS reboot pending
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $reasons.Add('CBS')
}

# 2) Windows Update reboot required
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $reasons.Add('WindowsUpdate')
}

# 3) Pending file rename operations
try {
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction Stop
    if ($pfro.PendingFileRenameOperations) { $reasons.Add('PendingFileRename') }
} catch { }

# 4) ComputerName change pending
try {
    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
    if ($active -ne $pending) { $reasons.Add('ComputerNameChange') }
} catch { }

# 5) Pending domain join
try {
    $netlogon = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -ErrorAction Stop
    $names = $netlogon.PSObject.Properties.Name
    if ($names -contains 'JoinDomain' -or $names -contains 'AvoidSpnSet') {
        $reasons.Add('DomainJoin')
    }
} catch { }

# 6) SCCM (Configuration Manager) client pending reboot
try {
    $ccm = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' `
                            -MethodName DetermineIfRebootPending -ErrorAction Stop
    if ($ccm.RebootPending -or $ccm.IsHardRebootPending) { $reasons.Add('SCCM') }
} catch { }

$pending  = $reasons.Count -gt 0
$status   = if ($pending) { 'pending' } else { 'ok' }
$exitCode = if ($pending) { 1 }         else { 0 }

$reasonStr = if ($pending) { ($reasons -join ',') } else { 'none' }

Write-Host ("RESULT|host={0}|pendingReboot={1}|reasons={2}|status={3}" -f `
    $env:COMPUTERNAME, $pending.ToString().ToLower(), $reasonStr, $status)
exit $exitCode
