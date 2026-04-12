# Branch Protection Setup Script for kushin77/code-server (PowerShell)
# This script configures the main branch with enterprise-grade protection rules
# REQUIRES: GitHub CLI (gh) installed and authenticated
# RUN: powershell -ExecutionPolicy Bypass -File BRANCH_PROTECTION_SETUP.ps1

param(
    [switch]$Confirm = $false
)

$REPO = "kushin77/code-server"
$BRANCH = "main"

Write-Host "🔐 Branch Protection Configuration - kushin77/code-server" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Check GitHub CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "❌ GitHub CLI (gh) is required but not installed" -ForegroundColor Red
    Write-Host "   Install: https://cli.github.com" -ForegroundColor Yellow
    exit 1
}

# Verify authentication
$authStatus = & gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Not authenticated with GitHub CLI" -ForegroundColor Red
    Write-Host "   Run: gh auth login" -ForegroundColor Yellow
    exit 1
}

# Verify repository access
Write-Host "✓ Verifying repository access..." -ForegroundColor Green
$repoCheck = & gh repo view $REPO 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Cannot access repository $REPO" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Repository verified: $REPO" -ForegroundColor Green
Write-Host ""

# Configure branch protection rule via GitHub API
Write-Host "📋 Configuring branch protection for '$BRANCH' branch..." -ForegroundColor Cyan
Write-Host ""

# Build the API request payload
$payload = @{
    required_status_checks = @{
        strict = $true
        contexts = @(
            "ci-validate",
            "security/dependency-check",
            "security/secret-scan"
        )
    }
    enforce_admins = $true
    required_pull_request_reviews = @{
        dismiss_stale_reviews = $true
        require_code_owner_reviews = $true
        require_last_push_approval = $true
        required_approving_review_count = 2
    }
    restrictions = $null
    required_linear_history = $true
    allow_force_pushes = $false
    allow_deletions = $false
    required_conversation_resolution = $false
    auto_delete_branch_on_merge = $true
    require_signed_commits = $true
} | ConvertTo-Json

Write-Host "📡 Sending configuration to GitHub API..." -ForegroundColor Yellow
Write-Host "   - Require 2 code owner approvals"
Write-Host "   - Enforce signed commits"
Write-Host "   - Block force pushes and deletions"
Write-Host "   - Require linear history"
Write-Host "   - Status checks: ci-validate, security/dependency-check, security/secret-scan"
Write-Host ""

if (-not $Confirm) {
    $response = Read-Host "Continue with branch protection setup? (yes/no)"
    if ($response -ne "yes") {
        Write-Host "❌ Setup cancelled" -ForegroundColor Yellow
        exit 0
    }
}

# Apply via GitHub API REST endpoint
try {
    $output = & gh api `
        --method PUT `
        "/repos/$REPO/branches/$BRANCH/protection" `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        -d $payload 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "API call failed: $output"
    }
    
    Write-Host "✅ Branch protection configured successfully!" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "❌ Failed to configure branch protection" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   This may happen if:" -ForegroundColor Yellow
    Write-Host "   - CI workflow checks don't exist yet (can add later)" -ForegroundColor Yellow
    Write-Host "   - Account permissions insufficient" -ForegroundColor Yellow
    Write-Host "   - Status check contexts not yet created in GitHub" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Manual setup: GitHub Settings → Branches → main → Edit protection rule" -ForegroundColor Yellow
    exit 1
}

Write-Host "📊 Active Protection Rules:" -ForegroundColor Cyan
Write-Host "   ✓ Require 2 approvals (code owners only)" -ForegroundColor Green
Write-Host "   ✓ Require signed commits" -ForegroundColor Green
Write-Host "   ✓ Enforce linear history" -ForegroundColor Green
Write-Host "   ✓ Block force pushes and deletions" -ForegroundColor Green
Write-Host "   ✓ Status checks required (ci-validate, security/*)" -ForegroundColor Green
Write-Host "   ✓ Auto-delete head branches on merge" -ForegroundColor Green
Write-Host ""

Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Set up CI workflow in .github/workflows/ (optional)" -ForegroundColor White
Write-Host "   2. Announce enforcement to team (see Issue #75)" -ForegroundColor White
Write-Host "   3. Configure GPG signing for local development:" -ForegroundColor White
Write-Host "      - gpg --full-generate-key" -ForegroundColor Gray
Write-Host "      - git config --global user.signingkey <KEY_ID>" -ForegroundColor Gray
Write-Host "      - git config --global commit.gpgsign true" -ForegroundColor Gray
Write-Host ""

Write-Host "📖 Reference: .github/BRANCH_PROTECTION.md" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
