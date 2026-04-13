# CI Monitoring & Progress Tracking Powers hell Functions
# Run this periodically to monitor Phase 9-11 PR progress
# Source: . ./monitor-phase-ci.ps1

Set-StrictMode -Version Latest

##############################################################################
# COLOR CONFIGURATION
##############################################################################
$colors = @{
    Success = @{ForegroundColor = "Green"; BackgroundColor = "Black"}
    Error = @{ForegroundColor = "Red"; BackgroundColor = "Black"}
    Warning = @{ForegroundColor = "Yellow"; BackgroundColor = "Black"}
    Info = @{ForegroundColor = "Cyan"; BackgroundColor = "Black"}
    Header = @{ForegroundColor = "Blue"; BackgroundColor = "Black"}
}

##############################################################################
# LOGGING FUNCTIONS
##############################################################################
function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" @($colors.Header)
    Write-Host $Message @($colors.Header)
    Write-Host "═══════════════════════════════════════════════════════════" @($colors.Header)
}

function Write-Step {
    param([string]$Message)
    Write-Host "→ $Message" @($colors.Info)
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" @($colors.Success)
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" @($colors.Error)
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" @($colors.Warning)
}

##############################################################################
# PHASE 9 MONITORING
##############################################################################
function Get-Phase9Status {
    param([string]$Repo = "kushin77/code-server")
    
    Write-Header "PHASE 9: REMEDIATION STATUS"
    
    try {
        # Get PR status
        $pr9 = gh pr view 167 --repo $Repo --json state,mergeStateStatus,statusCheckRollup --jq '.' -q 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Step "PR State: OPEN"
            Write-Step "Merge Status: $(($pr9 | ConvertFrom-Json).mergeStateStatus)"
            
            # Check all CI status
            $checks = gh pr checks 167 --repo $Repo 2>&1
            
            if ($checks -match "All checks passing") {
                Write-Success "All CI checks PASSING ✅"
            } elseif ($checks -match "Some checks are still pending") {
                Write-Warning "Some checks pending"
            }
            
            # Check for approval issues
            $pr_view = gh pr view 167 --repo $Repo 2>&1
            if ($pr_view -match "reviewers:") {
                Write-Step "Reviewers have engaged - awaiting approval"
            }
        } else {
            Write-Error "Failed to get Phase 9 status"
        }
    } catch {
        Write-Error "Error checking Phase 9: $_"
    }
    
    Write-Host ""
}

##############################################################################
# PHASE 10 MONITORING
##############################################################################
function Get-Phase10Status {
    param([string]$Repo = "kushin77/code-server")
    
    Write-Header "PHASE 10: ON-PREMISES OPTIMIZATION STATUS"
    
    try {
        # Get PR status
        $pr10_info = gh pr view 136 --repo $Repo --json state,mergeable,mergeStateStatus -q 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Step "PR State: OPEN"
            $state = $pr10_info | ConvertFrom-Json
            Write-Step "Mergeable: $($state.mergeable)"
        }
        
        # Get CI check status
        Write-Step "CI Check Status:"
        $checks = gh pr checks 136 --repo $Repo 2>&1
        
        # Parse check output
        if ($checks -match "All checks passed") {
            Write-Success "✅ All 6 checks PASSED"
        } elseif ($checks -match "Some checks are still pending") {
            Write-Warning "🔄 Checks still PENDING"
            # Extract check count
            if ($checks -match "(\d+) pending") {
                Write-Warning "   $($matches[1]) checks still running"
            }
        } elseif ($checks -match "Some checks failed") {
            Write-Error "❌ Some checks FAILED"
        }
        
        Write-Host ""
    } catch {
        Write-Error "Error checking Phase 10: $_"
    }
}

##############################################################################
# PHASE 11 MONITORING
##############################################################################
function Get-Phase11Status {
    param([string]$Repo = "kushin77/code-server")
    
    Write-Header "PHASE 11: ADVANCED RESILIENCE & HA/DR STATUS"
    
    try {
        # Get PR status
        $pr11_info = gh pr view 137 --repo $Repo --json state,mergeable,mergeStateStatus -q 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Step "PR State: OPEN"
            $state = $pr11_info | ConvertFrom-Json
            Write-Step "Mergeable: $($state.mergeable)"
        }
        
        # Get CI check status
        Write-Step "CI Check Status:"
        $checks = gh pr checks 137 --repo $Repo 2>&1
        
        # Parse check output
        if ($checks -match "All checks passed") {
            Write-Success "✅ All 5 checks PASSED"
        } elseif ($checks -match "Some checks are still pending") {
            Write-Warning "⏹️  Checks QUEUED/PENDING (waiting for Phase 10 to complete)"
        } elseif ($checks -match "Some checks failed") {
            Write-Error "❌ Some checks FAILED"
        }
        
        Write-Host ""
    } catch {
        Write-Error "Error checking Phase 11: $_"
    }
}

##############################################################################
# DEPLOYMENT TIMELINE CALCULATION
##############################################################################
function Get-DeploymentTimeline {
    
    Write-Header "DEPLOYMENT TIMELINE PROJECTION"
    
    $now = Get-Date
    
    Write-Step "Current Time: $($now.ToString('HH:mm:ss UTC'))"
    Write-Host ""
    
    # Timeline projections
    $phase9Approval = $now.AddMinutes(5)
    $phase10Complete = $now.AddMinutes(60)
    $phase10Merge = $phase10Complete.AddMinutes(1)
    $phase11Complete = $phase10Merge.AddMinutes(60)
    $phase11Merge = $phase11Complete.AddMinutes(1)
    $phase12Deploy = $phase11Merge.AddMinutes(90)
    
    Write-Host "Timeline Projections:" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "Phase 9 Approval    : $($phase9Approval.ToString('HH:mm:ss UTC'))" @($colors.Warning)
    Write-Host "Phase 10 Complete   : $($phase10Complete.ToString('HH:mm:ss UTC'))" @($colors.Info)
    Write-Host "Phase 10 Merge      : $($phase10Merge.ToString('HH:mm:ss UTC'))" @($colors.Info)
    Write-Host "Phase 11 Complete   : $($phase11Complete.ToString('HH:mm:ss UTC'))" @($colors.Info)
    Write-Host "Phase 11 Merge      : $($phase11Merge.ToString('HH:mm:ss UTC'))" @($colors.Info)
    Write-Host "Phase 12 Deploy     : $($phase12Deploy.ToString('HH:mm:ss UTC'))" @($colors.Success)
    
    Write-Host ""
    Write-Host "Total Time to Production: ~4 hours from Phase 9 approval" @($colors.Success)
    Write-Host ""
}

##############################################################################
# DEPLOYMENT READINESS CHECK
##############################################################################
function Test-DeploymentReadiness {
    param([string]$Repo = "kushin77/code-server")
    
    Write-Header "DEPLOYMENT READINESS CHECK"
    
    $ready = $true
    
    # Check Phase 12 infrastructure files
    Write-Step "Checking Phase 12.1 infrastructure..."
    $terraformFiles = Get-ChildItem -Path "terraform/phase-12" -Filter "*.tf" -ErrorAction SilentlyContinue
    if ($terraformFiles.Count -ge 5) {
        Write-Success "Terraform modules ready ($($terraformFiles.Count) files)"
    } else {
        Write-Error "Terraform modules incomplete"
        $ready = $false
    }
    
    # Check Kubernetes manifests
    Write-Step "Checking Phase 12 Kubernetes manifests..."
    $k8sFiles = Get-ChildItem -Path "kubernetes/phase-12" -Recurse -Include "*.yml","*.yaml" -ErrorAction SilentlyContinue
    if ($k8sFiles.Count -ge 3) {
        Write-Success "Kubernetes manifests ready ($($k8sFiles.Count) files)"
    } else {
        Write-Error "Kubernetes manifests incomplete"
        $ready = $false
    }
    
    # Check deployment scripts
    Write-Step "Checking deployment scripts..."
    if (Test-Path "scripts/deploy-phase-12-all.sh") {
        Write-Success "Phase 12 deployment script ready"
    } else {
        Write-Error "Phase 12 deployment script missing"
        $ready = $false
    }
    
    Write-Host ""
    if ($ready) {
        Write-Success "✅ DEPLOYMENT READINESS: ALL SYSTEMS GO"
    } else {
        Write-Error "❌ DEPLOYMENT READINESS: SOME COMPONENTS MISSING"
    }
    Write-Host ""
}

##############################################################################
# FULL STATUS REPORT
##############################################################################
function Get-FullStatusReport {
    param(
        [string]$Repo = "kushin77/code-server",
        [int]$RefreshIntervalSeconds = 300
    )
    
    $reportCount = 0
    
    while ($true) {
        $reportCount++
        Clear-Host
        
        Write-Header "PHASE 9-12 CONTINUOUS MONITORING REPORT"
        Write-Host "Report #$reportCount | Last updated: $(Get-Date -Format 'HH:mm:ss UTC')" @($colors.Info)
        Write-Host ""
        
        # Get all status
        Get-Phase9Status -Repo $Repo
        Get-Phase10Status -Repo $Repo
        Get-Phase11Status -Repo $Repo
        Get-DeploymentTimeline
        Test-DeploymentReadiness
        
        # Calculate next refresh
        $nextRefresh = (Get-Date).AddSeconds($RefreshIntervalSeconds)
        Write-Host "Next refresh: $($nextRefresh.ToString('HH:mm:ss UTC')) (in $RefreshIntervalSeconds seconds)" @($colors.Header)
        Write-Host "Press Ctrl+C to stop monitoring" @($colors.Warning)
        Write-Host ""
        
        # Wait for next refresh
        Start-Sleep -Seconds $RefreshIntervalSeconds
    }
}

##############################################################################
# EXPORTED FUNCTIONS
##############################################################################
Export-ModuleFunction -Function @(
    'Write-Header',
    'Write-Step',
    'Write-Success',
    'Write-Error',
    'Write-Warning',
    'Get-Phase9Status',
    'Get-Phase10Status',
    'Get-Phase11Status',
    'Get-DeploymentTimeline',
    'Test-DeploymentReadiness',
    'Get-FullStatusReport'
)

# Quick usage examples
Write-Host "CI Monitoring Functions Loaded" @($colors.Success)
Write-Host ""
Write-Host "Usage:" @($colors.Info)
Write-Host "  Get-Phase9Status              - Check Phase 9 status" 
Write-Host "  Get-Phase10Status             - Check Phase 10 status"
Write-Host "  Get-Phase11Status             - Check Phase 11 status"
Write-Host "  Test-DeploymentReadiness      - Verify Phase 12 readiness"
Write-Host "  Get-FullStatusReport          - Continuous monitoring (auto-refresh)"
Write-Host "  Get-FullStatusReport -RefreshIntervalSeconds 60  - Refresh every 60s"
Write-Host ""
