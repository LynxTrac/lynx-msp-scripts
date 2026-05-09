<#
.SYNOPSIS
Reports installed antivirus product status, including signature freshness.

.DESCRIPTION
Queries SecurityCenter2 (root\SecurityCenter2 \ AntivirusProduct) for installed AV
products and decodes the productState bitmask. When Defender is present, augments
with Get-MpComputerStatus for signature age and real-time protection. Server SKUs
without SecurityCenter2 fall back to Defender-only reporting.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation, security
#>

[CmdletBinding()]
param(
    [int] $StaleSignatureDays = 7
)

$exit     = 0
$products = @()
$defender = $null

try {
    $av = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName 'AntivirusProduct' -ErrorAction Stop
    foreach ($a in $av) {
        $state = [int]$a.productState
        $b1 = ($state -shr 8)  -band 0xFF   # enabled byte
        $b2 = ($state)         -band 0xFF   # signature byte
        $enabled  = ($b1 -band 0x10) -ne 0
        $upToDate = ($b2 -band 0x10) -eq 0
        $products += [pscustomobject]@{
            Name = $a.displayName; Enabled = $enabled; UpToDate = $upToDate
            State = ('0x{0:X6}' -f $state)
        }
    }
} catch {
    # SecurityCenter2 not available (typical on Server SKUs)
}

if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $sigAge = [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
        $defender = [pscustomobject]@{
            Enabled    = [bool]$mp.AntivirusEnabled
            RealTime   = [bool]$mp.RealTimeProtectionEnabled
            SigAgeDays = $sigAge
        }
    } catch { }
}

if ($products.Count -eq 0 -and -not $defender) {
    Write-Host ("RESULT|host={0}|av=none|status=critical" -f $env:COMPUTERNAME)
    exit 2
}

$rows   = @()
$status = 'ok'

foreach ($p in $products) {
    $rows += ("{0}=enabled:{1};upToDate:{2};state:{3}" -f $p.Name, $p.Enabled, $p.UpToDate, $p.State)
    if (-not $p.Enabled) { $status = 'critical'; $exit = 2 }
    elseif (-not $p.UpToDate -and $status -ne 'critical') {
        $status = 'warn'; if ($exit -lt 1) { $exit = 1 }
    }
}

if ($defender) {
    $rows += ("Defender=enabled:{0};realtime:{1};sigAgeDays:{2}" -f `
        $defender.Enabled, $defender.RealTime, $defender.SigAgeDays)

    if (-not $defender.Enabled -and $products.Count -eq 0) {
        $status = 'critical'; $exit = 2
    }
    if ($defender.SigAgeDays -gt $StaleSignatureDays -and $status -ne 'critical') {
        $status = 'warn'; if ($exit -lt 1) { $exit = 1 }
    }
}

Write-Host ("RESULT|host={0}|products={1}|status={2}" -f $env:COMPUTERNAME, ($rows -join ';'), $status)
exit $exit
