# Priority-Based Issue Management for GitHub Copilot
# =====================================================
# Ensures all issues are created with priority labels and retrieved in priority order

param(
    [ValidateSet('create', 'list', 'next', 'assign', 'prioritize')]
    [string]$Action = 'list',
    
    [string]$Title,
    [string]$Body,
    [ValidateSet('P0', 'P1', 'P2', 'P3')]
    [string]$Priority = 'P1',
    
    [string[]]$Labels = @(),
    [string]$Assignee,
    [string]$Milestone,
    
    [ValidateSet('open', 'closed', 'all')]
    [string]$State = 'open',
    
    [string]$Repo = 'kushin77/code-server',
    [int]$Count = 10
)

# Configuration
$PRIORITY_ORDER = @{ 'P0' = 0; 'P1' = 1; 'P2' = 2; 'P3' = 3 }
$DEFAULT_LABELS = @('prioritized')
$NO_PRIORITY_LABEL = 'needs-priority'

function Get-GithubToken {
    $token = $env:GITHUB_TOKEN
    if ([string]::IsNullOrEmpty($token)) {
        Write-Error "GITHUB_TOKEN environment variable not set"
        exit 1
    }
    return $token
}

function Test-PriorityLabel {
    param([string[]]$Labels)
    
    foreach ($label in $Labels) {
        if ($label -match '^P[0-3]$') {
            return $true
        }
    }
    return $false
}

function Invoke-GithubAPI {
    param(
        [string]$Endpoint,
        [string]$Method = 'GET',
        [object]$Body,
        [string]$Token
    )
    
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Accept' = 'application/vnd.github.v3+json'
        'Content-Type' = 'application/json'
    }
    
    $uri = "https://api.github.com$Endpoint"
    
    if ($Body) {
        $bodyJson = $Body | ConvertTo-Json -Depth 10
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers -Body $bodyJson
    } else {
        return Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
    }
}

function New-PrioritizedIssue {
    param(
        [string]$Title,
        [string]$Body,
        [string]$Priority,
        [string[]]$AdditionalLabels,
        [string]$Assignee,
        [string]$Milestone,
        [string]$Repo,
        [string]$Token
    )
    
    # Validate priority
    if (-not $PRIORITY_ORDER.ContainsKey($Priority)) {
        Write-Error "Invalid priority: $Priority. Use P0, P1, P2, or P3"
        return $null
    }
    
    # Ensure priority label is included
    $allLabels = @($Priority) + @($DEFAULT_LABELS) + @($AdditionalLabels)
    $allLabels = $allLabels | Select-Object -Unique
    
    # Prepare issue body
    $issueBody = @{
        title = $Title
        body = $Body
        labels = $allLabels
    }
    
    if ($Assignee) {
        $issueBody.assignee = $Assignee
    }
    
    if ($Milestone) {
        $issueBody.milestone = $Milestone
    }
    
    # Create issue
    try {
        $issue = Invoke-GithubAPI -Endpoint "/repos/$Repo/issues" -Method 'POST' -Body $issueBody -Token $Token
        Write-Host "✅ Issue created: #$($issue.number)" -ForegroundColor Green
        Write-Host "   Priority: $Priority"
        Write-Host "   Title: $($issue.title)"
        Write-Host "   URL: $($issue.html_url)"
        return $issue
    } catch {
        Write-Error "Failed to create issue: $_"
        return $null
    }
}

function Get-IssuesByPriority {
    param(
        [ValidateSet('P0', 'P1', 'P2', 'P3', 'all')]
        [string]$Priority = 'all',
        
        [ValidateSet('open', 'closed', 'all')]
        [string]$State = 'open',
        
        [string]$Repo,
        [string]$Token,
        [int]$Count = 10
    )
    
    # Build query
    $query = "repo:$Repo is:issue is:$State"
    
    if ($Priority -ne 'all') {
        $query += " label:$Priority"
    } else {
        # Include all priorities
        $query += " (label:P0 OR label:P1 OR label:P2 OR label:P3 OR label:$NO_PRIORITY_LABEL)"
    }
    
    try {
        $searchEndpoint = "/search/issues?q=$query&sort=created&order=desc&per_page=$Count"
        $results = Invoke-GithubAPI -Endpoint $searchEndpoint -Token $Token
        
        $issues = $results.items
        
        # Sort by priority (P0 first)
        $prioritized = @()
        $unprioritized = @()
        
        foreach ($issue in $issues) {
            $hasPriority = $false
            foreach ($label in $issue.labels) {
                if ($label.name -match '^P[0-3]$') {
                    $hasPriority = $true
                    break
                }
            }
            
            if ($hasPriority) {
                $prioritized += $issue
            } else {
                $unprioritized += $issue
            }
        }
        
        # Sort prioritized by priority order
        $prioritized = $prioritized | Sort-Object {
            $priority = 'P3'
            foreach ($label in $_.labels) {
                if ($label.name -match '^P[0-3]$') {
                    $priority = $label.name
                    break
                }
            }
            $PRIORITY_ORDER[$priority]
        } | Select-Object -First $Count
        
        return $prioritized + $unprioritized
        
    } catch {
        Write-Error "Failed to retrieve issues: $_"
        return @()
    }
}

function Get-NextPriorityIssue {
    param(
        [string]$Repo,
        [string]$Token
    )
    
    # Get P0 issues first
    $p0Issues = Get-IssuesByPriority -Priority 'P0' -State 'open' -Repo $Repo -Token $Token -Count 1
    if ($p0Issues.Count -gt 0) {
        return $p0Issues[0]
    }
    
    # Then P1
    $p1Issues = Get-IssuesByPriority -Priority 'P1' -State 'open' -Repo $Repo -Token $Token -Count 1
    if ($p1Issues.Count -gt 0) {
        return $p1Issues[0]
    }
    
    # Then P2
    $p2Issues = Get-IssuesByPriority -Priority 'P2' -State 'open' -Repo $Repo -Token $Token -Count 1
    if ($p2Issues.Count -gt 0) {
        return $p2Issues[0]
    }
    
    # Then P3
    $p3Issues = Get-IssuesByPriority -Priority 'P3' -State 'open' -Repo $Repo -Token $Token -Count 1
    if ($p3Issues.Count -gt 0) {
        return $p3Issues[0]
    }
    
    # Finally unprioritized (flag for immediate prioritization)
    $unprioritized = Get-IssuesByPriority -Priority 'all' -State 'open' -Repo $Repo -Token $Token -Count 5
    $noLabel = $unprioritized | Where-Object { 
        -not ($_.labels | Where-Object { $_.name -match '^P[0-3]$' })
    } | Select-Object -First 1
    
    if ($noLabel) {
        Write-Warning "No properly prioritized issues! Found unprioritized issue:"
        Write-Warning "   #$($noLabel.number): $($noLabel.title)"
        Write-Warning "   ACTION REQUIRED: Add priority label (P0-P3) to this issue"
        return $noLabel
    }
    
    return $null
}

function Set-IssuePriority {
    param(
        [int]$IssueNumber,
        [ValidateSet('P0', 'P1', 'P2', 'P3')]
        [string]$NewPriority,
        [string]$Repo,
        [string]$Token
    )
    
    try {
        # Get current issue
        $issue = Invoke-GithubAPI -Endpoint "/repos/$Repo/issues/$IssueNumber" -Token $Token
        
        # Remove existing priority labels
        $newLabels = @()
        foreach ($label in $issue.labels) {
            if ($label.name -notmatch '^P[0-3]$') {
                $newLabels += $label.name
            }
        }
        
        # Add new priority
        $newLabels += $NewPriority
        
        # Update issue
        $updateBody = @{
            labels = $newLabels
        }
        
        $updated = Invoke-GithubAPI -Endpoint "/repos/$Repo/issues/$IssueNumber" -Method 'PATCH' -Body $updateBody -Token $Token
        
        Write-Host "✅ Issue #$IssueNumber updated" -ForegroundColor Green
        Write-Host "   New priority: $NewPriority"
        Write-Host "   Labels: $($newLabels -join ', ')"
        return $updated
        
    } catch {
        Write-Error "Failed to update issue priority: $_"
        return $null
    }
}

# Main execution
$token = Get-GithubToken

switch ($Action) {
    'create' {
        if ([string]::IsNullOrEmpty($Title)) {
            Write-Error "Title is required for create action"
            exit 1
        }
        
        New-PrioritizedIssue -Title $Title -Body $Body -Priority $Priority -AdditionalLabels $Labels -Assignee $Assignee -Milestone $Milestone -Repo $Repo -Token $token
    }
    
    'list' {
        Write-Host "Issues by Priority [$Repo]" -ForegroundColor Cyan
        Write-Host "=================================" -ForegroundColor Cyan
        
        if ($Priority -eq 'P0' -or $Priority -eq 'all') {
            Write-Host "`n🔴 P0 (Critical)" -ForegroundColor Red
            $p0 = Get-IssuesByPriority -Priority 'P0' -State $State -Repo $Repo -Token $token -Count $Count
            foreach ($issue in $p0) {
                Write-Host "  #$($issue.number): $($issue.title)" -ForegroundColor Red
            }
        }
        
        if ($Priority -eq 'P1' -or $Priority -eq 'all') {
            Write-Host "`n🟠 P1 (High)" -ForegroundColor Yellow
            $p1 = Get-IssuesByPriority -Priority 'P1' -State $State -Repo $Repo -Token $token -Count $Count
            foreach ($issue in $p1) {
                Write-Host "  #$($issue.number): $($issue.title)" -ForegroundColor Yellow
            }
        }
        
        if ($Priority -eq 'P2' -or $Priority -eq 'all') {
            Write-Host "`n🟡 P2 (Medium)" -ForegroundColor Cyan
            $p2 = Get-IssuesByPriority -Priority 'P2' -State $State -Repo $Repo -Token $token -Count $Count
            foreach ($issue in $p2) {
                Write-Host "  #$($issue.number): $($issue.title)" -ForegroundColor Cyan
            }
        }
        
        if ($Priority -eq 'P3' -or $Priority -eq 'all') {
            Write-Host "`n🟢 P3 (Low)" -ForegroundColor Green
            $p3 = Get-IssuesByPriority -Priority 'P3' -State $State -Repo $Repo -Token $token -Count $Count
            foreach ($issue in $p3) {
                Write-Host "  #$($issue.number): $($issue.title)" -ForegroundColor Green
            }
        }
    }
    
    'next' {
        Write-Host "Next Priority Issue:" -ForegroundColor Cyan
        $nextIssue = Get-NextPriorityIssue -Repo $Repo -Token $token
        
        if ($nextIssue) {
            $priority = 'UNSET'
            foreach ($label in $nextIssue.labels) {
                if ($label.name -match '^P[0-3]$') {
                    $priority = $label.name
                    break
                }
            }
            
            Write-Host "  #$($nextIssue.number): $($nextIssue.title)" -ForegroundColor Cyan
            Write-Host "  Priority: $priority"
            Write-Host "  Status: $($nextIssue.state)"
            Write-Host "  URL: $($nextIssue.html_url)"
        } else {
            Write-Host "No open issues found" -ForegroundColor Yellow
        }
    }
    
    'assign' {
        if ([string]::IsNullOrEmpty($Assignee)) {
            Write-Error "Assignee is required for assign action"
            exit 1
        }
        
        $nextIssue = Get-NextPriorityIssue -Repo $Repo -Token $token
        if ($nextIssue) {
            # Assign issue
            $assignBody = @{
                assignees = @($Assignee)
            }
            $assigned = Invoke-GithubAPI -Endpoint "/repos/$Repo/issues/$($nextIssue.number)" -Method 'PATCH' -Body $assignBody -Token $token
            Write-Host "✅ Issue #$($nextIssue.number) assigned to $Assignee" -ForegroundColor Green
        } else {
            Write-Host "No open issues to assign" -ForegroundColor Yellow
        }
    }
    
    'prioritize' {
        if ([string]::IsNullOrEmpty($Title)) {
            Write-Error "Issue number/title is required for prioritize action"
            exit 1
        }
        
        # Title param is actually the issue number in this context
        if ($Title -match '^\d+$') {
            Set-IssuePriority -IssueNumber ([int]$Title) -NewPriority $Priority -Repo $Repo -Token $token
        } else {
            Write-Error "Issue number must be numeric"
            exit 1
        }
    }
    
    default {
        Write-Error "Unknown action: $Action"
        exit 1
    }
}
