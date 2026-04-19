#!/usr/bin/env bash
# @file        scripts/configure-google-oauth-uris.sh
# @module      oauth2/configuration
# @description Configure Google Cloud OAuth app with both IDE and portal redirect URIs
# @owner       infrastructure
# @status      manual - requires gcloud CLI and GCP credentials
#
# SYNOPSIS:
#   ./scripts/configure-google-oauth-uris.sh <client-id> <project-id>
#
# EXAMPLES:
#   # Interactive mode (prompts for inputs)
#   ./scripts/configure-google-oauth-uris.sh
#
#   # Direct mode
#   ./scripts/configure-google-oauth-uris.sh \
#     1025559705580-2oi5316d95j6ajoki7o51v9tq4eb9cd1.apps.googleusercontent.com \
#     my-gcp-project-id
#
# REQUIREMENTS:
#   - gcloud CLI installed and configured
#   - ADC (Application Default Credentials) or service account key
#   - Project with OAuth 2.0 Client ID already created
#
# OAUTH REDIRECT URIs TO REGISTER:
#   1. https://ide.kushnir.cloud/oauth2/callback     (IDE)
#   2. https://kushnir.cloud/oauth2/callback         (Portal)
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Default OAuth app details
OAUTH_CLIENT_ID="${1:-}"
GCP_PROJECT_ID="${2:-}"

# Redirect URIs
IDE_REDIRECT_URI="https://ide.kushnir.cloud/oauth2/callback"
PORTAL_REDIRECT_URI="https://kushnir.cloud/oauth2/callback"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verify gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_fatal "gcloud CLI not installed. Install with: curl https://sdk.cloud.google.com | bash"
fi

# Interactive input if not provided
if [[ -z "$OAUTH_CLIENT_ID" ]]; then
    echo -e "${YELLOW}OAuth Application Configuration${NC}"
    echo "=================================="
    echo ""
    read -p "Enter your GCP Project ID: " GCP_PROJECT_ID
    read -p "Enter OAuth 2.0 Client ID (from Google Cloud Console): " OAUTH_CLIENT_ID
fi

log_info "Configuring OAuth Redirect URIs for $OAUTH_CLIENT_ID"
log_info "Project: $GCP_PROJECT_ID"
echo ""

# Verify gcloud is authenticated
log_info "Checking gcloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_fatal "Not authenticated with gcloud. Run: gcloud auth login"
fi

# Get the actual OAuth client details
log_info "Fetching OAuth client configuration from Google Cloud..."

# Extract the numeric project ID from the client ID
# Format: PROJECT_NUMBER-HASH.apps.googleusercontent.com
PROJECT_NUMBER="${OAUTH_CLIENT_ID%%-*}"

if [[ -z "$PROJECT_NUMBER" ]] || [[ ! "$PROJECT_NUMBER" =~ ^[0-9]+$ ]]; then
    log_fatal "Invalid OAuth Client ID format. Expected: PROJECT_NUMBER-HASH.apps.googleusercontent.com"
fi

log_info "Project Number: $PROJECT_NUMBER"
log_info "Client ID: $OAUTH_CLIENT_ID"
echo ""

# Get the current OAuth client configuration
log_info "Retrieving current OAuth client configuration..."

OAUTH_CONFIG=$(gcloud oauth-app-profiles list \
    --project="$GCP_PROJECT_ID" \
    --format=json 2>&1 || echo "[]")

if [[ "$OAUTH_CONFIG" == "[]" ]] || [[ -z "$OAUTH_CONFIG" ]]; then
    log_warn "Could not fetch OAuth config via gcloud oauth-app-profiles"
    log_warn "This may require manual configuration in Google Cloud Console"
    echo ""
    echo -e "${YELLOW}Manual Configuration Steps:${NC}"
    echo "1. Go to: https://console.cloud.google.com/apis/credentials"
    echo "2. Find OAuth 2.0 Client ID: $OAUTH_CLIENT_ID"
    echo "3. Click the Edit (pencil) icon"
    echo "4. Under 'Authorized redirect URIs', add both:"
    echo "   - $IDE_REDIRECT_URI"
    echo "   - $PORTAL_REDIRECT_URI"
    echo "5. Click Save"
    echo ""
    exit 0
fi

# Parse redirect URIs from current config
CURRENT_URIS=$(echo "$OAUTH_CONFIG" | jq -r '.[].authFlow.redirectUri // empty' 2>/dev/null || echo "")

log_info "Current configured redirect URIs:"
if [[ -z "$CURRENT_URIS" ]]; then
    echo "  (None found - may require manual configuration)"
else
    echo "$CURRENT_URIS" | while read -r uri; do
        echo "  - $uri"
    done
fi
echo ""

# Check if both URIs are registered
HAS_IDE_URI=false
HAS_PORTAL_URI=false

if echo "$CURRENT_URIS" | grep -q "$IDE_REDIRECT_URI"; then
    HAS_IDE_URI=true
fi
if echo "$CURRENT_URIS" | grep -q "$PORTAL_REDIRECT_URI"; then
    HAS_PORTAL_URI=true
fi

echo -e "${GREEN}Required URIs:${NC}"
[[ "$HAS_IDE_URI" == "true" ]] && echo -e "  ${GREEN}✓${NC} $IDE_REDIRECT_URI" || echo -e "  ${RED}✗${NC} $IDE_REDIRECT_URI (MISSING)"
[[ "$HAS_PORTAL_URI" == "true" ]] && echo -e "  ${GREEN}✓${NC} $PORTAL_REDIRECT_URI" || echo -e "  ${RED}✗${NC} $PORTAL_REDIRECT_URI (MISSING)"
echo ""

if [[ "$HAS_IDE_URI" == "true" ]] && [[ "$HAS_PORTAL_URI" == "true" ]]; then
    log_info "✓ Both redirect URIs are already configured!"
    exit 0
fi

log_warn "Missing redirect URIs detected. Manual Google Cloud Console configuration required:"
echo ""
echo -e "${YELLOW}Steps:${NC}"
echo "1. Open: https://console.cloud.google.com/apis/credentials?project=$GCP_PROJECT_ID"
echo "2. Find and edit OAuth 2.0 Client ID: $OAUTH_CLIENT_ID"
echo "3. Add to 'Authorized redirect URIs':"
[[ "$HAS_IDE_URI" == "false" ]] && echo "   - $IDE_REDIRECT_URI"
[[ "$HAS_PORTAL_URI" == "false" ]] && echo "   - $PORTAL_REDIRECT_URI"
echo "4. Click 'Save'"
echo ""
log_info "Once completed, both OAuth flows (IDE and Portal) will work correctly."
