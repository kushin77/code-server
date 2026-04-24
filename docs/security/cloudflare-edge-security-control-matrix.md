# Cloudflare Free-Tier Security Control Matrix

**Purpose**: Cloudflare Free-Tier Security Control Matrix runbook — operational procedure for cloudflare edge security control matrix response.

---
title: Cloudflare Free-Tier Security Control Matrix
description: Inventory and status of all Cloudflare free-tier security controls for kushnir.cloud edge hardening
owner: platform
last_review_date: 2026-04-20
status: active
related_issues: ["#858", "#856", "#876", "#835", "#866"]
---

# Cloudflare Free-Tier Security Control Matrix

## Overview

This document captures every Cloudflare free-tier security control applicable to the
kushnir.cloud deployment. Controls are classified by category, mapped to acceptance
criteria in [#858](https://github.com/kushin77/code-server/issues/858), and include
validation method and escalation path.

**CI Enforcement**: `.github/workflows/edge-security-controls.yml` (weekly + on Caddyfile change)
**Validation Script**: `scripts/ci/check-edge-security-controls.sh`

---

## TLS / Transport Security

| Control | Status | Configuration | Validation |
|---|---|---|---|
| HTTPS enforcement (HTTP→HTTPS redirect) | ✅ Enabled | Cloudflare Always Use HTTPS (free) | `curl -I http://kushnir.cloud` → 301/302 |
| TLS minimum version 1.2 | ✅ Enabled | Cloudflare SSL/TLS → Edge certificates → Min TLS 1.2 | Cloudflare dashboard |
| HSTS header | ✅ Enabled | Caddyfile: `Strict-Transport-Security max-age=31536000; includeSubDomains; preload` | CI check |
| HSTS preload submission | ✅ Configured | `preload` flag in HSTS header; submit to hstspreload.org | https://hstspreload.org/?domain=kushnir.cloud |
| TLS certificate (Let's Encrypt) | ✅ Active | Caddy ACME via `acme-v02.api.letsencrypt.org` | `openssl s_client -connect kushnir.cloud:443` |
| Opportunistic Encryption | ✅ Enabled | Cloudflare default (free) | — |

---

## Security Headers

All headers are set at the Caddy level for all virtual hosts. Cloudflare passes them through untouched.

| Header | Value | Status | Notes |
|---|---|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | ✅ | All vhosts |
| `X-Content-Type-Options` | `nosniff` | ✅ | All vhosts |
| `X-Frame-Options` | `SAMEORIGIN` | ✅ | All vhosts |
| `X-XSS-Protection` | `1; mode=block` | ✅ | Legacy header; kept for old browsers |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | ✅ | Added 2026-04-20 |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=()` | ✅ | Added 2026-04-20 |
| `Server` header | Suppressed (`-Server`) | ✅ | All vhosts |
| `Content-Security-Policy` | Not set | ⚠️ P2 | Code-server inline scripts make strict CSP complex; tracked separately |

---

## Cloudflare Access (Zero-Trust)

| Control | Status | Details | Reference |
|---|---|---|---|
| Grafana behind Access | ✅ | `grafana.kushnir.cloud` — email allowlist + optional WARP | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| Prometheus behind Access | ✅ | `prometheus.kushnir.cloud` | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| AlertManager behind Access | ✅ | `alertmanager.kushnir.cloud` | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| Jaeger behind Access | ✅ | `jaeger.kushnir.cloud` | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| WARP device posture | ✅ Configurable | Set `cloudflare_warp_device_posture_id` in terraform.tfvars | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| Access audit log | ✅ Configurable | Logpush to R2 (`cloudflare_logpush_r2_bucket`) | [#876](../security/cloudflare-access-warp-zero-trust.md) |
| Service tokens for CI | ✅ | `ci_prometheus`, `ci_grafana` tokens (90-day expiry) | Terraform outputs |

---

## WAF / Rate Limiting (Cloudflare Free)

| Control | Status | Details |
|---|---|---|
| Cloudflare WAF (managed rules) | ✅ Enabled | Free tier includes OWASP core rule set (limited) |
| DDoS protection | ✅ Always-on | Cloudflare L3/L4/L7 DDoS mitigation (free) |
| Bot Fight Mode | ✅ Recommended | Enable in Cloudflare dashboard: Security → Bots |
| Rate limiting | ⚠️ Manual | Free tier: 1 rule via Cloudflare dashboard; paid tier needed for advanced |
| Browser Integrity Check | ✅ Enabled | Default on free tier |
| Hotlink Protection | ✅ Recommended | Enable in Cloudflare dashboard: Scrape Shield |

---

## Origin Concealment / Tunnel

| Control | Status | Details |
|---|---|---|
| Cloudflare Tunnel (cloudflared) | ✅ Active | Origin IP not exposed in DNS | 
| Proxied DNS records (orange cloud) | ✅ Required | All public-facing A/CNAME records must be proxied |
| Direct-to-IP access blocked | ✅ | Caddy only listens on localhost/tunnel; firewall blocks 80/443 direct |
| CF-Ray header present | ✅ | Verified by CI check — confirms traffic routes through CF edge |

---

## Certificate Management

| Control | Status | Details |
|---|---|---|
| Auto-renewal (Let's Encrypt) | ✅ | Caddy renews automatically (60 days before expiry) |
| Certificate expiry monitoring | ✅ | Alert rule in `alert-rules.yml` for <14 days expiry |
| Wildcard cert support | ✅ | `Caddyfile.production` uses wildcard via DNS challenge |
| Certificate pinning | ❌ Not applicable | HPKP deprecated; use HSTS preload instead |

---

## Escalation Paths

| Severity | Condition | Immediate Action | Owner |
|---|---|---|---|
| **P0** | HSTS missing or max-age < 1 year | Fix Caddyfile + `docker compose up -d caddy` on deploy host | Platform |
| **P0** | TLS certificate expired | Check Caddy logs; force renewal: `docker exec caddy caddy reload` | Platform |
| **P1** | Admin endpoint reachable without Access challenge | Re-apply Terraform cloudflare-access module | Platform |
| **P1** | CF-Ray absent (origin IP exposed) | Set DNS record to proxied in Cloudflare dashboard | Platform |
| **P1** | WAF block storm (false positives) | Temporarily disable rule in CF dashboard; create exception rule | Platform |
| **P2** | Missing security header | Add to Caddyfile and deploy | Platform |
| **P3** | Server header visible | Add `-Server` to Caddyfile header block | Platform |

---

## Rollback and Exception Handling

### Header Rollback
```bash
# Revert to previous Caddyfile
git checkout HEAD~1 -- Caddyfile
ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker compose up -d caddy"
```

### Access Policy Rollback
```bash
# Remove WARP posture enforcement
cd terraform/
terraform apply -var="cloudflare_warp_device_posture_id=" -var-file=terraform.tfvars
```

### Exception Process
1. Open a GitHub issue with label `security-exception`
2. Document: business justification, compensating controls, expiry date
3. Assign to CISO owner for sign-off
4. Update this control matrix with exception status and expiry

---

## Validation Evidence

Run locally:
```bash
# Static analysis (Caddyfile header declarations)
bash scripts/ci/check-edge-security-controls.sh

# Admin endpoint protection
ADMIN_BASE_URL=https://kushnir.cloud bash scripts/ci/verify-cloudflare-admin-access.sh
```

CI reports stored at:
- `artifacts/triage/edge-security-controls-report.md`
- `artifacts/triage/edge-security-controls-report.json`
- `artifacts/triage/cloudflare-admin-access-verify.md`
