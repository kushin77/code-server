# ════════════════════════════════════════════════════════════════════════════
# Phase 22b Batch 4 & 5 Automation (PowerShell): Script & Archive Reorganization
#
# This script automatically:
# 1. Categorizes 273+ shell and PowerShell scripts into 7 categories
# 2. Archives 50+ status documents by date
# 3. Archives phase summaries and GPU attempts
#
# Execution:
#   .\scripts\phase-22-batch-4-5-automation.ps1 -DryRun      # Preview changes
#   .\scripts\phase-22-batch-4-5-automation.ps1 -Execute     # Apply changes
# ════════════════════════════════════════════════════════════════════════════

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('Execute', 'DryRun')]
    [string]$Mode = 'DryRun'
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'Continue'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogFile = Join-Path $ProjectRoot "phase-22-batch-4-5.log"

# Colors
$ColorReset = "`e[0m"
$ColorBlue = "`e[34m"
$ColorGreen = "`e[32m"
$ColorYellow = "`e[33m"
$ColorRed = "`e[31m"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "[$timestamp] $Message"
    Write-Host $output
    Add-Content -Path $LogFile -Value $output
}

function Write-Success {
    param([string]$Message)
    Write-Host "${ColorGreen}✅ $Message${ColorReset}"
    Write-Log $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "${ColorYellow}⚠️  $Message${ColorReset}"
    Write-Log $Message
}

function Write-Error-Log {
    param([string]$Message)
    Write-Host "${ColorRed}❌ ERROR: $Message${ColorReset}"
    Write-Log "ERROR: $Message"
    throw $Message
}

# Initialize log
Write-Log "Phase 22b Batch 4 & 5 Automation (PowerShell)"
Write-Log "Mode = $Mode"
Write-Log "ProjectRoot = $ProjectRoot"

$DryRun = $Mode -eq 'DryRun'

# ─────────────────────────────────────────────────────────────────────────────
# Script Categorization Patterns
# ─────────────────────────────────────────────────────────────────────────────

$patterns = @{
    'install' = 'setup|installer|init|initialize|install'
    'deploy' = 'deploy|rollout|release|promote|migrate'
    'health' = 'health|check|validate|verify|status'
    'maintenance' = 'backup|restore|cleanup|prune|gc'
    'dev' = 'dev|local|debug|test|fix|broken'
    'ci' = 'ci|merge|auto|automation|github|gitlab'
    'lib' = 'common|util|logger|helper|shared'
}

# ─────────────────────────────────────────────────────────────────────────────
# BATCH 4: Script Reorganization
# ─────────────────────────────────────────────────────────────────────────────

Write-Log ""
Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"
Write-Host "${ColorBlue}BATCH 4: Script Reorganization (7 categories)${ColorReset}"
Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"

# Categorize shell and PowerShell scripts
Write-Log ""
Write-Log "Categorizing shell and PowerShell scripts from root..."

$scripts = @(
    Get-ChildItem -Path "$ProjectRoot\*.sh" -File
    Get-ChildItem -Path "$ProjectRoot\*.ps1" -File
)

foreach ($script in $scripts) {
    $basename = $script.Name
    $category = 'other'
    
    # Match against patterns
    foreach ($cat in $patterns.Keys) {
        if ($basename -match $patterns[$cat]) {
            $category = $cat
            break
        }
    }
    
    $destDir = Join-Path $ProjectRoot "scripts\$category"
    $destFile = Join-Path $destDir $basename
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Move $basename → scripts\$category\"
    } else {
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        if (!(Test-Path $destFile)) {
            Move-Item -Path $script.FullName -Destination $destFile
            Write-Success "Moved $basename to scripts\$category\"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BATCH 5: Archive Historical Content
# ─────────────────────────────────────────────────────────────────────────────

Write-Log ""
Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"
Write-Host "${ColorBlue}BATCH 5: Archive Historical Content${ColorReset}"
Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"

# Archive phase summaries
Write-Log ""
Write-Log "Archiving phase summaries..."

$phaseDocs = Get-ChildItem -Path "$ProjectRoot\PHASE-*.md" -File

foreach ($doc in $phaseDocs) {
    $basename = $doc.Name
    # Extract phase number: PHASE-21-observability.md → phase-21
    if ($basename -match 'PHASE-([0-9]+)') {
        $phaseNum = "phase-$($matches[1])"
    } else {
        $phaseNum = "unknown"
    }
    
    $destDir = Join-Path $ProjectRoot "archived\phase-summaries\$phaseNum"
    $destFile = Join-Path $destDir $basename
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Archive $basename → archived\phase-summaries\$phaseNum\"
    } else {
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        if (!(Test-Path $destFile)) {
            Copy-Item -Path $doc.FullName -Destination $destFile
            Write-Success "Archived $basename"
        }
    }
}

# Archive GPU attempts
Write-Log ""
Write-Log "Archiving GPU attempts..."

$gpuDocs = @(
    Get-ChildItem -Path "$ProjectRoot\GPU-*.md" -File -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$ProjectRoot\GPU-*.txt" -File -ErrorAction SilentlyContinue
)

foreach ($doc in $gpuDocs) {
    $basename = $doc.Name
    $destDir = Join-Path $ProjectRoot "archived\gpu-attempts"
    $destFile = Join-Path $destDir $basename
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Archive $basename → archived\gpu-attempts\"
    } else {
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        if (!(Test-Path $destFile)) {
            Copy-Item -Path $doc.FullName -Destination $destFile
            Write-Success "Archived $basename"
        }
    }
}

# Archive execution/status reports (date-organized)
Write-Log ""
Write-Log "Archiving execution and status reports..."

$statusDocs = @(
    Get-ChildItem -Path "$ProjectRoot\EXECUTION-*.md" -File -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$ProjectRoot\FINAL-*.md" -File -ErrorAction SilentlyContinue
    Get-ChildItem -Path "$ProjectRoot\APRIL-*.md" -File -ErrorAction SilentlyContinue
)

foreach ($doc in $statusDocs) {
    $basename = $doc.Name
    
    # Extract date: APRIL-13-*.md → 2026-04-13
    $dateStr = "undated"
    if ($basename -match 'APRIL-([0-9]+)') {
        $dateStr = "2026-04-$($matches[1])"
    }
    
    $destDir = Join-Path $ProjectRoot "archived\status-reports\$dateStr"
    $destFile = Join-Path $destDir $basename
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Archive $basename → archived\status-reports\$dateStr\"
    } else {
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        if (!(Test-Path $destFile)) {
            Copy-Item -Path $doc.FullName -Destination $destFile
            Write-Success "Archived $basename to $dateStr"
        }
    }
}

# Archive old terraform files
Write-Log ""
Write-Log "Archiving old terraform phase files..."

$tfFiles = Get-ChildItem -Path "$ProjectRoot\phase-*.tf" -File -ErrorAction SilentlyContinue

foreach ($tf in $tfFiles) {
    $basename = $tf.Name
    $destDir = Join-Path $ProjectRoot "archived\terraform-backup"
    $destFile = Join-Path $destDir $basename
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Archive $basename → archived\terraform-backup\"
    } else {
        if (!(Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        if (!(Test-Path $destFile)) {
            Copy-Item -Path $tf.FullName -Destination $destFile
            Write-Success "Archived $basename"
        }
    }
}

# Summary
Write-Log ""
Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"

if ($DryRun) {
    Write-Log "DRY RUN COMPLETE — No changes applied"
    Write-Log "Review output above and run with -Execute to apply changes"
} else {
    Write-Success "Batch 4 & 5 Complete!"
    Write-Success "All scripts categorized, all documents archived"
}

Write-Host "${ColorBlue}═══════════════════════════════════════════════════════════════════════════${ColorReset}"
