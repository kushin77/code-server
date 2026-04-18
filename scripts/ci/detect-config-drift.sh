#!/usr/bin/env bash
# @file        scripts/ci/detect-config-drift.sh
# @module      ci/config-validation
# @description Detect hardcoded config values that violate SSOT (single source of truth)
# @owner       kushnir77
# @status      production

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source common utilities
source "$SCRIPT_DIR/scripts/_common/init.sh"

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

# SSOT files (allowed to have config values)
declare -a SSOT_FILES=(
    ".env"
    ".env.example"
    ".env.defaults"
    ".env.schema.json"
    "terraform/variables.tf"
    "docs/PHASE-2-TASKS-3-4-IMPLEMENTATION.md"
)

# Directory prefixes to skip for domain/IP checks (config definitions, not scripts)
declare -a SKIP_DIRS=(
    "config/"
    "docker/configs/"
    "environments/"
    "scripts/nas-ingress.yaml"
    "alert-rules"
    "alertmanager"
    "k8s/"
    "terraform/"
    "code-server-config.yaml"
    "promtail-config.yml"
    "prometheus-rules"
    "otel-config.yml"
    "loki-config.yml"
    ".github/"
    ".pre-commit-hooks.yaml"
    "scripts/dev/check-config-drift.sh"
    "scripts/ci/detect-config-drift.sh"
    "phase-20-a1-config.yml"
    "docker-compose-phase-"
    "phase-"
)

# Hardcoded patterns to detect (should use env vars instead)
declare -A DRIFT_PATTERNS=(
    ["IP_192_168"]="192\.168\.168\.\d+"
    ["DOMAIN_KUSHNIR"]="kushnir\.cloud"
    ["DOMAIN_INTERNAL"]="prod\.internal"
    ["PORT_9090"]=":9090(?!\")"
    ["PORT_3000"]=":3000(?!\")"
    ["PORT_8080"]=":8080(?!\")"
)

# Files to scan
declare -a SCAN_PATTERNS=(
    "docker-compose*.yml"
    "docker-compose*.yaml"
    "Caddyfile*"
    "scripts/*.sh"
    "scripts/**/*.sh"
    "*.tf"
    "otel-config.yml"
)

# ─────────────────────────────────────────────────────────────────────────────
# Functions
# ─────────────────────────────────────────────────────────────────────────────

is_ssot_file() {
    local file="$1"
    for ssot in "${SSOT_FILES[@]}"; do
        if [[ "$file" == "$ssot" ]]; then
            return 0
        fi
    done
    return 1
}

is_skip_dir() {
    local file="$1"
    for dir in "${SKIP_DIRS[@]}"; do
        if [[ "$file" == "$dir"* ]]; then
            return 0
        fi
    done
    return 1
}

check_hardcoded_ips() {
    local drift_found=0
    
    log_info "Checking for hardcoded IPs (192.168.168.*)..."
    
    # Search for hardcoded IPs
    while IFS= read -r line; do
        local file="${line%%:*}"
        local content
        content=$(echo "$line" | cut -d: -f3-)
        
        # Skip SSOT files and archived directories
        if is_ssot_file "$file" || is_skip_dir "$file" || [[ "$file" =~ archived|_archive ]]; then
            continue
        fi
        
        # Skip comment lines
        if [[ "$content" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Skip lines where IP is already in an env-var default (${VAR:-ip})
        if echo "$line" | grep -qF '${'; then
            continue
        fi
        
        log_warn "  Found hardcoded IP in $file: $content"
        drift_found=1
    done < <(grep -rn "192\.168\.168\." \
        docker-compose.yml \
        docker-compose.production.yml \
        docker-compose.base.yml \
        docker-compose.dev.yml \
        Caddyfile \
        Caddyfile.production \
        2>/dev/null || true)
    
    return $drift_found
}

check_hardcoded_domains() {
    local drift_found=0
    
    log_info "Checking for hardcoded domains (kushnir.cloud, prod.internal)..."
    
    # Search for hardcoded domains
    while IFS= read -r line; do
        local file="${line%%:*}"
        local content
        content=$(echo "$line" | cut -d: -f3-)
        
        # Skip SSOT files and archived directories
        if is_ssot_file "$file" || is_skip_dir "$file" || [[ "$file" =~ archived|_archive ]]; then
            continue
        fi
        
        # Skip comment lines
        if [[ "$content" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Skip lines where domain is already in an env-var default (${VAR:-domain})
        if echo "$line" | grep -qF '${'; then
            continue
        fi
        
        log_warn "  Found hardcoded domain in $file: $content"
        drift_found=1
    done < <(grep -rn "kushnir\.cloud\|prod\.internal" \
        --include="*.yml" \
        --include="*.yaml" \
        --include="*.conf" \
        --include="*.json" \
        --exclude-dir=.git \
        --exclude-dir=archived \
        --exclude-dir=_archive \
        2>/dev/null || true)
    
    return $drift_found
}

check_hardcoded_ports() {
    local drift_found=0
    
    log_info "Checking for hardcoded ports (9090, 3000, 8080)..."
    
    # Search for hardcoded ports in docker-compose and Caddyfile
    while IFS= read -r line; do
        local file="${line%%:*}"
        local content
        content=$(echo "$line" | cut -d: -f3-)
        
        # Skip SSOT files and archived directories
        if is_ssot_file "$file" || is_skip_dir "$file" || [[ "$file" =~ archived|_archive ]]; then
            continue
        fi
        
        # Skip comment lines
        if [[ "$content" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Skip docker-compose port mapping lines ("NNNN:NNNN" format — required syntax)
        if [[ "$content" =~ [0-9]+:[0-9]+ ]] && [[ "$content" =~ ^[[:space:]]*- ]]; then
            continue
        fi
        
        # Skip health check localhost URLs (localhost:port is not hardcoded deployment config)
        if [[ "$content" =~ localhost:[0-9]+ ]]; then
            continue
        fi
        
        # Skip Docker internal service name URLs (e.g. http://prometheus:9090)
        if [[ "$content" =~ http[s]?://[a-z][a-z0-9_-]+:[0-9]+ ]]; then
            continue
        fi
        
        # Skip lines where port is already in an env-var interpolation
        if echo "$line" | grep -qF '${'; then
            continue
        fi
        
        log_warn "  Found hardcoded port in $file: $content"
        drift_found=1
    done < <(grep -rn ":[9308][0908][909][0]" \
        docker-compose*.yml \
        docker-compose*.yaml \
        Caddyfile* \
        --exclude-dir=.git \
        --exclude-dir=archived \
        --exclude-dir=_archive \
        2>/dev/null || true)
    
    return $drift_found
}

check_ssot_integrity() {
    log_info "Checking .env file integrity..."
    
    if [[ ! -f ".env" ]] && [[ ! -f ".env.example" ]] && [[ ! -f ".env.defaults" ]]; then
        log_fatal "No .env, .env.example, or .env.defaults found (SSOT master file required)"
    fi
    
    # Use whichever SSOT file exists
    local env_file=".env"
    [[ ! -f ".env" ]] && env_file=".env.example"
    [[ ! -f ".env.example" ]] && env_file=".env.defaults"
    
    # Verify required variables exist in SSOT
    local required_vars=(
        "DEPLOY_HOST"
        "DOMAIN"
    )
    
    local missing=0
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null; then
            log_warn "Missing variable in $env_file: $var"
            missing=1
        fi
    done
    
    return $missing
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    log_info "Starting config drift detection..."
    
    local total_drift=0
    
    # Run all checks
    check_ssot_integrity || total_drift=$((total_drift + 1))
    check_hardcoded_ips || total_drift=$((total_drift + 1))
    check_hardcoded_domains || total_drift=$((total_drift + 1))
    check_hardcoded_ports || total_drift=$((total_drift + 1))
    
    echo ""
    
    if [[ $total_drift -eq 0 ]]; then
        log_info "✓ No config drift detected (SSOT intact)"
        return 0
    else
        log_fatal "✗ Config drift detected in $total_drift area(s). Use env vars instead of hardcoded values."
    fi
}

main "$@"
