# ==============================================================================
# Validate-ConfigSSoT.ps1 - Phase 1 Configuration Consolidation Validation
# Validates master SSOT configurations are in place and no duplicates remain
# Exit Code: 0 = all validation passed | 1 = validation failures found
# ==============================================================================

param(
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

# Counters
$Passed = 0
$Failed = 0
$Warnings = 0

# Helper functions
function Pass {
    param([string]$Message)
    Write-Host "✓ PASS: $Message" -ForegroundColor Green
    $script:Passed++
}

function Fail {
    param([string]$Message)
    Write-Host "✗ FAIL: $Message" -ForegroundColor Red
    $script:Failed++
}

function Warn {
    param([string]$Message)
    Write-Host "⚠ WARN: $Message" -ForegroundColor Yellow
    $script:Warnings++
}

function Info {
    param([string]$Message)
    Write-Host "ℹ INFO: $Message" -ForegroundColor Cyan
}

# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

Write-Host "`n=== Phase 1 Configuration Consolidation Validation ===" -ForegroundColor Cyan
Write-Host ""

# 1. Master Caddyfile SSOT
Write-Host "[1] Validating Master Caddyfile SSOT" -ForegroundColor Cyan
if (Test-Path "Caddyfile") {
    $content = Get-Content -Path "Caddyfile" -Raw
    if ($content -match "security_headers_strict|cache_control|internal_only") {
        Pass "Master Caddyfile exists with consolidation markers"
    } else {
        Warn "Master Caddyfile exists but missing consolidation features"
    }
} else {
    Fail "Master Caddyfile not found"
}

# Check no competing Caddyfile in root
$orphanedCaddyfiles = @("Caddyfile.production", "Caddyfile.dev", "Caddyfile.base", "Caddyfile.new")
$foundOrphans = 0
foreach ($file in $orphanedCaddyfiles) {
    if (Test-Path $file) {
        $foundOrphans++
    }
}

if ($foundOrphans -eq 0) {
    Pass "No orphaned Caddyfile variants in root"
} else {
    Fail "Found $foundOrphans orphaned Caddyfile variants in root directory"
}

# 2. Prometheus Template
Write-Host "`n[2] Validating Prometheus Template" -ForegroundColor Cyan
if (Test-Path "prometheus.tpl") {
    $content = Get-Content -Path "prometheus.tpl" -Raw
    if ($content -match "global:|route:|scrape_configs:") {
        Pass "prometheus.tpl template exists with required sections"
    } else {
        Fail "prometheus.tpl missing required configuration sections"
    }
} else {
    Warn "prometheus.tpl template not found"
}

# Check deprecated prometheus configs archived
$deprecatedFiles = @("prometheus.yml", "prometheus.default.yml", "prometheus-production.yml")
$foundDeprecated = 0
foreach ($file in $deprecatedFiles) {
    if (Test-Path $file) {
        Fail "Deprecated $file still in root (should be archived)"
        $foundDeprecated++
    }
}

if ($foundDeprecated -eq 0) {
    Pass "All deprecated prometheus configs archived"
}

# 3. AlertManager Template
Write-Host "`n[3] Validating AlertManager Template" -ForegroundColor Cyan
if (Test-Path "alertmanager.tpl") {
    $content = Get-Content -Path "alertmanager.tpl" -Raw
    if ($content -match "global:|route:|receivers:") {
        if ($content -match "critical-team|high-team|medium-team|low-team") {
            Pass "alertmanager.tpl template exists with priority-based receivers"
        } else {
            Warn "alertmanager.tpl exists but missing priority-based routing"
        }
    } else {
        Fail "alertmanager.tpl missing required YAML sections"
    }
} else {
    Warn "alertmanager.tpl not found"
}

# 4. Alert Rules Consolidation
Write-Host "`n[4] Validating Alert Rules Consolidation" -ForegroundColor Cyan
if (Test-Path "alert-rules.yml") {
    $content = Get-Content -Path "alert-rules.yml" -Raw
    
    # Check for all required alert groups
    $requiredGroups = @("core_sla_alerts", "production_slos", "gpu_alerts", "nas_alerts", "application_alerts", "system_alerts")
    $groupsFound = 0
    
    foreach ($group in $requiredGroups) {
        if ($content -match "name: $group") {
            $groupsFound++
        }
    }
    
    if ($groupsFound -eq 6) {
        Pass "Master alert-rules.yml contains all 6 alert groups"
    } else {
        Warn "Master alert-rules.yml contains only $groupsFound/6 expected alert groups"
    }
} else {
    Fail "Master alert-rules.yml not found"
}

# Check no duplicate alert-rules in config/
$duplicateAlertRules = 0
if (Test-Path "config/alert-rules.yml") {
    Fail "Duplicate config/alert-rules.yml should be deleted"
    $duplicateAlertRules++
}
if (Test-Path "config/alert-rules-31.yaml") {
    Fail "Duplicate config/alert-rules-31.yaml should be merged and deleted"
    $duplicateAlertRules++
}

if ($duplicateAlertRules -eq 0) {
    Pass "No duplicate alert-rules files in config/"
}

# 5. Docker Compose References
Write-Host "`n[5] Validating Docker Compose References" -ForegroundColor Cyan
if (Test-Path "docker-compose.yml") {
    $content = Get-Content -Path "docker-compose.yml" -Raw
    
    if ($content -match "./alert-rules.yml:/etc/prometheus/alert-rules.yml") {
        Pass "docker-compose.yml references master alert-rules.yml"
    } else {
        Warn "docker-compose.yml may not reference master alert-rules.yml correctly"
    }
    
    if ($content -match "./Caddyfile:") {
        Pass "docker-compose.yml references master Caddyfile"
    } else {
        Warn "docker-compose.yml may not reference master Caddyfile correctly"
    }
} else {
    Warn "docker-compose.yml not found"
}

# 6. Archive Validation
Write-Host "`n[6] Validating Archive Structure" -ForegroundColor Cyan
if (Test-Path ".archived/caddy-variants-historical") {
    $caddyCount = (Get-ChildItem -Path ".archived/caddy-variants-historical" -Filter "Caddyfile*" -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($caddyCount -ge 5) {
        Pass "Archived $caddyCount Caddyfile variants"
    } else {
        Warn "Archived only $caddyCount Caddyfile variants (expected 6+)"
    }
} else {
    Warn ".archived/caddy-variants-historical directory not found"
}

if (Test-Path ".archived/prometheus-variants-historical") {
    $promCount = (Get-ChildItem -Path ".archived/prometheus-variants-historical" -Filter "prometheus*" -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($promCount -ge 3) {
        Pass "Archived $promCount prometheus config variants"
    } else {
        Warn "Archived only $promCount prometheus variants (expected 3+)"
    }
} else {
    Warn ".archived/prometheus-variants-historical directory not found"
}

# 7. Configuration Size Checks
Write-Host "`n[7] Configuration Size & Sanity Checks" -ForegroundColor Cyan
if (Test-Path "Caddyfile") {
    $caddyfileSize = (Get-Content -Path "Caddyfile" | Measure-Object -Line).Lines
    if ($caddyfileSize -gt 50) {
        Pass "Caddyfile consolidated ($caddyfileSize lines)"
    } else {
        Warn "Caddyfile may be incomplete ($caddyfileSize lines)"
    }
}

if (Test-Path "alert-rules.yml") {
    $alertRulesSize = (Get-Content -Path "alert-rules.yml" | Measure-Object -Line).Lines
    if ($alertRulesSize -gt 200) {
        Pass "alert-rules.yml consolidated ($alertRulesSize lines)"
    } else {
        Warn "alert-rules.yml may be incomplete ($alertRulesSize lines)"
    }
}

# ==============================================================================
# SUMMARY
# ==============================================================================

Write-Host ""
Write-Host "=== VALIDATION SUMMARY ===" -ForegroundColor Cyan
Write-Host "  ✓ Passed:  $Passed" -ForegroundColor Green
Write-Host "  ✗ Failed:  $Failed" -ForegroundColor Red
Write-Host "  ⚠ Warnings: $Warnings" -ForegroundColor Yellow
Write-Host ""

if ($Failed -eq 0) {
    Write-Host "Phase 1 Consolidation: ✓ COMPLETE" -ForegroundColor Green
    Write-Host "All configuration consolidation checks passed. Ready for Phase 2-3."
    exit 0
} else {
    Write-Host "Phase 1 Consolidation: ✗ INCOMPLETE" -ForegroundColor Red
    Write-Host "Please address the above failures before proceeding."
    exit 1
}
