# Domain Restriction Configuration for Matrix OIDC
# Validates all login attempts against allowed domain
# Deployed as part of Matrix authentication middleware

ALLOWED_EMAIL_DOMAIN="${allowed_domain}"
MATRIX_HOMESERVER_URL="${homeserver_url}"
SYNAPSE_ADMIN_TOKEN="${admin_token}"

# Domain validation strategy
# - STRICT: Only ${allowed_domain} users allowed (default)
# - PERMISSIVE: Log but allow other domains (testing only)
DOMAIN_VALIDATION_MODE="STRICT"

# User provisioning settings
AUTO_PROVISION_USERS="true"
AUTO_PROVISION_ROLE="user"  # Options: user, admin, moderator

# Display name sync
SYNC_DISPLAY_NAME_FROM_PROFILE="true"
SYNC_AVATAR_FROM_PROFILE="false"

# Account deprovisioning (Phase 2 - SCIM)
DEPROVISIONING_ENABLED="false"
SCIM_ENABLED="false"

# Logging and monitoring
LOG_LEVEL="INFO"
LOG_AUTH_EVENTS="true"
METRICS_ENABLED="true"

# Rate limiting for auth attempts
RATE_LIMIT_ENABLED="true"
RATE_LIMIT_PER_MINUTE=10
RATE_LIMIT_BURST=20

# Session settings
SESSION_TIMEOUT_MINUTES=10080  # 7 days
REMEMBER_ME_ENABLED="true"
REMEMBER_ME_TIMEOUT_DAYS=30

# Security headers
ENFORCE_HTTPS="true"
SECURE_COOKIES="true"
SAMESITE_POLICY="Strict"
