#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not $env:DOCKER_CONTEXT) {
    $env:DOCKER_CONTEXT = "desktop-linux"
}
Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue

Write-Host "[mandatory-redeploy] Building code-server image..."
docker.exe compose build code-server | Out-Host

Write-Host "[mandatory-redeploy] Recreating stack..."
docker.exe compose up -d --force-recreate code-server oauth2-proxy caddy | Out-Host

Write-Host "[mandatory-redeploy] Waiting for healthy services..."
$services = @("code-server", "oauth2-proxy", "caddy")
$deadline = (Get-Date).AddMinutes(3)

while ((Get-Date) -lt $deadline) {
    $allHealthy = $true
    foreach ($service in $services) {
        $health = docker.exe inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" $service 2>$null
        if ($LASTEXITCODE -ne 0 -or ($health -ne "healthy" -and $health -ne "none")) {
            $allHealthy = $false
            break
        }
    }

    if ($allHealthy) {
        Write-Host "[mandatory-redeploy] All services healthy."
        docker.exe compose ps | Out-Host
        exit 0
    }

    Start-Sleep -Seconds 5
}

Write-Error "[mandatory-redeploy] Timed out waiting for healthy services."
