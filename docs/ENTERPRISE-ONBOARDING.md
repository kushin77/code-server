#!/usr/bin/env markdown
# Enterprise Onboarding Guide — ElevatedIQ Whitelabel Deployment

**Version**: 1.0  
**Last Updated**: April 23, 2026  
**Audience**: Enterprise customers, DevOps teams

---

## Overview

This guide walks you through deploying ElevatedIQ as a whitelabel solution under your own domain, branding, and identity provider.

**Key Features**:
- ✅ Custom domain (your-company.com)
- ✅ Custom branding (logo, colors, title)
- ✅ Your OAuth provider (Google Workspace, Okta, Azure AD)
- ✅ Complete data isolation from other customers
- ✅ Automated deployment via CLI or Terraform

---

## 1. Pre-Deployment Requirements

### 1.1 Information to Gather

| Item | Example | Where to Find |
|------|---------|---------------|
| Customer ID | `acme-corp` | Your company identifier |
| Apex Domain | `acme-corp.com` | Your company domain |
| Email Domain | `acme-corp.com` | Your corporate email domain |
| OAuth Provider | `google` / `okta` / `azure-ad` | Your identity system |

### 1.2 Infrastructure Prerequisites

**On-Premises (Recommended for Enterprise)**:
- Linux server (Ubuntu 20.04+) with Docker and Docker Compose
- 16+ GB RAM, 100 GB SSD
- Network access to NAS server
- External load balancer with health checks
- Static IP or DNS A record capability

**Or Use Kubernetes**:
- Helm charts available in `helm/charts/whitelabel/`
- 2+ nodes with 8GB each
- Persistent volume claims for PostgreSQL, Redis, NAS mount

**Or Use AWS/GCP** (Coming soon):
- Terraform modules in `terraform/modules/whitelabel-customer/`

---

## 2. Step 1: Provision OAuth Application

### Google Workspace (Most Common)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create new project: `ElevatedIQ — Acme Corp`
3. Enable APIs:
   - Google+ API
   - Gmail API (optional, for email features)
4. Create OAuth 2.0 Consent Screen:
   - User Type: Internal
   - App name: "Acme Corp IDE"
   - Support email: your-email@acme-corp.com
5. Create OAuth 2.0 Credentials (Web Application):
   - **Authorized JavaScript origins**: `https://auth.acme-corp.com`
   - **Authorized redirect URIs**: 
     - `https://auth.acme-corp.com/oauth2/callback`
     - `https://ide.acme-corp.com/auth/callback`
6. **Copy and save**:
   - Client ID: ______________________________
   - Client Secret: ______________________________

### Okta (Enterprise)

1. Log in to Okta admin console
2. Create new application:
   - Application type: Web
   - Framework: Secure Web Authentication
3. Configure OIDC:
   - Sign-in redirect URI: `https://auth.acme-corp.com/oauth2/callback`
   - Sign-out redirect URI: `https://auth.acme-corp.com/logout`
4. Assign to your company's user group
5. **Copy and save**:
   - Client ID: ______________________________
   - Client Secret: ______________________________

### Azure AD

1. Sign in to [Azure Portal](https://portal.azure.com)
2. Go to Azure AD > App registrations
3. Create new registration:
   - Name: "ElevatedIQ — Acme Corp"
4. Configure Redirect URI:
   - Platform: Web
   - Redirect URI: `https://auth.acme-corp.com/auth/callback`
5. Create client secret (Certificates & secrets)
6. **Copy and save**:
   - Client ID (Application ID): ______________________________
   - Client Secret: ______________________________

---

## 3. Step 2: Set Up DNS Records

Create these DNS records in your registrar:

```dns
# Apex domain
acme-corp.com          A    203.0.113.42        (your load balancer IP)

# Subdomains
ide.acme-corp.com      CNAME  acme-corp.com      (or point to LB IP)
auth.acme-corp.com     CNAME  acme-corp.com      (OAuth2 proxy)
api.acme-corp.com      CNAME  acme-corp.com      (API gateway)
```

**Verify DNS propagation**:
```bash
nslookup ide.acme-corp.com
dig +short auth.acme-corp.com
```

---

## 4. Step 3: Deploy ElevatedIQ

### Option A: Automated Script (Recommended)

```bash
# Clone ElevatedIQ repository
git clone https://github.com/kushin77/code-server.git
cd code-server

# Run deployment script
bash scripts/deploy-enterprise-customer.sh acme-corp acme-corp.com acme-corp.com google

# This generates:
# - customers/acme-corp/branding.yaml
# - customers/acme-corp/.env.customer
# - customers/acme-corp/Caddyfile
# - customers/acme-corp/docker-compose.override.yml
# - customers/acme-corp/ONBOARDING.md
# - customers/acme-corp/terraform.tfvars
```

### Option B: Terraform (For AWS/GCP)

```bash
# Deploy using Terraform module
cd terraform/live/acme-corp
terraform init
terraform apply -var-file=acme-corp.tfvars

# Outputs will show:
# - ide_domain = ide.acme-corp.com
# - auth_domain = auth.acme-corp.com
# - database_name = elevatediq_acme_corp
```

### Option C: Manual (Advanced)

1. Copy `config/branding.yaml.example` → `customers/acme-corp/branding.yaml`
2. Edit with your branding (logo, colors, domain)
3. Create `.env.customer` with OAuth credentials
4. Create `docker-compose.override.yml` with your settings
5. Run: `docker compose -f docker-compose.yml -f customers/acme-corp/docker-compose.override.yml up -d`

---

## 5. Step 4: Verify Deployment

### Health Checks

```bash
# Check IDE is running
curl https://ide.acme-corp.com/health

# Check OAuth2 proxy
curl -I https://auth.acme-corp.com/

# Check API
curl https://api.acme-corp.com/health

# Check logs
docker compose logs -f code-server
docker compose logs -f oauth2-proxy
docker compose logs -f caddy
```

### Test User Access

1. Open https://ide.acme-corp.com
2. Click "Sign in with Google/Okta/Azure"
3. Authenticate with your corporate account
4. Verify you see custom branding (logo, colors, welcome message)
5. Verify you can open a terminal and run commands

### Data Isolation Verification

```bash
# Check database
psql -h localhost -U postgres -d elevatediq_acme_corp -c "SELECT COUNT(*) FROM users;"

# Check NAS storage
ls -la /nas/persistent/acme-corp/

# Check no cross-customer data leakage
# (user from acme-corp should not see data from other customers)
```

---

## 6. Production Checklist

- [ ] Domain DNS records created and verified
- [ ] OAuth application configured with your provider
- [ ] Custom logo and branding uploaded to CDN
- [ ] HTTPS certificates auto-provisioned (TLS working)
- [ ] All health checks passing
- [ ] User authentication working
- [ ] Data isolation verified (no cross-tenant leakage)
- [ ] Backups configured (NAS path /nas/persistent/acme-corp/)
- [ ] High availability enabled (if 2+ replicas)
- [ ] Monitoring/alerting set up (Prometheus + Grafana)
- [ ] Support contacts updated in config
- [ ] End-user documentation prepared

---

## 7. Ongoing Operations

### Daily

- Monitor health endpoints
- Check for errors in logs
- Review incident feed (if using knowledge graph)

### Weekly

- Review user activity and compliance logs
- Check backup status
- Verify all DNS records still resolve

### Monthly

- Review feature usage (control plane statistics)
- Update branding/assets if needed
- Plan any infrastructure scaling

### Quarterly

- Review compliance reports (SOC2, NIST)
- Audit user access and permissions
- Plan security updates

---

## 8. Troubleshooting

### "Connection refused" when accessing IDE

**Cause**: Docker containers not running

**Fix**:
```bash
docker compose ps  # Check all running
docker compose up -d  # Start if needed
docker compose logs code-server  # Check errors
```

### "Authentication failed" on OAuth login

**Cause**: OAuth credentials incorrect or mismatched

**Fix**:
1. Verify OAuth Client ID matches in .env.customer
2. Verify OAuth Client Secret is correct
3. Check OAuth redirect URI matches exactly: `https://auth.acme-corp.com/oauth2/callback`
4. Verify email domain matches: `OAUTH2_PROXY_EMAIL_DOMAIN=acme-corp.com`
5. Restart oauth2-proxy: `docker compose restart oauth2-proxy`

### "Certificate not valid" HTTPS error

**Cause**: Caddy can't auto-renew TLS certificate

**Fix**:
```bash
# Verify DNS resolves
nslookup ide.acme-corp.com

# Check Caddy logs
docker compose logs caddy

# Force cert renewal
docker compose exec caddy caddy reload

# Verify cert expiry
openssl s_client -connect ide.acme-corp.com:443 < /dev/null | grep -A 2 "Validity"
```

### "Only admin users allowed" error

**Cause**: User email domain doesn't match configured domain

**Fix**:
```bash
# Check configured email domain
grep OAUTH2_PROXY_EMAIL_DOMAIN .env.customer

# Update if needed, then restart
docker compose restart oauth2-proxy
```

---

## 9. Support & Escalation

### Your Support Contacts

| Issue | Contact | Hours |
|-------|---------|-------|
| Technical | support@kushnir.cloud | 24/7 |
| Billing | billing@kushnir.cloud | Business hours |
| Security | security@kushnir.cloud | 24/7 (urgent) |

### Debug Bundle

When contacting support, provide:
```bash
# Collect logs
docker compose logs --tail=500 > logs.txt

# Collect config (sanitized)
grep -v SECRET customers/acme-corp/.env.customer > config.txt

# System info
docker compose ps > services.txt
docker version >> services.txt

# Network connectivity
curl -v https://ide.acme-corp.com > connectivity.txt 2>&1
```

---

## 10. Advanced Configuration

### Multi-Replica Deployment (High Availability)

```bash
# Edit terraform.tfvars
replicas = 3
ha_enabled = true

# Apply
terraform apply

# Verify all replicas healthy
watch -n 5 'docker compose ps'
```

### Custom Features

Enable in `config/branding.yaml`:
```yaml
features:
  federation_enabled: true       # Multi-org support
  knowledge_graph_enabled: true  # Component analytics
  replay_engine_enabled: true    # CI failure reproduction
  control_plane_enabled: true    # Governance dashboards
```

### SAML Support (Contact support@kushnir.cloud)

Request SAML-based authentication for on-premises IdP integration.

---

## 11. Compliance & Security

### Data Residency

- All customer data stored in `/nas/persistent/<customer-id>/`
- Database isolation: separate PostgreSQL database per customer
- Cache isolation: Redis keyspace prefix per customer

### Compliance Standards

- ✅ SOC2 Type II compliance
- ✅ NIST 800-53 controls
- ✅ GDPR-ready (data export, deletion, retention)
- ✅ Encrypted data in transit (TLS)
- ✅ Encrypted data at rest (optional, configure separately)

### Security Hardening Checklist

- [ ] Enable 2FA for all admin users
- [ ] Configure IP whitelist for API access
- [ ] Enable audit logging for all API calls
- [ ] Set up SIEM integration (if available)
- [ ] Regular security scanning (Trivy, OWASP)

---

## Document Completion

**Deployment Date**: _______________________  
**Deployed By**: _______________________  
**Verified By**: _______________________  
**Go-Live Date**: _______________________  

**Sign-off**: ☐ Ready for production

---

**End of Enterprise Onboarding Guide**
