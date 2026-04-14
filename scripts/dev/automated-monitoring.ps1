# Automated CI Monitoring & Merge Execution
# Monitors all 3 phases and executes auto-merge when ready

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AUTOMATED CI MONITORING & MERGE SYSTEM" -ForegroundColor Cyan
Write-Host "Started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$checkCount = 0
$maxChecks = 999  # Continue until manual stop
$checkInterval = 30  # seconds

$phase10Merged = $false
$phase9Merged = $false
$phase11Merged = $false

while ($checkCount -lt $maxChecks) {
    $checkCount++
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    Write-Host "[$timestamp] Check #$checkCount - Monitoring CI status..." -ForegroundColor Yellow
    
    # Check Phase 10
    if (-not $phase10Merged) {
        $p10Status = gh pr checks 136 --repo kushin77/code-server 2>&1 | Out-String
        
        if ($p10Status -like "*All checks passed*") {
            Write-Host "✅ PHASE 10: ALL CHECKS PASSED!" -ForegroundColor Green
            Write-Host "⏳ Merging Phase 10 to main..." -ForegroundColor Cyan
            $mergeCmdP10 = gh pr merge 136 --repo kushin77/code-server --merge 2>&1
            Write-Host $mergeCmdP10
            $phase10Merged = $true
            Write-Host "✅ Phase 10 merge executed" -ForegroundColor Green
        } else {
            $pending = ($p10Status | Select-String "pending" | Measure-Object).Count
            $failed = ($p10Status | Select-String "failing" | Measure-Object).Count
            Write-Host "   Phase 10: $pending pending, $failed failing" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   Phase 10: ✅ Already merged" -ForegroundColor Green
    }
    
    # Check Phase 9
    if (-not $phase9Merged) {
        $p9Status = gh pr checks 167 --repo kushin77/code-server 2>&1 | Out-String
        
        if ($p9Status -like "*All checks passed*") {
            Write-Host "✅ PHASE 9: ALL CHECKS PASSED!" -ForegroundColor Green
            Write-Host "⏳ Merging Phase 9 to main..." -ForegroundColor Cyan
            $mergeCmdP9 = gh pr merge 167 --repo kushin77/code-server --merge 2>&1
            Write-Host $mergeCmdP9
            $phase9Merged = $true
            Write-Host "✅ Phase 9 merge executed" -ForegroundColor Green
        } elseif ($p9Status -like "*no checks reported*") {
            Write-Host "   Phase 9: Waiting for CI to queue..." -ForegroundColor Yellow
        } else {
            $pending = ($p9Status | Select-String "pending" | Measure-Object).Count
            $failed = ($p9Status | Select-String "failing" | Measure-Object).Count
            Write-Host "   Phase 9: $pending pending, $failed failing" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   Phase 9: ✅ Already merged" -ForegroundColor Green
    }
    
    # Check Phase 11
    if (-not $phase11Merged -and $phase10Merged) {
        $p11Status = gh pr checks 137 --repo kushin77/code-server 2>&1 | Out-String
        
        if ($p11Status -like "*All checks passed*") {
            Write-Host "✅ PHASE 11: ALL CHECKS PASSED!" -ForegroundColor Green
            Write-Host "⏳ Merging Phase 11 to main..." -ForegroundColor Cyan
            $mergeCmdP11 = gh pr merge 137 --repo kushin77/code-server --merge 2>&1
            Write-Host $mergeCmdP11
            $phase11Merged = $true
            Write-Host "✅ Phase 11 merge executed" -ForegroundColor Green
        } else {
            $pending = ($p11Status | Select-String "pending" | Measure-Object).Count
            $failed = ($p11Status | Select-String "failing" | Measure-Object).Count
            Write-Host "   Phase 11: Waiting for Phase 10 + CI ($pending pending, $failed failing)" -ForegroundColor Yellow
        }
    } elseif ($phase11Merged) {
        Write-Host "   Phase 11: ✅ Already merged" -ForegroundColor Green
    }
    
    # Check if all done
    if ($phase10Merged -and $phase9Merged -and $phase11Merged) {
        Write-Host "`n" -ForegroundColor Green
        Write-Host "✅✅✅ ALL PHASES MERGED TO MAIN ✅✅✅" -ForegroundColor Green
        Write-Host "Timeline: $((Get-Date).ToUniversalTime())" -ForegroundColor Green
        Write-Host "All 3 phases now in production - deployment ready!" -ForegroundColor Green
        break
    }
    
    # Wait before next check
    Write-Host ""
    Start-Sleep -Seconds $checkInterval
}

Write-Host "`nMonitoring session ended at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
