## P1: SSO/SCIM Integration with Existing IdP

### Summary

Integrate Matrix homeserver with existing identity provider (Google Workspace) for Single Sign-On (SSO) and automated user provisioning (SCIM). Users should log into Matrix with the same credentials as code-server/Appsmith.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Google Workspace (IdP)                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • User directory                                        │   │
│  │ • OIDC provider                                         │   │
│  │ • SCIM provisioning (optional)                          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                               │
           ┌───────────────────┴───────────────────┐
           │ OIDC                                  │ SCIM (optional)
           ▼                                       ▼
┌─────────────────────┐                 ┌─────────────────────┐
│ Matrix Homeserver   │                 │ SCIM Provisioning   │
│ (OIDC Login)        │                 │ Service             │
└─────────────────────┘                 └─────────────────────┘
           │
           │ Same SSO session
           ▼
┌─────────────────────────────────────────────────────────────────┐
│              code-server / oauth2-proxy                         │
│              (Already using Google OIDC)                        │
└─────────────────────────────────────────────────────────────────┘
```

### SSO Configuration (OIDC)

```yaml
# Synapse homeserver.yaml OIDC configuration

oidc_providers:
  - idp_id: google
    idp_name: "Google Workspace"
    issuer: "https://accounts.google.com"
    client_id: ${GOOGLE_CLIENT_ID}
    client_secret: ${GOOGLE_CLIENT_SECRET}
    scopes: ["openid", "profile", "email"]
    user_mapping_provider:
      config:
        localpart_template: "{{ user.email.split('@')[0] }}"
        display_name_template: "{{ user.name }}"
        email_template: "{{ user.email }}"
    allow_existing_users: true
    # Only allow users from kushnir.cloud domain
    attribute_requirements:
      - attribute: "hd"
        value: "kushnir.cloud"
```

### SCIM Provisioning (Optional)

For automatic user creation/deactivation when users are added/removed in Google Workspace:

```yaml
# Element Server Suite Pro SCIM configuration

scim:
  enabled: true
  bearer_token: ${SCIM_BEARER_TOKEN}
  
  # User attribute mapping
  user_mapping:
    userName: "email"
    displayName: "name.formatted"
    active: "active"
    
  # Group mapping (optional)
  group_mapping:
    displayName: "name"
    members: "members"
```

### Google Workspace Configuration

1. **OIDC Client** (same as oauth2-proxy):
   - Client ID: Use existing or create new
   - Authorized redirect URIs: Add Matrix callback URL
   - `https://matrix.kushnir.cloud/_synapse/client/oidc/callback`

2. **SCIM** (if using Element Server Suite Pro):
   - Configure in Google Workspace Admin Console
   - Enable automatic provisioning

### Shared Session Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    User Login Flow                              │
│                                                                 │
│  1. User opens kushnir.cloud                                    │
│     └─→ oauth2-proxy redirects to Google OIDC                  │
│                                                                 │
│  2. User authenticates with Google                              │
│     └─→ Token returned to oauth2-proxy                         │
│                                                                 │
│  3. User opens Matrix client (Element) or Team Hub extension   │
│     └─→ Same Google OIDC session used                          │
│     └─→ No additional login required                           │
│                                                                 │
│  4. Matrix access token obtained from OIDC session             │
│     └─→ Team Hub extension uses token for Matrix API           │
└─────────────────────────────────────────────────────────────────┘
```

### Team Hub Extension Token Flow

```typescript
// extensions/team-hub/src/auth.ts

async function getMatrixAccessToken(): Promise<string> {
  // Option 1: Use oauth2-proxy X-Forwarded-Access-Token
  // Requires oauth2-proxy to pass Google access token
  const googleToken = await getGoogleTokenFromProxy();
  
  // Exchange Google token for Matrix token via OIDC
  const matrixToken = await exchangeForMatrixToken(googleToken);
  return matrixToken;
}

async function exchangeForMatrixToken(googleToken: string): Promise<string> {
  const response = await fetch(`${MATRIX_HOMESERVER}/_matrix/client/v3/login`, {
    method: 'POST',
    body: JSON.stringify({
      type: 'm.login.token',
      token: googleToken  // Or use OIDC-based login flow
    })
  });
  return response.json().access_token;
}
```

### Acceptance Criteria

- [ ] Matrix homeserver accepts Google OIDC login
- [ ] Users can SSO into Matrix with same Google credentials
- [ ] Domain restriction: Only kushnir.cloud users allowed
- [ ] User provisioning: Automatic Matrix account on first login
- [ ] Display name synced from Google profile
- [ ] Team Hub extension authenticates via SSO session
- [ ] No separate Matrix password required
- [ ] User deactivation synced (optional SCIM)
- [ ] Documentation for admin setup

### Environment Variables

```bash
# .env additions
MATRIX_OIDC_CLIENT_ID=${GOOGLE_CLIENT_ID}
MATRIX_OIDC_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
MATRIX_ALLOWED_DOMAIN=kushnir.cloud
```

### Terraform Configuration

```hcl
# terraform/modules/matrix-sso/main.tf

# Use same Google OAuth client as oauth2-proxy
data "google_secret_manager_secret_version" "google_client_secret" {
  secret = "google-oauth-client-secret"
}

# Configure Synapse OIDC
resource "kubernetes_config_map" "synapse_oidc" {
  metadata {
    name = "synapse-oidc-config"
  }
  
  data = {
    "oidc.yaml" = templatefile("${path.module}/templates/oidc.yaml.tpl", {
      client_id     = var.google_client_id
      client_secret = data.google_secret_manager_secret_version.google_client_secret.secret_data
      allowed_domain = var.allowed_domain
    })
  }
}
```

### Dependencies

- Requires: #1001 (Matrix homeserver deployed)
- Requires: Existing Google OAuth configuration (oauth2-proxy)
- Blocks: #1002 (Team Hub extension needs auth)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
