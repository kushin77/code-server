# Cloudflare Access + WARP Zero-Trust for Admin Endpoints

**Purpose**: Cloudflare Access + WARP Zero-Trust for Admin Endpoints runbook — operational procedure for cloudflare access warp zero trust response.

---
title: Cloudflare Access + WARP Zero-Trust for Admin Endpoints
description: Zero-trust enforcement for Grafana, Prometheus, AlertManager, and Jaeger using Cloudflare Access and WARP device posture checks
owner: platform
last_review_date: 2026-04-20
status: active
related_issues: ["#876", "#866", "#835", "#858"]
---

# Cloudflare Access + WARP Zero-Trust for Admin Endpoints

## Overview

All admin and observability endpoints are protected by Cloudflare Access with optional WARP device
posture enforcement. No admin UI is reachable from the public internet without:

1. A valid Cloudflare identity (Google auth via `allowed-emails.txt`)
2. A WARP-enrolled managed device (when `CLOUDFLARE_WARP_DEVICE_POSTURE_ID` is set)

**Protected endpoints:**

| Subdomain | Port | Service |
|---|---|---|
| `grafana.kushnir.cloud` | 3000 | Grafana dashboards |
| `prometheus.kushnir.cloud` | 9090 | Prometheus metrics |
| `alertmanager.kushnir.cloud` | 9093 | AlertManager |
| `jaeger.kushnir.cloud` | 16686 | Jaeger tracing |

## Architecture

```
User Browser
    │
    ▼
Cloudflare Edge (Access challenge)
    │  ── Google OAuth identity check (allowed-emails.txt)
    │  ── WARP device posture check (if posture ID set)
    │
    ▼
Cloudflare Tunnel (cloudflared)
    │
    ▼
Caddy reverse proxy (localhost only)
    │
    ▼
Admin service (Grafana / Prometheus / etc.)
```

## Terraform Configuration

The Cloudflare Access module is defined at:
- **Module**: `terraform/modules/cloudflare-access/`
- **Wired via**: `terraform/modules-composition.tf` (module `cloudflare_access`)

### Key variables (`terraform.tfvars` or environment):

| Variable | Description | Required |
|---|---|---|
| `cloudflare_account_id` | Cloudflare account ID | Yes |
| `cloudflare_api_token` | API token (Zone:Edit, Access:Edit) | Yes |
| `apex_domain` | e.g. `kushnir.cloud` | Yes |
| `allowed_emails` | List of emails from `allowed-emails.txt` | Yes |
| `google_client_id` | Google OAuth2 client ID | Yes |
| `google_client_secret` | Google OAuth2 client secret | Yes |
| `primary_ip` | Deploy host IP (for bypass rule) | Yes |
| `cloudflare_warp_device_posture_id` | WARP posture integration ID | Optional |
| `cloudflare_logpush_r2_bucket` | R2 bucket for audit logs | Optional |

### Apply:

```bash
cd terraform/
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## WARP Device Enrollment

### Prerequisites
- Cloudflare Zero Trust account (free tier supports up to 50 users)
- WARP client installed on management device

### Steps

1. **Create a WARP enrollment policy** in the Cloudflare dashboard:
   - Zero Trust → Settings → WARP Client → Device enrollment
   - Restrict enrollment to email domain: `@kushnir.cloud` (or your domain)

2. **Install WARP client** on management device:
   - macOS/Linux: Download from `https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/warp/download-warp/`
   - Open WARP → Preferences → Account → Login with Cloudflare Zero Trust
   - Organization: your Cloudflare Zero Trust team name

3. **Create a device posture integration** (optional but recommended):
   - Zero Trust → Settings → WARP Client → Device posture
   - Add check: OS version, disk encryption, firewall
   - Copy the **Integration ID** → set as `CLOUDFLARE_WARP_DEVICE_POSTURE_ID` in env / `terraform.tfvars`

4. **Set the posture ID in Terraform**:
   ```bash
   # terraform.tfvars
   cloudflare_warp_device_posture_id = "your-posture-integration-id"
   ```

5. **Re-apply Terraform** to enforce posture on all Access applications.

### Verify WARP connectivity

```bash
# On the management device with WARP enrolled
curl -v https://grafana.kushnir.cloud/  # Should pass through without Access challenge
```

## CI/CD Service Tokens

Two short-lived service tokens are provisioned for CI pipelines:

| Token | Purpose | Max TTL |
|---|---|---|
| `ci_prometheus` | Prometheus health checks in CI | 90 days |
| `ci_grafana` | Grafana API calls in CI | 90 days |

Tokens are output from Terraform as sensitive values:
```bash
terraform output ci_prometheus_service_token_client_id
terraform output ci_prometheus_service_token_client_secret
```

Set these as GitHub secrets:
- `CF_ACCESS_CLIENT_ID_PROMETHEUS`
- `CF_ACCESS_CLIENT_SECRET_PROMETHEUS`
- `CF_ACCESS_CLIENT_ID_GRAFANA`
- `CF_ACCESS_CLIENT_SECRET_GRAFANA`

Usage in CI:
```bash
curl -H "CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID_PROMETHEUS}" \
     -H "CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET_PROMETHEUS}" \
     https://prometheus.kushnir.cloud/-/healthy
```

## Audit Logging (Logpush)

Access audit logs are pushed to Cloudflare R2 via Logpush when `cloudflare_logpush_r2_bucket` is set.

Logged fields per request:
- `RayID`, `Timestamp`, `Action`, `UserEmail`, `IPAddress`
- `DeviceID`, `AppDomain`, `RuleEvaluationSummary`, `DevicePostureCheckPass`

To enable:
```bash
# terraform.tfvars
cloudflare_logpush_r2_bucket = "your-r2-bucket-name"
```

Logs are retained indefinitely in R2 (apply your own lifecycle policy for cost management).

## Legacy IP Allow-List Removal

Before Access was enforced, some admin endpoints relied on Caddy-level IP allow-lists.
Cloudflare Access replaces this at the edge. The Caddyfile has been audited:

- ✅ No IP allow-list blocks for admin endpoints remain active in `Caddyfile`
- ✅ `192.168.168.31` appears only as a VIP comment reference, not as an allow-list rule
- ✅ All admin traffic from the public internet is challenged by Cloudflare Access before reaching Caddy
- The deploy host (192.168.168.31) has a bypass rule in Cloudflare Access (not an IP allow-list)

## CI Verification

The CI workflow `cloudflare-admin-access-verify.yml` runs scheduled and on-demand to verify that
all admin endpoints return a block/challenge response (302 to `/cdn-cgi/access`, 401, or 403)
when accessed without a valid Access token.

```bash
# Manual verification
ADMIN_BASE_URL=https://ide.kushnir.cloud bash scripts/ci/verify-cloudflare-admin-access.sh
```

Report is written to `artifacts/triage/cloudflare-admin-access-verify.md`.

If verification fails, a GitHub issue is auto-created and linked to #876.

## Protection Matrix

| Protection Layer | Admin Endpoints | IDE Endpoints |
|---|---|---|
| Cloudflare Access | ✅ Required | ❌ Not applied |
| WARP device posture | ✅ Configurable | ❌ Not applied |
| oauth2-proxy | Via Access IdP | ✅ Required |
| Caddy IP rules | ❌ Removed | Not applicable |
| CI enforcement | ✅ Weekly + on-demand | Not applicable |
