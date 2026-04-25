#!/usr/bin/env bash
# @governance: Terraform drop package verification — ensure scaffold completeness
# Purpose: Verify the Terraform drop package scaffold is present and complete
# Author: Autonomous Infrastructure
# Date: 2026-04-25
# Related issues: #1534 (IaC Governance), #1531 (Infrastructure as Code)

set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REQUIRED_TERRAFORM_PATHS="${REQUIRED_TERRAFORM_PATHS:-terraform/README.md:terraform/drop-package/README.md:terraform/drop-package/terraform.tfvars.example:terraform/environments/private/main.tf}"

# Convert colon-separated paths to array
IFS=':' read -ra required_paths <<< "${REQUIRED_TERRAFORM_PATHS}"

for required_path in "${required_paths[@]}"; do
  if [[ ! -e "${REPO_ROOT}/${required_path}" ]]; then
    echo "Missing required path: ${required_path}" >&2
    exit 1
  fi
done

echo "Terraform drop package scaffold verified."
