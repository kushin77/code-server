#!/usr/bin/env pwsh
<#
.SYNOPSIS
CI Completion Monitor & Automatic Merge Executor for Phase 9-11 PRs

.DESCRIPTION
Monitors GitHub Actions CI for PRs #167, #136, #137 and executes merge sequence
when all checks pass. Implements sequential merge: #167 → #136 → #137 → main

.USAGE
./ci-merge-automation.ps1 -Monitor -CheckInterval 30

.AUTHOR
GitHub Copilot | April 13, 2026
#>

param(
    [switch]$Monitor,
    [switch]$Merge,
    [int]$CheckInterval = 30,
    [string]$Repo = "kushin77/code-server"
)

function Get-PRCheckStatus {
    param([int]$PRNumber)
    
    try {
        $output = gh pr checks $PRNumber --repo $Repo 2>&1
        
        if ($output -match "All checks passed") {
            return @{ status = "PASSED"; detail = "All checks passed" }
        }
        elseif ($output -match "Some checks failed") {
            return @{ status = "FAILED"; detail = "Some checks failed" }
        }
        else {
            $pending = ($output | Select-String "pending" | Measure-Object).Count
            $failed = ($output | Select-String "failed" | Measure-Object).Count
            return @{ status = "RUNNING"; detail = "$pending pending, $failed failed"; pending = $pending; failed = $failed }
        }
    }
    catch {
        return @{ status = "ERROR"; detail = $_.Exception.Message }
    }
}

function Merge-PR {
    param([int]$PRNumber)
    
    Write-Host "→ Merging PR #$PRNumber..." -ForegroundColor Cyan
    $result = gh pr merge $PRNumber --repo $Repo --merge 2>&1
    
    if ($result -match "Pull Request successfully merged") {
        Write-Host "✅ PR #$PRNumber merged to main" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "❌ Failed to merge PR #$PRNumber: $result" -ForegroundColor Red
        return $false
    }
}

function Monitor-CI {
    Write-Host "`n========== CI Status Monitor ==========" -ForegroundColor Blue
    Write-Host "Checking PR #167 (Phase 9), #136 (Phase 10), #137 (Phase 11)"
    Write-Host "Check interval: $CheckInterval seconds"
    Write-Host "======================================`n" -ForegroundColor Blue
    
    $iteration = 0
    $allPassed = $false
    
    while ($true) {
        $iteration++
        $timestamp = Get-Date -Format "HH:mm:ss"
        
        Write-Host "[$timestamp] Check #$iteration" -ForegroundColor Yellow
        
        $status167 = Get-PRCheckStatus -PRNumber 167
        $status136 = Get-PRCheckStatus -PRNumber 136
        $status137 = Get-PRCheckStatus -PRNumber 137
        
        Write-Host "  PR #167 (Phase 9):   $($status167.status) - $($status167.detail)"
        Write-Host "  PR #136 (Phase 10):  $($status136.status) - $($status136.detail)"
        Write-Host "  PR #137 (Phase 11):  $($status137.status) - $($status137.detail)"
        
        # Check if all passed
        if ($status167.status -eq "PASSED" -and $status136.status -eq "PASSED" -and $status137.status -eq "PASSED") {
            Write-Host "`n🎉 ALL CI CHECKS PASSED! Ready for merge sequence." -ForegroundColor Green
            $allPassed = $true
            break
        }
        
        # Check for any failures
        if ($status167.status -eq "FAILED" -or $status136.status -eq "FAILED" -or $status137.status -eq "FAILED") {
            Write-Host "`n❌ CI FAILURE DETECTED" -ForegroundColor Red
            if ($status167.status -eq "FAILED") { Write-Host "  → PR #167 failed - check GitHub Actions logs" }
            if ($status136.status -eq "FAILED") { Write-Host "  → PR #136 failed - check GitHub Actions logs" }
            if ($status137.status -eq "FAILED") { Write-Host "  → PR #137 failed - check GitHub Actions logs" }
            break
        }
        
        Write-Host "  → Waiting $CheckInterval seconds for next check...`n"
        Start-Sleep -Seconds $CheckInterval
    }
    
    return $allPassed
}

function Execute-MergeSequence {
    Write-Host "`n========== MERGE SEQUENCE EXECUTION ==========" -ForegroundColor Cyan
    
    Write-Host "`nStep 1: Merge PR #167 (Phase 9) to main"
    if (-not (Merge-PR -PRNumber 167)) {
        Write-Host "❌ Phase 9 merge failed - aborting sequence" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds 5
    
    Write-Host "`nStep 2: Merge PR #136 (Phase 10) to main"
    if (-not (Merge-PR -PRNumber 136)) {
        Write-Host "❌ Phase 10 merge failed - aborting sequence" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds 5
    
    Write-Host "`nStep 3: Merge PR #137 (Phase 11) to main"
    if (-not (Merge-PR -PRNumber 137)) {
        Write-Host "❌ Phase 11 merge failed - aborting sequence" -ForegroundColor Red
        return $false
    }
    
    Write-Host "`n✅ ALL THREE PHASES MERGED TO MAIN!" -ForegroundColor Green
    Write-Host "   Code-server is now production-ready with:"
    Write-Host "   • Phase 9: Operational readiness"
    Write-Host "   • Phase 10: On-premises optimization"
    Write-Host "   • Phase 11: Advanced resilience & HA/DR"
    Write-Host "`n📋 Next: Deploy Phase 12 multi-region federation`n"
    
    return $true
}

# Main execution
if ($Monitor) {
    $ciPassed = Monitor-CI
    
    if ($ciPassed -and $Merge) {
        Write-Host "`n🤖 Auto-executing merge sequence..." -ForegroundColor Cyan
        Execute-MergeSequence
    }
    elseif ($ciPassed) {
        Write-Host "`n→ Run with -Merge flag to execute merge sequence automatically"
    }
}
elseif ($Merge -and (Get-PRCheckStatus -PRNumber 167).status -eq "PASSED") {
    Write-Host "All checks passed - executing merge sequence..."
    Execute-MergeSequence
}
else {
    Write-Host "Usage:"
    Write-Host "  ./ci-merge-automation.ps1 -Monitor                  # Monitor CI until complete"
    Write-Host "  ./ci-merge-automation.ps1 -Monitor -Merge          # Monitor and auto-merge when done"
    Write-Host "  ./ci-merge-automation.ps1 -Merge                   # Execute merge if all CI passed"
    Write-Host ""
    Write-Host "Current Status:"
    $status167 = Get-PRCheckStatus -PRNumber 167
    $status136 = Get-PRCheckStatus -PRNumber 136
    $status137 = Get-PRCheckStatus -PRNumber 137
    Write-Host "  PR #167: $($status167.status)"
    Write-Host "  PR #136: $($status136.status)"
    Write-Host "  PR #137: $($status137.status)"
}
