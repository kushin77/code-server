# Phase 8: Comprehensive Security Hardening Roadmap

**Status**: Planning Phase (April 16-30, 2026)  
**Owner**: kushin77  
**Blocks**: Production GA  
**Priority**: P0 (All P1 issues critical path)

---

## Executive Summary

Phase 8 implements six independent, production-grade security layers across the entire stack:

1. **Host Layer** (#349) — OS hardening, CIS benchmark, fail2ban, auditd
2. **Container Layer** (#354) — Docker hardening, capability dropping, network segmentation
3. **Network Layer** (#350, #348) — Egress filtering, Cloudflare edge security
4. **Secrets Layer** (#356) — Encryption at rest, dynamic credentials, rotation automation
5. **Supply Chain Layer** (#355) — Image signing, SBOM, digest pinning
6. **Observability Layer** (#359, #357, #358) — Runtime monitoring, policy enforcement, dependency management

Each issue is:
- ✅ **Immutable**: IaC (Terraform, Ansible, Docker Compose)
- ✅ **Independent**: No blocking dependencies (except #349 → #354)
- ✅ **Observable**: Prometheus metrics, JSON logs, traces
- ✅ **Reversible**: Can rollback within 60 seconds
- ✅ **Production-Ready**: No demos, no staging

---

## Complete Issue Matrix

| ID | Title | Priority | Effort | Owner | Depends | Status |
|----|-------|----------|--------|-------|---------|--------|
| #349 | OS Hardening (CIS+fail2ban+auditd+AIDE) | P1 | 40h | akushnir | — | PLANNING |
| #354 | Container Hardening (cap_drop+read_only) | P1 | 30h | akushnir | #349 | PLANNING |
| #350 | Container Egress Filtering | P1 | 25h | akushnir | #354 | PLANNING |
| #348 | Cloudflare Tunnel + WAF (Terraform) | P1 | 35h | akushnir | — | PLANNING |
| #355 | Supply Chain (cosign+SBOM) | P1 | 30h | akushnir | — | PLANNING |
| #356 | Secrets Management (SOPS+Vault) | P1 | 35h | akushnir | — | PLANNING |
| #359 | Falco Runtime Monitoring | P2 | 25h | akushnir | #354 | PLANNING |
| #357 | OPA Policy Enforcement | P2 | 20h | akushnir | — | PLANNING |
| #358 | Renovate Dependencies | P2 | 15h | akushnir | — | PLANNING |

**Total Effort**: 255 hours  
**P1 (Critical Path)**: 195 hours  
**P2 (Operations)**: 60 hours

---

## Execution Timeline

### Week 1 (April 16-20, 2026): Phase 7 Final Push + P1 Security Foundation
- Complete Phase 7c (DR tests)
- Deploy Phase 7d (HAProxy + health checks)
- **START #349**: OS Hardening
- **START #354**: Container Hardening

### Week 2 (April 21-27, 2026): P1 Security Acceleration
- Complete #349 (OS Hardening)
- Complete #354 (Container Hardening)
- **START #350**: Egress Filtering
- **START #348**: Cloudflare Tunnel
- **START #355**: Supply Chain

### Week 3 (April 28-30, 2026): P1 Completion + P2 Planning
- Complete #350, #348, #355
- **START #356**: Secrets Management
- Plan P2 work (#359, #357, #358)

### Week 4+ (May 2026): P2 Observability & Maintenance
- Complete #356 (Secrets)
- Implement P2 issues in priority order
- Production sign-off

---

## Dependency Graph

```
#349 (OS Hardening)
  ↓
#354 (Container Hardening)
  ↓
#350 (Egress Filtering)

#348 (Cloudflare Tunnel) — INDEPENDENT

#355 (Supply Chain) — INDEPENDENT

#356 (Secrets) — INDEPENDENT

#359 (Falco) — Depends on #354
#357 (OPA) — INDEPENDENT
#358 (Renovate) — INDEPENDENT
```

**Key**: Only #349→#354→#350 has a blocking chain. All other work can parallelize.

---

## Detailed Issue Breakdown

### #349: OS Hardening (40 hours)

**What**: CIS Ubuntu 22.04 benchmark implementation.

**Components**:
- fail2ban: Automated IP banning for brute force + OAuth abuse
- unattended-upgrades: Automatic security patching
- auditd: Privileged operation audit logs (tamper-evident)
- AIDE: File integrity monitoring (detect binary tampering)
- sysctl hardening: Kernel parameters (ASLR, SYN cookies, spoofing protection)
- SSH hardening: Disable root login, disable passwords, strong crypto only

**Deliverables**:
- `scripts/hardening/apply-cis-hardening.sh` (idempotent, reproducible)
- `terraform/host-hardening.tf` (IaC for provisioning)
- `prometheus-rules.yml` (alerts: failed login attempts, AIDE changes, kernel panics)
- Grafana dashboard: "Host Security" (fail2ban bans/hr, AIDE status, audit events)
- Runbook: "OS Hardening Procedures"

**Acceptance Criteria**:
- [ ] fail2ban active, 3 failed SSH attempts → auto-ban → PagerDuty alert
- [ ] AIDE daily check detects file tampering within 24h
- [ ] auditd logging all sudo/su operations to Loki (1-year retention)
- [ ] unattended-upgrades dry-run shows 0 pending security updates
- [ ] `sysctl kernel.randomize_va_space == 2` (ASLR enabled)
- [ ] SSH audit tool shows no weak algorithms

**Estimated Duration**: 40 hours  
**Start Date**: April 16, 2026  
**Completion Target**: April 20, 2026

---

### #354: Container Hardening (30 hours)

**What**: Docker security hardening: capability dropping, read-only filesystems, network segmentation, non-root users.

**Components**:
- `security_opt: [no-new-privileges:true]` on all services (prevents privilege escalation)
- `cap_drop: [ALL]` on all services (drop unnecessary Linux capabilities)
- `read_only: true` on stateless services (immutable filesystem)
- Network segmentation: frontend, app, data, monitoring tiers
- Non-root user directive on stateless services
- Remove host port bindings for internal services (only expose caddy/80/443)

**Deliverables**:
- Updated `docker-compose.yml` with hardening anchors
- `scripts/cis-docker-benchmark.sh` (CIS benchmark runner)
- Prometheus metrics: container capability usage, read-only status
- Grafana dashboard: "Container Security"
- Runbook: "Container Hardening Troubleshooting"

**Acceptance Criteria**:
- [ ] `docker inspect | jq '.[0].HostConfig.SecurityOpt'` shows `no-new-privileges:true`
- [ ] `docker inspect | jq '.[0].HostConfig.CapDrop'` shows `["ALL"]`
- [ ] caddy, oauth2-proxy, prometheus, alertmanager running as non-root
- [ ] From caddy container: `curl http://postgres:5432` → connection refused (network isolation)
- [ ] Postgres no longer listening on `0.0.0.0:5432` (only Docker network)
- [ ] CIS Docker Benchmark: zero FAIL items, minimal WARN

**Estimated Duration**: 30 hours  
**Start Date**: April 18, 2026 (after #349)  
**Completion Target**: April 22, 2026

---

### #350: Container Egress Filtering (25 hours)

**What**: Prevent container data exfiltration via egress allow-lists.

**Components**:
- DOCKER-USER iptables chain rules (block internal port exposure)
- Per-network egress rules (postgres: no outbound; ollama: only HuggingFace)
- nftables modern replacement (atomic rule sets, Docker-compatible)
- Egress monitoring via Prometheus (log blocked egress attempts)
- Falco integration (syscall-level exfiltration detection)

**Deliverables**:
- `scripts/hardening/docker-egress-hardening.sh`
- `scripts/hardening/nftables-config.nft`
- Prometheus metrics: `container_egress_blocked_total{container}`
- Alert: `UnexpectedContainerEgress` (P1 if suspicious outbound)
- Runbook: "Egress Filtering Troubleshooting"

**Acceptance Criteria**:
- [ ] From postgres container: `curl https://attacker.com` → blocked (no egress to internet)
- [ ] From caddy container: outbound to port 80/443 → allowed
- [ ] From postgres container: outbound to redis (internal network) → blocked (isolation)
- [ ] Rules persist across Docker daemon/host reboot
- [ ] `iptables -L DOCKER-USER -n` shows DROP rules for internal ports (5432, 6379, etc.)
- [ ] Prometheus metric `container_egress_blocked_total` increasing when tests trigger blocks

**Estimated Duration**: 25 hours  
**Start Date**: April 22, 2026 (after #354)  
**Completion Target**: April 25, 2026

---

### #348: Cloudflare Tunnel + WAF (35 hours)

**What**: Activate Cloudflare Tunnel as production ingress + configure WAF, edge security.

**Components**:
- cloudflared Docker service running in docker-compose
- Tunnel configuration (proper credentials, health checks)
- Cloudflare Access policy (CF Access MFA for ide.kushnir.cloud)
- WAF custom rules (block path traversal, SQL injection, scanners)
- Zone settings (TLS 1.3 only, SSL strict, HTTP/3, Brotli)
- DNSSEC, CAA, SPF/DMARC records
- Health checks + monitoring
- Terraform management of all CF resources

**Deliverables**:
- `docker-compose.yml` cloudflared service
- `terraform/cloudflare.tf` (complete zone management)
- `scripts/cf-access-policy-sync.sh` (sync allowed-emails.txt ↔ CF Access)
- Prometheus scrape: cloudflared metrics
- Dashboard: "Cloudflare Edge Security"
- Runbook: "Tunnel Debugging + Recovery"

**Acceptance Criteria**:
- [ ] `docker-compose ps cloudflared` shows healthy
- [ ] `dig ide.kushnir.cloud` resolves to Cloudflare IP (not 192.168.x.x)
- [ ] Accessing ide.kushnir.cloud without Google auth → CF Access login
- [ ] Path traversal test: `curl ide.kushnir.cloud/../etc/passwd` → 403 (WAF block)
- [ ] TLS 1.3 minimum: `nmap --script ssl-enum-ciphers ide.kushnir.cloud` shows only TLS 1.3
- [ ] DNSSEC enabled: `dig +dnssec kushnir.cloud SOA` shows RRSIG
- [ ] Tunnel certificate valid: `echo | openssl s_client -connect ide.kushnir.cloud:443 | grep -A2 issuer`
- [ ] Terraform apply idempotent (second apply = no changes)

**Estimated Duration**: 35 hours  
**Start Date**: April 16, 2026 (INDEPENDENT, can start immediately)  
**Completion Target**: April 20, 2026

---

### #355: Supply Chain Security (30 hours)

**What**: Image signing (cosign) + SBOM generation (syft) + digest pinning.

**Components**:
- cosign signing of all pushed images
- syft SBOM generation (SPDX JSON + CycloneDX)
- Trivy exit-code enforcement (fail on CRITICAL/HIGH)
- Base image digest pinning (Dockerfile + renovate)
- Provenance attestation (SLSA L2)
- Signature verification before deploy
- GitHub Actions workflow updates

**Deliverables**:
- Updated `.github/workflows/dagger-cicd-pipeline.yml` (cosign + syft steps)
- `scripts/verify-image-signature.sh` (deploy-time verification)
- `cosign.pub` committed to repo (public key)
- `terraform/image-signing.tf` (cosign secret management)
- Prometheus metrics: `trivy_scan_vulnerabilities{severity}`
- Dashboard: "Supply Chain Integrity"
- Runbook: "Image Signing Troubleshooting"

**Acceptance Criteria**:
- [ ] All pushed images signed: `cosign verify --key cosign.pub image` succeeds
- [ ] SBOM generated on every build: `sbom.spdx.json` artifact present
- [ ] Trivy scan with `exit-code: 1` → CRITICAL/HIGH vulns block merge
- [ ] Dockerfile base images pinned by digest: `FROM alpine:3.19@sha256:abc...`
- [ ] Deploy script verifies signature: unsigned image → deploy failure
- [ ] `cosign.pub` public key in repo (transparency)
- [ ] `COSIGN_KEY` secret in Vault (not in repo)

**Estimated Duration**: 30 hours  
**Start Date**: April 16, 2026 (INDEPENDENT)  
**Completion Target**: April 22, 2026

---

### #356: Secrets Management (35 hours)

**What**: Encrypt .env at rest (SOPS+age) + Vault dynamic PostgreSQL credentials + secret rotation automation.

**Components**:
- SOPS encryption of .env file (checked into git as .env.enc)
- age key generation + Vault storage
- Vault PostgreSQL dynamic secrets (1-hour TTL, automatic rotation)
- Secret rotation script (quarterly: POSTGRES_PASSWORD, REDIS_PASSWORD, COOKIE_SECRET)
- Prometheus alert for secret staleness (>90 days)
- `sops exec-env` for deploy (no plaintext on disk)

**Deliverables**:
- `.sops.yaml` (encryption configuration)
- `.env.enc` (encrypted environment file)
- `terraform/vault-postgres-secrets.tf` (dynamic secrets config)
- `scripts/rotate-secrets.sh` (quarterly rotation)
- `Makefile` updated: `deploy` target uses `sops exec-env`
- Prometheus rule: `SecretNotRotated` alert
- Runbook: "Secret Rotation Procedures"

**Acceptance Criteria**:
- [ ] `.env.enc` committed to git (plaintext .env never checked in)
- [ ] SOPS decryption works: `SOPS_AGE_KEY_FILE=/etc/sops/age.key sops -d .env.enc`
- [ ] Vault dynamic PostgreSQL creds work: `vault read database/creds/app-role`
- [ ] Deploy via `make deploy` uses `sops exec-env` (no plaintext .env file)
- [ ] age private key in /etc/sops/age.key on host (NOT in repo)
- [ ] age key backed up in Vault: `vault kv get secret/sops/age-key`
- [ ] Prometheus alert fires if secret > 90 days old

**Estimated Duration**: 35 hours  
**Start Date**: April 16, 2026 (INDEPENDENT)  
**Completion Target**: April 24, 2026

---

### #359: Falco Runtime Monitoring (P2, 25 hours)

**What**: Kernel syscall monitoring for runtime security anomalies.

**Components**:
- Falco Docker service (0.37+ with eBPF probe, no kernel module)
- Custom rules: shell spawn detection, outbound connection anomalies, sensitive file reads, crypto mining
- falcosidekick integration (forward events to AlertManager)
- Prometheus metrics: `falco_events_total{rule, priority, container}`
- Grafana dashboard: "Falco Security Events"

**Depends On**: #354 (container hardening must be done first)

**Deliverables**:
- `docker-compose.yml` falco + falcosidekick services
- `config/falco/rules.local.yaml` (custom rules)
- Prometheus metrics endpoint
- AlertManager integration
- Grafana dashboard
- Runbook: "Falco Alert Triage"

**Estimated Duration**: 25 hours  
**Start Date**: April 26, 2026 (after #354)  
**Completion Target**: April 30, 2026

---

### #357: OPA Policy Enforcement (P2, 20 hours)

**What**: Conftest + OPA for IaC policy validation.

**Components**:
- `policy/*.rego` files (deny rules for: hardcoded secrets, missing security_opt, exposed DB ports)
- `conftest test` CI step (block merge on policy violation)
- Remove `continue-on-error: true` from gitleaks + tflint
- Checkov + tfsec for additional Terraform scanning

**Deliverables**:
- `policy/docker-compose.rego`
- `policy/terraform.rego`
- Updated `iac-governance.yml` workflow
- Runbook: "OPA Policy Troubleshooting"

**Estimated Duration**: 20 hours  
**Start Date**: April 28, 2026  
**Completion Target**: May 2, 2026

---

### #358: Renovate Dependencies (P2, 15 hours)

**What**: Automated dependency updates with digest pinning.

**Components**:
- `renovate.json` configuration
- GitHub Actions workflow or Renovate app integration
- Digest pinning for all Docker images
- Auto-merge policy for patch updates (after tests pass)
- Manual review for major version bumps

**Deliverables**:
- `renovate.json` in repo root
- `.github/workflows/renovate.yml` (optional self-hosted runner)
- Runbook: "Dependency Update Procedures"

**Estimated Duration**: 15 hours  
**Start Date**: April 28, 2026  
**Completion Target**: May 1, 2026

---

## Acceptance Criteria (All Issues)

### Security Layer Acceptance (All P1 Issues)
- ✅ All code committed to main (no staging branches)
- ✅ All changes in Terraform + IaC (no manual CLI commands)
- ✅ Prometheus metrics for every security control
- ✅ Grafana dashboard showing security posture
- ✅ Alert rules for all critical security events
- ✅ Runbooks for debugging + recovery
- ✅ Zero hardcoded secrets (encrypted or dynamic)
- ✅ All changes production-tested (on 192.168.168.31 before merge)

### Quality Standards
- ✅ Code review: ≥1 senior engineer approval
- ✅ Test coverage: 95%+ on new code
- ✅ Security scans passing: SAST (Trivy), container (Trivy), dependencies (gitleaks)
- ✅ No new CVEs introduced (Trivy scan clean)
- ✅ All acceptance criteria documented and verified

---

## Production Readiness Checklist

Before merging any P1 issue:

- [ ] Code compiles/runs without errors
- [ ] All tests passing (unit + integration)
- [ ] Security scans clean (SAST, container, dependencies)
- [ ] Performance benchmarks met (no latency regressions)
- [ ] Deployed to 192.168.168.31 and tested in production
- [ ] Monitoring/alerts configured and firing correctly
- [ ] Runbook documented and validated
- [ ] Rollback procedure tested (<60 seconds)
- [ ] Code review approved with "production-ready" comment
- [ ] GitHub issue acceptance criteria all checked

---

## Risk Mitigation

### Risk: #349→#354→#350 Blocking Chain
**Mitigation**: Parallelize with #348, #355, #356 (start immediately)

### Risk: SSH Hardening Locks Out User
**Mitigation**: Test on replica first, verify SSH access before merging

### Risk: SOPS Encryption Breaks Deploy
**Mitigation**: Test on staging, verify .env.enc → plaintext decryption works

### Risk: Cloudflare Tunnel Down Causes Outage
**Mitigation**: Keep DNS fallback IP pointing to primary host (secondary route)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Security Scan Coverage** | 100% | Trivy, gitleaks, Checkov all passing |
| **Code Coverage** | 95%+ | `go test -cover` on all new code |
| **Mean Time to Remediation (MTTR)** | <30 min | Alert firing → fix merged |
| **Uptime** | 99.99% | Phase 7 + Phase 8 combined |
| **CVEs High/Critical** | 0 | Trivy scan results |
| **Failed Deployments** | 0 | Per 100 merges |

---

## Completion Criteria

**Phase 8 is COMPLETE when**:
- ✅ All P1 issues (#349-#356) merged to main
- ✅ All acceptance criteria verified
- ✅ Production sign-off from security team
- ✅ Comprehensive security audit report generated
- ✅ Phase 7 + 8 combined uptime = 99.99% (measured over 1 week)

---

## Documentation References

- Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- ADR-001: [ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md](ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md)
- Phase 7 Complete: [PHASE-7-PRODUCTION-DEPLOYMENT-COMPLETE.md](PHASE-7-PRODUCTION-DEPLOYMENT-COMPLETE.md)
- Elite Best Practices: [ELITE-MASTER-ENHANCEMENTS.md](ELITE-MASTER-ENHANCEMENTS.md)

---

**Next Action**: Begin implementation of independent issues (#348, #355, #356) while completing Phase 7c/7d/7e.
