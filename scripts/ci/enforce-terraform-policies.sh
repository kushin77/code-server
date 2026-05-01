#!/bin/bash
#
# Policy enforcement: Prevent drift masking anti-patterns in Terraform
# Detects `ignore_changes` patterns that hide configuration drift
#

set -euo pipefail

trap 'echo "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform/environments/private"

# Policy violations
POLICY_ERRORS=()

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "Terraform Policy Enforcement"
echo "============================================"
echo ""

# Check 1: Forbid blanket ignore_changes
echo "Checking for drift masking patterns..."

# Pattern 1: ignore_changes with all (never allowed)
if grep -rn 'ignore_changes = \[all\]' "${TF_DIR}" >/dev/null; then
  echo -e "${RED}✗ POLICY VIOLATION: ignore_changes = [all] detected${NC}"
  POLICY_ERRORS+=("Forbidden: ignore_changes = [all] (masks all drift)")
  grep -rn 'ignore_changes = \[all\]' "${TF_DIR}"
fi

# Pattern 2: ignore_changes without explicit justification comment
# (but we allow specific patterns: image, network_mode, ports, env)
# This is a warning, not an error
echo "Checking for documented ignore_changes patterns..."

# Identify all ignore_changes usages
IGNORE_CHANGES=$(grep -rn 'ignore_changes' "${TF_DIR}/modules/stack" --include="*.tf" || true)

if [[ -n "$IGNORE_CHANGES" ]]; then
  echo "$IGNORE_CHANGES" | while read -r line; do
    file=$(echo "$line" | cut -d: -f1)
    lineno=$(echo "$line" | cut -d: -f2)
    content=$(echo "$line" | cut -d: -f3-)
    
    # Check if line has justification comment
    if ! grep -q "# TODO\|# FIXME\|# NOTE\|reason:" <(echo "$content"); then
      if [[ "$content" != *"image"* ]] && [[ "$content" != *"network_mode"* ]]; then
        echo -e "${YELLOW}⚠ No justification for ignore_changes at ${file}:${lineno}${NC}"
        echo "  ${content}"
      fi
    fi
  done
fi

# Pattern 3: No env in ignore_changes (we removed this in Phase 4)
if grep -rn 'ignore_changes.*env' "${TF_DIR}/modules/stack" --include="*.tf" >/dev/null 2>&1; then
  echo -e "${RED}✗ POLICY VIOLATION: env in ignore_changes detected${NC}"
  echo "  (env drift must be visible, not masked)"
  POLICY_ERRORS+=("Forbidden: env in ignore_changes (Phase 4 remediation)")
  grep -rn 'ignore_changes.*env' "${TF_DIR}/modules/stack" --include="*.tf"
fi

# Pattern 4: Verify all containers have lifecycle rules
echo ""
echo "Checking container lifecycle policies..."

# Better counting: look for resource + lifecycle pairs more accurately
CONTAINERS=$(find "${TF_DIR}/modules/stack" -name "containers-*.tf" -exec grep -h 'resource "docker_container"' {} \; | wc -l)
CONTAINERS_WITH_LIFECYCLE=$(find "${TF_DIR}/modules/stack" -name "containers-*.tf" -exec grep -l 'ignore_changes' {} \; | xargs grep -h 'ignore_changes' | wc -l)

echo "Containers defined: ${CONTAINERS}"
echo "ignore_changes entries found: ${CONTAINERS_WITH_LIFECYCLE}"

if (( CONTAINERS > CONTAINERS_WITH_LIFECYCLE )); then
  POLICY_ERRORS+=("INFO: Found ${CONTAINERS_WITH_LIFECYCLE}/${CONTAINERS} ignore_changes entries (not all containers may need them)")
fi

echo ""
echo "============================================"
echo "Policy Check Summary"
echo "============================================"

if (( ${#POLICY_ERRORS[@]} == 0 )); then
  echo -e "${GREEN}✓ All policies compliant${NC}"
  exit 0
else
  echo -e "${RED}Policy violations found:${NC}"
  for error in "${POLICY_ERRORS[@]}"; do
    echo "  • $error"
  done
  exit 1
fi
