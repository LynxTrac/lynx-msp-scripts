<#
.SYNOPSIS
Produces an inventory of installed software from the registry uninstall keys.

.DESCRIPTION
Reads HKLM 32-bit and 64-bit Uninstall hives plus per-user uninstall hives, emitting a
deduplicated list with name, version, publisher, and install date. Output is JSON to
stdout (pipe-friendly) followed by a one-line RESULT summary. Read-only.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation, inventory
#>

[CmdletBinding()]
param(
    [switch] $JsonOnly,
    [string] $OutFile
)

$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# include per-user hives that are currently loaded under HKEY_USERS
Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'S-1-5-21' -and $_.Name -notmatch '_Classes$' } |
    ForEach-Object { $paths += "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Uninstall" }

$items = New-Object System.Collections.Generic.List[object]

foreach ($p in $paths) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    try {
        Get-ChildItem -LiteralPath $p -ErrorAction Stop | ForEach-Object {
            $k = Get-ItemProperty -LiteralPath $_.PsPath -ErrorAction SilentlyContinue
            if (-not $k.DisplayName) { return }
            if ($k.SystemComponent -eq 1) { return }
            if ($k.ParentKeyName)         { return }   # patches / updates
            $items.Add([pscustomobject]@{
                Name        = $k.DisplayName
                Version     = $k.DisplayVersion
                Publisher   = $k.Publisher
                InstallDate = $k.InstallDate
                Hive        = $p
            })
        }
    } catch { }
}

$unique = $items | Sort-Object Name, Version -Unique
$count  = @($unique).Count
$json   = $unique | ConvertTo-Json -Compress -Depth 3

if ($OutFile) {
    try { $json | Set-Content -LiteralPath $OutFile -Encoding UTF8 }
    catch {
        Write-Host ("WARN|host={0}|outFile={1}|message={2}" -f $env:COMPUTERNAME, $OutFile, $_.Exception.Message)
    }
}

if ($JsonOnly) {
    Write-Host $json
} else {
    Write-Host $json
    Write-Host ("RESULT|host={0}|installed={1}|status=ok" -f $env:COMPUTERNAME, $count)
}
exit 0
