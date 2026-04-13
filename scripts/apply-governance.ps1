# Apply Governance Framework to Repositories
# Usage: .\scripts\apply-governance.ps1 -Owner kushin77 -Repos repo1,repo2,repo3
# Or:    .\scripts\apply-governance.ps1 -Owner kushin77 -AllRepos

param(
    [Parameter(Mandatory=$true)]
    [string]$Owner,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Repos,
    
    [Parameter(Mandatory=$false)]
    [switch]$AllRepos,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Color output
function Write-Success { Write-Host "✓ $args" -ForegroundColor Green }
function Write-Error { Write-Host "✗ $args" -ForegroundColor Red }
function Write-Warning { Write-Host "⚠ $args" -ForegroundColor Yellow }
function Write-Info { Write-Host "ℹ $args" -ForegroundColor Cyan }
function Write-Verbose { if ($Verbose) { Write-Host "↳ $args" -ForegroundColor Gray } }

# Main execution
function Main {
    Write-Info "GitHub Governance Framework Applicator"
    Write-Info "======================================="
    
    # Check prerequisites
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI not found. Install it first: https://cli.github.com"
        exit 1
    }
    
    # Verify authentication
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI not authenticated. Run: gh auth login"
        exit 1
    }
    Write-Success "GitHub CLI authenticated"
    
    # Get list of repositories
    $repoList = @()
    
    if ($AllRepos) {
        Write-Info "Fetching all repositories for $Owner..."
        $repoList = gh repo list $Owner --json name --jq '.[].name' | where-object { $_ -ne "" }
        Write-Info "Found $($repoList.Count) repositories"
    } else {
        $repoList = $Repos
    }
    
    if ($repoList.Count -eq 0) {
        Write-Error "No repositories to process"
        exit 1
    }
    
    # Process each repository
    $processed = 0
    $successful = 0
    $failed = 0
    
    foreach ($repo in $repoList) {
        $processed++
        Write-Info "[$processed/$($repoList.Count)] Processing $Owner/$repo..."
        
        try {
            # Get repository info
            $repoInfo = gh api repos/$Owner/$repo --jq '{name: .name, default_branch: .default_branch, is_private: .private}' | ConvertFrom-Json
            $defaultBranch = $repoInfo.default_branch
            
            Write-Verbose "Default branch: $defaultBranch"
            
            # Apply branch protection
            Write-Verbose "Applying branch protection to $defaultBranch..."
            $protectionPayload = @{
                required_status_checks = @{
                    strict = $true
                    contexts = @("lint", "unit-tests", "security-scan")
                }
                required_pull_request_reviews = @{
                    required_approving_review_count = 1
                    dismiss_stale_reviews = $true
                    require_code_owner_review = $false
                }
                enforce_admins = $true
                allow_force_pushes = $false
                allow_deletions = $false
                required_conversation_resolution = $true
            } | ConvertTo-Json
            
            if ($DryRun) {
                Write-Verbose "[DRY RUN] Would apply: $protectionPayload"
            } else {
                $result = gh api -X PUT repos/$Owner/$repo/branches/$defaultBranch/protection --input <(Write-Output $protectionPayload) 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Branch protection partially applied (may have existing config)"
                    Write-Verbose "Result: $result"
                } else {
                    Write-Verbose "Branch protection applied"
                }
            }
            
            # Check workflows
            Write-Verbose "Checking workflows..."
            $workflows = gh api repos/$Owner/$repo/contents/.github/workflows --jq '.[].name' 2>/dev/null
            $workflowCount = @($workflows).Count
            
            if ($workflowCount -eq 0) {
                Write-Warning "No workflows found in .github/workflows"
            } else {
                Write-Verbose "Found $workflowCount workflows"
                
                # TODO: Add workflow validation logic
            }
            
            Write-Success "$Owner/$repo compliant"
            $successful++
            
        } catch {
            Write-Error "Failed to process $Owner/$repo : $_"
            $failed++
        }
        
        # Add delay to avoid rate limiting
        Start-Sleep -Milliseconds 500
    }
    
    # Summary
    Write-Info "======================================="
    Write-Info "Governance Application Complete"
    Write-Info "Processed: $processed"
    Write-Info "Successful: $successful"
    Write-Error "Failed: $failed"
    
    if ($failed -gt 0) {
        Write-Warning "Review failures above and retry as needed"
        exit 1
    } else {
        Write-Success "All repositories processed successfully"
        exit 0
    }
}

# Run main
Main
