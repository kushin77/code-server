#!/usr/bin/env bash
# scripts/configure-oidc-phase1.sh
# P1 #388 Phase 1: OIDC Provider Configuration
# Sets up Google/GitHub OIDC providers for identity federation

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}P1 #388 Phase 1: OIDC Provider Configuration${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Configuration paths
OIDC_CONFIG_DIR="config/iam/oidc"
OAUTH2_CONFIG="${OIDC_CONFIG_DIR}/oauth2-proxy-config.yaml"
KEYCLOAK_CONFIG="${OIDC_CONFIG_DIR}/keycloak-realm.json"

mkdir -p "$OIDC_CONFIG_DIR"

# 1. Create oauth2-proxy Configuration
echo -e "${BLUE}[1/4] Creating oauth2-proxy configuration...${NC}"
cat > "$OAUTH2_CONFIG" << 'EOF'
# OAuth2-Proxy Configuration for Code-Server
# Phase 1: OIDC Provider Setup

# Server Configuration
http_address = "0.0.0.0:4180"
https_address = "0.0.0.0:4443"
upstreamUrl = "http://127.0.0.1:8080"

# Session Configuration
sessionExpiryWindow = 3600  # 1 hour default
sessionRefreshWindow = 1800 # 30 min refresh window
sessionMaxLifetime = 86400  # 24 hour max lifetime

# Cookie Configuration (via env vars - DO NOT put secrets here)
# cookie_secret = LOADED FROM ENV
# cookie_name = "_proxy"
# cookie_domain = LOADED FROM ENV
# cookie_httponly = true
# cookie_secure = true  # HTTPS only in production
# cookie_samesite = "Lax"

# OIDC Configuration
oidc_issuer_url = "${OIDC_ISSUER:=https://accounts.google.com}"

# Provider-specific settings
scope = "email profile"
email_domains = "*"
skip_jwt_bearer_tokens = false

# Header Configuration (send to upstream services)
set_xauthrequest = true
pass_authorization_header = true
pass_access_token = true
pass_user_bearer_token = true

# Upstream Headers
request_headers = {
  "Authorization" = "Bearer {access_token}",
  "X-Auth-Request-User" = "{user}",
  "X-Auth-Request-Email" = "{email}",
  "X-Auth-Request-Groups" = "{groups}",
  "X-Auth-Request-Preferred-Username" = "{preferred_username}",
  "X-Auth-Request-Id-Token" = "{id_token}",
  "X-Real-IP" = "${HTTP_X_REAL_IP}"
}

# Advanced OIDC Configuration
oidc_keyset_url = "${OIDC_KEYSET_URL:=https://www.googleapis.com/oauth2/v3/certs}"
oidc_token_endpoint = "${OIDC_TOKEN_ENDPOINT:=https://oauth2.googleapis.com/token}"
oidc_authorization_endpoint = "${OIDC_AUTH_ENDPOINT:=https://accounts.google.com/o/oauth2/v2/auth}"

# Skip OIDC provider verification (set to false in production)
insecure_oidc_discovery = false

# Access Control
alpha_allow_preflight_bypass = false

# Logging Configuration
logging_level = "info"
logging_format = "json"

# Metrics
metrics_bind_address = "0.0.0.0:44180"

# OAuth2 Application (loaded from environment variables)
# client_id = LOADED FROM ENV
# client_secret = LOADED FROM ENV
# redirect_url = LOADED FROM ENV (e.g., http://localhost:4180/oauth2/callback)
EOF
echo -e "${GREEN}✓ Created $OAUTH2_CONFIG${NC}"

# 2. Create Keycloak Realm Configuration
echo -e "${BLUE}[2/4] Creating Keycloak realm configuration (fallback OIDC provider)...${NC}"
cat > "$KEYCLOAK_CONFIG" << 'EOF'
{
  "realm": "code-server",
  "displayName": "Code-Server Platform",
  "enabled": true,
  "accessTokenLifespan": 3600,
  "refreshTokenLifespan": 86400,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 86400,
  "offlineSessionIdleTimeout": 2592000,
  "offlineSessionMaxLifespan": 5184000,
  "accessCodeLifespan": 600,
  "accessCodeLifespanUserAction": 300,
  "accessCodeLifespanLogin": 1800,
  "notBefore": 0,
  "defaultSignatureAlgorithm": "RS256",
  "requiredCredentials": ["password"],
  "passwordPolicy": "length(12) and specialChars(1) and digits(1) and lowerCase(1) and upperCase(1)",
  "otpPolicyType": "totp",
  "otpPolicyAlgorithm": "HmacSHA1",
  "otpPolicyInitialCounter": 0,
  "otpPolicyDigits": 6,
  "otpPolicyLookAheadWindow": 1,
  "otpPolicyPeriod": 30,
  "otpSupportedApplications": [
    "FreeOTP",
    "Google Authenticator",
    "Authy",
    "Microsoft Authenticator"
  ],
  "browserFlow": "browser",
  "registrationFlow": "registration",
  "directGrantFlow": "direct grant",
  "resetCredentialsFlow": "reset credentials",
  "clientAuthenticationFlow": "clients",
  "dockerAuthenticationFlow": "docker auth",
  "defaultRoles": [
    "offline_access",
    "uma_authorization"
  ],
  "requiredActions": [
    {
      "alias": "VERIFY_EMAIL",
      "name": "Verify Email",
      "providerId": "verify-email",
      "enabled": true,
      "defaultAction": false,
      "priority": 50,
      "config": {}
    },
    {
      "alias": "CONFIGURE_TOTP",
      "name": "Configure OTP",
      "providerId": "CONFIGURE_TOTP",
      "enabled": true,
      "defaultAction": false,
      "priority": 10,
      "config": {}
    }
  ],
  "clients": [
    {
      "clientId": "code-server",
      "name": "Code-Server Application",
      "enabled": true,
      "publicClient": false,
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": true,
      "authenticateByDefault": false,
      "bearerTokensRedirectable": true,
      "consentRequired": false,
      "clientAuthenticatorType": "client-secret",
      "redirectUris": [
        "http://code-server.192.168.168.31.nip.io:8080/oauth2/callback",
        "https://code-server.kushnir.cloud/oauth2/callback"
      ],
      "webOrigins": [
        "http://code-server.192.168.168.31.nip.io:8080",
        "https://code-server.kushnir.cloud"
      ],
      "defaultClientScopes": [
        "email",
        "profile",
        "roles"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access"
      ],
      "access": {
        "view": true,
        "manage": true,
        "manage-scope": true
      }
    }
  ],
  "users": [
    {
      "username": "admin",
      "firstName": "Admin",
      "lastName": "User",
      "email": "admin@kushnir.cloud",
      "enabled": true,
      "totp": false,
      "emailVerified": true,
      "requiredActions": [],
      "realmRoles": [
        "default-roles-code-server",
        "admin",
        "uma_authorization"
      ],
      "groups": [
        "admins"
      ],
      "attributes": {
        "mfa_required": ["true"],
        "platform_role": ["admin"]
      }
    }
  ],
  "groups": [
    {
      "name": "admins",
      "path": "/admins",
      "attributes": {
        "platform_role": ["admin"],
        "mfa_required": ["true"]
      },
      "realmRoles": ["admin"]
    },
    {
      "name": "operators",
      "path": "/operators",
      "attributes": {
        "platform_role": ["operator"],
        "mfa_required": ["false"]
      },
      "realmRoles": ["operator"]
    },
    {
      "name": "viewers",
      "path": "/viewers",
      "attributes": {
        "platform_role": ["viewer"],
        "mfa_required": ["false"]
      },
      "realmRoles": ["viewer"]
    }
  ],
  "roles": {
    "realm": [
      {
        "name": "admin",
        "description": "Administrator - Full platform access",
        "composite": false,
        "clientRole": false,
        "containerId": "code-server",
        "attributes": {
          "mfa_required": ["true"]
        }
      },
      {
        "name": "operator",
        "description": "Operator - Infrastructure management",
        "composite": false,
        "clientRole": false,
        "containerId": "code-server",
        "attributes": {
          "mfa_required": ["false"]
        }
      },
      {
        "name": "viewer",
        "description": "Viewer - Read-only access",
        "composite": false,
        "clientRole": false,
        "containerId": "code-server",
        "attributes": {
          "mfa_required": ["false"]
        }
      }
    ]
  },
  "scope": [
    {
      "name": "email",
      "displayName": "Email address",
      "protocol": "openid-connect",
      "protocolMappers": [
        {
          "name": "email",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "email",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "email",
            "jsonType.label": "String"
          }
        }
      ]
    },
    {
      "name": "profile",
      "displayName": "User profile",
      "protocol": "openid-connect",
      "protocolMappers": [
        {
          "name": "name",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-full-name-mapper",
          "consentRequired": false,
          "config": {
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "preferred_username",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "username",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "preferred_username",
            "jsonType.label": "String"
          }
        }
      ]
    },
    {
      "name": "roles",
      "displayName": "User roles",
      "protocol": "openid-connect",
      "protocolMappers": [
        {
          "name": "client roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-client-role-mapper",
          "consentRequired": false,
          "config": {
            "user.roles.query.scope": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "roles",
            "jsonType.label": "String",
            "multivalued": "true"
          }
        },
        {
          "name": "realm roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "user.roles.query.scope": "true",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "realm_roles",
            "jsonType.label": "String",
            "multivalued": "true"
          }
        }
      ]
    }
  ]
}
EOF
echo -e "${GREEN}✓ Created $KEYCLOAK_CONFIG${NC}"

# 3. Create environment variable template
echo -e "${BLUE}[3/4] Creating .env.oidc template (for credentials)...${NC}"
cat > "config/iam/oidc/.env.template" << 'EOF'
# OAuth2-Proxy OIDC Configuration
# Phase 1 - Configure these before running

# Google OAuth2 Configuration
GOOGLE_CLIENT_ID=<your-google-client-id>
GOOGLE_CLIENT_SECRET=<your-google-client-secret>
GOOGLE_OAUTH_REDIRECT_URL=http://localhost:4180/oauth2/callback

# GitHub OAuth2 Configuration
GITHUB_CLIENT_ID=<your-github-client-id>
GITHUB_CLIENT_SECRET=<your-github-client-secret>
GITHUB_OAUTH_REDIRECT_URL=http://localhost:4180/oauth2/callback

# Cookie Security
COOKIE_SECRET=$(openssl rand -hex 16)  # Must be 16, 24, or 32 bytes hex
COOKIE_DOMAIN=.192.168.168.31.nip.io
COOKIE_SECURE=false  # Set to true in production (HTTPS only)

# OIDC Configuration
OIDC_ISSUER=https://accounts.google.com
OIDC_KEYSET_URL=https://www.googleapis.com/oauth2/v3/certs
OIDC_CLIENT_ID=$GOOGLE_CLIENT_ID
OIDC_CLIENT_SECRET=$GOOGLE_CLIENT_SECRET

# Session Configuration
SESSION_EXPIRY_WINDOW=3600
SESSION_REFRESH_WINDOW=1800
SESSION_MAX_LIFETIME=86400

# Keycloak Configuration (fallback provider)
KEYCLOAK_REALM=code-server
KEYCLOAK_CLIENT_ID=code-server
KEYCLOAK_CLIENT_SECRET=<generate-via-keycloak>
KEYCLOAK_URL=http://keycloak.192.168.168.31.nip.io:8080
EOF
echo -e "${GREEN}✓ Created config/iam/oidc/.env.template${NC}"

# 4. Create Docker Compose service configuration
echo -e "${BLUE}[4/4] Creating OAuth2-Proxy docker-compose service snippet...${NC}"
cat > "config/iam/oidc/docker-compose.oauth2-proxy.yml" << 'EOF'
# OAuth2-Proxy Service Configuration
# Add this to docker-compose.yml under services:

  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:v7.5.1
    container_name: oauth2-proxy
    ports:
      - "4180:4180"  # HTTP
      - "4443:4443"  # HTTPS (future)
    volumes:
      - ./config/iam/oidc/oauth2-proxy-config.yaml:/etc/oauth2-proxy/oauth2-proxy.cfg:ro
      - ./config/iam/oidc/.env:/etc/oauth2-proxy/.env:ro
    env_file:
      - config/iam/oidc/.env
    environment:
      # Override via environment
      - OAUTH2_PROXY_HTTP_ADDRESS=0.0.0.0:4180
      - OAUTH2_PROXY_UPSTREAM=http://code-server:8080
      - OAUTH2_PROXY_COOKIE_SECURE=false  # Set to true in production
      - OAUTH2_PROXY_SKIP_PROVIDER_BUTTON=false
      - OAUTH2_PROXY_PASS_ACCESS_TOKEN=true
      - OAUTH2_PROXY_PASS_USER_BEARER_TOKEN=true
      - OAUTH2_PROXY_SET_XAUTHREQUEST=true
    depends_on:
      - code-server
    restart: unless-stopped
    networks:
      - code-server-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4180/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF
echo -e "${GREEN}✓ Created oauth2-proxy docker-compose snippet${NC}"

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Phase 1 OIDC Configuration Complete${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Generate OAuth2 credentials:"
echo "   - Google OAuth2: https://console.cloud.google.com/apis/credentials"
echo "   - GitHub OAuth App: https://github.com/settings/developers"
echo ""
echo "2. Copy and populate credentials:"
echo "   cp config/iam/oidc/.env.template config/iam/oidc/.env"
echo "   # Edit with your credentials"
echo ""
echo "3. Update docker-compose.yml with oauth2-proxy service"
echo "   # Copy contents of config/iam/oidc/docker-compose.oauth2-proxy.yml"
echo ""
echo "4. Deploy and test:"
echo "   docker-compose up -d oauth2-proxy"
echo "   curl http://localhost:4180/ping"
echo ""
echo "Configuration files created:"
echo "  - $OAUTH2_CONFIG"
echo "  - $KEYCLOAK_CONFIG"
echo "  - config/iam/oidc/.env.template"
echo "  - config/iam/oidc/docker-compose.oauth2-proxy.yml"
echo ""
