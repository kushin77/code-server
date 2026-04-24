# Matrix SSO Module - Google OIDC Integration

Terraform module for integrating Google Workspace SSO with Synapse Matrix homeserver using OpenID Connect (OIDC).

## Overview

This module configures Google OIDC authentication for Matrix, allowing team members to:
- Log in with Google Workspace credentials
- Automatic account provisioning on first login
- Display name synchronization from Google profiles
- Domain restriction to @kushnir.cloud only

**Status**: Phase 1 - OIDC Authentication  
**Phase 2 (Planned)**: SCIM user deprovisioning, group mapping, avatar sync

## Features

- ✅ **Google OIDC Integration**: Complete OpenID Connect provider configuration
- ✅ **Domain Restriction**: Only @kushnir.cloud users allowed
- ✅ **Auto-Provisioning**: Automatic Matrix account creation on first login
- ✅ **Profile Sync**: Display name from Google profile
- ✅ **Session Management**: 7-day default timeout with "Remember Me"
- ✅ **Rate Limiting**: DDoS and brute-force protection
- ✅ **Audit Logging**: Complete audit trail of auth events
- ⏳ **SCIM Deprovisioning**: Phase 2 integration
- ⏳ **Group Mapping**: Phase 2 - map Google groups to Matrix roles
- ⏳ **Avatar Sync**: Phase 2 - sync profile pictures

## Usage

### Basic Configuration

```hcl
module "matrix_sso" {
  source = "./modules/matrix-sso"

  environment            = "prod"
  synapse_homeserver_url = "https://matrix.kushnir.cloud"
  google_client_id       = var.google_client_id
  google_client_secret   = var.google_client_secret
  allowed_email_domain   = "kushnir.cloud"
  synapse_admin_token    = var.synapse_admin_token
  synapse_database_url   = "postgresql://synapse:pass@postgres/synapse"

  auto_provision_users   = true
  sync_display_name      = true
  deprovisioning_enabled = false  # Phase 2

  tags = {
    project = "matrix"
    owner   = "platform"
  }
}
```

### Google OAuth Setup

1. Create OAuth 2.0 credentials in [GCP Console](https://console.cloud.google.com)
2. Application type: Web application
3. Authorized redirect URIs:
   ```
   https://matrix.kushnir.cloud/_synapse/oidc/callback
   ```
4. Scopes: `openid`, `profile`, `email`
5. Enable Google+ API for directory integration

### Deploy & Verify

```bash
# Apply module
terraform apply -target=module.matrix_sso

# Output generated configuration files
terraform output matrix_sso.oidc_config_path

# Update Synapse homeserver.yaml
cat $(terraform output matrix_sso.oidc_patch_path) >> /srv/synapse/homeserver.yaml

# Restart Synapse
docker restart synapse-homeserver

# Verify integration
bash $(terraform output matrix_sso.health_check_script_path)
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `oidc_config_path` | Path to full OIDC provider configuration |
| `oidc_patch_path` | Patch for homeserver.yaml |
| `provisioning_script_path` | User provisioning script |
| `health_check_script_path` | OIDC integration verification script |
| `sso_setup_guide_path` | Complete setup documentation |
| `oidc_provider_id` | OIDC provider identifier (`google`) |
| `allowed_domain` | Enforced email domain |
| `auto_provisioning_enabled` | Whether auto-provisioning is active |

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | "prod" | Deployment environment |
| `synapse_homeserver_url` | string | required | Synapse URL (https://matrix.kushnir.cloud) |
| `google_client_id` | string | required | Google OAuth client ID |
| `google_client_secret` | string | required | Google OAuth client secret (sensitive) |
| `allowed_email_domain` | string | "kushnir.cloud" | Restrict login to this domain |
| `synapse_admin_token` | string | required | Synapse admin API token (sensitive) |
| `synapse_database_url` | string | required | PostgreSQL connection string (sensitive) |
| `auto_provision_users` | bool | true | Create Matrix accounts on first login |
| `sync_display_name` | bool | true | Sync Google profile display name |
| `deprovisioning_enabled` | bool | false | Enable SCIM deprovisioning (Phase 2) |
| `tags` | map(string) | {} | Resource tags |

## Configuration Files Generated

### 1. OIDC Provider Configuration (`oidc-provider.yaml`)

Complete OpenID Connect provider configuration with:
- Client credentials (ID, secret)
- Google issuer configuration
- User mapping templates
- Domain validation attributes
- Session management settings

### 2. Homeserver Patch (`homeserver-oidc.yaml`)

YAML snippet to add to `homeserver.yaml`:
- OIDC provider block
- User provisioning policy
- Domain restriction
- Admin API token reference

### 3. Domain Restriction Config

Environment variables for domain enforcement:
- `ALLOWED_EMAIL_DOMAIN`
- `AUTO_PROVISION_USERS`
- `SYNC_DISPLAY_NAME`
- Rate limiting settings

### 4. Health Check Script

Bash script to verify integration:
```bash
bash scripts/verify-oidc-integration.sh
# Output:
# ✓ Synapse running
# ✓ OIDC configuration
# ✓ Google OAuth discovery
# ✓ Domain restriction
# ✓ Auto-provisioning
# ✅ All checks passed
```

### 5. SSO Setup Guide

Complete documentation including:
- Quick start instructions
- Google OAuth configuration steps
- Deployment checklist
- Troubleshooting guide
- API reference
- Compliance notes (GDPR, SOC2)

## User Journey

### First-Time Login

```
User → Matrix Client
         ↓
     "Sign in with Google"
         ↓
     Redirect to Google
         ↓
     Google auth flow
         ↓
     Domain check (hd=kushnir.cloud)
         ↓
     Return to Synapse callback
         ↓
     Create Matrix account (auto-provisioning)
         ↓
     Issue session token
         ↓
     Logged in as alice_johnson
```

### Subsequent Logins

- SSO session cached (7-day TTL)
- Auto-login on revisit
- No password entry needed

## Security Features

### Authentication

- **OIDC Standards**: Full OAuth 2.0/OIDC compliance
- **Domain Validation**: Server-side hd claim verification
- **Token Validation**: Synapse validates with Google

### Session Management

- **Secure Cookies**: HttpOnly, Secure, SameSite=Strict
- **Session Timeout**: 7 days by default
- **Logout**: Clears Matrix tokens and OIDC sessions

### Rate Limiting

- 10 authentication attempts/minute
- 20-attempt burst allowance
- IP-based tracking (via oauth2-proxy)

### Audit Logging

- All auth events logged with timestamp
- User email and domain logged
- Success/failure tracking
- Anomaly detection ready

## Troubleshooting

### Users Cannot Login

```bash
# Check Synapse logs
docker logs synapse-homeserver | grep -i oidc

# Verify Google OAuth configuration
curl -s https://accounts.google.com/.well-known/openid-configuration | jq

# Test callback URL
curl -v https://matrix.kushnir.cloud/_synapse/oidc/callback
```

### Auto-Provisioning Not Working

```bash
# Check homeserver.yaml
grep -A 3 "auto_provision_users" /srv/synapse/homeserver.yaml

# Should show: auto_provision_users: true
```

### Display Names Not Syncing

```bash
# Check user mapping template
grep -A 5 "display_name_template" /srv/synapse/homeserver.yaml

# Restart Synapse
docker restart synapse-homeserver
```

## Cost

- **Software**: $0 (open source)
- **Integration**: Terraform module
- **Operational**: ~5 hours/month for monitoring

## Support Matrix

| Component | Status | Support |
|-----------|--------|---------|
| OIDC Auth | ✅ Phase 1 | Full |
| Auto-provisioning | ✅ Phase 1 | Full |
| Display name sync | ✅ Phase 1 | Full |
| SCIM deprovisioning | ⏳ Phase 2 | Planned Q3 2026 |
| Group mapping | ⏳ Phase 2 | Planned Q3 2026 |
| Avatar sync | ⏳ Phase 2 | Planned Q3 2026 |

## References

- [Matrix OIDC Spec](https://matrix-org.github.io/synapse/latest/modules/oidc_auth.html)
- [Google OAuth 2.0 Documentation](https://developers.google.com/identity/protocols/oauth2)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)

## Contributing

See main repository CONTRIBUTING.md for guidelines.

## License

Same as parent project (kushin77/code-server)
