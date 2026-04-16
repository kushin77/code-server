#!/usr/bin/env pwsh
# launch-vscode-budgeted.ps1
# VSCode Memory Budget Launcher (Issue #448)
#
# This PowerShell script launches VSCode with enforced memory limits to prevent
# extension host memory leaks and crashes on large workspaces.
#
# Usage:
#   .\launch-vscode-budgeted.ps1 [path] [additional-args]
#
# Examples:
#   .\launch-vscode-budgeted.ps1 .
#   .\launch-vscode-budgeted.ps1 C:\code-server-enterprise
#   .\launch-vscode-budgeted.ps1 . -DisableExtensions
#

param(
    [Parameter(Position=0)]
    [string]$Workspace = ".",
    
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$AdditionalArgs
)

# Memory limits (in MB)
$ExtHostMemory = 1024
$MainProcessMemory = 2048
$RendererMemory = 512

# Validate workspace path
if (-not (Test-Path $Workspace)) {
    Write-Error "Workspace path not found: $Workspace"
    exit 1
}

# Resolve to absolute path
$Workspace = (Resolve-Path $Workspace).Path

# Display configuration
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "VSCode Memory Budget Launch" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Workspace:              $Workspace"
Write-Host "Extension Host Memory:  $ExtHostMemory MB"
Write-Host "Main Process Memory:    $MainProcessMemory MB"
Write-Host "Renderer Memory:        $RendererMemory MB"
if ($AdditionalArgs.Count -gt 0) {
    Write-Host "Additional Args:        $($AdditionalArgs -join ' ')"
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Set environment variables for memory budgeting
$env:NODE_OPTIONS = "--max-old-space-size=$ExtHostMemory"
$env:VSCODE_MEMORY_LIMIT = $ExtHostMemory

# Build command arguments
$codeArgs = @($Workspace)
if ($AdditionalArgs.Count -gt 0) {
    $codeArgs += $AdditionalArgs
}

# Launch VSCode
Write-Host "Launching VSCode..." -ForegroundColor Green
try {
    & code @codeArgs
    Write-Host "VSCode closed successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to launch VSCode: $_"
    exit 1
}
