#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $env:DOCKER_CONTEXT) {
    $env:DOCKER_CONTEXT = "desktop-linux"
}
Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

Write-Host "[smoke] Checking container health..."
$services = @("code-server", "oauth2-proxy", "caddy")
foreach ($service in $services) {
    $health = docker.exe inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" $service
    Assert-True ($LASTEXITCODE -eq 0) "[smoke] Service '$service' not found."
    Assert-True (($health -eq "healthy") -or ($health -eq "none")) "[smoke] Service '$service' health is '$health'."
}

Write-Host "[smoke] Verifying required Copilot extensions..."
$extensionsRaw = docker.exe exec code-server sh -lc '/usr/bin/code-server --list-extensions --extensions-dir /home/coder/.local/share/code-server/extensions'
Assert-True ($LASTEXITCODE -eq 0) "[smoke] Failed to list code-server extensions."
$extensions = $extensionsRaw -split "`r?`n"
Assert-True ($extensions -contains "github.copilot") "[smoke] Missing extension: github.copilot"
Assert-True ($extensions -contains "github.copilot-chat") "[smoke] Missing extension: github.copilot-chat"

Write-Host "[smoke] Verifying caddy reset/no-store config is active..."
$caddyConfigLines = docker.exe exec caddy sh -lc 'cat /etc/caddy/Caddyfile'
Assert-True ($LASTEXITCODE -eq 0) "[smoke] Failed to read active Caddyfile."
$caddyConfig = ($caddyConfigLines -join "`n")
Assert-True ($caddyConfig -match "@reset path /reset-browser-state") "[smoke] Missing /reset-browser-state endpoint in Caddy config."
Assert-True ($caddyConfig -match "@stableAssets path /stable-\*") "[smoke] Missing /stable-* cache control matcher in Caddy config."

Write-Host "[smoke] Verifying health endpoint responds..."
$healthResponse = docker.exe exec code-server sh -lc 'curl -fsS http://localhost:8080/healthz'
Assert-True ($LASTEXITCODE -eq 0) "[smoke] code-server /healthz check failed."
Assert-True ($healthResponse -match '"status"') "[smoke] Unexpected /healthz payload."

Write-Host "[smoke] All runtime smoke checks passed."
