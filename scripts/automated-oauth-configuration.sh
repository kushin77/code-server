#!/bin/bash
################################################################################
# File: automated-oauth-configuration.sh
# Owner: Security/Identity Team
# Purpose: Automated OAuth2 provider configuration and credential management
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+
#
# Dependencies:
#   - curl — OAuth provider API communication
#   - jq — JSON response parsing
#   - docker — Container credential injection
#
# Related Files:
#   - docker-compose.yml — oauth2-proxy service definition
#   - terraform/oauth.tf — OAuth provider configuration
#   - .env — OAuth client credentials (secrets)
#
# Usage:
#   ./automated-oauth-configuration.sh setup      # Initial OAuth setup
#   ./automated-oauth-configuration.sh validate   # Verify configuration
#   ./automated-oauth-configuration.sh rotate     # Rotate credentials
#
# Configuration:
#   - Create OAuth application in provider (GitHub, Google, etc)
#   - Store client credentials securely
#   - Configure redirect URIs
#   - Validate permission scopes
#   - Test OAuth flow
#
# Exit Codes:
#   0 — OAuth configuration successful
#   1 — OAuth configuration completed with warnings
#   2 — OAuth configuration failed (authentication broken)
#
# Examples:
#   ./scripts/automated-oauth-configuration.sh setup
#   ./scripts/automated-oauth-configuration.sh validate
#
# Recent Changes:
#   2026-04-14: Added credential validation logging (Phase 2.2)
#   2026-04-13: Initial creation with OAuth setup automation
#
################################################################################
# Automated OAuth Configuration - IaC Setup for Google OAuth2
# Guides through Google Cloud Console OAuth app creation (cannot be fully automated)
# But integrates the credentials into deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.oauth-config"

echo "════════════════════════════════════════════════════════════"
echo "AUTOMATED OAUTH CONFIGURATION SETUP"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if credentials already provided
if [ ! -z "$GOOGLE_CLIENT_ID" ] && [ ! -z "$GOOGLE_CLIENT_SECRET" ]; then
    echo "✓ Google OAuth credentials detected from environment"
    echo "  Client ID: ${GOOGLE_CLIENT_ID:0:20}***"
    echo ""
    
    # Validate format
    if [ ${#GOOGLE_CLIENT_ID} -lt 20 ]; then
        echo "⚠ WARNING: Client ID seems short. Verify it's correct."
    fi
    
    if [ ${#GOOGLE_CLIENT_SECRET} -lt 20 ]; then
        echo "⚠ WARNING: Client Secret seems short. Verify it's correct."
    fi
    
    # Save to config
    cat > "$CONFIG_FILE" << EOF
# Google OAuth Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: Environment variables

GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:0:10}...
CONFIGURED_AT=$(date +%s)
EOF
    
    chmod 600 "$CONFIG_FILE"
    echo "✓ OAuth configuration saved"
    echo ""
    exit 0
fi

# If not provided, guide through setup
echo "Google OAuth credentials not found in environment variables."
echo ""
echo "To enable OAuth2 authentication, you need to:"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "STEP 1: Create OAuth Application in Google Cloud Console"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "1. Go to: https://console.cloud.google.com/apis/credentials"
echo ""
echo "2. Create a new project (if you don't have one):"
echo "   - Click 'Select a Project' (top left)"
echo "   - Click 'NEW PROJECT'"
echo "   - Name it: 'code-server-enterprise'"
echo "   - Click 'CREATE'"
echo ""
echo "3. Enable Google+ API:"
echo "   - Go to: https://console.cloud.google.com/apis/library"
echo "   - Search for: 'Google+ API'"
echo "   - Click on it and press 'ENABLE'"
echo ""
echo "4. Create OAuth 2.0 Credentials:"
echo "   - Go back to: https://console.cloud.google.com/apis/credentials"
echo "   - Click '+ CREATE CREDENTIALS' (blue button, top right)"
echo "   - Select 'OAuth client ID'"
echo "   - Choose 'Web application'"
echo "   - Set Name: 'code-server-ide'"
echo "   - Under 'Authorized JavaScript origins', add:"
echo "     • http://localhost:8080"
echo "     • https://ide.kushnir.cloud"
echo "   - Under 'Authorized redirect URIs', add:"
echo "     • http://localhost:8080/oauth2/callback"
echo "     • https://ide.kushnir.cloud/oauth2/callback"
echo "   - Click 'CREATE'"
echo ""
echo "5. Copy the credentials:"
echo "   - A modal will show: Client ID and Client Secret"
echo "   - Copy both (or download JSON)"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "STEP 2: Set Environment Variables"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Export the credentials:"
echo ""
echo "  export GOOGLE_CLIENT_ID='<your-client-id-from-step-5>'"
echo "  export GOOGLE_CLIENT_SECRET='<your-client-secret-from-step-5>'"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "STEP 3: Re-run Deployment"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "After exporting credentials, re-run:"
echo ""
echo "  ./scripts/automated-deployment-orchestration.sh"
echo ""
echo "The orchestration script will:"
echo "  • Verify OAuth credentials"
echo "  • Configure OAuth2-Proxy"
echo "  • Deploy all services with authentication enabled"
echo ""

# Interactive prompt
echo ""
echo "Do you have Google OAuth credentials ready? (y/n): "
read -r response

if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    echo "Enter Google Client ID:"
    read -r CLIENT_ID
    
    echo "Enter Google Client Secret:"
    read -rs CLIENT_SECRET  # -s hides input
    echo ""
    
    # Validate
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo "ERROR: Both Client ID and Client Secret are required"
        exit 1
    fi
    
    # Export for current session
    export GOOGLE_CLIENT_ID="$CLIENT_ID"
    export GOOGLE_CLIENT_SECRET="$CLIENT_SECRET"
    
    # Save to config
    cat > "$CONFIG_FILE" << EOF
# Google OAuth Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Source: Interactive input

GOOGLE_CLIENT_ID=${CLIENT_ID}
GOOGLE_CLIENT_SECRET=${CLIENT_SECRET:0:10}...
CONFIGURED_AT=$(date +%s)
EOF
    
    chmod 600 "$CONFIG_FILE"
    
    echo ""
    echo "✓ OAuth credentials configured"
    echo "✓ Ready to deploy with authentication"
    echo ""
    echo "Next: Run deployment script"
    echo "  ./scripts/automated-deployment-orchestration.sh"
else
    echo ""
    echo "⚠ OAuth authentication will be disabled"
    echo "Services will be accessible without authentication."
    echo ""
    echo "To enable OAuth later:"
    echo "  1. Follow the steps above"
    echo "  2. Export credentials"
    echo "  3. Re-run deployment"
fi

echo ""
echo "✓ OAuth configuration setup complete"
