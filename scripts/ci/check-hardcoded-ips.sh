#!/usr/bin/env bash
# @file        scripts/ci/check-hardcoded-ips.sh
# @module      ci/network
# @description Enforce DNS-based networking: detect hardcoded IPs and reject additions per issue #888

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# List of patterns to reject in source code (NOT config/docs)
REJECT_PATTERNS=(
  "192\.168\.168\.(31|42|30|56)"  # On-prem IPs
  "127\.0\.0\.1:[0-9]+"           # Localhost with port (should use DNS names)
)

# Files/paths that are allowed to contain IPs (config, docs, examples)
ALLOWLIST_PATTERNS=(
  "^\.env"                         # Environment files
  "^\.envrc"                       # direnv
  "^terraform/"                    # Terraform (already parameterized with defaults)
  "^config/"                       # Configuration files
  "^docs/"                         # Documentation
  "^environments/"                 # Infrastructure inventory (hosts.yml, etc)
  "^Makefile\."                    # Makefile variants (handled separately)
)

# File types that should NOT contain hardcoded IPs
CHECKED_EXTENSIONS=(
  "*.sh"                           # Shell scripts
  "*.ts"                           # TypeScript
  "*.js"                           # JavaScript
  "*.py"                           # Python
)

fail=0
violations_log="artifacts/triage/hardcoded-ips-violations.log"
mkdir -p "$(dirname "$violations_log")"
: > "$violations_log"

log_info "Scanning for hardcoded IPs (issue #888 enforcement)..."
echo "=== Hardcoded IP Detection Report ===" >> "$violations_log"
echo "Scan date: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$violations_log"
echo "" >> "$violations_log"

violation_count=0

# Scan each file type
for ext in "${CHECKED_EXTENSIONS[@]}"; do
  while IFS= read -r file; do
    # Skip allowlisted paths
    skip=0
    for allow_pattern in "${ALLOWLIST_PATTERNS[@]}"; do
      if [[ "$file" =~ $allow_pattern ]]; then
        skip=1
        break
      fi
    done
    
    if [[ $skip -eq 1 ]]; then
      continue
    fi
    
    # Check each pattern
    for pattern in "${REJECT_PATTERNS[@]}"; do
      if grep -n "$pattern" "$file" 2>/dev/null | grep -v "^Binary" > /tmp/matches.txt; then
        while IFS= read -r line; do
          violation_count=$((violation_count + 1))
          log_warn "VIOLATION: $file — $line" || true
          echo "VIOLATION: $file — $line" >> "$violations_log"
          fail=1
        done < /tmp/matches.txt
      fi
    done
  done < <(find . -type f -name "$ext" -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null)
done

echo "" >> "$violations_log"
echo "Total violations found: $violation_count" >> "$violations_log"
echo "" >> "$violations_log"
echo "=== Remediation Guidance ===" >> "$violations_log"
echo "For issue #888 compliance:" >> "$violations_log"
echo "1. Use environment variables: \${DEPLOY_HOST}, \${REPLICA_HOST}, \${VIP_HOST}" >> "$violations_log"
echo "2. Use DNS names: primary.prod.internal, replica.prod.internal, vip.prod.internal" >> "$violations_log"
echo "3. For services: <service>.svc.internal (e.g., postgres.svc.internal)" >> "$violations_log"
echo "4. Keep hardcoded IPs ONLY in: .env files, terraform defaults, docs/" >> "$violations_log"
echo "" >> "$violations_log"
echo "See: docs/dns-architecture.md and issue #888 for details" >> "$violations_log"

if [[ $fail -ne 0 ]]; then
  log_fatal "Hardcoded IP check FAILED: $violation_count violation(s) detected (see $violations_log)"
fi

log_info "✅ Hardcoded IP check PASSED (zero violations)"
exit 0
