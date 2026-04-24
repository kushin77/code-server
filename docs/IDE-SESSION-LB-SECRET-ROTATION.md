# IDE_SESSION_LB_SECRET Rotation Procedure

## Overview

This document describes the complete procedure for rotating the `IDE_SESSION_LB_SECRET` from the hardcoded `secret734` to a secure, GSM-managed secret with failover validation.

## Context

- **Issue**: #1163 (P0 SECURITY: Caddyfile Secret Rotation & GSM Deployment)
- **Parent Issue**: #1032 (identified hardcoded `secret734` in Caddyfile)
- **Impact**: Sticky-session cookie HMAC key used by Caddy load balancer
- **Risk**: Compromised key could allow attackers to forge session affinity, potentially bypassing sticky routing

## Pre-Rotation Checklist

- [ ] Both hosts (primary 192.168.168.31 and replica 192.168.168.42) are operational
- [ ] All 14 services are healthy on both hosts
- [ ] GCP project credentials are available (`gcloud` CLI authenticated)
- [ ] SSH access to both hosts is verified
- [ ] Backup of `.env` on both hosts exists
- [ ] Monitoring/alerting is active to detect issues

## Step 1: Preparation (5 minutes)

### 1.1 Verify connectivity to both hosts

```bash
ssh akushnir@192.168.168.31 "docker ps -q | wc -l"  # Should show ~14 services
ssh akushnir@192.168.168.42 "docker ps -q | wc -l"  # Should show ~14 services
```

### 1.2 Verify GCP project access

```bash
gcloud config get-value project
gcloud secrets list --project=gcp-eiq | grep -i session  # Existing secrets
```

### 1.3 Create `.env` backups (manual safeguard)

```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && cp .env .env.backup-pre-rotation.$(date +%Y%m%d-%H%M%S)"
ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && cp .env .env.backup-pre-rotation.$(date +%Y%m%d-%H%M%S)"
```

## Step 2: Secret Provisioning (10 minutes)

### 2.1 Generate new secret and provision to GSM

**Run the provisioning script in dry-run mode first:**

```bash
DRY_RUN=1 bash scripts/ops/provision-ide-session-lb-secret.sh
```

**Review the output to verify the plan:**

```
Generating 128-bit secure random secret...
Creating/updating GSM secret: ide-session-lb-secret
[DRY-RUN] Would create GSM secret: ide-session-lb-secret
[DRY-RUN] Secret value: 12345678...
...
```

### 2.2 Execute the provisioning (real mode)

```bash
DRY_RUN=0 bash scripts/ops/provision-ide-session-lb-secret.sh
```

**Expected output:**

```
IDE_SESSION_LB_SECRET Rotation & Deployment
═══════════════════════════════════════════════════════
Generated new secret: a1b2c3d4...
✓ GSM secret created/updated
✓ Secret deployed to 192.168.168.31
✓ Secret deployed to 192.168.168.42
✓ Failover test completed
```

## Step 3: Failover Validation (15 minutes)

### 3.1 Run automated verification

```bash
bash scripts/ops/verify-ide-session-lb-secret.sh
```

**Expected output:**

```
Verifying IDE_SESSION_LB_SECRET rotation...
[1/6] Checking primary Caddyfile for hardcoded secret734...
✓ No hardcoded 'secret734' found in primary
...
═══════════════════════════════════════════════════════
Verification Summary: 6/6 checks passed
✓ All verification checks passed!
```

### 3.2 Manual failover test (optional but recommended)

**Test 1: Primary active, replica standby**

```bash
# Test primary can handle traffic
curl -v https://ide.kushnir.cloud/health

# Check sticky-session cookie
curl -v -c /tmp/cookies.txt https://ide.kushnir.cloud/ 2>&1 | grep -i "ide_session_lb"
```

**Test 2: Primary shutdown, replica active**

```bash
# Shutdown primary Caddy
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && docker-compose exec caddy caddy stop"

# Verify traffic routes to replica via Cloudflare DNS failover
sleep 10
curl -v https://ide.kushnir.cloud/health

# Restore primary
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && docker-compose up -d caddy"
```

## Step 4: Git History Cleanup (5-10 minutes)

### 4.1 Identify commits containing `secret734`

```bash
git log --all -S 'secret734' --oneline | head -10
```

### 4.2 Remove secret from git history

**WARNING**: This step rewrites git history. Coordinate with team before proceeding.

```bash
# Install git-filter-repo if needed
pip install git-filter-repo

# Create filter file
echo "secret734==>REDACTED_OLD_SECRET" > /tmp/secret-filter.txt

# Apply filter
git-filter-repo --replace-text /tmp/secret-filter.txt

# Force push to main (requires admin override on protected branch)
git push origin main --force-with-lease
```

## Step 5: Verification & Closeout (5 minutes)

### 5.1 Verify secret is not in git

```bash
git log --all -S 'secret734' --oneline | wc -l  # Should output 0
git log --all -S 'secret734'  # Should show nothing

# Also check current HEAD
grep -r 'secret734' . --exclude-dir=.git 2>/dev/null | wc -l  # Should output 0
```

### 5.2 Verify CI/CD checks pass

```bash
# Run config drift check (should pass)
bash scripts/ci/check-hardcoded-ips.sh
bash scripts/ci/check-no-hardcoded-credentials.sh
bash scripts/ci/detect-config-drift.sh
```

### 5.3 Post-rotation evidence

Create a summary with:
- ✓ New secret provisioned to GSM (date/time)
- ✓ Secret deployed to both hosts
- ✓ Failover testing completed
- ✓ Git history cleaned
- ✓ CI/CD checks passing

## Rollback Procedure (If Needed)

If issues arise, rollback is simple:

### 3.1 Restore .env from backup

```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && \
  cp .env.backup-pre-rotation.* .env"

ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && \
  cp .env.backup-pre-rotation.* .env"
```

### 3.2 Reload Caddy

```bash
ssh akushnir@192.168.168.31 "cd ~/code-server-enterprise && \
  docker-compose exec caddy caddy reload"

ssh akushnir@192.168.168.42 "cd ~/code-server-enterprise && \
  docker-compose exec caddy caddy reload"
```

### 3.3 Verify rollback

```bash
bash scripts/ops/verify-ide-session-lb-secret.sh  # Should still show healthy
```

## Testing Matrix

| Scenario | Expected Result | Command |
|----------|-----------------|---------|
| Primary active | Traffic routes to primary | `curl https://ide.kushnir.cloud/health` |
| Replica active (primary down) | Traffic routes to replica via Cloudflare | Same curl after primary stops |
| Sticky sessions work | User maintains session across requests | Cookie inspection in browser DevTools |
| Failback to primary | Traffic returns to primary when it's up | Same curl after primary restarts |
| Old secret inactive | Forged cookies with secret734 rejected | Attempted manual cookie manipulation |

## Metrics & Monitoring

Post-rotation, monitor:

1. **Caddy health**
   - Restart count (should be low)
   - Error rate (should be <0.1%)
   - Configuration reload latency (<100ms)

2. **Session stability**
   - Cookie expiry time (should match Caddy config)
   - Sticky routing success rate (should be ~100%)
   - Session loss events (should be 0 during normal operation)

3. **Failover behavior**
   - DNS resolution latency
   - Failover trigger time (< 2min from primary health check failure)
   - Session preservation across failover (should be 100%)

## References

- [Caddy Load Balancer Documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy#policy)
- [Google Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)
- [Git Filter Repo](https://github.com/newren/git-filter-repo)
- [OWASP Secret Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

## Questions & Support

For questions or issues during rotation:
1. Check the rollback procedure above
2. Review CI/CD logs for errors
3. File an issue referencing #1163 with evidence

---

**Document Version**: 1.0  
**Last Updated**: April 22, 2026  
**Author**: Copilot AI Agent  
**Related Issues**: #1163 (parent), #1032 (original finding)
