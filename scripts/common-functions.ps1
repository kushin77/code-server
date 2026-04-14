#!/usr/bin/env pwsh
<#
.SYNOPSIS
Shared PowerShell functions for GitHub operations, formatting, and CI automation.
Source this file in all .ps1 scripts to avoid duplication.

.EXAMPLE
. "scripts/common-functions.ps1"
Write-Success "Operation completed"
Get-PRCheckStatus -PRNumber 123 -Repo "kushin77/code-server"

.AUTHOR
GitHub Copilot | April 14, 2026
#>

# ─────────────────────────────────────────────────────────────────────────────
# FORMATTING & OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

# Color codes for terminal output
$script:Colors = @{
    Reset   = "`e[0m"
    Red     = "`e[31m"
    Green   = "`e[32m"
    Yellow  = "`e[33m"
    Blue    = "`e[34m"
    Cyan    = "`e[36m"
    Bold    = "`e[1m"
}

function Write-Success {
    <#
    .SYNOPSIS
    Write success message with green checkmark.
    #>
    param([string]$Message)
    Write-Host "$($Colors.Green)✅ $Message$($Colors.Reset)" -ForegroundColor Green
}

function Write-Error-Colored {
    <#
    .SYNOPSIS
    Write error message with red X.
    #>
    param([string]$Message)
    Write-Host "$($Colors.Red)❌ $Message$($Colors.Reset)" -ForegroundColor Red
}

function Write-Warning-Colored {
    <#
    .SYNOPSIS
    Write warning message with yellow indicator.
    #>
    param([string]$Message)
    Write-Host "$($Colors.Yellow)⚠️  $Message$($Colors.Reset)" -ForegroundColor Yellow
}

function Write-Info-Colored {
    <#
    .SYNOPSIS
    Write info message with blue indicator.
    #>
    param([string]$Message)
    Write-Host "$($Colors.Cyan)ℹ️  $Message$($Colors.Reset)" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────────────────────
# GITHUB API OPERATIONS (Consolidated)
# ─────────────────────────────────────────────────────────────────────────────

function Invoke-GitHubAPI {
    <#
    .SYNOPSIS
    Wrapper for GitHub CLI API calls with error handling.
    
    .PARAMETER Method
    HTTP method (GET, POST, PUT, DELETE, PATCH)
    
    .PARAMETER Endpoint
    API endpoint (e.g., /repos/owner/repo/issues)
    
    .PARAMETER Data
    Request body (optional)
    
    .PARAMETER Raw
    Return raw output instead of JSON
    #>
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [string]$Data,
        [switch]$Raw
    )
    
    $args = @("api", "-X", $Method, $Endpoint)
    
    if ($Data) {
        $args += @("-d", $Data)
    }
    
    try {
        $output = & gh @args 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub API error: $output"
        }
        
        if ($Raw) {
            return $output
        }
        else {
            return $output | ConvertFrom-Json
        }
    }
    catch {
        Write-Error-Colored "API call failed: $($_.Exception.Message)"
        return $null
    }
}

function Get-PRCheckStatus {
    <#
    .SYNOPSIS
    Get the current status of CI checks for a pull request.
    
    .PARAMETER PRNumber
    Pull request number
    
    .PARAMETER Repo
    Repository in format "owner/repo"
    
    .OUTPUTS
    PSCustomObject with properties: status (PASSED/FAILED/RUNNING/ERROR), detail, pending, failed
    #>
    param(
        [int]$PRNumber,
        [string]$Repo
    )
    
    try {
        $output = gh pr checks $PRNumber --repo $Repo 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            return @{ 
                status = "ERROR"
                detail = $output
            }
        }
        
        if ($output -match "All checks passed") {
            return @{ 
                status = "PASSED"
                detail = "All checks passed"
            }
        }
        elseif ($output -match "Some checks failed") {
            return @{ 
                status = "FAILED"
                detail = "Some checks failed"
            }
        }
        else {
            $pending = ($output | Select-String "pending" | Measure-Object).Count
            $failed = ($output | Select-String "failed" | Measure-Object).Count
            return @{ 
                status = "RUNNING"
                detail = "$pending pending, $failed failed"
                pending = $pending
                failed = $failed
            }
        }
    }
    catch {
        return @{ 
            status = "ERROR"
            detail = $_.Exception.Message
        }
    }
}

function Merge-PullRequest {
    <#
    .SYNOPSIS
    Merge a pull request using GitHub CLI.
    
    .PARAMETER PRNumber
    Pull request number
    
    .PARAMETER Repo
    Repository in format "owner/repo"
    
    .PARAMETER Method
    Merge method: merge, squash, rebase (default: merge)
    
    .OUTPUTS
    Boolean - $true if successful, $false otherwise
    #>
    param(
        [int]$PRNumber,
        [string]$Repo,
        [string]$Method = "merge"
    )
    
    Write-Info-Colored "Merging PR #$PRNumber with '$Method' strategy..."
    
    try {
        $result = gh pr merge $PRNumber --repo $Repo --$Method 2>&1
        
        if ($result -match "successfully merged" -or $LASTEXITCODE -eq 0) {
            Write-Success "PR #$PRNumber merged to main"
            return $true
        }
        else {
            Write-Error-Colored "Failed to merge PR #$PRNumber: $result"
            return $false
        }
    }
    catch {
        Write-Error-Colored "Merge error: $($_.Exception.Message)"
        return $false
    }
}

function Get-BranchProtectionRules {
    <#
    .SYNOPSIS
    Retrieve branch protection rules from GitHub API.
    
    .PARAMETER Owner
    Repository owner
    
    .PARAMETER Repo
    Repository name
    
    .PARAMETER Branch
    Branch name (default: main)
    #>
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Branch = "main"
    )
    
    try {
        $rules = Invoke-GitHubAPI -Method GET -Endpoint "repos/$Owner/$Repo/branches/$Branch/protection"
        return $rules
    }
    catch {
        Write-Error-Colored "Failed to get branch protection: $($_.Exception.Message)"
        return $null
    }
}

function Update-BranchProtectionRules {
    <#
    .SYNOPSIS
    Update branch protection rules on GitHub.
    
    .PARAMETER Owner
    Repository owner
    
    .PARAMETER Repo
    Repository name
    
    .PARAMETER Branch
    Branch name
    
    .PARAMETER RulesJSON
    JSON-formatted rules object
    #>
    param(
        [string]$Owner,
        [string]$Repo,
        [string]$Branch = "main",
        [string]$RulesJSON
    )
    
    try {
        $result = Invoke-GitHubAPI -Method PUT -Endpoint "repos/$Owner/$Repo/branches/$Branch/protection" -Data $RulesJSON
        Write-Success "Branch protection updated"
        return $result
    }
    catch {
        Write-Error-Colored "Failed to update branch protection: $($_.Exception.Message)"
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log {
    <#
    .SYNOPSIS
    Write timestamped log message to console and file.
    
    .PARAMETER Message
    Log message
    
    .PARAMETER Level
    Log level: INFO, WARN, ERROR, DEBUG (default: INFO)
    
    .PARAMETER LogFile
    Output log file path
    #>
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile = ".logs/deployment.log"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    
    # Ensure logs directory exists
    if (-not (Test-Path ".logs")) {
        mkdir ".logs" -ErrorAction SilentlyContinue | Out-Null
    }
    
    # Write to console with colors
    switch ($Level) {
        "ERROR" { Write-Error-Colored $formatted }
        "WARN"  { Write-Warning-Colored $formatted }
        "DEBUG" { Write-Host $formatted -ForegroundColor Gray }
        default { Write-Host $formatted }
    }
    
    # Write to file
    Add-Content -Path $LogFile -Value $formatted
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

function Test-RepositoryExists {
    <#
    .SYNOPSIS
    Verify that a GitHub repository is accessible.
    
    .PARAMETER Repo
    Repository in format "owner/repo"
    #>
    param([string]$Repo)
    
    try {
        $result = gh repo view $Repo 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Test-GitHubAuth {
    <#
    .SYNOPSIS
    Verify GitHub CLI authentication status.
    #>
    try {
        $user = gh auth status 2>&1
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Write-Success',
    'Write-Error-Colored',
    'Write-Warning-Colored',
    'Write-Info-Colored',
    'Write-Log',
    'Invoke-GitHubAPI',
    'Get-PRCheckStatus',
    'Merge-PullRequest',
    'Get-BranchProtectionRules',
    'Update-BranchProtectionRules',
    'Test-RepositoryExists',
    'Test-GitHubAuth'
) -Variable @('Colors')
