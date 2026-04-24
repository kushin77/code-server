#!/bin/bash
# @file        tests/iac-validation-test-simple.sh
# @module      test/iac
# @description Simple validation test for QA Credentials IaC components
#

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== QA Credentials IaC Validation Tests ==="
echo ""

PASS=0
FAIL=0

echo "Test 1: Terraform files exist"
if [ -f "terraform/qa-credentials.tf" ] && [ -f "terraform/variables.tf" ]; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 2: Deployment script exists"
if [ -f "scripts/deploy-qa-credentials-iac.sh" ]; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 3: Validation script exists"
if [ -f "scripts/validate-qa-iac.sh" ]; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 4: GitHub Actions workflow exists"
if [ -f ".github/workflows/e2e-oauth-automatic.yml" ]; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 5: Documentation exists"
if [ -f "docs/QA-CREDENTIALS-IaC-IMMUTABLE-IDEMPOTENT.md" ]; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 6: Immutability annotations in Terraform"
if grep -q "prevent_destroy = true" terraform/qa-credentials.tf; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 7: IAM bindings configured"
if grep -q "google_secret_manager_secret_iam_member" terraform/qa-credentials.tf; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo "Test 8: OAuth workflow configured"
if grep -q "E2E_USER_EMAIL" .github/workflows/e2e-oauth-automatic.yml; then
  echo "PASS"
  ((PASS++))
else
  echo "FAIL"
  ((FAIL++))
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ $FAIL -eq 0 ]; then
  echo "SUCCESS: All tests passed"
  exit 0
else
  echo "FAILED: Some tests failed"
  exit 1
fi
