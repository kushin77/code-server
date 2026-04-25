#!/bin/bash
# @file        audit-network-hardcoding.sh
# @module      scripts/ci
# @description Audit for hardcoded IPs, domains, and network configuration violations
# @governance  GOV-002: Template-driven configuration, env-var substitution
# Issue #1536: Networking, DNS & Performance

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
HARDCODED_IPS=0
HARDCODED_DOMAINS=0
VIOLATIONS=()

echo "🔍 Auditing Repository for Network Hardcoding Violations..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1: Audit for Hardcoded IPs (192.168.168.x)
# ─────────────────────────────────────────────────────────────────────────────

echo "📋 Phase 1: Scanning for hardcoded IPs (192.168.168.x)..."
echo ""

# Scan all relevant file types
SCAN_PATTERNS=(
    "scripts/**/*.sh"
    "terraform/**/*.tf"
    "docker-compose*.yml"
    "Caddyfile"
    "config/caddy/Caddyfile*"
    ".github/workflows/**/*.yml"
)

for pattern in "${SCAN_PATTERNS[@]}"; do
    while IFS= read -r file; do
        if [[ -z "$file" ]] || [[ "$file" == *".md" ]] || [[ "$file" == *"_base-config.env" ]]; then
            continue
        fi
        
        # Search for hardcoded IPs
        if grep -E "192\.168\.168\.(31|42|56)" "$file" >/dev/null 2>&1; then
            # Extract matching lines
            matches=$(grep -nE "192\.168\.168\.(31|42|56)" "$file" 2>/dev/null | grep -v "^#" | head -5)
            if [[ -n "$matches" ]]; then
                echo "  ❌ $file:"
                echo "$matches" | while IFS= read -r line; do
                    echo "     $line"
                    HARDCODED_IPS=$((HARDCODED_IPS + 1))
                    VIOLATIONS+=("Hardcoded IP in $file: $line")
                done
            fi
        fi
    done < <(find . -path .git -prune -o -type f -path "$pattern" -print 2>/dev/null)
done

echo ""
echo "  Hardcoded IP violations found: $HARDCODED_IPS"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2: Audit for Hardcoded Domains
# ─────────────────────────────────────────────────────────────────────────────

echo "📋 Phase 2: Scanning for hardcoded domains (kushnir.cloud)..."
echo ""

for pattern in "${SCAN_PATTERNS[@]}"; do
    while IFS= read -r file; do
        if [[ -z "$file" ]] || [[ "$file" == *".md" ]] || [[ "$file" == *".env" ]]; then
            continue
        fi
        
        # Search for hardcoded domains (exclude comments and APEX_DOMAIN references)
        if grep -E "kushnir\.cloud" "$file" >/dev/null 2>&1; then
            matches=$(grep -nE "kushnir\.cloud" "$file" 2>/dev/null | grep -v "^#" | grep -v "APEX_DOMAIN" | head -5)
            if [[ -n "$matches" ]]; then
                echo "  ❌ $file:"
                echo "$matches" | while IFS= read -r line; do
                    echo "     $line"
                    HARDCODED_DOMAINS=$((HARDCODED_DOMAINS + 1))
                    VIOLATIONS+=("Hardcoded domain in $file: $line")
                done
            fi
        fi
    done < <(find . -path .git -prune -o -type f -path "$pattern" -print 2>/dev/null)
done

echo ""
echo "  Hardcoded domain violations found: $HARDCODED_DOMAINS"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3: Verify Environment Variable Usage
# ─────────────────────────────────────────────────────────────────────────────

echo "📋 Phase 3: Verifying environment variable usage..."
echo ""

echo "  Checking for PRIMARY_HOST references..."
primary_host_refs=$(grep -r "PRIMARY_HOST\|primary_host" scripts/ terraform/ 2>/dev/null | wc -l)
echo "    PRIMARY_HOST references: $primary_host_refs"

echo "  Checking for REPLICA_HOST references..."
replica_host_refs=$(grep -r "REPLICA_HOST\|replica_host" scripts/ terraform/ 2>/dev/null | wc -l)
echo "    REPLICA_HOST references: $replica_host_refs"

echo "  Checking for NAS_HOST references..."
nas_host_refs=$(grep -r "NAS_HOST\|nas_host" scripts/ terraform/ 2>/dev/null | wc -l)
echo "    NAS_HOST references: $nas_host_refs"

echo "  Checking for APEX_DOMAIN references..."
apex_refs=$(grep -r "APEX_DOMAIN\|apex_domain" scripts/ terraform/ docker-compose*.yml Caddyfile* 2>/dev/null | wc -l)
echo "    APEX_DOMAIN references: $apex_refs"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Phase 4: Summary and Recommendations
# ─────────────────────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 AUDIT SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL_VIOLATIONS=$((HARDCODED_IPS + HARDCODED_DOMAINS))

if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}✅ No hardcoding violations detected!${NC}"
    echo "   Repository is compliant with networking standards."
else
    echo -e "${RED}❌ Found $TOTAL_VIOLATIONS violation(s):${NC}"
    echo ""
    echo "Hardcoded IPs: $HARDCODED_IPS"
    echo "Hardcoded Domains: $HARDCODED_DOMAINS"
    echo ""
    echo "Violations:"
    for violation in "${VIOLATIONS[@]}"; do
        echo "  - $violation"
    done
    echo ""
    echo "⚠️  REMEDIATION REQUIRED:"
    echo "  1. Replace hardcoded IPs with \$PRIMARY_HOST, \$REPLICA_HOST, \$NAS_HOST"
    echo "  2. Replace hardcoded domains with \$APEX_DOMAIN and subdomain vars"
    echo "  3. Verify all templates use environment variable substitution"
    echo "  4. Re-run this audit to verify compliance"
fi

echo ""

# Exit with appropriate status
if [[ $TOTAL_VIOLATIONS -gt 0 ]]; then
    exit 1
else
    exit 0
fi
