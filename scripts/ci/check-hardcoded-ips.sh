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

# File types and filenames that should NOT contain hardcoded IPs
CHECKED_PATTERNS=(
  "*.sh"                           # Shell scripts
  "*.ts"                           # TypeScript
  "*.js"                           # JavaScript
  "*.py"                           # Python
  "*.go"                           # Go
  "*.yml"                          # GitHub Actions / compose
  "*.yaml"                         # Kubernetes / automation manifests
  "*.tf"                           # Terraform
  "*.json"                         # Config/schema files
  "*.sql"                          # SQL scripts
  "Caddyfile"                      # Caddy routing config
  "Dockerfile"                     # Container build config
  "Dockerfile.*"                   # Variant Dockerfiles
  "Makefile"                       # Build orchestration
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

# Scan tracked files once, then filter by path and filename pattern.
while IFS= read -r -d '' file; do
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

    scan_file=0
    for file_pattern in "${CHECKED_PATTERNS[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$file" == $file_pattern ]]; then
        scan_file=1
        break
      fi
    done

    if [[ $scan_file -eq 0 ]]; then
      continue
    fi
    
    # Check each pattern
    for reject_pattern in "${REJECT_PATTERNS[@]}"; do
      if grep -n "$reject_pattern" "$file" 2>/dev/null | grep -v "^Binary" > /tmp/matches.txt; then
        while IFS= read -r line; do
          violation_count=$((violation_count + 1))
          log_warn "VIOLATION: $file — $line" || true
          echo "VIOLATION: $file — $line" >> "$violations_log"
          fail=1
        done < /tmp/matches.txt
      fi
    done
done < <(git ls-files -z)

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
