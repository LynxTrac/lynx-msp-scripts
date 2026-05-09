<#
.SYNOPSIS
Reclaims disk space on Windows endpoints from safe-to-delete locations and reports results.

.DESCRIPTION
Clears Windows temp folders, user temp folders, Windows Update download cache, CBS logs,
Delivery Optimization cache, ETL traces, prefetch, and the Recycle Bin. Writes a structured
log file and emits a single-line summary on the last stdout line for RMM custom field capture.
Idempotent and safe for unattended execution across large fleets.

.AUTHOR
LynxTrac

.VERSION
1.0

.TAGS
windows, msp, rmm, automation
#>

[CmdletBinding()]
param(
    [switch] $Execute,
    [int]    $AgeDays   = 7,
    [int]    $MinFreeGB = 0,
    [string] $Drive     = $env:SystemDrive,
    [string] $LogRoot   = (Join-Path $env:ProgramData 'MSP\Logs\DiskCleanup')
)

$ErrorActionPreference = 'Continue'
$script:ExitCode       = 0
$script:Reclaimed      = 0L
$script:Buckets        = @{}

# --- bootstrap log file ---------------------------------------------------
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}
$LogFile = Join-Path $LogRoot ("{0}_{1}.log" -f (Get-Date -Format 'yyyy-MM-dd'), $env:COMPUTERNAME)

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')]$Level='INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
    if ($Level -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Level -eq 'WARN') { Write-Host $line -ForegroundColor Yellow }
    else { Write-Host $line }
}

function Get-FreeBytes {
    param([string]$DriveLetter)
    try {
        $d = Get-PSDrive -Name ($DriveLetter.TrimEnd(':','\')) -ErrorAction Stop
        return [int64]$d.Free
    } catch {
        Write-Log "Unable to read free space for $DriveLetter : $($_.Exception.Message)" 'WARN'
        return -1
    }
}

# Walks a path, totals files older than $Cutoff, and deletes them when -Execute is set.
function Clear-PathOlderThan {
    param(
        [string]   $Path,
        [datetime] $Cutoff,
        [string]   $BucketName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Skip [$BucketName]: path not present ($Path)" 'INFO'
        return 0L
    }

    $totalBytes  = 0L
    $failedItems = 0

    try {
        $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Enumeration failed for $Path : $($_.Exception.Message)" 'WARN'
        return 0L
    }

    foreach ($item in $items) {
        if ($item.PSIsContainer) { continue }
        if ($item.LastWriteTime -gt $Cutoff) { continue }

        $size = [int64]$item.Length
        if ($Execute) {
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $totalBytes += $size
            } catch {
                $failedItems++
            }
        } else {
            $totalBytes += $size
        }
    }

    if ($Execute) {
        try {
            Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object {
                    if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }
        } catch { }
    }

    if ($failedItems -gt 0) {
        Write-Log ("[{0}] {1} item(s) could not be deleted (in use / ACL)" -f $BucketName, $failedItems) 'WARN'
        $script:ExitCode = [Math]::Max($script:ExitCode, 1)
    }

    return $totalBytes
}

function Add-Bucket {
    param([string]$Name, [int64]$Bytes)
    $script:Buckets[$Name] = $Bytes
    $script:Reclaimed     += $Bytes
    $mb   = [math]::Round($Bytes / 1MB, 1)
    $verb = if ($Execute) { 'reclaimed' } else { 'would reclaim' }
    Write-Log ("[{0}] {1} {2} MB" -f $Name, $verb, $mb)
}

# --- pre-flight -----------------------------------------------------------
Write-Log "=== Disk Cleanup run started on $env:COMPUTERNAME ==="
$modeLabel = if ($Execute) { 'EXECUTE' } else { 'DRYRUN' }
Write-Log ("Mode={0}  Drive={1}  AgeDays={2}  MinFreeGB={3}" -f $modeLabel, $Drive, $AgeDays, $MinFreeGB)

$preFree = Get-FreeBytes $Drive
if ($preFree -lt 0) {
    Write-Log "Cannot determine free space on $Drive. Aborting." 'ERROR'
    exit 2
}
$preFreeGB = [math]::Round($preFree / 1GB, 2)
Write-Log "Pre-cleanup free space on $Drive : $preFreeGB GB"

if ($MinFreeGB -gt 0 -and $preFreeGB -ge $MinFreeGB) {
    Write-Log "Free space ($preFreeGB GB) already meets threshold ($MinFreeGB GB). Nothing to do."
    Write-Host ("RESULT|host={0}|drive={1}|preGB={2}|postGB={2}|reclaimedMB=0|status=skipped" -f `
        $env:COMPUTERNAME, $Drive, $preFreeGB)
    exit 0
}

$cutoff = (Get-Date).AddDays(-$AgeDays)

# --- 1. Windows Temp ------------------------------------------------------
Add-Bucket 'WinTemp' (Clear-PathOlderThan `
    -Path "$env:SystemRoot\Temp" -Cutoff $cutoff -BucketName 'WinTemp')

# --- 2. Per-user temp folders --------------------------------------------
$userBytes = 0L
try {
    $profileRoot = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' `
                    -ErrorAction Stop).ProfilesDirectory
    if (-not $profileRoot) { $profileRoot = "$env:SystemDrive\Users" }
    $profileRoot = [Environment]::ExpandEnvironmentVariables($profileRoot)

    Get-ChildItem -LiteralPath $profileRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('Default','Default User','Public','All Users') } |
        ForEach-Object {
            $userTemp = Join-Path $_.FullName 'AppData\Local\Temp'
            $userBytes += Clear-PathOlderThan -Path $userTemp -Cutoff $cutoff `
                          -BucketName ("UserTemp:{0}" -f $_.Name)
        }
} catch {
    Write-Log "User temp pass failed: $($_.Exception.Message)" 'WARN'
    $script:ExitCode = [Math]::Max($script:ExitCode, 1)
}
Add-Bucket 'UserTemp' $userBytes

# --- 3. SoftwareDistribution\Download (WU cache) -------------------------
$wuPath      = "$env:SystemRoot\SoftwareDistribution\Download"
$wuStopped   = $false
$bitsStopped = $false
try {
    if ($Execute) {
        if ((Get-Service wuauserv -ErrorAction Stop).Status -eq 'Running') {
            Stop-Service wuauserv -Force -ErrorAction Stop
            $wuStopped = $true
        }
        if ((Get-Service bits -ErrorAction Stop).Status -eq 'Running') {
            Stop-Service bits -Force -ErrorAction Stop
            $bitsStopped = $true
        }
    }
    Add-Bucket 'WindowsUpdateCache' (Clear-PathOlderThan -Path $wuPath -Cutoff $cutoff `
                                     -BucketName 'WindowsUpdateCache')
} catch {
    Write-Log "Skipping WU cache - service control failed: $($_.Exception.Message)" 'WARN'
    $script:ExitCode = [Math]::Max($script:ExitCode, 1)
} finally {
    if ($bitsStopped) {
        try { Start-Service bits -ErrorAction Stop } catch {
            Write-Log "Failed to restart BITS: $($_.Exception.Message)" 'ERROR'
            $script:ExitCode = [Math]::Max($script:ExitCode, 1)
        }
    }
    if ($wuStopped) {
        try { Start-Service wuauserv -ErrorAction Stop } catch {
            Write-Log "Failed to restart wuauserv: $($_.Exception.Message)" 'ERROR'
            $script:ExitCode = [Math]::Max($script:ExitCode, 1)
        }
    }
}

# --- 4. CBS / DISM logs --------------------------------------------------
Add-Bucket 'CBSLogs' (Clear-PathOlderThan -Path "$env:SystemRoot\Logs\CBS" `
    -Cutoff $cutoff -BucketName 'CBSLogs')

# --- 5. Delivery Optimization cache --------------------------------------
Add-Bucket 'DeliveryOptimization' (Clear-PathOlderThan `
    -Path "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization\Cache" `
    -Cutoff $cutoff -BucketName 'DeliveryOptimization')

# --- 6. WER queued reports -----------------------------------------------
Add-Bucket 'WERReports' (Clear-PathOlderThan `
    -Path "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" `
    -Cutoff $cutoff -BucketName 'WERReports')

# --- 7. Prefetch ---------------------------------------------------------
Add-Bucket 'Prefetch' (Clear-PathOlderThan `
    -Path "$env:SystemRoot\Prefetch" -Cutoff $cutoff -BucketName 'Prefetch')

# --- 8. Recycle Bin ------------------------------------------------------
if ($Execute) {
    try {
        $rbBytes = 0L
        $rbPath  = Join-Path $Drive '$Recycle.Bin'
        if (Test-Path -LiteralPath $rbPath) {
            $rbBytes = (Get-ChildItem -LiteralPath $rbPath -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer } |
                        Measure-Object -Sum Length).Sum
        }
        Clear-RecycleBin -DriveLetter ($Drive.TrimEnd(':','\')) -Force -ErrorAction Stop
        Add-Bucket 'RecycleBin' ([int64]$rbBytes)
    } catch {
        Write-Log "Recycle Bin clear failed: $($_.Exception.Message)" 'WARN'
        $script:ExitCode = [Math]::Max($script:ExitCode, 1)
        Add-Bucket 'RecycleBin' 0
    }
} else {
    Add-Bucket 'RecycleBin' 0
}

# --- summary -------------------------------------------------------------
$postFree    = Get-FreeBytes $Drive
$postFreeGB  = if ($postFree -ge 0) { [math]::Round($postFree / 1GB, 2) } else { $preFreeGB }
$reclaimedMB = [math]::Round($script:Reclaimed / 1MB, 1)

Write-Log "Per-bucket breakdown:"
foreach ($k in $script:Buckets.Keys | Sort-Object) {
    Write-Log ("  {0,-22} {1,10:N1} MB" -f $k, ($script:Buckets[$k] / 1MB))
}
Write-Log ("Pre={0} GB  Post={1} GB  Reclaimed={2} MB  Exit={3}" -f `
    $preFreeGB, $postFreeGB, $reclaimedMB, $script:ExitCode)
Write-Log "=== Disk Cleanup run finished ==="

$status = if (-not $Execute)              { 'dryrun' }
          elseif ($script:ExitCode -eq 0) { 'ok' }
          else                            { 'partial' }

Write-Host ("RESULT|host={0}|drive={1}|preGB={2}|postGB={3}|reclaimedMB={4}|status={5}" -f `
    $env:COMPUTERNAME, $Drive, $preFreeGB, $postFreeGB, $reclaimedMB, $status)

exit $script:ExitCode
