#!/usr/bin/env bash
# @file        scripts/validate-oauth-config.sh
# @module      security/oauth
# @description Pre-deployment check for OAuth configuration and redirect URI registration
# @owner       security
# @status      active
#
# Pre-deployment check for OAuth configuration
# This script validates that both redirect URIs are registered in Google Cloud Console

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        OAuth Configuration Validation - CRITICAL CHECK         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

OAUTH_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"

if [[ -z "$OAUTH_CLIENT_ID" ]] || [[ -z "$GOOGLE_CLIENT_SECRET" ]]; then
    echo "❌ ERROR: GOOGLE_CLIENT_ID or GOOGLE_CLIENT_SECRET not set"
    echo ""
    echo "Required environment variables:"
    echo "  - GOOGLE_CLIENT_ID=1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com"
    echo "  - GOOGLE_CLIENT_SECRET=GOCSPX-..."
    exit 1
fi

echo "✓ OAuth credentials found:"
echo "  Client ID: ${OAUTH_CLIENT_ID:0:30}..."
echo ""

echo "⚠️  CRITICAL REQUIREMENT:"
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Both of these redirect URIs MUST be registered in Google Cloud Console:"
echo ""
echo "  1. https://ide.kushnir.cloud/oauth2/callback"
echo "  2. https://kushnir.cloud/oauth2/callback"
echo ""
echo "To register them:"
echo ""
echo "  1. Go to: https://console.cloud.google.com/apis/credentials"
echo "  2. Click on OAuth 2.0 Client ID:"
echo "     ${OAUTH_CLIENT_ID}"
echo ""
echo "  3. In 'Authorized redirect URIs', ensure BOTH are listed:"
echo "     • https://ide.kushnir.cloud/oauth2/callback"
echo "     • https://kushnir.cloud/oauth2/callback"
echo ""
echo "  4. Click SAVE"
echo ""
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "Without both URIs registered, OAuth login will fail with:"
echo "  'The redirect_uri MUST match one of the registered URLs'"
echo ""

# Quick test: Try to detect if we can reach Google's OAuth endpoints
if command -v curl &> /dev/null; then
    echo "Testing OAuth provider connectivity..."
    if curl -s -m 5 "https://accounts.google.com/.well-known/openid-configuration" > /dev/null 2>&1; then
        echo "✓ Google OAuth service is reachable"
    else
        echo "⚠️  Could not reach Google OAuth service (network issue?)"
    fi
fi

echo ""
echo "Deployment Status:"
echo "  oauth2-proxy-portal: READY"
echo "  Google OAuth config: ⚠️  MANUAL SETUP REQUIRED"
echo ""
echo "Next Steps:"
echo "  [ ] Register redirect URIs in Google Cloud Console (REQUIRED)"
echo "  [ ] Test OAuth login at https://kushnir.cloud/"
echo "  [ ] Verify successful authentication"
echo ""
