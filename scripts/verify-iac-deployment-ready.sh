#!/bin/bash
# @file        scripts/verify-iac-deployment-ready.sh
# @module      validation/deployment-readiness
# @description Simple verification that QA Credentials IaC is ready for deployment
#

echo "=================================="
echo "QA CREDENTIALS IaC - READINESS CHECK"
echo "=================================="
echo ""

PASS=0
FAIL=0

echo "TERRAFORM FILES:"
if [ -f terraform/qa-credentials.tf ]; then
  echo "✓ terraform/qa-credentials.tf"
  PASS=$((PASS + 1))
else
  echo "✗ terraform/qa-credentials.tf MISSING"
  FAIL=$((FAIL + 1))
fi

if [ -f terraform/variables.tf ]; then
  echo "✓ terraform/variables.tf"
  PASS=$((PASS + 1))
else
  echo "✗ terraform/variables.tf MISSING"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "DEPLOYMENT SCRIPTS:"
if [ -f DEPLOY-QA-IaC-NOW.sh ]; then
  echo "✓ DEPLOY-QA-IaC-NOW.sh"
  PASS=$((PASS + 1))
else
  echo "✗ DEPLOY-QA-IaC-NOW.sh MISSING"
  FAIL=$((FAIL + 1))
fi

if [ -f scripts/deploy-qa-credentials-to-gcp.sh ]; then
  echo "✓ scripts/deploy-qa-credentials-to-gcp.sh"
  PASS=$((PASS + 1))
else
  echo "✗ scripts/deploy-qa-credentials-to-gcp.sh MISSING"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "VALIDATION SCRIPTS:"
if [ -f scripts/validate-qa-iac.sh ]; then
  echo "✓ scripts/validate-qa-iac.sh"
  PASS=$((PASS + 1))
else
  echo "✗ scripts/validate-qa-iac.sh MISSING"
  FAIL=$((FAIL + 1))
fi

if [ -f tests/iac-validation-test-simple.sh ]; then
  echo "✓ tests/iac-validation-test-simple.sh"
  PASS=$((PASS + 1))
else
  echo "✗ tests/iac-validation-test-simple.sh MISSING"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "CI/CD CONFIGURATION:"
if [ -f .github/workflows/e2e-oauth-automatic.yml ]; then
  echo "✓ .github/workflows/e2e-oauth-automatic.yml"
  PASS=$((PASS + 1))
else
  echo "✗ .github/workflows/e2e-oauth-automatic.yml MISSING"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "DOCUMENTATION:"
if [ -f QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md ]; then
  echo "✓ QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md"
  PASS=$((PASS + 1))
else
  echo "✗ QA-CREDENTIALS-IaC-COMPLETE-SOLUTION.md MISSING"
  FAIL=$((FAIL + 1))
fi

if [ -f README-DEPLOY-QA-IaC-NOW.md ]; then
  echo "✓ README-DEPLOY-QA-IaC-NOW.md"
  PASS=$((PASS + 1))
else
  echo "✗ README-DEPLOY-QA-IaC-NOW.md MISSING"
  FAIL=$((FAIL + 1))
fi

if [ -f docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md ]; then
  echo "✓ docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md"
  PASS=$((PASS + 1))
else
  echo "✗ docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md MISSING"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=================================="
echo "RESULTS: $PASS PASS, $FAIL FAIL"
echo "=================================="
echo ""

if [ $FAIL -eq 0 ]; then
  echo "✓ ALL COMPONENTS READY FOR DEPLOYMENT"
  echo ""
  echo "Next steps:"
  echo "  1. SSH to production host:"
  echo "     ssh akushnir@192.168.168.31"
  echo ""
  echo "  2. Deploy:"
  echo "     cd code-server-enterprise"
  echo "     bash DEPLOY-QA-IaC-NOW.sh"
  echo ""
  exit 0
else
  echo "✗ MISSING FILES - DEPLOYMENT NOT READY"
  exit 1
fi
