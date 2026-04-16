#Requires -Version 5.1
<#
.SYNOPSIS
    VSCode Stale Terminal Reaper — manual invocation only.

.DESCRIPTION
    Identifies PowerShell/bash processes that have been idle (no CPU activity)
    for longer than the specified IdleMinutes threshold and prompts the user
    before terminating any of them.

    SAFETY REQUIREMENTS (Issue #448):
    - MANUAL INVOCATION ONLY — never called by automation or CI
    - Always prompts before killing anything
    - Dry-run flag available (-DryRun) for safe preview
    - Never kills the current PowerShell host process

.PARAMETER IdleMinutes
    Processes idle longer than this threshold are flagged. Default: 30.

.PARAMETER DryRun
    If specified, prints candidates but does NOT kill anything.

.EXAMPLE
    # Preview idle processes (no kills):
    .\scripts\vscode-terminal-reaper.ps1 -DryRun

    # Kill processes idle > 20 minutes (with confirmation prompt):
    .\scripts\vscode-terminal-reaper.ps1 -IdleMinutes 20

.NOTES
    Issue: #448 — VSCode Memory Budget & Process Guard
    Safety: Manual invoke only. Prompts required. Never auto-runs.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateRange(1, 1440)]
    [int]$IdleMinutes = 30,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$currentPid = $PID
$cutoffTime = (Get-Date).AddMinutes(-$IdleMinutes)

Write-Host "=== VSCode Terminal Reaper ===" -ForegroundColor Cyan
Write-Host "Timestamp  : $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
Write-Host "Idle cutoff: $IdleMinutes minutes (before $(Get-Date $cutoffTime -Format 'HH:mm:ss'))"
if ($DryRun) {
    Write-Host "Mode       : DRY-RUN (no processes will be killed)" -ForegroundColor Yellow
}
Write-Host ""

# Find pwsh/powershell processes started before the cutoff
$candidates = Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Id -ne $currentPid -and           # Never kill ourselves
        $_.StartTime -lt $cutoffTime -and     # Older than idle threshold
        $_.CPU -lt 1                          # No meaningful CPU activity
    } |
    Sort-Object StartTime

if ($null -eq $candidates -or $candidates.Count -eq 0) {
    Write-Host "✅ No idle terminals found (idle > $IdleMinutes min with CPU < 1s)." -ForegroundColor Green
    Write-Host "   Total pwsh/powershell processes: $((Get-Process -Name pwsh, powershell -ErrorAction SilentlyContinue).Count)"
    exit 0
}

Write-Host "Found $($candidates.Count) candidate process(es) idle > $IdleMinutes minutes:" -ForegroundColor Yellow
Write-Host ""
$candidates | Format-Table -AutoSize @(
    @{Label='PID';     Expression={$_.Id}},
    @{Label='Name';    Expression={$_.Name}},
    @{Label='Started'; Expression={$_.StartTime.ToString('HH:mm:ss')}},
    @{Label='CPU(s)';  Expression={[math]::Round($_.CPU, 1)}},
    @{Label='Mem(MB)'; Expression={[math]::Round($_.WorkingSet64 / 1MB, 1)}}
)

if ($DryRun) {
    Write-Host "DRY-RUN: No processes were killed. Remove -DryRun to enable termination." -ForegroundColor Yellow
    exit 0
}

# Explicit confirmation required — never skip
$confirm = Read-Host "Kill these $($candidates.Count) process(es)? [y/N]"
if ($confirm -ne 'y') {
    Write-Host "Aborted. No processes were killed." -ForegroundColor Green
    exit 0
}

$killed = 0
$failed = 0
foreach ($proc in $candidates) {
    try {
        Stop-Process -Id $proc.Id -Force
        Write-Host "  Killed PID $($proc.Id) ($($proc.Name))" -ForegroundColor Green
        $killed++
    } catch {
        Write-Warning "  Failed to kill PID $($proc.Id): $_"
        $failed++
    }
}

Write-Host ""
Write-Host "Done: $killed killed, $failed failed." -ForegroundColor Cyan
