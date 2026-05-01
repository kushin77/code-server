#!/usr/bin/env bash
# @file        scripts/ops/verify-drop-deployment.sh
# @module      ops/terraform-drop-package
# @description Verify the Terraform drop package scaffold is present and complete
set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

required_paths=(
  "terraform/README.md"
  "terraform/drop-package/README.md"
  "terraform/drop-package/terraform.tfvars.example"
  "terraform/environments/private/main.tf"
)

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "${REPO_ROOT}/${required_path}" ]]; then
    echo "Missing required path: ${required_path}" >&2
    exit 1
  fi
done

echo "Terraform drop package scaffold verified."
