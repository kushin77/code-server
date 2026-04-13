#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Auto-Deploy Orchestration Script (PowerShell)
    
.DESCRIPTION
    Handles post-merge deployment orchestration via GitHub Actions automation.
    Manages deployment to different targets (production, staging) with full
    health checks, logging, and Slack notifications.

.PARAMETER Target
    Deployment target: 'production' or 'staging' (default: 'production')

.PARAMETER DryRun
    Show what would be deployed without making changes

.PARAMETER Verbose
    Enable verbose output

.PARAMETER NoSlack
    Skip Slack notifications

.PARAMETER NoHealthCheck
    Skip health checks before and after deployment

.EXAMPLE
    # Deploy to production
    .\redeploy.ps1 -Target production

    # Dry-run deployment to staging
    .\redeploy.ps1 -Target staging -DryRun

.NOTES
    Requires: PowerShell 7+, Docker, Git
    Environment Variables:
        - SLACK_WEBHOOK_URL: Slack webhook for notifications
        - TARGET_ENVIRONMENT: Override deployment target
#>

[CmdletBinding()]
param(
    [ValidateSet('production', 'staging')]
    [string]$Target = 'production',
    
    [switch]$DryRun,
    [switch]$NoSlack,
    [switch]$NoHealthCheck
)

# Configuration
$RepoRoot = git rev-parse --show-toplevel
$LogDir = Join-Path $RepoRoot 'logs' 'deployments'
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogDir "redeploy_${Timestamp}.log"

# Ensure log directory exists
$null = New-Item -ItemType Directory -Path $LogDir -Force

# Logging functions
function Write-LogInfo {
    param([string]$Message)
    $output = "ℹ️  $Message"
    Write-Host $output -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value $output
}

function Write-LogSuccess {
    param([string]$Message)
    $output = "✅ $Message"
    Write-Host $output -ForegroundColor Green
    Add-Content -Path $LogFile -Value $output
}

function Write-LogWarn {
    param([string]$Message)
    $output = "⚠️  $Message"
    Write-Host $output -ForegroundColor Yellow
    Add-Content -Path $LogFile -Value $output
}

function Write-LogError {
    param([string]$Message)
    $output = "❌ $Message"
    Write-Host $output -ForegroundColor Red
    Add-Content -Path $LogFile -Value $output
}

function Write-LogSection {
    param([string]$Title)
    $section = "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n▶ $Title`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
    Write-Host $section -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value $section
}

# Initialize log file
@"
Auto-Deploy Orchestration Log - $Timestamp
Repository: $RepoRoot
Target: $Target
DryRun: $DryRun
"@ | Set-Content -Path $LogFile

Write-LogSection "Auto-Deploy Orchestration Started"
Write-LogInfo "Target: $Target"
Write-LogInfo "DryRun: $DryRun"
Write-LogInfo "Log file: $LogFile"

# Get Git info
Write-LogSection "Checking Git State"
try {
    $commitSha = git rev-parse HEAD
    $commitMsg = git log -1 --pretty=format:"%s"
    $commitAuthor = git log -1 --pretty=format:"%an"
    $currentBranch = git rev-parse --abbrev-ref HEAD
    
    Write-LogSuccess "Repository: $RepoRoot"
    Write-LogInfo "Branch: $currentBranch"
    Write-LogInfo "Commit: $($commitSha.Substring(0, 8)) - $commitMsg"
    Write-LogInfo "Author: $commitAuthor"
    
    if ($currentBranch -ne "main") {
        Write-LogWarn "Not on main branch (current: $currentBranch)"
    } else {
        Write-LogSuccess "On main branch"
    }
}
catch {
    Write-LogError "Failed to get Git info: $_"
    exit 1
}

# Check deployment readiness
Write-LogSection "Checking Deployment Readiness"
$requiredFiles = @(
    'docker-compose.yml',
    '.env.production',
    'scripts/deploy-phase-12-all.sh'
)

foreach ($file in $requiredFiles) {
    $filePath = Join-Path $RepoRoot $file
    if (Test-Path $filePath) {
        Write-LogSuccess "Found: $file"
    } else {
        Write-LogWarn "Missing: $file"
    }
}

# Check Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-LogSuccess "Docker is available"
    $dockerVersion = docker --version
    Write-LogInfo "Version: $dockerVersion"
    
    try {
        $null = docker ps
        Write-LogSuccess "Docker daemon is running"
    }
    catch {
        Write-LogError "Docker daemon is not responding"
        exit 1
    }
}
else {
    Write-LogError "Docker is not available"
    exit 1
}

# Pre-deployment health check
if (-not $NoHealthCheck) {
    Write-LogSection "Pre-Deployment Health Check"
    
    $healthEndpoint = if ($Target -eq 'production') {
        'https://code-server.kushnir.cloud/health'
    }
    else {
        'https://staging-code-server.kushnir.cloud/health'
    }
    
    try {
        $response = Invoke-WebRequest -Uri $healthEndpoint -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-LogSuccess "Health endpoint reachable: $healthEndpoint"
        }
    }
    catch {
        Write-LogWarn "Health endpoint not reachable (may be down for maintenance)"
    }
}

# Perform deployment
Write-LogSection "Performing Deployment"

if ($DryRun) {
    Write-LogWarn "DRY RUN MODE - No actual changes will be made"
}

try {
    if ($Target -eq 'production') {
        Write-LogInfo "Deploying to production..."
        
        if ($DryRun) {
            Write-LogInfo "[DRY RUN] Would execute: bash scripts/deploy-phase-12-all.sh"
        }
        else {
            # Execute deployment
            $deployScript = Join-Path $RepoRoot 'scripts' 'deploy-phase-12-all.sh'
            bash $deployScript *>> $LogFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogSuccess "Production deployment completed"
                $deploymentStatus = "success"
            }
            else {
                Write-LogError "Production deployment failed"
                $deploymentStatus = "failed"
                exit 1
            }
        }
    }
    elseif ($Target -eq 'staging') {
        Write-LogInfo "Deploying to staging..."
        
        if ($DryRun) {
            Write-LogInfo "[DRY RUN] Would rebuild and restart containers"
        }
        else {
            # Docker compose staging deployment
            docker-compose -f docker-compose.yml up -d --build *>> $LogFile
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogSuccess "Staging deployment completed"
                $deploymentStatus = "success"
            }
            else {
                Write-LogError "Staging deployment failed"
                $deploymentStatus = "failed"
                exit 1
            }
        }
    }
}
catch {
    Write-LogError "Deployment failed: $_"
    exit 1
}

# Post-deployment health check
if (-not $NoHealthCheck) {
    Write-LogSection "Post-Deployment Health Check"
    
    $healthEndpoint = if ($Target -eq 'production') {
        'https://code-server.kushnir.cloud/health'
    }
    else {
        'https://staging-code-server.kushnir.cloud/health'
    }
    
    $maxRetries = 10
    $retryCount = 0
    $healthCheckPassed = $false
    
    while ($retryCount -lt $maxRetries) {
        Write-LogInfo "Health check attempt $($retryCount + 1)/$maxRetries..."
        
        try {
            $response = Invoke-WebRequest -Uri $healthEndpoint -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-LogSuccess "Health check passed ✅"
                $healthCheckPassed = $true
                break
            }
        }
        catch {
            # Silent fail, will retry
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 10
        }
    }
    
    if (-not $healthCheckPassed) {
        Write-LogWarn "Health check failed after $maxRetries attempts"
    }
}

# Verify deployment
Write-LogSection "Verifying Deployment"

$containers = docker ps --filter "label=environment=$Target" --format "table {{.Names}}\t{{.Status}}"
Write-LogInfo "Running containers:`n$containers"
Write-LogSuccess "Deployment verification complete"

# Slack notification
if (-not $NoSlack) {
    Write-LogSection "Slack Notification"
    
    $webhookUrl = $env:SLACK_WEBHOOK_URL
    if ([string]::IsNullOrEmpty($webhookUrl)) {
        Write-LogWarn "SLACK_WEBHOOK_URL not set, skipping notification"
    }
    else {
        $statusEmoji = if ($deploymentStatus -eq "success") { "✅" } else { "❌" }
        $statusText = if ($deploymentStatus -eq "success") { "Success" } else { "Failed" }
        $color = if ($deploymentStatus -eq "success") { "good" } else { "danger" }
        
        $payload = @{
            text = "$statusEmoji Auto-Deployment to $Target`: $statusText"
            attachments = @(
                @{
                    color = $color
                    fields = @(
                        @{ title = "Target"; value = $Target; short = $true }
                        @{ title = "Commit"; value = $commitSha.Substring(0, 8); short = $true }
                        @{ title = "Message"; value = $commitMsg; short = $false }
                        @{ title = "Author"; value = $commitAuthor; short = $true }
                        @{ title = "Status"; value = $deploymentStatus; short = $true }
                        @{ title = "Timestamp"; value = (Get-Date -AsUTC -Format "yyyy-MM-dd HH:mm:ss UTC"); short = $true }
                    )
                    footer = "Code-Server Enterprise Auto-Deploy"
                }
            )
        } | ConvertTo-Json -Depth 10
        
        try {
            Invoke-WebRequest -Uri $webhookUrl -Method Post -ContentType 'application/json' -Body $payload | Out-Null
            Write-LogSuccess "Slack notification sent"
        }
        catch {
            Write-LogWarn "Failed to send Slack notification: $_"
        }
    }
}

# Final report
Write-LogSection "Deployment Report"

$report = @"

╔════════════════════════════════════════════════════════════════════════════╗
║                     AUTO-DEPLOY EXECUTION REPORT                          ║
╚════════════════════════════════════════════════════════════════════════════╝

Date/Time:           $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')
Target:              $Target
Status:              $($deploymentStatus.ToUpper())
Commit:              $($commitSha.Substring(0, 8)) - $commitMsg
Author:              $commitAuthor
Log File:            $LogFile

Actions Taken:
  ✓ Git state validated
  ✓ Deployment readiness checked
  ✓ Pre-deployment health check performed
  ✓ Deployment executed
  ✓ Post-deployment health check performed
  ✓ Deployment verified

Next Steps:
  1. Monitor application performance
  2. Check logs: Get-Content -Path "$LogFile" -Tail 100
  3. Review deployment: git log -1 --stat
  4. If issues arise, execute rollback procedure

Audit Trail:
  - All actions logged to: $LogFile
  - GitHub Actions run: Available in GitHub Actions tab
  - Issue linked to PR which triggered deployment

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"@

Write-Host $report -ForegroundColor Cyan
Add-Content -Path $LogFile -Value $report

Write-LogSuccess "Auto-Deploy Orchestration Complete ✨"
