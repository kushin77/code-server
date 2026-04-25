#!/bin/bash

###############################################################################
# @governance: Network hardcoding audit — detect unauthorized static config
# Purpose: Epic #1536 Phase 1 - Network Hardcoding Audit
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1536 (Network Hardcoding Audit), #1534 (IaC Governance)
#
# Audits the repository for hardcoded network configuration that violates:
# - GOV-002 governance standards (template-driven configuration)
# - FAANG best practices (environment-driven infrastructure)
# - Epic #1536 acceptance criteria (zero hardcoded IPs, zero hardcoded domains)
#
# Detects:
# - Hardcoded IPs: 192.168.168.* (PRIMARY_HOST, REPLICA_HOST, NAS_HOST)
# - Hardcoded domains: kushnir.cloud, *.kushnir.cloud
# - Hardcoded subdomains without variable substitution
#
# Exit codes:
# 0 = No violations (compliant)
# 1 = Violations found (requires remediation)
###############################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/tmp}"
readonly AUDIT_TIMESTAMP="${AUDIT_TIMESTAMP:-$(date +%s)}"
readonly AUDIT_LOG="${AUDIT_LOG:-${AUDIT_LOG_DIR}/network-hardcoding-audit-${AUDIT_TIMESTAMP}.log}"

# Color codes for output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
NC='\033[0m'

# Violation counter
VIOLATION_COUNT=0
VIOLATION_FILES=()

###############################################################################
# Phase 1: Scan for hardcoded IPs
###############################################################################
echo "Phase 1: Scanning for hardcoded IPs (192.168.168.*)" | tee -a "$AUDIT_LOG"

# Files to scan
SCAN_PATHS=(
    "scripts/**/*.sh"
    "terraform/**/*.tf"
    "docker-compose*.yml"
    "Caddyfile*"
    ".github/workflows/**/*.yml"
    "config/**/*.yaml"
    "config/**/*.yml"
)

while IFS= read -r file; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    
    # Skip binary files and common exclusions
    case "$file" in
        *.lock|*.json|node_modules/*|.git/*|.backups/*|htmlcov/*) continue ;;
    esac
    
    # Look for hardcoded IPs that aren't in comments or strings
    if grep -n "192\.168\.168\.[0-9]\+" "$file" 2>/dev/null | grep -v "^\s*#" | grep -v "^\s*//" > /dev/null; then
        VIOLATIONS=$(grep -n "192\.168\.168\.[0-9]\+" "$file" | grep -v "^\s*#" | grep -v "^\s*//")
        if [[ -n "$VIOLATIONS" ]]; then
            echo -e "${RED}[VIOLATION]${NC} Hardcoded IP in: $file" | tee -a "$AUDIT_LOG"
            echo "$VIOLATIONS" | tee -a "$AUDIT_LOG"
            ((VIOLATION_COUNT++))
            VIOLATION_FILES+=("$file")
        fi
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.sh" -o -name "*.tf" -o -name "*.yml" -o -name "*.yaml" -o -name "Caddyfile*" \) -not -path "*/.backups/*" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/htmlcov/*" -not -name "audit-network-hardcoding.sh" -not -name "validate-dns-service-discovery.sh" 2>/dev/null)

###############################################################################
# Phase 2: Scan for hardcoded domains
###############################################################################
echo -e "\nPhase 2: Scanning for hardcoded domains (kushnir.cloud)" | tee -a "$AUDIT_LOG"

while IFS= read -r file; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    
    case "$file" in
        *.lock|*.json|node_modules/*|.git/*|.backups/*|htmlcov/*) continue ;;
    esac
    
    # Look for hardcoded kushnir.cloud that isn't in comments
    if grep -n "kushnir\.cloud" "$file" 2>/dev/null | grep -v "^\s*#" | grep -v "^\s*//" | grep -v "APEX_DOMAIN" > /dev/null; then
        VIOLATIONS=$(grep -n "kushnir\.cloud" "$file" | grep -v "^\s*#" | grep -v "^\s*//" | grep -v "APEX_DOMAIN")
        if [[ -n "$VIOLATIONS" ]]; then
            echo -e "${RED}[VIOLATION]${NC} Hardcoded domain in: $file" | tee -a "$AUDIT_LOG"
            echo "$VIOLATIONS" | tee -a "$AUDIT_LOG"
            ((VIOLATION_COUNT++))
            VIOLATION_FILES+=("$file")
        fi
    fi
done < <(find "$REPO_ROOT" -type f \( -name "*.sh" -o -name "*.tf" -o -name "*.yml" -o -name "*.yaml" -o -name "Caddyfile*" \) -not -path "*/.backups/*" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/htmlcov/*" -not -name "audit-network-hardcoding.sh" -not -name "validate-dns-service-discovery.sh" 2>/dev/null)

###############################################################################
# Phase 3: Verify environment variable usage
###############################################################################
echo -e "\nPhase 3: Verifying environment variable substitution patterns" | tee -a "$AUDIT_LOG"

REQUIRED_ENV_VARS=(
    'PRIMARY_HOST'
    'REPLICA_HOST'
    'NAS_HOST'
    'APEX_DOMAIN'
)

TERRAFORM_PATTERNS_FOUND=0
SHELL_PATTERNS_FOUND=0
COMPOSE_PATTERNS_FOUND=0

for var in "${REQUIRED_ENV_VARS[@]}"; do
    echo "  Checking for \$$var or \${$var} usage..." | tee -a "$AUDIT_LOG"
    
    # Terraform pattern: var.primary_host
    if grep -r "var\\.$(echo $var | tr '[:upper:]' '[:lower:]')" "$REPO_ROOT/terraform" 2>/dev/null | head -1 > /dev/null; then
        ((TERRAFORM_PATTERNS_FOUND++))
    fi
    
    # Shell pattern: $PRIMARY_HOST or ${PRIMARY_HOST}
    if grep -r "\${$var}\|\\\$$var" "$REPO_ROOT/scripts" 2>/dev/null | head -1 > /dev/null; then
        ((SHELL_PATTERNS_FOUND++))
    fi
    
    # Compose pattern: ${PRIMARY_HOST}
    if grep -r "\${$var}" "$REPO_ROOT"/docker-compose*.yml 2>/dev/null | head -1 > /dev/null; then
        ((COMPOSE_PATTERNS_FOUND++))
    fi
done

echo "  ✓ Terraform patterns found: $TERRAFORM_PATTERNS_FOUND/4" | tee -a "$AUDIT_LOG"
echo "  ✓ Shell patterns found: $SHELL_PATTERNS_FOUND/4" | tee -a "$AUDIT_LOG"
echo "  ✓ Compose patterns found: $COMPOSE_PATTERNS_FOUND/4" | tee -a "$AUDIT_LOG"

###############################################################################
# Phase 4: Report summary
###############################################################################
echo -e "\n${YELLOW}========== AUDIT REPORT ==========${NC}" | tee -a "$AUDIT_LOG"
echo "Scan Date: $(date)" | tee -a "$AUDIT_LOG"
echo "Scan Location: $REPO_ROOT" | tee -a "$AUDIT_LOG"
echo "Audit Log: $AUDIT_LOG" | tee -a "$AUDIT_LOG"

if [[ $VIOLATION_COUNT -eq 0 ]]; then
    echo -e "\n${GREEN}✓ COMPLIANT${NC}: No hardcoded network configuration found" | tee -a "$AUDIT_LOG"
    echo "Exit Code: 0" | tee -a "$AUDIT_LOG"
    exit 0
else
    echo -e "\n${RED}✗ VIOLATIONS FOUND: $VIOLATION_COUNT${NC}" | tee -a "$AUDIT_LOG"
    echo "Affected Files:" | tee -a "$AUDIT_LOG"
    
    # Deduplicate and sort violation files
    printf '%s\n' "${VIOLATION_FILES[@]}" | sort -u | while read -r file; do
        echo "  - $file" | tee -a "$AUDIT_LOG"
    done
    
    echo -e "\n${YELLOW}Remediation Steps:${NC}" | tee -a "$AUDIT_LOG"
    echo "1. Replace hardcoded IPs with environment variables:" | tee -a "$AUDIT_LOG"
    echo "   - 192.168.168.31 → \${ONPREM_PRIMARY_IP}" | tee -a "$AUDIT_LOG"
    echo "   - 192.168.168.42 → \${ONPREM_REPLICA_IP}" | tee -a "$AUDIT_LOG"
    echo "   - 192.168.168.56 → \${ONPREM_NAS_IP}" | tee -a "$AUDIT_LOG"
    echo "" | tee -a "$AUDIT_LOG"
    echo "2. Replace hardcoded domains with environment variables:" | tee -a "$AUDIT_LOG"
    echo "   - kushnir.cloud → \${DNS_ZONE}" | tee -a "$AUDIT_LOG"
    echo "   - *.kushnir.cloud → \${SUBDOMAIN}.\${DNS_ZONE}" | tee -a "$AUDIT_LOG"
    echo "" | tee -a "$AUDIT_LOG"
    echo "3. Source Epic #1536 Network Configuration SSOT (_epic-1536-network-config.env)" | tee -a "$AUDIT_LOG"
    echo "4. Verify templates use environment variable substitution" | tee -a "$AUDIT_LOG"
    echo "5. Re-run this script to verify compliance" | tee -a "$AUDIT_LOG"
    
    echo -e "\nExit Code: 1" | tee -a "$AUDIT_LOG"
    exit 1
fi
