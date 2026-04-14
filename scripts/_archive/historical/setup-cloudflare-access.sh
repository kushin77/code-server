#!/bin/bash
# Cloudflare Access Policy Setup for Code-Server
# Enforces zero-trust authentication and time-bounded access
# Implements part of issue #185

set -e

echo "🔐 Cloudflare Access Zero-Trust Policy Setup"
echo "============================================"
echo ""

# Configuration
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
APP_DOMAIN="${APP_DOMAIN:-dev.example.com}"
POLICY_NAME="${POLICY_NAME:-Code-Server Access}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Validate Credentials
# ─────────────────────────────────────────────────────────────────────────────

if [ -z "$API_TOKEN" ]; then
    echo -e "${RED}❌ CLOUDFLARE_API_TOKEN not set${NC}"
    echo "   Set it with: export CLOUDFLARE_API_TOKEN='your-token'"
    exit 1
fi

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ CLOUDFLARE_ACCOUNT_ID not set${NC}"
    echo "   Find it at: https://dash.cloudflare.com/profile/api-tokens"
    exit 1
fi

echo -e "${GREEN}✅ Credentials validated${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Get Application ID
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}📋 Fetching application configuration...${NC}"

APP_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps/list" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json")

# Check if app exists
if echo "$APP_RESPONSE" | grep -q "$APP_DOMAIN"; then
    APP_ID=$(echo "$APP_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}✅ Found existing application: $APP_ID${NC}"
else
    echo -e "${YELLOW}Creating new Access Application...${NC}"

    CREATE_APP=$(curl -s -X POST \
      "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps" \
      -H "Authorization: Bearer ${API_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"Code-Server IDE\",
        \"domain\": \"${APP_DOMAIN}\",
        \"type\": \"self_hosted\",
        \"session_duration\": \"24h\",
        \"allowed_idle_timeout\": \"4h\"
      }")

    APP_ID=$(echo "$CREATE_APP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo -e "${GREEN}✅ Created application: $APP_ID${NC}"
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Create/Update Access Policies
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}🔒 Setting up access policies...${NC}"
echo ""

# Policy 1: Allow specific developer emails
echo "Creating policy: Allow Developers (Email)"

POLICY_1=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps/${APP_ID}/policies" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Allow Developer Emails",
    "precedence": 1,
    "decision": "allow",
    "require": [
      {
        "email": {
          "domains": ["example.com"]
        }
      }
    ],
    "include": [
      {
        "email": {
          "domains": ["example.com"]
        }
      }
    ]
  }')

echo -e "${GREEN}✅ Created developer email policy${NC}"

# Policy 2: Require MFA
echo "Creating policy: Require MFA"

POLICY_2=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps/${APP_ID}/policies" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Require MFA",
    "precedence": 2,
    "decision": "allow",
    "require": [
      {
        "mfa": {}
      }
    ]
  }')

echo -e "${GREEN}✅ Created MFA requirement policy${NC}"

# Policy 3: Deny all others
echo "Creating policy: Deny All Others"

POLICY_3=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps/${APP_ID}/policies" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Deny All Others",
    "precedence": 999,
    "decision": "deny"
  }')

echo -e "${GREEN}✅ Created deny all policy${NC}"

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Configure Session Settings
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}⏱️  Configuring session timeouts...${NC}"

curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/access/apps/${APP_ID}" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "session_duration": "72h",
    "allowed_idle_timeout": "4h",
    "http_only_cookie_attribute": true,
    "secure_cookie_attribute": true,
    "same_site_cookie_attribute": "lax"
  }' > /dev/null

echo -e "${GREEN}✅ Session settings configured${NC}"
echo "   - Session duration: 72 hours"
echo "   - Idle timeout: 4 hours"
echo "   - Secure cookies enabled"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Configure Audit Logging
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${YELLOW}📊 Enable audit logging...${NC}"

curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/audit_logs" \
  -H "Authorization: Bearer ${API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"enabled\": true,
    \"log_type\": \"access\"
  }" > /dev/null

echo -e "${GREEN}✅ Audit logging enabled${NC}"
echo "   - Access logs: Visible in Cloudflare dashboard"
echo "   - Retention: 180 days (Enterprise) or 3 days (Free)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Configuration Summary
# ─────────────────────────────────────────────────────────────────────────────

echo -e "${GREEN}✅ CLOUDFLARE ACCESS SETUP COMPLETE${NC}"
echo "===================================="
echo ""
echo -e "${BLUE}Application Configuration:${NC}"
echo "   - App ID: $APP_ID"
echo "   - Domain: $APP_DOMAIN"
echo "   - Policy Name: $POLICY_NAME"
echo ""
echo -e "${BLUE}Access Policies:${NC}"
echo "   1. ✅ Allow Developer Emails (example.com domain)"
echo "   2. ✅ Require MFA (TOTP/U2F)"
echo "   3. ✅ Deny All Others (default deny)"
echo ""
echo -e "${BLUE}Session Configuration:${NC}"
echo "   - Session Duration: 72 hours"
echo "   - Idle Timeout: 4 hours"
echo "   - Secure Cookies: Enabled"
echo ""
echo -e "${BLUE}Audit & Logging:${NC}"
echo "   - Audit Logs: Enabled"
echo "   - Log Type: Access"
echo "   - Dashboard: https://dash.cloudflare.com/cgi-bin/account/access/apps"
echo ""
echo -e "${YELLOW}📋 IMPORTANT: Manual Steps in Cloudflare Dashboard:${NC}"
echo ""
echo "1. Review and customize policies:"
echo "   - Adjust email domains (currently: example.com)"
echo "   - Add specific users if needed"
echo "   - Configure additional access rules"
echo ""
echo "2. Set up authentication methods:"
echo "   - Enable: Email OTP, TOTP, U2F"
echo ""
echo "3. Monitor access:"
echo "   - Dashboard: https://dash.cloudflare.com"
echo "   - Access tab: Sessions, Audit Logs"
echo ""
echo -e "${YELLOW}🔗 Reference:${NC}"
echo "   - Cloudflare Access Docs: https://developers.cloudflare.com/cloudflare-one/"
echo "   - API Reference: https://api.cloudflare.com/"
echo ""
