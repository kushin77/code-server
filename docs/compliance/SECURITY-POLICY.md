# Security Policy - Code-Server Enterprise
**Version:** 1.0  
**Status:** ✅ DRAFT - Phase 7.1 Implementation  
**Created:** April 26, 2026  
**Governance:** GOV-002 Compliant (IaC-first, immutable, idempotent)  

---

## 1. Security Policy Overview

### 1.1 Policy Scope
This security policy defines the security baseline, controls, and compliance requirements for code-server-enterprise infrastructure across all environments:
- **Development:** Local Docker Compose on Windows/WSL
- **Staging:** Multi-host replica deployment (192.168.168.31 + .42)
- **Production:** K3s cluster on-premise (v1.28+) with Istio service mesh

### 1.2 Policy Authority
- **Owner:** DevOps/Security Team
- **Approver:** CTO/Infrastructure Lead
- **Review Cycle:** Quarterly (Jan/Apr/Jul/Oct) + ad-hoc for incidents
- **Effective Date:** April 26, 2026
- **Next Review:** July 26, 2026

### 1.3 Policy Objectives
- Protect sensitive data (credentials, API keys, customer data)
- Ensure infrastructure integrity through IaC governance
- Maintain audit trail for compliance (SOC2, ISO27001)
- Enable rapid incident response (RTO < 5 min)
- Establish secure-by-default configurations

---

## 2. Infrastructure Security Architecture

### 2.1 Zero-Trust Network Model (IaC-Defined)

**Network Perimeter:**
```
┌─ External (kushnir.cloud)
│  └─ Caddy reverse proxy (TLS 1.2+) on VRRP VIP 192.168.168.100
│     └─ OAuth2-proxy (authentication layer)
├─ Internal (192.168.168.0/24)
│  ├─ Primary: 192.168.168.31 (K3s server + PostgreSQL)
│  ├─ Replica: 192.168.168.42 (K3s agent + Qdrant)
│  ├─ NAS: 192.168.168.56 (persistent storage)
│  └─ Management: SSH only (no direct HTTP)
└─ Isolated (service mesh)
   └─ Istio mTLS: service-to-service encryption
```

**IaC Enforcement (GOV-002):**
- All network configs in `terraform/` (immutable state)
- Firewall rules defined as code (`policies/opa/*.rego`)
- No manual network changes (automated validation)

### 2.2 Authentication & Authorization

**Multi-Layer Auth (IaC-Configured):**

**Layer 1: External Access**
- OAuth2-proxy with OIDC (GitHub/LDAP/Okta configurable)
- TLS client certificates for API access (mTLS)
- Session timeout: 30 min idle, 24 hr absolute
- Configuration: `helm/values.auth.yaml`

**Layer 2: Application Level**
- Role-based access control (RBAC) via OPA
- Service accounts for inter-service communication
- Configuration: `policies/opa/authorization.rego`

**Layer 3: Infrastructure Access**
- SSH key-based auth (no passwords)
- Passwordless sudo for automation (selective commands)
- Configuration: `scripts/ops/setup-k3s-sudoers.sh` (immutable, idempotent)

**Credential Management (IaC-First):**
```yaml
# Environment-driven, no hardcoding (GOV-002)
OAUTH_CLIENT_ID:      "${OIDC_CLIENT_ID}"        # From Vault/GSM
OAUTH_CLIENT_SECRET:  "${OIDC_CLIENT_SECRET}"    # From Vault/GSM
DATABASE_PASSWORD:    "${DB_ADMIN_PASSWORD}"     # From Vault/GSM
SSH_KEY_PATH:         "${HOME}/.ssh/cluster-key" # Service account
```

### 2.3 Data Protection (At-Rest & In-Transit)

**Encryption Standards (IaC-Enforced):**

| Layer | Standard | Configuration | Enforcement |
|-------|----------|----------------|-------------|
| **Transit** | TLS 1.2+ | Caddy + Istio mTLS | `Caddyfile` + `istio/` |
| **Secrets** | AES-256 | Kubernetes Secrets API | `helm/charts/` |
| **DB** | AES-256 at rest | PostgreSQL pgcrypto | `terraform/rds.tf` |
| **Backups** | gzip + AES-256 | `scripts/phase7/backup-and-restore-automation.sh` | Idempotent |
| **Volume** | Linux dm-crypt | LUKS on NAS mount | `systemd/mount.service` |

**Database Security:**
```sql
-- IaC-automated (terraform/postgresql.tf)
CREATE ROLE app_user WITH LOGIN PASSWORD gen_random_uuid();
GRANT SELECT, INSERT, UPDATE ON public.* TO app_user;
REVOKE DELETE ON public.* FROM app_user;
-- Row-level security (RLS) enabled per table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
```

### 2.4 Secrets Management (Vault/GSM)

**Secret Storage Hierarchy (IaC-Defined):**
```
Development:
  └─ .env.local (gitignored, immutable example: .env.example)
  
Staging/Production:
  ├─ HashiCorp Vault (kubernetes auth, automatic rotation)
  ├─ Google Secret Manager (for GCP deployments, optional)
  └─ Kubernetes Secrets (for non-sensitive config)
```

**Rotation Policy:**
- Credentials: 90 days
- TLS certificates: 30 days
- SSH keys: Annual + on compromise
- API tokens: 30 days
- Database passwords: 180 days

**IaC Implementation:**
```bash
# scripts/ops/rotate-secrets.sh (idempotent)
#!/bin/bash
set -euo pipefail
export VAULT_ADDR="${VAULT_ADDR:-https://vault.kushnir.cloud:8200}"

# Rotate via Vault API (state management built-in)
curl -X POST "${VAULT_ADDR}/v1/auth/kubernetes/rotate" \
  -H "X-Vault-Token: $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"

# Restart services with new credentials (idempotent restart)
kubectl rollout restart deployment/auth-server -n code-server
```

---

## 3. Access Control & RBAC

### 3.1 Role Definitions (OPA-Enforced)

**Roles with Minimum Privileges:**

```rego
# policies/opa/authorization.rego (enforced at ingress)
package authz

default allow = false

# Admin: All permissions
allow {
  input.user.role == "admin"
  input.resource == "*"
}

# Developer: Read code repos, submit PRs
allow {
  input.user.role == "developer"
  input.action in ["read", "write-code"]
  input.resource in ["git", "ci-cd"]
}

# Operator: Deploy, scale, monitor
allow {
  input.user.role == "operator"
  input.action in ["deploy", "scale", "restart"]
  input.resource in ["kubernetes", "infrastructure"]
}

# Viewer: Read-only access
allow {
  input.user.role == "viewer"
  input.action == "read"
}
```

### 3.2 Service Accounts & API Keys

**Service Account Lifecycle (Immutable):**

```bash
# Create service account (idempotent)
kubectl create serviceaccount copilot-engine \
  --namespace code-server \
  --dry-run=client -o yaml | kubectl apply -f -

# Grant permissions (RBAC policy)
kubectl create rolebinding copilot-reader \
  --clusterrole=reader \
  --serviceaccount=code-server:copilot-engine \
  --namespace code-server \
  --dry-run=client -o yaml | kubectl apply -f -

# Rotate token (automatic via Kubernetes)
kubectl delete secret copilot-engine-token \
  --namespace code-server || true
# Token auto-regenerated on next pod start
```

### 3.3 SSH Key Management

**SSH Key Policy (GOV-002 Compliant):**
- Key size: RSA 4096 or ED25519
- Storage: `~/.ssh/` (400 perms), NAS backup (immutable copy)
- Rotation: Annual + on compromise
- Backup: Encrypted in Vault, accessible only via Kubernetes auth

```bash
# Generate key (idempotent - checks existing first)
if [[ ! -f ~/.ssh/cluster-key ]]; then
  ssh-keygen -t ed25519 -f ~/.ssh/cluster-key -N ""
  chmod 600 ~/.ssh/cluster-key
fi

# Deploy to vault (immutable upload)
vault write secret/data/ssh/cluster-key \
  key="@${HOME}/.ssh/cluster-key" \
  --ttl=8766h  # 1 year
```

---

## 4. Network Security

### 4.1 Firewall Rules (IaC-Defined)

**Ingress Rules (Terraform):**
```hcl
# terraform/firewall.tf (immutable state)
resource "aws_security_group" "allow_https" {
  name = "code-server-https"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTPS only
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["203.0.113.0/24"]  # Admin IPs only
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 4.2 Network Segmentation

**Internal Only (No Public Route):**
- PostgreSQL: 5432 (internal only)
- Qdrant: 6333 (service mesh only)
- Redis: 6379 (internal only)
- Caddy admin: 2019 (localhost only)

**Public Endpoints (HTTPS only):**
- kushnir.cloud/api/* (443)
- kushnir.cloud/oauth2/* (443)

### 4.3 DDoS & Rate Limiting

**Caddy Configuration (IaC-Defined in Caddyfile):**
```caddy
kushnir.cloud {
  # Rate limiting: 100 req/min per IP
  rate_limit 100/m

  # Request timeout: 30 seconds
  request_timeout 30s

  # Body size limit: 10MB
  request_body_max_size 10485760

  # Keep-alive timeout: 15 seconds
  keepalive_timeout 15s
}
```

---

## 5. Application Security

### 5.1 Input Validation (IaC-Enforced Middleware)

**Validation Layers:**
1. **Caddy** - Size limits, charset validation
2. **OAuth2-proxy** - Token validation, header inspection
3. **Application** - Schema validation (per API spec)
4. **Database** - Parameterized queries (ORM-enforced)

### 5.2 Vulnerability Management

**CVE Response Workflow (IaC-Driven):**

```bash
# 1. Detection (automated)
curl -s https://api.deps.dev/v3alpha/vulnerabilities | jq . > cves.json

# 2. Triage (manual review)
grep "CRITICAL\|HIGH" cves.json

# 3. Patch (immutable upgrade)
npm install package@NEW_VERSION  # Tested upgrade
git commit -m "fix(security): patch CVE-2024-XXXXX"

# 4. Deploy (idempotent rollout)
kubectl set image deployment/app-name \
  app=image:v2.0.0 \
  --record
# Automatic rollback if health check fails
```

### 5.3 Code Security Scanning

**CI/CD Security Gates (GitHub Actions):**
```yaml
# .github/workflows/security.yml (immutable policy)
name: Security Scanning

on: [pull_request, push]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # 1. Dependency check
      - run: npm audit --audit-level=moderate || exit 1
      
      # 2. Secret scanning
      - uses: trufflesecurity/trufflehog@main
      
      # 3. SAST analysis
      - run: sonarqube-scanner
      
      # 4. Container scan
      - run: trivy image --exit-code 1 --severity HIGH $IMAGE
```

---

## 6. Logging & Audit Trail

### 6.1 Centralized Logging (ELK Stack - IaC-Deployed)

**Log Collection (Filebeat):**
```yaml
# filebeat.yml (immutable configuration)
filebeat.inputs:
  - type: container
    paths:
      - '/var/lib/docker/containers/*/*.log'
    
output.elasticsearch:
  hosts: ['elasticsearch:9200']
  index: 'logs-%{+YYYY.MM.dd}'

# Immutable retention: 90 days (automated cleanup)
```

### 6.2 Audit Events

**Events to Log (GOV-002 Mandated):**
- ✅ User login/logout (OAuth2-proxy logs)
- ✅ API calls (Envoy access logs via Istio)
- ✅ Configuration changes (Git commit + audit)
- ✅ Permission changes (OPA decision logs)
- ✅ Secret access (Vault audit log)
- ✅ Infrastructure changes (Terraform state)
- ✅ SSH command execution (auditd)

### 6.3 Log Retention & Compliance

```
Log Type              Retention  Format         Storage
────────────────────────────────────────────────────────
Application          30 days    JSON/ELK       Elasticsearch
Security/Audit       7 years    Encrypted      NAS + S3 archive
Database audit       1 year     PostgreSQL     PostgreSQL pg_audit
API access           90 days    Caddy/Istio    Elasticsearch
Kubernetes events    30 days    JSON           Elasticsearch
```

**Immutable Archive (S3/NAS):**
```bash
# scripts/ops/archive-logs.sh (idempotent, runs nightly)
#!/bin/bash
set -euo pipefail

# Export logs
kubectl logs --namespace code-server --all-containers \
  --since=24h > /tmp/logs-$(date +%Y%m%d).tar.gz

# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 /tmp/logs-*.tar.gz

# Upload to S3 (immutable + versioning enabled)
aws s3 cp /tmp/logs-*.tar.gz.gpg \
  s3://code-server-backups/logs/ \
  --sse=AES256 --storage-class=GLACIER

# Cleanup local
rm -f /tmp/logs-*
```

---

## 7. Incident Response

### 7.1 Incident Response Plan (IaC-Automated)

**Response Workflow (Immutable Procedures):**

```bash
# scripts/ops/incident-response.sh (idempotent)
#!/bin/bash
set -euo pipefail

INCIDENT_ID="INC-$(date +%s)"
ESCALATION_CHANNEL="#security-incidents"

# 1. Detect & Alert
detect_incident() {
  if [[ $ALERT_LEVEL == "CRITICAL" ]]; then
    # Immutable isolation: Disable all external access
    kubectl patch netpol default \
      -p '{"spec":{"ingress":[]}}'
    
    # Notify
    slack_message "${ESCALATION_CHANNEL}" \
      "🚨 CRITICAL INCIDENT: ${INCIDENT_ID} - $(date)"
  fi
}

# 2. Investigate (non-destructive)
investigate_incident() {
  # Export logs without modification
  kubectl logs deployment/affected-service > /tmp/incident-${INCIDENT_ID}.log
  
  # Freeze state (immutable snapshot)
  kubectl get all -o yaml > /tmp/incident-${INCIDENT_ID}-state.yaml
  
  # Check git history for recent changes
  git log --oneline --all -20
}

# 3. Remediate (with rollback capability)
remediate_incident() {
  # Rollback to previous stable commit
  kubectl set image deployment/affected-service \
    app=image:${PREVIOUS_VERSION} \
    --record
  
  # Verify health
  kubectl rollout status deployment/affected-service
}

# 4. Recover (restore services)
recover_incident() {
  # From NAS backup (immutable copy)
  bash scripts/phase7/backup-and-restore-automation.sh \
    --mode=restore \
    --backup-date=$(date -d '1 hour ago' +%Y%m%d)
}

# 5. Post-Incident (non-destructive analysis)
postincident_analysis() {
  # Generate report (immutable artifact)
  cat > "/tmp/incident-${INCIDENT_ID}-report.md" << EOF
# Incident Report: ${INCIDENT_ID}

## Timeline
$(grep "timestamp\|event" /tmp/incident-${INCIDENT_ID}.log)

## Root Cause
[To be determined during analysis]

## Remediation
[Actions taken and timeframes]

## Prevention
[Changes to prevent recurrence]

## Follow-up
[Action items and owners]
EOF
  
  # Archive (immutable storage)
  mv /tmp/incident-${INCIDENT_ID}-* /var/log/incidents/
}

main() {
  detect_incident
  investigate_incident
  remediate_incident
  recover_incident
  postincident_analysis
}

main "$@"
```

### 7.2 Disaster Recovery

**RTO/RPO Targets (IaC-Tested):**
- RTO (Recovery Time Objective): < 5 minutes
- RPO (Recovery Point Objective): < 15 minutes

**Backup Automation (Phase 7 - Idempotent):**
```bash
# scripts/phase7/backup-and-restore-automation.sh
# - PostgreSQL: Daily full + hourly incremental
# - Volumes: Hourly via NAS rsync
# - Config: Continuous via Git
# - Archives: Encrypted to S3 (immutable versioning)

# Usage:
bash scripts/phase7/backup-and-restore-automation.sh --mode=backup
bash scripts/phase7/backup-and-restore-automation.sh --mode=restore \
  --backup-date=20260426
```

---

## 8. Compliance Framework

### 8.1 SOC2 Type 1 Controls

**Trust Services Mapped (Phase 7 - Under Implementation):**

| Control | Requirement | Implementation | Status |
|---------|-------------|-----------------|--------|
| **CC6** | Logical access controls | OPA + RBAC + SSH keys | ✅ Phase 7 |
| **CC7** | System monitoring | ELK + Prometheus | ✅ Phase 7 |
| **CC8** | Incident response | Incident procedures (above) | 🔄 Phase 7 |
| **CC9** | Change management | Git-based + terraform approval | ✅ Phase 7 |
| **A1** | Availability | Redundancy + failover | ✅ Existing |
| **A2** | Performance | Monitoring + alerting | ✅ Existing |
| **PI1** | Data privacy | Encryption + access control | ✅ Phase 7 |
| **C1** | Confidentiality | mTLS + secrets mgmt | ✅ Phase 7 |

### 8.2 ISO27001 Controls

**Key Annexes Covered (Phase 7):**
- **A5**: Information security policies
- **A6**: Organization of information security
- **A7**: Human resource security
- **A8**: Asset management
- **A9**: Access control
- **A10**: Cryptography
- **A11**: Physical and environmental security
- **A12**: Operations security
- **A13**: Communications security
- **A14**: System acquisition & maintenance
- **A15**: Supplier relationships
- **A16**: Information security incident management

---

## 9. Security Governance

### 9.1 Policy Review & Update

**Annual Review Process (Immutable Checklist):**
- [ ] Threat landscape assessment (Q1)
- [ ] Vulnerability analysis (ongoing)
- [ ] Incident trends (quarterly)
- [ ] Compliance audit (Q2)
- [ ] Policy update + stakeholder review (Q3)
- [ ] Training update (Q4)

### 9.2 Staff Training & Awareness

**Required Training:**
- Onboarding: Security policy overview (1 hour)
- Annual: Security awareness (2 hours)
- Role-based: Specific responsibilities (varies)
- Incident-driven: Post-incident review (as needed)

### 9.3 Third-Party Management

**Vendor Security Assessment:**
- Pre-qualification: Security assessment form
- Ongoing: Annual compliance audit
- Incident-driven: Immediate investigation if vendor breach
- Termination: Data deletion confirmation (immutable proof)

---

## 10. Configuration Management (GOV-002 Immutable)

### 10.1 Infrastructure as Code (IaC Principles)

**All security configurations must be:**
1. **Version-controlled** (Git with commit history)
2. **Immutable** (state applied via code, no manual changes)
3. **Idempotent** (safe to re-run without side effects)
4. **Audited** (all changes tracked + signed commits)
5. **Tested** (validation before production)

**IaC Checklist:**
```bash
#!/bin/bash
# scripts/ci/validate-iac-governance.sh (CI gate)

# 1. Check all terraform/.tf files are in git
git ls-files 'terraform/**/*.tf' || exit 1

# 2. Verify no hardcoded credentials
grep -r "password\|key\|token" terraform/ | grep -v "var\." && exit 1

# 3. Validate terraform state
terraform validate -chdir=terraform || exit 1

# 4. Check scripts use env vars (not hardcoded)
grep -r "192.168.168\." scripts/ && \
  if ! grep "PRIMARY_HOST\|REPLICA_HOST" scripts/*.sh; then
    exit 1  # Hardcoded IPs not allowed
  fi

# 5. Ensure all secrets use Vault/GSM
grep -r "export.*=" scripts/*.sh | grep -v "\${" && exit 1

echo "✅ IaC governance validation passed"
```

---

## 11. Security Incident Report Template

**For use in incident response (Section 7):**

```markdown
# Security Incident Report Template

**Incident ID:** INC-YYYYMMDD-HHmm  
**Date Detected:** YYYY-MM-DD HH:MM UTC  
**Severity:** Critical | High | Medium | Low  

## Summary
[1-2 paragraph overview]

## Timeline
- **HH:MM** - Event occurred
- **HH:MM** - Alert triggered
- **HH:MM** - Investigation started
- **HH:MM** - Remediation initiated
- **HH:MM** - All-clear confirmed

## Impact Assessment
- Systems affected: [list]
- Data affected: [customer IDs, types]
- Users impacted: [number + categories]
- Duration: [total downtime]

## Root Cause
[Technical analysis]

## Remediation Actions
- [Action 1] - Completed HH:MM
- [Action 2] - Completed HH:MM

## Prevention
- [Control 1] to prevent recurrence
- [Process change 2]
- [Monitoring 3]

## Follow-up
- [ ] Code review (owner, due date)
- [ ] Control testing (owner, due date)
- [ ] Incident retro (team, due date)
```

---

## Appendix: Quick Reference

### Emergency Contacts
- Security On-Call: [phone + Slack]
- Incident Commander: [contact]
- External Counsel: [contact]

### Key Documents
- Incident Response Plan: `docs/compliance/INCIDENT-RESPONSE.md`
- Access Control Matrix: `docs/compliance/ACCESS-CONTROL-MATRIX.md`
- Disaster Recovery: `scripts/phase7/backup-and-restore-automation.sh`
- Audit Procedures: `docs/compliance/AUDIT-PROCEDURES.md`

### Related Policies
- Data Classification: See section 2.3
- Change Management: See section 8.2
- Third-Party Security: See section 9.3

---

**Policy Approval**

| Role | Name | Date | Signature |
|------|------|------|-----------|
| CTO | [Name] | [Date] | [Signed] |
| Security Lead | [Name] | [Date] | [Signed] |
| Compliance Officer | [Name] | [Date] | [Signed] |

---

**Document History**

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-26 | Initial Phase 7.1 Implementation |
| [Future] | TBD | Updates per quarterly review |

---

**Status:** ✅ DRAFT - Ready for Security Review  
**Next:** CREATE Incident Response & Access Control Matrix documents  
