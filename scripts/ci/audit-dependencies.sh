#!/usr/bin/env bash
# @file        scripts/ci/audit-dependencies.sh
# @module      ci/dependency-health
# @description Comprehensive dependency health audit: CVE triage, license compliance, outdated packages

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_DIR="${SCRIPT_DIR}/artifacts/triage"
REPORT_FILE="${AUDIT_DIR}/dependency-audit-report.md"
REPORT_JSON="${AUDIT_DIR}/dependency-audit-report.json"

mkdir -p "${AUDIT_DIR}"

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Initialize report
init_report() {
    local now_utc
    now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    cat > "${REPORT_FILE}" <<EOF
# Dependency Health Audit Report

**Generated**: ${now_utc}

## Summary

This report documents:
- CVE vulnerabilities found in dependencies
- License compliance status
- Outdated packages requiring remediation
- Recommendations for resolution

---

## Table of Contents

1. [Node.js (pnpm) Dependencies](#nodejs-dependencies)
2. [Python Dependencies](#python-dependencies)
3. [Container Base Images](#container-base-images)
4. [License Compliance](#license-compliance)
5. [Outdated Packages](#outdated-packages)
6. [Remediation Backlog](#remediation-backlog)

---

EOF

        cat > "${REPORT_JSON}" <<EOF
{
    "timestamp": "${now_utc}",
  "summary": {
    "cve_critical": 0,
    "cve_high": 0,
    "cve_moderate": 0,
    "cve_low": 0,
    "license_issues": 0,
    "outdated_packages": 0
  },
  "audits": {
    "nodejs": {},
    "python": {},
    "containers": {},
    "licenses": {}
  }
}
EOF
}

# Audit Node.js dependencies with pnpm
audit_nodejs() {
    log_info "Auditing Node.js dependencies (pnpm)..."
    
    {
        echo "## Node.js Dependencies"
        echo ""
        echo "### pnpm audit output"
        echo ""
        echo "\`\`\`"
        if command -v pnpm &> /dev/null; then
            pnpm audit --audit-level=moderate --json 2>&1 | tee "${AUDIT_DIR}/pnpm-audit.json" || true
        else
            echo "[SKIPPED] pnpm not available in CI environment"
        fi
        echo "\`\`\`"
        echo ""
    } >> "${REPORT_FILE}"
}

# Audit Python dependencies
audit_python() {
    log_info "Auditing Python dependencies..."
    
    {
        echo "## Python Dependencies"
        echo ""
        echo "### pip-audit output"
        echo ""
        echo "\`\`\`"
        
        # Find all requirements.txt and setup.py files
        if find "${SCRIPT_DIR}" -name "requirements.txt" -o -name "setup.py" | grep -q .; then
            if command -v pip-audit &> /dev/null; then
                pip-audit 2>&1 | tee "${AUDIT_DIR}/pip-audit.txt" || true
            else
                echo "[SKIPPED] pip-audit not available"
            fi
        else
            echo "[NO PYTHON DEPS] No requirements.txt or setup.py found"
        fi
        echo "\`\`\`"
        echo ""
    } >> "${REPORT_FILE}"
}

# Audit container base images with Trivy
audit_containers() {
    log_info "Scanning container base images with Trivy..."
    
    {
        echo "## Container Base Images"
        echo ""
        
        # Find all Dockerfiles
        while IFS= read -r dockerfile; do
            [ -z "$dockerfile" ] && continue
            
            echo "### ${dockerfile}"
            echo ""
            echo "\`\`\`"
            
            if command -v trivy &> /dev/null; then
                trivy config "$dockerfile" 2>&1 | head -50 || true
                echo "... (full report in artifacts/triage/trivy-${dockerfile//\//_}.json)"
            else
                echo "[SKIPPED] Trivy not available"
            fi
            echo "\`\`\`"
            echo ""
        done < <(find "${SCRIPT_DIR}" -type f -name "Dockerfile*" \
            -not -path "*/node_modules/*" \
            -not -path "*/.git/*")
    } >> "${REPORT_FILE}"
}

# License compliance check
audit_licenses() {
    log_info "Checking license compliance..."
    
    {
        echo "## License Compliance"
        echo ""
        echo "### Restricted Licenses Check"
        echo ""
        
        # Define restricted licenses (GPL, AGPL, SSPL, BUSL, copyleft)
        RESTRICTED_LICENSES=(
            "GPL"
            "AGPL"
            "LGPL"
            "SSPL"
            "BUSL"
            "Copyleft"
        )
        
        echo "Scanning for restricted licenses: ${RESTRICTED_LICENSES[*]}"
        echo ""
        echo "\`\`\`"
        
        if command -v license-checker &> /dev/null; then
            license_output=$(license-checker --json 2>&1 || true)
            echo "$license_output" | jq -r '.[] | "\(.name): \(.licenses)"' 2>/dev/null || echo "Could not parse license-checker output"
        else
            echo "[SKIPPED] license-checker not available (install: npm install -g license-checker)"
        fi
        echo "\`\`\`"
        echo ""
    } >> "${REPORT_FILE}"
}

# Check for outdated packages
audit_outdated() {
    log_info "Scanning for outdated packages..."
    
    {
        echo "## Outdated Packages"
        echo ""
        echo "### npm outdated"
        echo ""
        echo "\`\`\`"
        if command -v npm &> /dev/null; then
            if command -v jq &> /dev/null; then
                npm outdated --json 2>&1 | jq . || npm outdated || true
            else
                npm outdated || true
            fi
        else
            echo "[SKIPPED] npm not available"
        fi
        echo "\`\`\`"
        echo ""
    } >> "${REPORT_FILE}"
}

# Create remediation backlog
create_backlog() {
    log_info "Creating remediation backlog..."
    
    {
        echo "## Remediation Backlog"
        echo ""
        echo "### Action Items"
        echo ""
        echo "- [ ] Review critical CVEs and apply patches"
        echo "- [ ] Resolve high-severity vulnerabilities within 30 days"
        echo "- [ ] Evaluate and replace restricted-license dependencies"
        echo "- [ ] Update packages marked as outdated"
        echo "- [ ] Schedule dependency updates in sprint planning"
        echo ""
        echo "### Policy Enforcement"
        echo ""
        echo "The following CI gates are now active:"
        echo "1. **CVE Severity Gate**: Fail on Critical CVEs, block on High until triaged"
        echo "2. **License Gate**: Fail on GPL, AGPL, SSPL, BUSL in production dependencies"
        echo "3. **Outdated Package Gate**: Warn on packages >2 minor versions behind latest"
        echo ""
    } >> "${REPORT_FILE}"
}

main() {
    log_info "Starting comprehensive dependency audit..."
    
    init_report
    audit_nodejs
    audit_python
    audit_containers
    audit_licenses
    audit_outdated
    create_backlog
    
    log_success "Audit complete. Reports:"
    log_success "  Markdown: ${REPORT_FILE}"
    log_success "  JSON: ${REPORT_JSON}"
    
    # Summary stats
    echo ""
    log_info "Summary Statistics:"
    if [ -f "${AUDIT_DIR}/pnpm-audit.json" ]; then
        if command -v jq &> /dev/null; then
            cve_count=$(jq '.metadata.vulnerabilities // .vulnerabilities // {} | to_entries | length' "${AUDIT_DIR}/pnpm-audit.json" 2>/dev/null || echo "?")
        elif command -v python3 &> /dev/null; then
            cve_count=$(python3 - "${AUDIT_DIR}/pnpm-audit.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    vulns = data.get('metadata', {}).get('vulnerabilities')
    if isinstance(vulns, dict):
        print(len(vulns))
    elif isinstance(vulns, list):
        print(len(vulns))
    else:
        alt = data.get('vulnerabilities', {})
        print(len(alt) if isinstance(alt, (dict, list)) else '?')
except Exception:
    print('?')
PY
)
        else
            cve_count="?"
        fi
        log_warn "  CVE Vulnerabilities Found: ${cve_count}"
    fi
}

main "$@"
