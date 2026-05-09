<#
.SYNOPSIS
Lints every PowerShell script in the repo (parse + PSScriptAnalyzer).

.DESCRIPTION
Walks the repo for *.ps1 files, runs the PowerShell language parser to catch
syntax errors, then runs PSScriptAnalyzer at Warning and Error severity.
Exits 1 if any file has a parse error or an Error-severity analyzer finding.
Run before committing or rely on CI to enforce.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "Installing PSScriptAnalyzer (CurrentUser scope)..."
    try {
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
    } catch {
        Write-Host "Failed to install PSScriptAnalyzer: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
Import-Module PSScriptAnalyzer

$scripts = Get-ChildItem -Path $repo -Filter *.ps1 -Recurse -File |
           Where-Object { $_.FullName -notmatch '\\\.git\\' }

if (-not $scripts) {
    Write-Host "No PowerShell scripts found under $repo"
    exit 0
}

$failed = 0
foreach ($s in $scripts) {
    $rel = $s.FullName.Substring($repo.Length + 1)
    Write-Host "Linting: $rel"

    # 1) Parse check
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $s.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) {
        Write-Host "  PARSE ERRORS:" -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host ("    L{0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red
        }
        $failed++
        continue
    }

    # 2) PSScriptAnalyzer
    $issues = Invoke-ScriptAnalyzer -Path $s.FullName -Severity Warning,Error
    if ($issues) {
        $hadError = $false
        foreach ($i in $issues) {
            $color = if ($i.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
            if ($i.Severity -eq 'Error') { $hadError = $true }
            Write-Host ("  [{0}] L{1}: {2} - {3}" -f `
                $i.Severity, $i.Line, $i.RuleName, $i.Message) -ForegroundColor $color
        }
        if ($hadError) { $failed++ }
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host "$failed script(s) failed linting" -ForegroundColor Red
    exit 1
}
Write-Host "All scripts passed linting" -ForegroundColor Green
exit 0
