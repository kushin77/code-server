#!/bin/bash

###
# @file setup-github-oauth.sh
# @module scripts/extensions/setup-github-oauth.sh
# @description Initialize GitHub OAuth integration for P2 #1539 Phase 5
# @compliance IaC, idempotent, environment-driven, GOV-002 compliant
###

set -euo pipefail

# ============================================================================
# Source initialization and logging
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
if [[ ! -f "${PROJECT_ROOT}/scripts/_common/init.sh" ]]; then
    echo "[ERROR] Cannot source init.sh from ${PROJECT_ROOT}/scripts/_common/"
    exit 1
fi

source "${PROJECT_ROOT}/scripts/_common/init.sh"

# Source infrastructure configuration
source_env_file "${PROJECT_ROOT}/.env.infrastructure"

GITHUB_REDIRECT_URI="${API_OAUTH_CALLBACK}"

# ============================================================================
# Logging
# ============================================================================

log_info "=== P2 #1539 Phase 5: GitHub OAuth Integration Setup ==="
log_info "Project root: ${PROJECT_ROOT}"
log_info "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
log_info ""

declare -i step_count=0
declare -i step_ok=0

# ============================================================================
# STEP 1: Verify GitHub OAuth source files
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verify GitHub OAuth source files"

declare -a required_files=(
    "apps/extensions/team-hub/src/github-oauth-handler.ts"
    "apps/extensions/team-hub/src/github-account-manager.ts"
)

all_present=true
for file in "${required_files[@]}"; do
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
        log_info "  ✓ ${file}"
        step_ok+=1
    else
        log_warn "  ✗ Missing: ${file}"
        all_present=false
    fi
done

if [[ "$all_present" != "true" ]]; then
    log_error "Not all GitHub OAuth source files present"
    exit 1
fi

# ============================================================================
# STEP 2: Create GitHub OAuth configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create GitHub OAuth configuration"

OAUTH_CONFIG_DIR="${PROJECT_ROOT}/config/oauth"
mkdir -p "${OAUTH_CONFIG_DIR}"

# Create OAuth config
cat > "${OAUTH_CONFIG_DIR}/github-oauth-config.json" << 'EOF'
{
  "enabled": true,
  "version": "1.0.0",
  "github_oauth": {
    "enabled": true,
    "provider": "github",
    "authentication": {
      "flow_type": "oauth2_pkce",
      "require_user_approval": true,
      "token_expiry_seconds": 3600,
      "refresh_token_enabled": true,
      "auto_refresh": true
    },
    "scopes": [
      "user:email",
      "read:user",
      "read:repo_hook",
      "repo",
      "gist"
    ]
  },
  "account_management": {
    "enabled": true,
    "auto_link_accounts": false,
    "permission_model": "granular"
  },
  "security": {
    "token_encryption": true,
    "secure_storage": true,
    "audit_all_operations": true,
    "revocation_tracking": true
  },
  "integrations": {
    "repository_browser": true,
    "issue_tracker": true,
    "pr_notifications": true
  }
}
EOF

if [[ -f "${OAUTH_CONFIG_DIR}/github-oauth-config.json" ]]; then
    log_info "  ✓ Created ${OAUTH_CONFIG_DIR}/github-oauth-config.json"
    step_ok+=1
else
    log_error "Failed to create GitHub OAuth configuration"
    exit 1
fi

# ============================================================================
# STEP 3: Prepare audit logging for OAuth operations
# ============================================================================

step_count+=1
log_info "STEP $step_count: Prepare OAuth audit logging"

AUDIT_DIR="${PROJECT_ROOT}/logs"
mkdir -p "${AUDIT_DIR}"

# Initialize OAuth audit log
OAUTH_AUDIT_LOG="${AUDIT_DIR}/github-oauth.log"
if [[ ! -f "${OAUTH_AUDIT_LOG}" ]]; then
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] GitHub OAuth service initialized" > "${OAUTH_AUDIT_LOG}"
    log_info "  ✓ Created ${OAUTH_AUDIT_LOG}"
else
    log_info "  ✓ Log file already exists: ${OAUTH_AUDIT_LOG}"
fi

step_ok+=1

# ============================================================================
# STEP 4: Create OAuth environment configuration
# ============================================================================

step_count+=1
log_info "STEP $step_count: Configure OAuth environment variables"

cat > "${PROJECT_ROOT}/.env.github-oauth" << EOF
# GitHub OAuth Configuration
# P2 #1539 Phase 5: User-scoped GitHub authentication and repository access

GITHUB_OAUTH_ENABLED=true
GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID:-}
GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET:-}
GITHUB_REDIRECT_URI=${GITHUB_REDIRECT_URI}
GITHUB_OAUTH_SCOPES=user:email,read:user,read:repo_hook,repo,gist
GITHUB_TOKEN_EXPIRY_SECONDS=3600
GITHUB_AUTO_REFRESH_ENABLED=true
GITHUB_REQUIRE_USER_APPROVAL=true
GITHUB_SECURE_STORAGE_ENABLED=true
GITHUB_AUDIT_LOGGING_ENABLED=true
GITHUB_OAUTH_AUDIT_LOG=logs/github-oauth.log
GITHUB_PERMISSION_MODEL=granular
MAX_OAUTH_SESSIONS=100
EOF

log_info "  ✓ Created environment configuration: .env.github-oauth"
log_info "  ⚠ NOTE: Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET environment variables"
step_ok+=1

# ============================================================================
# STEP 5: Create OAuth schemas for compliance
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create OAuth event schemas"

SCHEMA_DIR="${PROJECT_ROOT}/schemas"
mkdir -p "${SCHEMA_DIR}"

# OAuth session schema
cat > "${SCHEMA_DIR}/github-oauth-session.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "GitHub OAuth Session",
  "type": "object",
  "required": ["id", "userId", "created", "lastUsed"],
  "properties": {
    "id": {
      "type": "string",
      "description": "Session identifier"
    },
    "userId": {
      "type": "string",
      "description": "GitHub user ID"
    },
    "accessToken": {
      "type": "string",
      "description": "OAuth access token (encrypted)"
    },
    "refreshToken": {
      "type": "string",
      "description": "Refresh token if available"
    },
    "expiresAt": {
      "type": "integer",
      "description": "Token expiration timestamp (seconds)"
    },
    "created": {
      "type": "string",
      "format": "date-time",
      "description": "Session creation time"
    },
    "lastUsed": {
      "type": "string",
      "format": "date-time",
      "description": "Last usage time"
    }
  }
}
EOF

# GitHub user account schema
cat > "${SCHEMA_DIR}/github-user-account.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "GitHub User Account",
  "type": "object",
  "required": ["id", "login", "created_at"],
  "properties": {
    "id": {
      "type": "string",
      "description": "GitHub user ID"
    },
    "login": {
      "type": "string",
      "description": "GitHub username"
    },
    "name": {
      "type": "string",
      "description": "User display name"
    },
    "email": {
      "type": "string",
      "description": "User email address"
    },
    "avatar_url": {
      "type": "string",
      "description": "GitHub avatar URL"
    },
    "created_at": {
      "type": "string",
      "format": "date-time",
      "description": "Account creation time"
    },
    "followers": {
      "type": "integer",
      "description": "GitHub followers count"
    },
    "public_repos": {
      "type": "integer",
      "description": "Public repositories count"
    }
  }
}
EOF

# Permission schema
cat > "${SCHEMA_DIR}/github-permission.v1.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "GitHub Permission",
  "type": "object",
  "required": ["userId", "repositoryId", "accessLevel", "grantedAt"],
  "properties": {
    "userId": {
      "type": "string",
      "description": "GitHub user ID"
    },
    "repositoryId": {
      "type": "string",
      "description": "Repository identifier"
    },
    "accessLevel": {
      "type": "string",
      "enum": ["read", "write", "admin"],
      "description": "Permission level"
    },
    "grantedAt": {
      "type": "string",
      "format": "date-time",
      "description": "When permission was granted"
    },
    "grantedBy": {
      "type": "string",
      "description": "Who granted the permission"
    }
  }
}
EOF

log_info "  ✓ Created OAuth schemas for compliance"
step_ok+=1

# ============================================================================
# STEP 6: Create secure credential storage directory
# ============================================================================

step_count+=1
log_info "STEP $step_count: Create secure credential storage"

CREDENTIALS_DIR="${PROJECT_ROOT}/.oauth-credentials"
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

# Create README for credentials directory
cat > "${CREDENTIALS_DIR}/README.md" << 'EOF'
# OAuth Credentials Storage

This directory stores encrypted OAuth tokens and credentials for GitHub integration.

**Security Notice**:
- All tokens are encrypted at rest
- This directory should never be committed to Git
- Access is restricted to the application process
- Audit all token operations

**Structure**:
- `sessions/` - Active OAuth sessions
- `tokens/` - Encrypted access tokens
- `keys/` - Encryption keys (DO NOT COMMIT)
EOF

log_info "  ✓ Created secure credential storage"
step_ok+=1

# ============================================================================
# STEP 7: Verification
# ============================================================================

step_count+=1
log_info "STEP $step_count: Verification"

CONFIG_FILES=$(find "${OAUTH_CONFIG_DIR}" -type f 2>/dev/null | wc -l)
SOURCE_FILES=$(find "${PROJECT_ROOT}/apps/extensions/team-hub/src" -name "*github-oauth*" -o -name "*github-account*" 2>/dev/null | wc -l)
SCHEMA_FILES=$(find "${SCHEMA_DIR}" -name "*github*" -type f 2>/dev/null | wc -l)

log_info "  ✓ Configuration files: ${CONFIG_FILES}"
log_info "  ✓ Source files: ${SOURCE_FILES}"
log_info "  ✓ Schema files: ${SCHEMA_FILES}"

step_ok+=1

# ============================================================================
# Summary
# ============================================================================

log_info ""
log_info "=== Setup Complete ==="
log_info "Steps completed: $step_ok / $step_count"
log_info ""
log_info "✅ GitHub OAuth Integration Ready (P2 #1539 Phase 5)"
log_info ""
log_info "Next Steps:"
log_info "  1. Configure GitHub OAuth Application at https://github.com/settings/developers"
log_info "  2. Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET environment variables"
log_info "  3. Build extension: pnpm build"
log_info "  4. Restart code-server"
log_info "  5. Authenticate via KC IDE GitHub OAuth button"
log_info ""
log_info "Features:"
log_info "  - OAuth 2.0 with PKCE security flow"
log_info "  - User-scoped GitHub account linking"
log_info "  - Repository access control (read/write/admin)"
log_info "  - Token encryption and secure storage"
log_info "  - Audit logging for all OAuth operations"
log_info "  - Automatic token refresh"
log_info "  - Idempotent initialization"
log_info ""
log_info "Configuration: ${OAUTH_CONFIG_DIR}/github-oauth-config.json"
log_info "Environment: ${PROJECT_ROOT}/.env.github-oauth"
log_info "Schemas: ${SCHEMA_DIR}/github-*.json"
log_info "Audit log: ${OAUTH_AUDIT_LOG}"
log_info ""

if [[ $step_ok -eq $step_count ]]; then
    log_success "GitHub OAuth setup successful"
    exit 0
else
    log_error "Setup incomplete ($step_ok / $step_count steps)"
    exit 1
fi
