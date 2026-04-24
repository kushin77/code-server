# Phase 4-5 IaC Execution Plan (Epic #1545)
**Date**: April 24, 2026  
**Status**: Ready for autonomous execution  
**IaC Principles**: All operations are Infrastructure as Code, Immutable, Idempotent

---

## Phase 4: Whitelabel & Custom Domain Support (#1674)

### 4.1 Caddy Custom Domain Routing (IaC)
**Goal**: Add dynamic domain routing to Caddy configuration  
**Files**:
- `Caddyfile` (update with custom domain matcher)
- `docker-compose.yml` (add domain volume mount)

**Implementation**:
```caddy
# Add to Caddyfile
@custom_domain {
  header X-Custom-Domain {host}
}
# Dynamic reverse proxy to saas-api with domain context
reverse_proxy @custom_domain saas-api:5000 {
  header_up X-Custom-Domain {host}
}
```

**Idempotent**: Caddyfile restart is idempotent (matches same rules)  
**Immutable**: All config in version control, no manual Caddy CLI calls

### 4.2 Database Schema Extension (IaC)
**Goal**: Add custom domain validation and DNS verification tables  
**Files**:
- `migrations/002_custom_domains_schema.sql` (NEW)

**Schema Changes**:
```sql
CREATE TABLE custom_domains (
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL REFERENCES organizations(id),
  domain_name VARCHAR(255) NOT NULL UNIQUE,
  verification_token VARCHAR(255) NOT NULL,
  is_verified BOOLEAN DEFAULT false,
  verified_at TIMESTAMP,
  tls_cert_path VARCHAR(500),
  acme_order_id VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW() ON UPDATE,
  deleted_at TIMESTAMP,
  CONSTRAINT domain_length CHECK (char_length(domain_name) >= 4)
);

CREATE UNIQUE INDEX idx_custom_domains_org_domain ON custom_domains(org_id, domain_name);
CREATE INDEX idx_custom_domains_verification ON custom_domains(verification_token, is_verified);
```

**Idempotent**: Migrations only run once (checked by database)  
**Immutable**: Schema changes tracked in git, applied via migration runner

### 4.3 API Endpoints for Custom Domains (IaC)
**Goal**: Add REST endpoints for domain management  
**Files**:
- `apps/saas-api/src/custom-domains.js` (NEW)

**Endpoints**:
```javascript
POST /api/domains — Add custom domain (org admin)
  Request: { domain_name: "example.com" }
  Response: { id, domain_name, verification_token }
  Action: Generate DNS TXT token

GET /api/domains/{org_id} — List org domains
GET /api/domains/{id}/verify — Check DNS validation
  Action: Query DNS TXT record, update is_verified if match found

DELETE /api/domains/{id} — Remove domain (revoke TLS)
```

**Idempotent**: DNS queries are read-only, verification is idempotent

### 4.4 ACME Integration for Auto-TLS (IaC)
**Goal**: Automatic TLS provisioning for custom domains  
**Files**:
- `scripts/lib/acme-manager.sh` (NEW)
- `docker-compose.yml` (add certbot sidecar)

**ACME Flow**:
1. Domain verified via DNS TXT
2. Caddy Admin API (`localhost:2019`) triggers ACME order
3. certbot validates and stores cert
4. Caddy reloads with new cert via `/admin/config/apps/tls`

**Idempotent**: Cert renewal checks expiry before requesting  
**Immutable**: All ACME state stored in docker volumes

---

## Phase 5: SSO Playwright Validation Tests (#1675)

### 5.1 E2E Test Suite (IaC)
**Goal**: Automated SSO flow validation  
**Files**:
- `tests/e2e/sso-flows.spec.ts` (NEW)
- `.github/workflows/sso-validation.yml` (NEW)

**Test Scenarios**:
1. **New User Onboarding**:
   - Visit kushnir.cloud → OAuth → Google auth → Profile setup → Dashboard → Access IDE without re-auth
   - Assert: Single sign-on session persists across subdomains

2. **Returning User**:
   - IDE access with valid session → Instant redirect to IDE
   - Assert: Response time < 3s

3. **VPN Isolation**:
   - All flows through WireGuard tunnel
   - Assert: No CORS/CSP/TLS errors

4. **Session Expiry**:
   - Token expires → Graceful redirect to login → Re-login returns to previous URL
   - Assert: Session recovery works

**Idempotent**: Tests are read-only (check state, don't modify)  
**Immutable**: Test code in git, runs in isolated containers

### 5.2 CI/CD Integration (IaC)
**Goal**: Automated daily SSO validation  
**Files**:
- `.github/workflows/sso-validation.yml` (NEW)

**Workflow**:
```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:  # Manual trigger

jobs:
  sso-e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm install --prefix tests/e2e
      - run: npx playwright install --with-deps
      - run: npx playwright test tests/e2e/sso-flows.spec.ts
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: tests/e2e/playwright-report/
```

**Idempotent**: Test runs don't modify app state  
**Immutable**: Workflow defined in git

---

## Implementation Sequence (Idempotent, Immutable, IaC)

### 4.1: Caddy Configuration Update
```bash
# Local development
cd /mnt/c/code-server-enterprise
# Edit Caddyfile to add custom domain routes

# Deploy to both replicas
scp -i ~/.ssh/id_rsa_onprem Caddyfile akushnir@192.168.168.31:code-server-enterprise/
scp -i ~/.ssh/id_rsa_onprem Caddyfile akushnir@192.168.168.42:code-server-enterprise/

# Restart Caddy (idempotent — reloads same config)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart caddy"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose restart caddy"
```

### 4.2: Database Migration
```bash
# Create migration file
echo "migrations/002_custom_domains_schema.sql"

# Deploy to replicas
scp -i ~/.ssh/id_rsa_onprem migrations/002_custom_domains_schema.sql akushnir@192.168.168.31:code-server-enterprise/migrations/
scp -i ~/.ssh/id_rsa_onprem migrations/002_custom_domains_schema.sql akushnir@192.168.168.42:code-server-enterprise/migrations/

# Run migration (idempotent — migration runner checks if already applied)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose up saas-db-init"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose up saas-db-init"
```

### 4.3: API Implementation
```bash
# Create custom domains module
echo "apps/saas-api/src/custom-domains.js"

# Deploy to replicas
scp -i ~/.ssh/id_rsa_onprem apps/saas-api/src/custom-domains.js akushnir@192.168.168.31:code-server-enterprise/apps/saas-api/src/
scp -i ~/.ssh/id_rsa_onprem apps/saas-api/src/custom-domains.js akushnir@192.168.168.42:code-server-enterprise/apps/saas-api/src/

# Restart API (volume mount picks up new code)
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose restart saas-api"
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose restart saas-api"
```

### 4.4: ACME Integration
```bash
# Add ACME manager script
echo "scripts/lib/acme-manager.sh"

# Deploy (idempotent — script checks cert expiry before renewal)
scp -i ~/.ssh/id_rsa_onprem scripts/lib/acme-manager.sh akushnir@192.168.168.31:code-server-enterprise/scripts/lib/
scp -i ~/.ssh/id_rsa_onprem scripts/lib/acme-manager.sh akushnir@192.168.168.42:code-server-enterprise/scripts/lib/
```

### 5.1: Test Suite
```bash
# Create test files
echo "tests/e2e/sso-flows.spec.ts"

# Deploy to git (CI/CD runs from repo)
git add tests/e2e/sso-flows.spec.ts
git commit -m "feat(P2-1675): SSO Playwright validation tests"
git push origin main
```

### 5.2: CI/CD Workflow
```bash
# Create GitHub Actions workflow
echo ".github/workflows/sso-validation.yml"

# Deploy to git
git add .github/workflows/sso-validation.yml
git commit -m "ci(P2-1675): Daily SSO validation workflow"
git push origin main
```

---

## Verification Checklist (Idempotent, Immutable, IaC)

- [ ] All files in version control (no manual changes)
- [ ] All deployments via docker-compose (immutable containers)
- [ ] All migrations idempotent (safe to run multiple times)
- [ ] All API endpoints stateless (can scale horizontally)
- [ ] All workflows defined in CI/CD (no manual triggers)
- [ ] All TLS management automated (no manual cert uploads)
- [ ] All domain routing in code (no Caddy CLI calls)
- [ ] Both replicas have identical config (deployment sync)

---

## Success Criteria

✅ Phase 4 Complete:
- Custom domains accepted via API
- DNS verification working
- TLS certificates auto-provisioned
- Caddy routes custom domains to portal

✅ Phase 5 Complete:
- SSO flows tested daily
- Test results published
- Slack notifications on failures
- All scenarios passing

✅ Epic #1545 Complete:
- Portal fully functional
- OAuth unified across subdomains
- User/Org/Group management working
- Whitelabel support enabled
- SSO validated end-to-end
