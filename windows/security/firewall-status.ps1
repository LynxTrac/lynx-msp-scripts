<#
.SYNOPSIS
Reports the status of all three Windows Firewall profiles.

.DESCRIPTION
Reads Domain, Private, and Public profile state via Get-NetFirewallProfile and emits an
RMM-friendly summary line. Flags any disabled profile; treats a disabled Public profile
as critical. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation, security
#>

[CmdletBinding()]
param()

if (-not (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
    Write-Host ("RESULT|host={0}|status=unsupported|message=NetSecurity module not available" -f $env:COMPUTERNAME)
    exit 2
}

try {
    $profiles = Get-NetFirewallProfile -ErrorAction Stop
} catch {
    Write-Host ("ERROR|host={0}|message={1}" -f $env:COMPUTERNAME, $_.Exception.Message)
    exit 2
}

$rows     = @()
$disabled = @()

foreach ($p in $profiles) {
    $enabled = [bool]$p.Enabled
    $rows   += ("{0}=enabled:{1};inbound:{2};outbound:{3}" -f `
                $p.Name, $enabled, $p.DefaultInboundAction, $p.DefaultOutboundAction)
    if (-not $enabled) { $disabled += $p.Name }
}

$exit = 0
if ($disabled.Count -eq 0)        { $status = 'ok' }
elseif ($disabled -contains 'Public') { $status = 'critical'; $exit = 2 }
else                              { $status = 'warn'; $exit = 1 }

$disStr = if ($disabled.Count) { $disabled -join ',' } else { 'none' }

Write-Host ("RESULT|host={0}|profiles={1}|disabled={2}|status={3}" -f `
    $env:COMPUTERNAME, ($rows -join ';'), $disStr, $status)
exit $exit
