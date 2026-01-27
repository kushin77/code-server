#!/usr/bin/env bash
set -euo pipefail

echo "Running repository validation checks"

# Run pre-commit checks
if command -v pre-commit >/dev/null 2>&1; then
  echo "Running pre-commit..."
  pre-commit run --all-files
else
  echo "pre-commit not installed; skipping pre-commit checks"
fi

# Terraform checks (if Terraform files present)
if command -v terraform >/dev/null 2>&1 && ls **/*.tf 1> /dev/null 2>&1; then
  echo "Terraform files detected — running fmt and validate"
  terraform fmt -check -recursive || (echo "terraform fmt failed"; exit 1)
  terraform init -backend=false || true
  terraform validate || (echo "terraform validate failed"; exit 1)
else
  echo "No terraform files or terraform not installed; skipping terraform checks"
fi

# tflint (optional)
if command -v tflint >/dev/null 2>&1; then
  echo "Running tflint (optional)"
  tflint || (echo "tflint failed"; exit 1)
fi

echo "Validation completed successfully"
