# Production Deployment Checklist - IAM Phase 2/3/4

**Issue**: #1085  
**Status**: Ready for Execution  
**Last Updated**: April 22, 2026  
**Owner**: Infrastructure Team  

---

## Overview

This checklist consolidates all pre-deployment validation steps for Phase 2/3/4 (OIDC Issuer, JWT Service Auth, and RBAC Enforcement) deployment to production.

**Critical Path**: ~4-6 hours from go/no-go decision to production validation complete.

---

## Pre-Deployment Phase (1 hour)

### ✅ Infrastructure Verification

- [ ] Primary host (192.168.168.31) is healthy
  ```bash
  ssh akushnir@192.168.168.31 'docker ps --format "table {{.Names}}\t{{.Status}}" | wc -l'
  # Should show ~14 services running
  ```
  
- [ ] Replica host (192.168.168.42) is healthy
  ```bash
  ssh akushnir@192.168.168.42 'docker ps --format "table {{.Names}}\t{{.Status}}" | wc -l'
  # Should show ~14 services running
  ```
  
- [ ] PostgreSQL replication is synced
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "SELECT slot_name, restart_lsn FROM pg_replication_slots;"'
  ```
  
- [ ] Redis is operational on both hosts
  ```bash
  ssh akushnir@192.168.168.31 'redis-cli ping'
  ssh akushnir@192.168.168.42 'redis-cli ping'
  # Both should return PONG
  ```
  
- [ ] Network connectivity between hosts is stable
  ```bash
  ssh akushnir@192.168.168.31 'ping -c 3 192.168.168.42'
  ```

### ✅ Credentials & Secrets Management

- [ ] Google Secret Manager (GSM) is accessible
  ```bash
  gcloud auth list
  gcloud config get project  # Should be kushin77-ops
  ```
  
- [ ] All required GSM secrets exist and are current
  - [ ] `oidc-issuer-signing-key` (RSA private key for JWT signing)
  - [ ] `jwt-service-account-creds-code-server` (client credentials)
  - [ ] `jwt-service-account-creds-session-broker` (client credentials)
  - [ ] `ide-session-lb-secret` (Caddy LB HMAC key)
  - [ ] `postgres-replication-password`
  - [ ] `redis-auth-password`
  
  ```bash
  gcloud secrets list --project=kushin77-ops | grep -E "oidc|jwt|ide-session|postgres|redis"
  ```
  
- [ ] Backup of current production state taken
  ```bash
  ssh akushnir@192.168.168.31 'cd /home/akushnir/code-server-enterprise && tar -czf /tmp/pre-phase-234-backup.tar.gz .env docker-compose.yml && ls -lh /tmp/pre-phase-234-backup.tar.gz'
  ```
  
- [ ] Backup transferred to safe location
  ```bash
  scp akushnir@192.168.168.31:/tmp/pre-phase-234-backup.tar.gz ./artifacts/backups/
  ```

### ✅ Access & Permissions

- [ ] SSH access to both hosts verified
  ```bash
  ssh akushnir@192.168.168.31 'whoami'  # Should output: akushnir
  ssh akushnir@192.168.168.42 'whoami'  # Should output: akushnir
  ```
  
- [ ] Sudo access available (for Docker operations)
  ```bash
  ssh akushnir@192.168.168.31 'sudo docker ps -q'
  ```
  
- [ ] GSM read access confirmed
  ```bash
  gcloud secrets versions list oidc-issuer-signing-key --project=kushin77-ops
  ```
  
- [ ] GitHub CLI authenticated and repo accessible
  ```bash
  gh repo view kushin77/code-server --json name
  ```

---

## Phase 2.1 - OIDC Issuer Deployment (1 hour)

**Reference**: `docs/PHASE-2-1-OIDC-ISSUER-DEPLOYMENT-PRODUCTION.md`

### ✅ OIDC Configuration

- [ ] OIDC issuer signing key generated and stored in GSM
  ```bash
  gcloud secrets versions access latest --secret="oidc-issuer-signing-key" --project=kushin77-ops | head -5
  # Should output PEM-format RSA key
  ```
  
- [ ] Issuer URL configured: `https://ide.kushnir.cloud`
  - [ ] TLS certificate valid (Let's Encrypt)
  - [ ] Certificate expiry: > 90 days
  
  ```bash
  openssl s_client -connect ide.kushnir.cloud:443 </dev/null 2>/dev/null | openssl x509 -noout -enddate
  ```

### ✅ OIDC Service Deployment

- [ ] `oauth2-oidc-issuer` service added to docker-compose.yml
  - [ ] Port 4182 (internal)
  - [ ] Environment variables: `OIDC_ISSUER_SIGNING_KEY`, `OIDC_ISSUER_SIGNING_KID`
  - [ ] Health check configured
  
- [ ] Service deployed on primary
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose up -d oauth2-oidc-issuer && sleep 5 && docker logs oauth2-oidc-issuer --tail 20'
  ```
  
- [ ] Service deployed on replica
  ```bash
  ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose up -d oauth2-oidc-issuer && sleep 5 && docker logs oauth2-oidc-issuer --tail 20'
  ```

### ✅ OIDC Endpoint Validation

- [ ] OIDC discovery endpoint responds (no auth required)
  ```bash
  curl -s https://ide.kushnir.cloud/.well-known/openid-configuration | jq '.issuer, .token_endpoint, .jwks_uri'
  # Should output issuer URL and endpoints
  ```
  
- [ ] JWKS endpoint returns valid public keys
  ```bash
  curl -s https://ide.kushnir.cloud/.well-known/jwks.json | jq '.keys[0] | {kty, alg, use}'
  # Should output RS256 signing key
  ```
  
- [ ] Token endpoint accepts client credentials (with valid credentials)
  ```bash
  curl -X POST https://ide.kushnir.cloud/oauth2/token \
    -d 'grant_type=client_credentials&client_id=code-server&client_secret=<SECRET>' \
    | jq '.access_token, .token_type, .expires_in'
  # Should output Bearer token with 3600s expiry
  ```

### ✅ Caddy Routing

- [ ] Caddyfile updated with OIDC routing
  - [ ] `/.well-known/openid-configuration` → `oauth2-oidc-issuer:4182` (no auth)
  - [ ] `/.well-known/jwks.json` → `oauth2-oidc-issuer:4182` (no auth)
  - [ ] `/oauth2/token` → `oauth2-oidc-issuer:4182` (with credentials)
  
- [ ] Caddy reloaded on primary
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose exec caddy caddy reload --address localhost:2019'
  ```
  
- [ ] Caddy reloaded on replica
  ```bash
  ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose exec caddy caddy reload --address localhost:2019'
  ```

---

## Phase 2C - JWT Service Account Provisioning (1 hour)

**Reference**: `docs/PHASE-2-DEPLOYMENT-GUIDE.md` (Section 2C)

### ✅ Service Credentials Generation

- [ ] Code-server service account credentials generated and stored in GSM
  ```bash
  gcloud secrets versions list jwt-service-account-creds-code-server --project=kushin77-ops
  # Should show versions with recent timestamp
  ```
  
- [ ] Session-broker service account credentials generated and stored in GSM
  ```bash
  gcloud secrets versions list jwt-service-account-creds-session-broker --project=kushin77-ops
  # Should show versions with recent timestamp
  ```

### ✅ Environment Variables Configuration

- [ ] Load GSM secrets into .env on primary
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && source scripts/fetch-gsm-secrets.sh && echo $JWT_SERVICE_ACCOUNT_ID'
  # Should output service account ID
  ```
  
- [ ] Load GSM secrets into .env on replica
  ```bash
  ssh akushnir@192.168.168.42 'cd code-server-enterprise && source scripts/fetch-gsm-secrets.sh && echo $JWT_SERVICE_ACCOUNT_ID'
  # Should output service account ID
  ```

### ✅ Service Restart with JWT Config

- [ ] code-server service restarted with JWT environment variables
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose restart code-server && sleep 10 && docker logs code-server --tail 20'
  ```
  
- [ ] session-broker service restarted with JWT environment variables
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose restart session-broker && sleep 10 && docker logs session-broker --tail 20'
  ```
  
- [ ] Replica services restarted
  ```bash
  ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose restart code-server session-broker && sleep 10 && docker logs code-server --tail 5'
  ```

### ✅ JWT Token Acquisition Test

- [ ] Code-server can acquire JWT token
  ```bash
  # This requires internal test - check logs on code-server
  ssh akushnir@192.168.168.31 'docker exec code-server curl -s -X POST http://oauth2-oidc-issuer:4182/oauth2/token \
    -d "grant_type=client_credentials&client_id=code-server&client_secret=$JWT_CODE_SERVER_SECRET" \
    | jq ".access_token" | head -c 50'
  # Should output JWT token (first 50 chars)
  ```

---

## Phase 3 - RBAC Enforcement Deployment (1 hour)

**Reference**: `docs/PHASE-3-RBAC-ENFORCEMENT.md` (if exists, or implementation PR #1030)

### ✅ Database Schema Migration

- [ ] RBAC tables created in PostgreSQL
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "\dt rbac*"'
  # Should output: rbac_roles, rbac_role_assignments tables
  ```
  
- [ ] RBAC views created for monitoring
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "\dv rbac*"'
  # Should output RBAC views
  ```

### ✅ Backend Service Restart

- [ ] Backend services restarted with RBAC middleware
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose restart code-server && sleep 10 && docker logs code-server --tail 30 | grep -i rbac'
  ```

### ✅ JWT Claims Extension

- [ ] JWT tokens include roles claim
  ```bash
  # Test: Acquire token and verify roles claim
  ssh akushnir@192.168.168.31 'docker exec code-server /bin/sh -c "
  TOKEN=\$(curl -s -X POST http://oauth2-oidc-issuer:4182/oauth2/token \\
    -d \"grant_type=client_credentials&client_id=code-server&client_secret=\$JWT_CODE_SERVER_SECRET\" \\
    | jq -r \".access_token\")
  echo \$TOKEN | cut -d. -f2 | base64 -d | jq .roles
  "'
  # Should output roles array
  ```

### ✅ RBAC Endpoint Authorization

- [ ] GET endpoints require viewer role (allow)
- [ ] POST/PUT endpoints require editor role (allow/deny based on role)
- [ ] DELETE endpoints require admin role (deny for viewer/editor)

Test endpoints:
```bash
# Test read endpoint (should work with any role)
curl -H "Authorization: Bearer <JWT_TOKEN>" https://ide.kushnir.cloud/api/v1/sessions

# Test write endpoint (should check role)
curl -X POST -H "Authorization: Bearer <JWT_TOKEN>" https://ide.kushnir.cloud/api/v1/sessions/terminate \
  -d '{"sessionId": "test"}'
```

---

## Phase 4 - Audit Logging Deployment (30 min)

**Reference**: Issue #1025 (or implementation PR if exists)

### ✅ Audit Table & Views

- [ ] Audit log table created in PostgreSQL
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "SELECT count(*) FROM audit_logs;"'
  # Should return: 0 (or existing audit log count)
  ```
  
- [ ] Audit views created for monitoring
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "\dv audit*"'
  # Should output audit views
  ```

### ✅ Audit Service Integration

- [ ] Backend services emit audit events
  ```bash
  # Check logs for audit event emission
  ssh akushnir@192.168.168.31 'docker logs code-server --tail 50 | grep -i "audit\|authorization"'
  ```

### ✅ Audit Event Sampling

- [ ] Verify audit log entries are being recorded
  ```bash
  ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "SELECT user_id, action, status FROM audit_logs ORDER BY timestamp DESC LIMIT 5;"'
  ```

---

## Post-Deployment Validation (1 hour)

### ✅ Health Checks - All Services

- [ ] All 14 services healthy on primary
  ```bash
  ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose ps | grep -E "Up|running"'
  # Should show 14 healthy services
  ```
  
- [ ] All 14 services healthy on replica
  ```bash
  ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose ps | grep -E "Up|running"'
  # Should show 14 healthy services
  ```

### ✅ HTTPS/OAuth Gate

- [ ] TLS certificate valid
  ```bash
  openssl s_client -connect ide.kushnir.cloud:443 </dev/null 2>/dev/null | openssl x509 -noout -subject,dates
  ```
  
- [ ] OAuth health endpoint returns 200
  ```bash
  curl -s -o /dev/null -w "%{http_code}" https://ide.kushnir.cloud/oauth2/health
  # Should output: 200
  ```

### ✅ Prometheus & Grafana Metrics

- [ ] Prometheus scrapes all targets
  ```bash
  curl -s http://192.168.168.31:9090/api/v1/targets | jq '.data.activeTargets | length'
  # Should show number of scraped targets
  ```
  
- [ ] Grafana dashboards reflect current data
  - [ ] OAuth2 Proxy dashboard (latency, requests/sec)
  - [ ] JWT Auth Service Metrics dashboard (token issuance, cache hit rate)
  - [ ] RBAC Authorization dashboard (allow/deny counts)
  - [ ] Audit Logging dashboard (authorization decision log)

### ✅ E2E Test Suite Execution

- [ ] Run full E2E test suite
  ```bash
  bash scripts/ci/run-comprehensive-e2e-tests.sh --all --workers=4
  # Should complete in ~15 minutes with all scenarios passing
  ```
  
- [ ] OAuth flow test passes
  ```bash
  E2E_USER_EMAIL=qa@kushnir.cloud E2E_USER_PASSWORD=<PASSWORD> \
  BASE_URL=https://ide.kushnir.cloud \
  bash scripts/ci/run-comprehensive-e2e-tests.sh --suite=oauth
  ```
  
- [ ] JWT token validation test passes
  ```bash
  TOKEN_ENDPOINT=https://ide.kushnir.cloud/oauth2/token \
  bash scripts/ci/run-comprehensive-e2e-tests.sh --suite=jwt
  ```
  
- [ ] RBAC authorization test passes
  ```bash
  E2E_USER_EMAIL=qa@kushnir.cloud E2E_USER_PASSWORD=<PASSWORD> \
  API_BASE_URL=https://api.kushnir.cloud \
  bash scripts/ci/run-comprehensive-e2e-tests.sh --suite=rbac
  ```
  
- [ ] Failover scenario test passes
  ```bash
  bash scripts/ci/run-comprehensive-e2e-tests.sh --suite=failover
  ```

### ✅ Manual Smoke Tests

- [ ] User can log in via Google OAuth
  - [ ] Navigate to https://kushnir.cloud
  - [ ] Click "Sign in with Google"
  - [ ] Complete Google login
  - [ ] Redirected to dashboard
  
- [ ] JWT token visible in browser storage
  - [ ] Open DevTools → Application → Cookies
  - [ ] Verify `code-server-jwt` cookie present
  - [ ] Cookie contains base64-encoded JWT
  
- [ ] RBAC authorization working
  - [ ] Login with QA user (viewer role)
  - [ ] Attempt to access admin-only endpoint
  - [ ] Verify 403 Forbidden response
  
- [ ] Audit logging active
  - [ ] Check logs on primary
  - [ ] Query audit_logs table for recent entries
  - [ ] Verify authorization events are logged

---

## Rollback Plan (If Needed)

### ✅ Automatic Rollback Triggers

If any of the following occur, execute rollback immediately:

- [ ] **Service crash loop**: Any service fails to start > 3 times
  - **Action**: `bash scripts/ops/rollback.sh`
  
- [ ] **OAuth broken**: Login fails for all users
  - **Action**: Verify oauth2-proxy health, then rollback if needed
  
- [ ] **JWT validation failing**: > 5% of requests return 401/403
  - **Action**: Check JWT service logs, then rollback if needed
  
- [ ] **Database connection pool exhausted**: Connections refused
  - **Action**: `bash scripts/ops/incident-isolation.sh` then rollback
  
- [ ] **Primary/replica sync broken**: Replication lagging > 1 hour
  - **Action**: Check PostgreSQL logs, then rollback if needed

### ✅ Rollback Procedure

```bash
# On primary host
ssh akushnir@192.168.168.31 'cd code-server-enterprise && bash scripts/ops/rollback.sh'

# Verify all services recovered
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker compose ps'

# Verify replica follows
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker compose ps'

# Re-run smoke tests after rollback
bash scripts/ci/run-comprehensive-e2e-tests.sh --suite=sanity
```

---

## Sign-Off

### Pre-Deployment Approval

- [ ] Infrastructure lead reviews all pre-deployment checks
- [ ] Security lead verifies all secrets are managed via GSM
- [ ] QA lead confirms E2E test suite is passing
- [ ] Ops lead confirms backup and rollback procedures ready

**Approved By**: ________________  
**Date**: ________________  
**Time**: ________________  

### Post-Deployment Approval

- [ ] All health checks passing
- [ ] E2E tests 100% passing on production infrastructure
- [ ] Smoke tests completed successfully
- [ ] Audit logs showing normal authorization decisions
- [ ] No error spikes in Prometheus/Grafana

**Approved By**: ________________  
**Date**: ________________  
**Time**: ________________  

---

## Reference Documents

- **Phase 2.1 OIDC**: `docs/PHASE-2-1-OIDC-ISSUER-DEPLOYMENT-PRODUCTION.md`
- **Phase 2C JWT**: `docs/PHASE-2-DEPLOYMENT-GUIDE.md`
- **Phase 3 RBAC**: Issue #1030 (PR fe1e7970e)
- **Phase 4 Audit**: Issue #1025
- **E2E Tests**: `docs/E2E-TEST-SUITE-EXECUTION.md`
- **Runbooks**: `docs/runbooks/`
- **Rollback**: `scripts/ops/rollback.sh`

---

## Quick Reference - Critical Commands

```bash
# Verify infrastructure health
ssh akushnir@192.168.168.31 'docker ps -q | wc -l'  # Should show 14

# View service logs
ssh akushnir@192.168.168.31 'docker logs <service-name> --tail 50'

# Test OIDC endpoint
curl -s https://ide.kushnir.cloud/.well-known/openid-configuration | jq .issuer

# Test JWT token acquisition
curl -X POST https://ide.kushnir.cloud/oauth2/token \
  -d 'grant_type=client_credentials&client_id=code-server&client_secret=<SECRET>'

# Run E2E tests
bash scripts/ci/run-comprehensive-e2e-tests.sh --all

# Rollback (if needed)
bash scripts/ops/rollback.sh

# Check PostgreSQL replication
ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "SELECT slot_name, restart_lsn FROM pg_replication_slots;"'

# Monitor audit logs
ssh akushnir@192.168.168.31 'psql -U postgres -d code_server -c "SELECT * FROM audit_logs ORDER BY timestamp DESC LIMIT 10;"'
```

---

**Status**: ✅ Ready for Production Deployment  
**Estimated Duration**: 4-6 hours start to finish  
**Go/No-Go Decision**: TBD (Awaiting infrastructure team approval)  

**Last Updated**: April 22, 2026  
**Next Review**: After Phase 2/3/4 deployment completion
