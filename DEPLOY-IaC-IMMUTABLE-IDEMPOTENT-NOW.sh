#!/usr/bin/env bash
# @file        DEPLOY-IaC-IMMUTABLE-IDEMPOTENT-NOW.sh
# @module      deployment/execution
# @description Production deployment script for IaC/immutable/idempotent services
#
# This script deploys sentry-integration-api and slack-slash-commands-api
# with full IaC/immutable/idempotent compliance verification
#
# Usage: bash DEPLOY-IaC-IMMUTABLE-IDEMPOTENT-NOW.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "════════════════════════════════════════════════════════════════════════════"
echo "IaC/Immutable/Idempotent Production Deployment"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 1: Pre-deployment validation
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 1: Pre-Deployment Validation..."
echo ""

# Check required tools
if ! command -v docker &> /dev/null; then
    echo "ERROR: docker not found. Install Docker to proceed."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "ERROR: docker-compose not found. Install Docker Compose to proceed."
    exit 1
fi

echo "  ✓ Docker and Docker Compose available"
echo ""

# Check configuration
if [[ ! -f "$SCRIPT_DIR/.env.integration-services" ]]; then
    echo "  ℹ Configuration file .env.integration-services not found"
    echo "    Creating from template..."
    if [[ -f "$SCRIPT_DIR/.env.integration-services.example" ]]; then
        cp "$SCRIPT_DIR/.env.integration-services.example" "$SCRIPT_DIR/.env.integration-services"
        echo "  ✓ Configuration created from template"
        echo ""
        echo "  ⚠ NEXT STEP: Edit .env.integration-services with actual credentials:"
        echo "    nano .env.integration-services"
        echo ""
        echo "    Required credentials from:"
        echo "    - SENTRY_AUTH_TOKEN: https://sentry.io/settings/account/api/auth-tokens/"
        echo "    - SENTRY_ORG_SLUG: Your Sentry organization slug"
        echo "    - GITHUB_TOKEN: https://github.com/settings/tokens"
        echo "    - SLACK_SIGNING_SECRET: From your Slack app settings"
        echo "    - SLACK_BOT_TOKEN: From your Slack app OAuth"
        echo ""
        exit 1
    else
        echo "  ✗ FAIL: Template not found at .env.integration-services.example"
        exit 1
    fi
fi

echo "  ✓ Configuration file found"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 2: Load and validate environment
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 2: Environment Validation..."
echo ""

# Source the environment file
set +u
source "$SCRIPT_DIR/.env.integration-services"
set -u

# Check required environment variables
required_vars=(
    "SENTRY_AUTH_TOKEN"
    "SENTRY_ORG_SLUG"
    "GITHUB_TOKEN"
    "SLACK_SIGNING_SECRET"
    "SLACK_BOT_TOKEN"
)

missing_vars=0
for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "  ✗ Missing: $var"
        missing_vars=$((missing_vars + 1))
    else
        echo "  ✓ Set: $var (length: ${#!var})"
    fi
done

if [[ $missing_vars -gt 0 ]]; then
    echo ""
    echo "  ✗ FAIL: $missing_vars required environment variables are missing"
    echo "    Edit .env.integration-services and set all required credentials"
    exit 1
fi

echo ""
echo "  ✓ All environment variables are set"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 3: Build services
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 3: Building Docker Images..."
echo ""

cd "$SCRIPT_DIR"

if docker-compose build sentry-integration-api slack-slash-commands-api; then
    echo ""
    echo "  ✓ Docker images built successfully"
else
    echo ""
    echo "  ✗ FAIL: Docker build failed"
    exit 1
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 4: Start services
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 4: Starting Services..."
echo ""

if docker-compose up -d sentry-integration-api slack-slash-commands-api; then
    echo ""
    echo "  ✓ Services started"
else
    echo ""
    echo "  ✗ FAIL: Failed to start services"
    exit 1
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 5: Wait for services to be ready
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 5: Waiting for Services to Be Ready..."
echo ""

sleep 3

max_attempts=30
attempt=0

while [[ $attempt -lt $max_attempts ]]; do
    if docker-compose ps sentry-integration-api | grep -q "Up"; then
        echo "  ✓ sentry-integration-api is running"
        break
    fi
    attempt=$((attempt + 1))
    if [[ $attempt -lt $max_attempts ]]; then
        echo "  ℹ Waiting... (attempt $attempt/$max_attempts)"
        sleep 1
    fi
done

if [[ $attempt -eq $max_attempts ]]; then
    echo "  ✗ FAIL: sentry-integration-api did not start in time"
    docker-compose logs sentry-integration-api
    exit 1
fi

attempt=0
while [[ $attempt -lt $max_attempts ]]; do
    if docker-compose ps slack-slash-commands-api | grep -q "Up"; then
        echo "  ✓ slack-slash-commands-api is running"
        break
    fi
    attempt=$((attempt + 1))
    if [[ $attempt -lt $max_attempts ]]; then
        echo "  ℹ Waiting... (attempt $attempt/$max_attempts)"
        sleep 1
    fi
done

if [[ $attempt -eq $max_attempts ]]; then
    echo "  ✗ FAIL: slack-slash-commands-api did not start in time"
    docker-compose logs slack-slash-commands-api
    exit 1
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 6: Verify services
# ════════════════════════════════════════════════════════════════════════════
echo "▶ Step 6: Verifying Services..."
echo ""

# Run verification script
if bash "$SCRIPT_DIR/scripts/verify-iac-immutable-idempotent-deployment.sh" > /dev/null 2>&1; then
    echo "  ✓ Deployment verification passed"
else
    echo "  ✗ Deployment verification failed"
    exit 1
fi

# Run integration tests
if bash "$SCRIPT_DIR/scripts/test-iac-immutable-idempotent-live.sh" > /dev/null 2>&1; then
    echo "  ✓ Integration tests passed"
else
    echo "  ✗ Integration tests failed"
    exit 1
fi

echo ""

# ════════════════════════════════════════════════════════════════════════════
# Step 7: Final status
# ════════════════════════════════════════════════════════════════════════════
echo "════════════════════════════════════════════════════════════════════════════"
echo "✓ DEPLOYMENT SUCCESSFUL"
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Services now running:"
echo ""
docker-compose ps sentry-integration-api slack-slash-commands-api
echo ""
echo "Service Endpoints:"
echo "  • Sentry Integration API: http://localhost:9095"
echo "  • Slack Slash Commands API: http://localhost:9096"
echo ""
echo "Verify with:"
echo "  curl http://localhost:9095/health"
echo "  curl http://localhost:9096/health"
echo ""
echo "View logs:"
echo "  docker-compose logs -f sentry-integration-api"
echo "  docker-compose logs -f slack-slash-commands-api"
echo ""
echo "Stop services:"
echo "  docker-compose down"
echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo "Status: ✅ PRODUCTION READY"
echo "════════════════════════════════════════════════════════════════════════════"
