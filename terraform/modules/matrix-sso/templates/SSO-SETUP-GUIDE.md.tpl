# Matrix SSO Integration Guide

## Overview

This module configures Google OIDC single sign-on for Synapse homeserver, allowing team members to log in with their Google Workspace credentials.

**Status**: Phase 1 (OIDC authentication)  
**Users Supported**: Only @${allowed_domain} accounts  
**Deprovisioning**: Phase 2 (SCIM integration)

---

## Quick Start

### 1. Prerequisites

- Google Cloud Project with OAuth 2.0 credentials
- Google Client ID and Client Secret (from [GCP Console](https://console.cloud.google.com))
- Synapse homeserver running (from module matrix-collab)
- Terraform access to update homeserver configuration

### 2. Configuration

Set these variables in terraform.tfvars:

```hcl
module "matrix_sso" {
  source = "./modules/matrix-sso"

  environment             = "prod"
  synapse_homeserver_url  = "https://matrix.${var.apex_domain}"
  google_client_id        = var.google_client_id
  google_client_secret    = var.google_client_secret
  allowed_email_domain    = "kushnir.cloud"
  synapse_admin_token     = var.synapse_admin_token
  synapse_database_url    = "postgresql://synapse:password@postgres:5432/synapse"
  
  auto_provision_users    = true
  sync_display_name       = true
  deprovisioning_enabled  = false  # Phase 2
}
```

### 3. Google OAuth Configuration

In [GCP Console](https://console.cloud.google.com):

1. Create OAuth 2.0 credentials (Web application type)
2. Add authorized redirect URIs:
   ```
   https://${HOMESERVER_DOMAIN}/_synapse/oidc/callback
   ```
3. Set scopes: `openid`, `profile`, `email`
4. Configure domain restrictions in Google Admin Console

### 4. Deploy OIDC Configuration

```bash
# Apply Terraform
terraform apply -target=module.matrix_sso

# Update Synapse homeserver.yaml
cat $(terraform output sso.oidc_patch_path) >> /srv/synapse/homeserver.yaml

# Restart Synapse
docker restart synapse-homeserver

# Verify integration
bash $(terraform output sso.health_check_script_path)
```

---

## Features

### ✅ Implemented (Phase 1)

- **OIDC Authentication**: Google Workspace login
- **Domain Restriction**: Only @${allowed_domain} users
- **Auto-provisioning**: Automatic Matrix account creation on first login
- **Profile Sync**: Display name from Google profile
- **Session Management**: 7-day session timeout with optional "Remember Me"
- **Rate Limiting**: 10 attempts/minute with 20-burst protection
- **Logging**: Audit trail of all authentication events

### ⏳ Planned (Phase 2)

- **SCIM Integration**: Automatic user deprovisioning when removed from Google
- **Avatar Sync**: Profile picture from Google workspace
- **Group Mapping**: Map Google groups to Matrix roles (user/moderator/admin)
- **2FA Enforcement**: Require 2FA for Synapse admin users
- **Conditional Access**: IP-based or device-based restrictions

---

## User Experience

### First-Time Login

1. User navigates to `https://matrix.kushnir.cloud` (or Element client)
2. Clicks "Sign in with Google"
3. Redirected to Google login page
4. Google performs domain check (hd=kushnir.cloud)
5. Redirected back to Synapse
6. Matrix account automatically created (if auto-provisioning enabled)
7. User logged in as `firstname.lastname`

### Subsequent Logins

1. SSO session cached (7-day default)
2. Auto-login on next visit
3. "Forgot password" unavailable (OIDC-managed only)

### Admin Tasks

Register an existing user as admin (one-time):

```bash
# SSH to Synapse server
docker exec synapse-homeserver /usr/local/bin/register_new_matrix_user \
  -c /data/homeserver.yaml \
  -a \
  -u alice \
  https://matrix.kushnir.cloud
```

Or use admin API:

```bash
curl -X POST https://matrix.kushnir.cloud/_synapse/admin/v2/users/alice:matrix.kushnir.cloud/admin \
  -H "Authorization: Bearer $SYNAPSE_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"admin": true}'
```

---

## Troubleshooting

### Users Cannot Login

**Symptom**: "Invalid OIDC response" or redirect loop

**Checks**:
1. Google Client ID and Secret are correct
2. Redirect URI matches exactly: `https://${HOMESERVER}/_synapse/oidc/callback`
3. Google Admin Console allows ${allowed_domain} users
4. Synapse logs show OIDC discovery success:
   ```bash
   docker logs synapse-homeserver | grep -i oidc
   ```

**Fix**:
```bash
# Verify OIDC configuration
curl https://matrix.kushnir.cloud/.well-known/openid-configuration

# Check homeserver.yaml OIDC section
grep -A 20 "oidc_providers:" /srv/synapse/homeserver.yaml
```

### Auto-Provisioning Not Working

**Symptom**: User logs in successfully but no Matrix account created

**Cause**: `auto_provision_users: false` in homeserver.yaml

**Fix**:
```bash
# Edit homeserver.yaml
echo "auto_provision_users: true" >> /srv/synapse/homeserver.yaml

# Restart
docker restart synapse-homeserver
```

### Display Names Not Syncing

**Symptom**: Users show as `alice` instead of `Alice Johnson`

**Cause**: `sync_displayname_from_oidc: false` or OIDC mapping template issue

**Fix**:
```bash
# Check template in homeserver.yaml
grep -A 5 "display_name_template" /srv/synapse/homeserver.yaml

# Update and restart
docker restart synapse-homeserver
```

### Admin API Not Accessible

**Symptom**: "Unauthorized" when calling `/_synapse/admin/*`

**Fix**: Set admin token environment variable
```bash
# In docker-compose.yml
environment:
  - SYNAPSE_ADMIN_TOKEN=${SYNAPSE_ADMIN_TOKEN}

# Restart
docker-compose up -d synapse
```

---

## Security Considerations

### ✅ Implemented

- **Domain Restriction**: Only ${allowed_domain} users can login
- **HTTPS Enforcement**: All OIDC callbacks use HTTPS
- **Token Validation**: Synapse validates OIDC tokens with Google
- **Session Security**: Secure, HttpOnly cookies
- **Rate Limiting**: Brute force protection
- **Audit Logging**: All auth events logged
- **No Password Storage**: Credentials managed by Google

### ⚠️ Important

1. **Protect Admin Token**: `SYNAPSE_ADMIN_TOKEN` is highly sensitive
   - Store in secret manager (not env vars)
   - Rotate regularly
   - Use strong random value (min 32 chars)

2. **Google OAuth Security**:
   - Enable 2FA in Google Admin Console
   - Review authorized redirect URIs quarterly
   - Monitor "Suspicious activity" reports

3. **Synapse Access**:
   - Place behind reverse proxy (Caddy)
   - Require authentication for `/_synapse/admin/*`
   - Enable rate limiting

---

## API Reference

### User Provisioning (Admin API)

Create user via API:

```bash
curl -X POST https://matrix.kushnir.cloud/_synapse/admin/v2/users/@alice:kushnir.cloud \
  -H "Authorization: Bearer $SYNAPSE_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "password": "unused_with_oidc",
    "auth_provider": "oidc",
    "displayname": "Alice Johnson",
    "admin": false
  }'
```

Deactivate user (Phase 2 - SCIM):

```bash
curl -X POST https://matrix.kushnir.cloud/_synapse/admin/v2/users/@alice:kushnir.cloud/deactivate \
  -H "Authorization: Bearer $SYNAPSE_ADMIN_TOKEN" \
  -H "Content-Type: application/json"
```

### Health Check

Verify OIDC integration:

```bash
# Run health check
bash scripts/verify-oidc-integration.sh

# Output:
# ✓ Synapse running
# ✓ OIDC provider configured
# ✓ Google OAuth discovery OK
# ✓ Domain restriction active
# ✓ Auto-provisioning enabled
```

---

## Compliance & Auditing

### GDPR

- Users can request data deletion via `/_synapse/admin/v2/users` endpoint
- All personal data (display name, email) deletable
- Audit logs retained per company policy (90 days default)

### SOC 2

- All authentication events logged
- Session tokens encrypted (TLS)
- Admin API access logged
- Metrics exported for monitoring

---

## Support & Escalation

| Issue | Severity | Contact | SLA |
|-------|----------|---------|-----|
| Login failures (>5% users) | P0 | On-call | 1 hour |
| Slow authentication (<5 users) | P2 | Platform team | 4 hours |
| Profile sync issues | P2 | Platform team | 1 day |
| Feature request (SCIM, groups) | P3 | Backlog | Next sprint |

---

## References

- [Synapse OIDC Module](https://matrix-org.github.io/synapse/latest/modules/oidc_auth.html)
- [Google OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)
- [OIDC Standard](https://openid.net/connect/)
- [Matrix Client API - Login](https://spec.matrix.org/unstable/client-server-api/#login)

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-22 | Initial OIDC integration guide (Phase 1) |

