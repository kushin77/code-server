#!/usr/bin/env bash
# @file        scripts/ops/verify-drop-deployment.sh
# @module      ops/terraform-drop-package
# @description Verify the Terraform drop package scaffold is present and complete
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
