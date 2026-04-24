#!/bin/bash
# Reset QA credentials to Google Secret Manager

set -euo pipefail

echo "=== Resetting QA Credentials for qa@kushnir.cloud ==="
echo ""

# Generate password
QA_PASSWORD=$(cat /dev/urandom | base64 | tr -d '/+' | cut -c1-32)
echo "Generated password: $QA_PASSWORD"
echo ""

# Get current project
PROJECT=$(gcloud config get-value project)
echo "Using GCP project: $PROJECT"
echo ""

# Create or update GSM secrets
echo "Updating GSM secrets..."
echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=- --project=kushin77-ops 2>&1 || {
  echo "Creating qa-user-email secret..."
  gcloud secrets create qa-user-email --replication-policy=automatic --project=kushin77-ops
  echo -n "qa@kushnir.cloud" | gcloud secrets versions add qa-user-email --data-file=- --project=kushin77-ops
}

echo -n "$QA_PASSWORD" | gcloud secrets versions add qa-user-password --data-file=- --project=kushin77-ops 2>&1 || {
  echo "Creating qa-user-password secret..."
  gcloud secrets create qa-user-password --replication-policy=automatic --project=kushin77-ops
  echo -n "$QA_PASSWORD" | gcloud secrets versions add qa-user-password --data-file=- --project=kushin77-ops
}

echo ""
echo "✓ GSM secrets updated successfully"
echo ""
echo "QA Credentials:"
echo "  Email: qa@kushnir.cloud"
echo "  Password: $QA_PASSWORD"
echo ""
echo "Store this password securely - it will be used for E2E testing."
