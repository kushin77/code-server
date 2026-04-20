## P3: Air-Gapped Deployment Configuration for Regulated Environments

### Summary

Configure Matrix collaboration stack for air-gapped (network-isolated) environments to support regulated industries (government, healthcare, finance) with no external network dependencies.

### Air-Gap Requirements

| Requirement | Implementation |
|-------------|----------------|
| **No External DNS** | All services resolve via internal DNS/hosts |
| **No External Network** | Zero outbound connections required |
| **Offline Images** | Pre-pulled container images |
| **Local SSO** | On-prem IdP (Keycloak, AD FS) |
| **No Federation** | Matrix federation disabled |
| **No External Bridges** | No Slack/Teams/Google (or internal-only) |

### Architecture (Air-Gapped)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Air-Gapped Network                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                 Matrix Homeserver                        │   │
│  │  • Federation: DISABLED                                  │   │
│  │  • External API calls: NONE                              │   │
│  │  • SSO: Internal Keycloak/AD FS                          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │ Internal Services                                         │ │
│  │ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐  │ │
│  │ │ code-server │ │ Element Web │ │ Presence Sidecar   │  │ │
│  │ │ + Team Hub  │ │ (Local)     │ │ (Internal Only)    │  │ │
│  │ └─────────────┘ └─────────────┘ └─────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │ Internal Infrastructure                                   │ │
│  │ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐  │ │
│  │ │ PostgreSQL  │ │ Redis       │ │ Internal DNS        │  │ │
│  │ │ (Local)     │ │ (Local)     │ │ (CoreDNS/hosts)     │  │ │
│  │ └─────────────┘ └─────────────┘ └─────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ❌ No Internet Connection                                      │
│  ❌ No External DNS Resolution                                  │
│  ❌ No Federation with External Matrix Servers                  │
│  ❌ No Slack/Teams/Google Chat Bridges                          │
└─────────────────────────────────────────────────────────────────┘
```

### Homeserver Configuration (Air-Gapped)

```yaml
# homeserver.yaml for air-gapped deployment

server_name: "matrix.internal.corp"

# CRITICAL: Disable federation
federation_domain_whitelist: []
allow_public_rooms_over_federation: false
allow_public_rooms_without_auth: false

# CRITICAL: Disable external HTTP requests
enable_url_preview: false
max_spider_size: 0
url_preview_ip_range_blacklist:
  - '0.0.0.0/0'  # Block all external IPs

# No metrics reporting
enable_metrics: true  # Internal only
report_stats: false

# Internal OIDC (Keycloak/AD FS)
oidc_providers:
  - idp_id: internal
    idp_name: "Corporate SSO"
    issuer: "https://keycloak.internal.corp/auth/realms/matrix"
    client_id: "${INTERNAL_OIDC_CLIENT_ID}"
    client_secret: "${INTERNAL_OIDC_CLIENT_SECRET}"
    scopes: ["openid", "profile", "email"]
```

### Offline Container Images

```bash
# Pre-pull and save images for air-gapped transfer

# On internet-connected machine:
docker pull matrixdotorg/synapse:v1.98.0
docker pull vectorim/element-web:v1.11.55
docker pull kushin77/presence-sidecar:v1.0.0
docker pull livekit/livekit-server:v1.4.0

docker save matrixdotorg/synapse:v1.98.0 > synapse.tar
docker save vectorim/element-web:v1.11.55 > element-web.tar
docker save kushin77/presence-sidecar:v1.0.0 > presence-sidecar.tar
docker save livekit/livekit-server:v1.4.0 > livekit.tar

# Transfer via secure media to air-gapped network

# On air-gapped host:
docker load < synapse.tar
docker load < element-web.tar
docker load < presence-sidecar.tar
docker load < livekit.tar
```

### Internal DNS Configuration

```yaml
# CoreDNS Corefile for air-gapped Matrix

.:53 {
    hosts {
        192.168.168.31 matrix.internal.corp
        192.168.168.31 element.internal.corp
        192.168.168.31 presence.internal.corp
        192.168.168.31 call.internal.corp
        192.168.168.31 keycloak.internal.corp
        fallthrough
    }
    forward . /etc/resolv.conf
    cache 30
    log
}
```

### Terraform Variables (Air-Gapped Mode)

```hcl
# terraform/environments/airgap/terraform.tfvars

environment = "airgap"
airgap_mode = true

# No external services
enable_slack_bridge = false
enable_teams_bridge = false
enable_google_chat_bridge = false
enable_google_meet = false  # Use Element Call instead

# Internal SSO
oidc_issuer = "https://keycloak.internal.corp/auth/realms/matrix"
oidc_client_id = "matrix-client"
oidc_client_secret_from_gsm = false  # Use local secret

# No federation
federation_enabled = false

# Local DNS
matrix_domain = "matrix.internal.corp"
use_internal_dns = true

# Offline images
synapse_image = "matrixdotorg/synapse:v1.98.0"  # Pinned, pre-loaded
element_image = "vectorim/element-web:v1.11.55"
```

### Validation Checklist

```bash
#!/usr/bin/env bash
# scripts/ops/validate-airgap.sh

# Verify no external DNS resolution
nslookup matrix.org 2>&1 | grep -q "NXDOMAIN" || echo "FAIL: External DNS works"

# Verify no outbound HTTP
curl -s --connect-timeout 5 https://matrix.org && echo "FAIL: External HTTP works"

# Verify federation disabled
curl -s http://matrix.internal.corp:8008/_matrix/federation/v1/version | \
  grep -q "404" && echo "PASS: Federation disabled"

# Verify internal DNS
nslookup matrix.internal.corp && echo "PASS: Internal DNS works"

# Verify container images loaded
docker images | grep -q "synapse" && echo "PASS: Synapse image loaded"
docker images | grep -q "element-web" && echo "PASS: Element image loaded"
```

### Compliance Documentation

```markdown
# Air-Gapped Deployment Compliance Attestation

## Network Isolation Verification
- [ ] No external DNS resolution
- [ ] No outbound HTTP/HTTPS connections
- [ ] Federation disabled in Matrix homeserver
- [ ] All container images loaded from approved registry

## Data Sovereignty
- [ ] All data stored on internal storage
- [ ] No external cloud services
- [ ] Backups stored on internal backup system

## Identity Management
- [ ] SSO via internal IdP (Keycloak/AD FS)
- [ ] No external identity provider connections
- [ ] User provisioning via internal SCIM

## Audit Trail
- [ ] All administrative actions logged
- [ ] Logs stored on internal SIEM
- [ ] Retention policy: [X] years

Certified By: ___________________
Date: ___________________
```

### Acceptance Criteria

- [ ] Homeserver configured for zero external network
- [ ] Federation completely disabled
- [ ] Internal OIDC (Keycloak/AD FS) integrated
- [ ] Container images pre-loaded (no Docker Hub pulls)
- [ ] Internal DNS configured
- [ ] Element Call works without external dependencies
- [ ] Validation script passes all checks
- [ ] Compliance attestation document created
- [ ] Terraform module for air-gapped deployment
- [ ] Runbook for image updates

### Dependencies

- Requires: #1001 (Matrix architecture - air-gapped variant)
- Requires: #1008 (Element Call - replaces Google Meet)
- Optional: Internal SSO (Keycloak deployment)

### Parent

EPIC #TBD (Matrix Collaboration Hub)
