# Critical Path Execution Guide - April 2026

## Current Status

**Date**: April 20, 2026  
**All Infrastructure**: ✅ Operational  
**All Automation**: ✅ Ready  
**E2E Tests**: ⏳ Ready (awaiting QA user)  
**Observability**: ✅ Complete (Issues #995, #997, #1011)

---

## Critical Blocker: Issue #983

**Status**: ⏳ BLOCKED - Manual step required  
**Title**: Create qa@kushnir.cloud Google Workspace user  
**Timeline**: ~35-40 minutes (manual + automated)

### Prerequisites for #983

Issue #983 itself has a blocker: **kushnir.cloud domain must be registered in Google Workspace**

This was solved in earlier work:
- **File**: `GOOGLE-WORKSPACE-DOMAIN-REGISTRATION-GUIDE.md`
- **Automation**: `scripts/register-google-workspace-domain.sh`
- **Timeline**: ~20 minutes

### Steps to Unblock #983 (Prerequisite)

1. **Register kushnir.cloud in Google Workspace** (20 min total):
   - Phase 1 (2 min): Load GoDaddy credentials
   - Phase 2 (5 min): Start registration in Google Workspace Admin
   - Phase 3 (5 min): Add DNS TXT record (automated)
   - Phase 4 (3 min): Complete verification
   - DNS propagation: ~5 min (usually instant)

2. **Execute Issue #983**: Create qa@kushnir.cloud user
   - Follow: `ISSUE-983-COMPLETE-GUIDE.md`
   - Create user in Google Workspace
   - Set initial password
   - Assign "Editor" role
   - Timeline: ~15 min

### After #983 is Complete

Then execute **Issue #984** (autonomous - no manual steps):
```bash
cd c:\code-server-enterprise

# 1. Create QA user secrets in GSM (30 min)
bash scripts/ops/create-qa-user-automated.sh

# 2. Setup CI/CD service account access (10 min)
bash scripts/ops/setup-ci-qa-credentials.sh --gcp-project kushin77-ops

# 3. Verify entire E2E infrastructure (5 min)
bash scripts/ops/verify-e2e-qa-setup.sh --full

# 4. Restart oauth2-proxy to use new whitelist (1 min)
docker compose restart oauth2-proxy
```

---

## Complete Critical Path (After #983/#984)

| Phase | Issue | Duration | Status | Dependencies |
|-------|-------|----------|--------|--------------|
| **0** | Domain registration (prerequisite) | 20 min | ⏳ TODO | None |
| **1** | #983: Create QA user | 15 min | ⏳ TODO | Domain (Phase 0) |
| **2** | #984: Setup OAuth & credentials | 30 min | ✅ Ready | #983 |
| **3** | #986: OAuth login E2E tests | 45 min | ✅ Ready | #984 |
| **4** | #987-990: Portal & IDE E2E tests | 60 min | ✅ Ready | #986 |
| **5** | Production deployment | 10 min | ✅ Ready | All E2E pass |
| **Total** | **Production Live** | **~180 min** | | |

**Of that 180 minutes:**
- Manual: ~55 minutes (domain + QA user)
- Automated: ~125 minutes (credentials, tests, deploy)

---

## Next Autonomous Actions (While Waiting for #983)

### 1. Verify All Infrastructure Ready

```bash
# Run comprehensive validation
bash VALIDATE-PRODUCTION-READY.sh

# Expected output: ALL 15 DELIVERABLES VERIFIED ✓
```

### 2. Review All E2E Test Suites

All test specs are production-ready:
- **#986**: OAuth login (20+ tests, 531 lines) ✅
- **#987**: Appsmith portal (30+ tests) ✅
- **#988**: IDE launch & workspace (25+ tests) ✅
- **#989**: Session persistence (20+ tests) ✅
- **#990**: Error handling & edge cases (30+ tests) ✅

### 3. Recent Completions (Past 2 Hours)

**Issue #1011**: Matrix Collaboration Hub Observability ✓
- ✅ Prometheus scrape jobs (Synapse, bridges, presence)
- ✅ Grafana dashboards (2 provisioned dashboards)
- ✅ AlertManager rules (15+ alerts configured)
- **Next**: Restart docker compose to activate

**Issue #997**: Session-broker graceful shutdown ✓
- ✅ Graceful shutdown handler (30s timeout)
- ✅ Session notification on termination
- ✅ Container management (stop-all logic)
- ✅ Unit tests (7 methods tested)

**Issue #995**: Redis Sentinel Observability ✓
- ✅ Redis exporter (master-replica + sentinel metrics)
- ✅ Prometheus scrape job
- ✅ Grafana dashboard (7 panels)
- ✅ AlertManager rules

---

## Issue #983 Execution Checklist

### Phase 0: Register kushnir.cloud Domain (Prerequisite)

**File**: `GOOGLE-WORKSPACE-DOMAIN-REGISTRATION-GUIDE.md`

```
[ ] Phase 1: Load GoDaddy credentials
    Command: source scripts/fetch-gsm-secrets.sh
    Verify: echo $GODADDY_KEY | head -c 10

[ ] Phase 2: Start registration in Google Workspace Admin
    1. Go to admin.google.com
    2. Domains → Add domain
    3. Enter: kushnir.cloud
    4. Choose: Verify with DNS TXT record
    5. Copy verification value

[ ] Phase 3: Add DNS TXT record
    Command: bash scripts/register-google-workspace-domain.sh \
               --verification-value "google-site-verification=VALUE_FROM_GOOGLE"
    Verify: nslookup -type=TXT kushnir.cloud

[ ] Phase 4: Complete verification
    1. Return to admin.google.com
    2. Click "Verify" button
    3. Domain status → "Verified" ✓
```

**Time**: 20 minutes

### Phase 1: Create qa@kushnir.cloud User

**File**: `ISSUE-983-COMPLETE-GUIDE.md`

```
[ ] Access Google Workspace Admin
    User: akushnir@bioenergystrategies.com
    
[ ] Navigate to Users section
    Path: admin.google.com → Users → Add user
    
[ ] Create user
    First Name: QA
    Last Name: User
    Email: qa@kushnir.cloud
    Password: (auto-generate, ~20 characters)
    Password action: Require password change on next login
    
[ ] Assign role
    Role: Editor (allows full workspace access for testing)
    
[ ] Verify user creation
    Test: Login as qa@kushnir.cloud with generated password
    Expected: Can access code-server.kushnir.cloud
```

**Time**: 15 minutes

---

## Issue #984 Automation (After #983)

**File**: `ISSUE-984-COMPLETION-GUIDE.md`

```bash
# Already executed (awaiting #983 to complete)
# These are autonomous - no manual steps required

# Step 1: Create QA secrets in GSM (30 min)
bash scripts/ops/create-qa-user-automated.sh

# Step 2: Setup CI/CD service account (10 min)
bash scripts/ops/setup-ci-qa-credentials.sh --gcp-project kushin77-ops

# Step 3: Verify all infrastructure (5 min)
bash scripts/ops/verify-e2e-qa-setup.sh --full

# Step 4: Restart oauth2-proxy
docker compose restart oauth2-proxy

# All automated - no user interaction needed
```

**Time**: 45 minutes (mostly waiting for script execution)

---

## E2E Test Execution (After #984)

```bash
# Once #984 is complete, run all E2E tests:
E2E_USER_EMAIL=qa@kushnir.cloud \
E2E_USER_PASSWORD=$(gcloud secrets versions access latest --secret="qa-user-password") \
npx playwright test tests/e2e/

# Expected results:
# - #986: 20+ OAuth tests PASS
# - #987: 30+ Portal tests PASS
# - #988: 25+ IDE tests PASS
# - #989: 20+ Session tests PASS
# - #990: 30+ Error handling tests PASS

# Total: 120+ end-to-end tests passing
```

**Time**: 45 minutes

---

## Production Deployment (After E2E Tests)

```bash
# All services already running on 192.168.168.31
# Just need to verify post-deployment

# 1. Verify all services health
bash scripts/verify-production-readiness-quick.sh

# 2. Run post-deployment smoke tests
bash scripts/ops/verify-e2e-qa-setup.sh --full

# 3. Monitor logs (10 min)
docker compose logs -f

# 4. Verify accessible from browser
# https://code-server.kushnir.cloud
# https://ide.kushnir.cloud  
# https://portal.kushnir.cloud
```

**Time**: 10 minutes

---

## Timeline Summary

| Activity | Duration | Blocker | Status |
|----------|----------|---------|--------|
| Domain registration (Phase 0) | 20 min | None | ⏳ **NEXT** |
| Issue #983 (QA user creation) | 15 min | Domain ↑ | ⏳ **NEXT** |
| Issue #984 (Credentials setup) | 45 min | #983 ↑ | ✅ Ready |
| E2E tests (#986-990) | 45 min | #984 ↑ | ✅ Ready |
| Production live | 10 min | E2E ↑ | ✅ Ready |
| **TOTAL** | **~135 min** | | |

---

## Key Files Reference

### Infrastructure & Automation
- **Automation scripts**: `scripts/ops/*.sh` (credential setup, verification)
- **Docker compose**: `docker-compose.yml` (all services running)
- **Prometheus**: `prometheus.yml` (all scrape jobs configured)
- **AlertManager**: `alert-rules.yml` (all alerts configured)
- **Grafana**: `config/grafana-*.json` (all dashboards provisioned)

### Domain Registration (Prerequisite for #983)
- **Guide**: `GOOGLE-WORKSPACE-DOMAIN-REGISTRATION-GUIDE.md` (20 min)
- **Script**: `scripts/register-google-workspace-domain.sh` (automated)
- **GoDaddy API**: Credentials in GSM (GODADDY_KEY, GODADDY_SECRET)

### Issue #983 (QA User Creation)
- **Guide**: `ISSUE-983-COMPLETE-GUIDE.md` (step-by-step)
- **Manual steps**: Create user in Google Workspace Admin
- **Timeline**: ~15 minutes

### Issue #984 (Credentials & Setup)
- **Guide**: `ISSUE-984-COMPLETION-GUIDE.md` (380 lines)
- **Scripts**: All autonomous
- **Timeline**: ~45 minutes

### E2E Tests (#986-990)
- **#986**: OAuth login (20+ tests) - `tests/e2e/oauth-login.spec.ts`
- **#987**: Portal features (30+ tests) - `tests/e2e/appsmith-portal.spec.ts`
- **#988**: IDE launch (25+ tests) - `tests/e2e/ide-launch.spec.ts`
- **#989**: Session persistence (20+ tests) - `tests/e2e/session-persistence.spec.ts`
- **#990**: Error handling (30+ tests) - `tests/e2e/error-handling.spec.ts`

---

## Current Sprint Status

**Completed This Sprint** (Past 4 hours):
- ✅ Issue #1011: Matrix observability (Prometheus, Grafana, Alerts)
- ✅ Issue #997: Session-broker graceful shutdown
- ✅ Issue #995: Redis Sentinel observability
- ✅ All E2E test suites ready (120+ tests)
- ✅ All production infrastructure ready
- ✅ Domain registration solution created (for #983 prerequisite)

**Remaining**:
- ⏳ Domain registration (Phase 0) - 20 min
- ⏳ Issue #983: QA user creation - 15 min
- ✅ Issue #984 ready (45 min autonomous)
- ✅ E2E tests ready (45 min automated)
- ✅ Production deployment ready (10 min)

**Blocked By**: Issue #983 (manual QA user creation)  
**Unblocks**: Issues #984-990 (entire E2E pipeline)

---

## Next Immediate Actions

1. **Start Issue #983 Domain Registration** (now):
   - Read: `GOOGLE-WORKSPACE-DOMAIN-REGISTRATION-GUIDE.md`
   - Execute: 4-phase registration process
   - Time: ~20 minutes
   - Then: Proceed to QA user creation

2. **Complete Issue #983** (after domain verified):
   - Read: `ISSUE-983-COMPLETE-GUIDE.md`
   - Create qa@kushnir.cloud user
   - Time: ~15 minutes
   - Then: Comment on #983 to unblock #984

3. **Trigger #984 Automation**:
   - Scripts ready to execute
   - No manual steps required
   - Time: ~45 minutes
   - Runs: Credential setup, CI/CD config, verification

4. **Run E2E Tests** (after #984):
   - All test specs ready (120+ tests)
   - Time: ~45 minutes
   - Validates entire auth → IDE pipeline

5. **Deploy to Production**:
   - Services already running
   - Just verify & activate
   - Time: ~10 minutes
   - Result: ✅ Production Live

---

**Summary**: Everything is ready. The critical path is blocked only on manual QA user creation (Issue #983), which requires its prerequisite domain registration (20 min) and then 15 minutes to create the user. After that, the entire pipeline is autonomous and takes ~100 minutes to complete.

**Estimated Total Time to Production Live**: ~175 minutes (~3 hours) from now
