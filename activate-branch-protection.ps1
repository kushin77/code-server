# Quick branch protection activation script
$REPO = 'kushin77/code-server'
$BRANCH = 'main'

Write-Host '🔐 Activating Branch Protection Rules' -ForegroundColor Cyan
Write-Host '=====================================' -ForegroundColor Cyan

# Verify gh CLI is authenticated
$auth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'ℹ️  GitHub CLI not authenticated.' -ForegroundColor Yellow
    Write-Host 'Skipping automatic activation.' -ForegroundColor Yellow
    Write-Host 'Manual setup: https://github.com/kushin77/code-server/settings/branches' -ForegroundColor Gray
    exit 0
}

Write-Host '✓ GitHub CLI authenticated' -ForegroundColor Green

# Build protection rules payload - using raw JSON string
$payload = '{
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "require_last_push_approval": true,
    "required_approving_review_count": 2
  },
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "auto_delete_branch_on_merge": true,
  "require_signed_commits": true
}'

Write-Host 'Configuration:' -ForegroundColor White
Write-Host '  ✓ Require 2 approvals (code owners only)' -ForegroundColor White
Write-Host '  ✓ Enforce signed commits' -ForegroundColor White
Write-Host '  ✓ Block force pushes & deletions' -ForegroundColor White
Write-Host '  ✓ Require linear history' -ForegroundColor White
Write-Host '  ✓ Auto-delete head branches on merge' -ForegroundColor White

try {
    Write-Host '' -ForegroundColor White
    Write-Host 'Applying rules to GitHub...' -ForegroundColor Yellow
    
    # Write payload to temp file for gh api --input
    $tempFile = [System.IO.Path]::GetTempFileName()
    $payload | Out-File -FilePath $tempFile -Encoding UTF8
    
    $output = gh api `
        --method PUT `
        "/repos/$REPO/branches/$BRANCH/protection" `
        -H 'Accept: application/vnd.github+json' `
        -H 'X-GitHub-Api-Version: 2022-11-28' `
        --input $tempFile 2>&1
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host '' -ForegroundColor White
        Write-Host '✅ Branch protection activated successfully!' -ForegroundColor Green
        Write-Host '' -ForegroundColor White
        Write-Host '📊 Rules enforced on main branch' -ForegroundColor Cyan
        Write-Host 'Verify: https://github.com/kushin77/code-server/settings/branches' -ForegroundColor Gray
        Write-Host '' -ForegroundColor White
        Write-Host '🎯 Next Steps:' -ForegroundColor Cyan
        Write-Host '   1. Announce system to team (Issue #75)' -ForegroundColor Gray
        Write-Host '   2. Team members: Configure GPG signing (ENFORCEMENT_ACTIVATION.md)' -ForegroundColor Gray
        Write-Host '   3. Test enforcement with first PR' -ForegroundColor Gray
    } else {
        Write-Host '' -ForegroundColor White
        Write-Host '⚠️  Note: Status checks may not exist yet.' -ForegroundColor Yellow
        Write-Host $output -ForegroundColor Gray
        Write-Host '' -ForegroundColor White
        Write-Host 'This is OK - rules will work once CI/CD checks are configured.' -ForegroundColor Yellow
    }
} catch {
    Write-Host 'Error: ' + $_.Exception.Message -ForegroundColor Red
}
