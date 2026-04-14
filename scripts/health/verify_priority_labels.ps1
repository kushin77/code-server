# Verify all GitHub issues have priority labels

$repo = "kushin77/code-server"
$allIssues = gh issue list -R $repo --state all --limit 300 --json number,title,labels | ConvertFrom-Json

$stats = @{
    "P0" = 0
    "P1" = 0
    "P2" = 0
    "P3" = 0
    "No Priority" = 0
}

foreach ($issue in $allIssues) {
    $hasPriority = $false
    foreach ($label in $issue.labels) {
        if ($label.name -match '^P[0-3]$') {
            $stats[$label.name]++
            $hasPriority = $true
            break
        }
    }
    if (-not $hasPriority) {
        $stats["No Priority"]++
    }
}

Write-Host "════════════════════════════════════════════"
Write-Host "PRIORITY LABEL VERIFICATION REPORT"
Write-Host "════════════════════════════════════════════"
Write-Host "Repository: $repo"
Write-Host ""
Write-Host "Priority Distribution:"
Write-Host "  P0 (Critical): $($stats['P0'])"
Write-Host "  P1 (High): $($stats['P1'])"
Write-Host "  P2 (Medium): $($stats['P2'])"
Write-Host "  P3 (Low): $($stats['P3'])"
Write-Host "  No Priority: $($stats['No Priority'])"
Write-Host ""
Write-Host "Total Issues: $($allIssues.Count)"
$coveragePercent = [Math]::Round((($stats['P0'] + $stats['P1'] + $stats['P2'] + $stats['P3']) / $allIssues.Count) * 100, 1)
Write-Host "Coverage: $coveragePercent%"
Write-Host "════════════════════════════════════════════"

if ($stats["No Priority"] -eq 0) {
    Write-Host "✅ SUCCESS: All issues have priority labels!"
} else {
    Write-Host "❌ INCOMPLETE: $($stats['No Priority']) issues still need priority labels"
}
