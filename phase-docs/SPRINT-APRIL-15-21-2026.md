# Sprint Planning: April 15-21, 2026

**Sprint Goal**: Enable Phase 2 governance automation + Phase 23-A observability foundation
**Duration**: April 15-21 (one week)
**Parallel Tracks**: 3
**Owner**: @kushin77 (DevOps/Platform Lead)
**Status**: 🟢 PLANNING PHASE

---

## 📊 Sprint Overview

| Track | Title | Priority | Effort | Owner | Status |
|-------|-------|----------|--------|-------|--------|
| 1 | Phase 2 Branch Protection | P0 | 8h | @kushin77 | ⏳ NEXT |
| 2 | Dependabot Security CVEs | P0 | 6h | @kushin77 | ⏳ NEXT |
| 3 | Phase 23-A Observability | P1 | 12h | @kushin77 | ⏳ PLANNED |
| **TOTAL** | — | — | **~26 hours** | — | — |

---

## Track 1: Phase 2 Branch Protection Setup (8 hours)

**Objective**: Enable CI checks as required PR status checks + configure branch protection
**Timeline**: April 15-17 (Mon-Wed)
**Success Criteria**: All PRs passing validation before merge

### Task 1.1: Enable Required Status Checks (2 hours)

```bash
# Go to GitHub → Settings → Branches → main
# Configure branch protection rules:

✓ Require status checks to pass before merging
  ├─ validate-config (must pass)
  ├─ docker-compose syntax
  ├─ terraform plan
  ├─ shell script lint
  ├─ secrets scan
  └─ configuration validation

✓ Dismiss stale pull request approvals when new commits pushed
✓ Require code review approval (minimum 1)
✓ Require branches to be up to date before merging
```

**Acceptance**: GitHub shows "This branch is protected by rules" on main

### Task 1.2: Test with Sample PR (3 hours)

Create test PR to verify validation pipeline:

```bash
# Create test branch
git checkout -b test/governance-enforcement

# Make deliberate changes to test validation:
# - Intentionally break docker-compose syntax
# - Introduce hardcoded secret
# - Add obsolete phase-specific file

# Create PR → watch CI run validation
# Verify:
#   ✓ PR status shows "validation failed"
#   ✓ Merge button disabled
#   ✓ Users see detailed error messages
```

**Deliverable**: Screenshot showing failed validation + error details

### Task 1.3: Document CI Feedback Loop (2 hours)

**Create**: `.github/VALIDATION-GUIDE.md`

```markdown
# CI Validation Guide (Phase 2)

## What Gets Validated

### 1. Configuration Files
- docker-compose.yml: syntax validation (docker-compose config)
- Caddyfile: caddy syntax check
- terraform: terraform validate + plan
- alertmanager: yamllint + amtool verify

### 2. Secrets Detection
- Hardcoded credentials (regex: PASSWORD=, API_KEY=, etc)
- AWS keys, GitHub tokens, private keys
- `.env` file contents
- Run: `trufflehog` + custom patterns

### 3. Script Validation
- Bash: shellcheck -x (all shell scripts)
- PowerShell: PSAnalyzer (OPTIONAL)
- Python: pylint, pyflakes

### 4. Composition Validation
- Verify docker-compose.base.yml composes with all variants
- Check .env.* files are sourced correctly
- Validate terraform module references

## How to Fix Validation Failures

[Detailed troubleshooting guide for each check]
```

---

## Track 2: Dependabot Security CVEs (6 hours)

**Objective**: Address 5 vulnerabilities (2 high, 3 moderate) identified by Dependabot
**Timeline**: April 15-19 (Mon-Fri, parallelizable)
**Success Criteria**: Dependabot shows "0 vulnerabilities"

### Current Vulnerabilities (from GitHub alerts)

Need to investigate specific CVEs from:
```
https://github.com/kushin77/code-server/security/dependabot
```

### Task 2.1: Audit Dependencies (2 hours)

```bash
# Run vulnerability scanner locally
npm audit  # if Node.js project
pip check  # if Python project
terraform init && terraform providers lock  # if Terraform

# Document each CVE:
# - CVE ID
# - Affected package/version
# - Severity (high/moderate)
# - Required version
# - Breaking changes?
```

### Task 2.2: Update Vulnerable Packages (3 hours)

```bash
# Create feature branch
git checkout -b fix/dependabot-cves-20260414

# Update dependencies
npm update vulnerable-package@latest  # if available
pip install --upgrade vulnerable-package  # if available
# Or manually edit package.json/requirements.txt

# Test locally
npm test  # or equivalent
```

### Task 2.3: Testing & Merge (1 hour)

```bash
# Run full test suite before merge
npm test
# OR
pytest tests/

# Verify no regressions
# Create PR → get review → merge
```

**Deliverable**: PR with all CVEs addressed + passing tests

---

## Track 3: Phase 23-A Observability Foundation (12 hours)

**Objective**: Deploy OpenTelemetry + Jaeger distributed tracing infrastructure
**Timeline**: April 15-18 (Mon-Thu)
**Success Criteria**: Jaeger UI shows traces from code-server, caddy, ollama

### Task 3.1: OTel Collector Deployment (3 hours)

```bash
# 1. Create docker container for OTel Collector
docker run -d \
  --name otel-collector \
  --restart unless-stopped \
  --network code-server-enterprise_enterprise \
  -p 4317:4317  # gRPC receiver
  -p 4318:4318  # HTTP receiver
  -p 14250:14250 # Jaeger gRPC receiver (export)
  -v /home/akushnir/code-server-enterprise/otel-config.yml:/etc/otel/config.yml \
  otel/opentelemetry-collector-contrib:0.88.0

# 2. Verify health
curl http://localhost:13133/healthz
```

**Config needed**: `/home/akushnir/code-server-enterprise/otel-config.yml`

### Task 3.2: Jaeger Backend Deployment (3 hours)

```bash
# Deploy Jaeger all-in-one (for dev/staging)
docker run -d \
  --name jaeger \
  --restart unless-stopped \
  --network code-server-enterprise_enterprise \
  -p 16686:16686  # Jaeger UI
  -p 14268:14268  # Collector HTTP
  -p 14250:14250  # Collector gRPC
  -e COLLECTOR_OTLP_ENABLED=true \
  jaegertracing/all-in-one:latest

# Verify UI accessible
curl -s http://localhost:16686 | head -c 200
```

**Deliverable**: Jaeger UI running on http://192.168.168.31:16686

### Task 3.3: Application Instrumentation (4 hours)

Add OpenTelemetry SDKs to each service:

**For code-server (if Node.js-based)**:
- Install: `npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node`
- Configure in startup
- Verify traces appear in Jaeger

**For ollama (Python-based if applicable)**:
- Install: `pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-jaeger`
- Add instrumentation to FastAPI app
- Verify traces appear

**For caddy (native instrumentation)**:
- Caddy has built-in OpenTelemetry support
- Enable in Caddyfile: `admin localhost:2019`
- Configure OTLP exporter

**Deliverable**: First traces visible in Jaeger UI showing request lifecycle

---

## Daily Schedule (April 15-21)

### Monday, April 15
- **09:00-11:00** (2h): Track 1.1 - Enable branch protection (GitHub UI setup)
- **11:00-13:00** (2h): Track 3.1 - Deploy OTel Collector
- **14:00-16:00** (2h): Track 2.1 - Audit dependencies
- **16:00-17:00** (1h): Daily standup + checkpoint

### Tuesday, April 16
- **09:00-12:00** (3h): Track 1.2 - Test PR validation
- **12:00-14:00** (2h): Track  3.2 - Deploy Jaeger
- **14:00-16:00** (2h): Track 2.2 - Update vulnerable packages (parallel)
- **16:00-17:00** (1h): Standup

### Wednesday, April 17
- **09:00-11:00** (2h): Track 1.3 - Document validation guide
- **11:00-15:00** (4h): Track 3.3 - Instrument applications
- **15:00-16:00** (1h): Track 2.3 - Test & merge CVE fixes
- **16:00-17:00** (1h): Standup + review results

### Thursday, April 18
- **09:00-12:00** (3h): Track 3.3 continued - Complete traces
- **12:00-14:00** (2h): Verify all deliverables
- **14:00-16:00** (2h): Documentation + final testing
- **16:00-17:00** (1h): Sprint wrap-up

### Friday, April 19
- **09:00-11:00** (2h): Final verification + testing
- **11:00-12:00** (1h): Prepare Phase 3 governance kickoff (Apr 21)
- **12:00-14:00** (2h): Buffer for issues + cleanup
- **14:00-17:00**: Sprint review + retrospective

---

## Deliverables by Track

### Track 1: Phase 2 Branch Protection
- ✅ GitHub branch protection enabled
- ✅ Sample PR tested + documented
- ✅ `.github/VALIDATION-GUIDE.md` (user-facing documentation)
- ✅ All developers aware of validation requirements

### Track 2: Dependabot CVEs
- ✅ All 5 vulnerabilities identified + categorized
- ✅ Dependency updates tested locally
- ✅ PR created + reviewed + merged
- ✅ Dependabot shows 0 vulnerabilities

### Track 3: Phase 23-A Foundation
- ✅ OTel Collector running (port 4317, 4318 responding)
- ✅ Jaeger running (UI accessible at :16686)
- ✅ Applications instrumented with traces
- ✅ Sample trace visible Jaeger UI (request → response → ollama)

---

## Success Metrics (April 21 EOD)

| Metric | Target | Status |
|--------|--------|--------|
| **Phase 2**: Branch protection enabled | YES | ⏳ |
| **Phase 2**: 100% test PRs pass validation | 100% | ⏳ |
| **Phase 2**: Developers trained | 100% | ⏳ |
| **Phase 2**: GOVERNANCE-VALIDATION-GUIDE published | YES | ⏳ |
| **CVEs**: Dependabot vulnerabilities | 0 | ⏳ |
| **CVEs**: All tests passing | 100% | ⏳ |
| **Phase 23-A**: OTel Collector healthy | YES | ⏳ |
| **Phase 23-A**: Jaeger UI accessible | YES | ⏳ |
| **Phase 23-A**: Traces visible (>10 samples) | YES | ⏳ |
| **Phase 23-A**: Code-server instrumented | YES | ⏳ |

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Dependabot CVEs have breaking changes | Medium | High | Test thoroughly, use canary branch |
| OTel SDK breaks code-server startup | Medium | High | Use separate feature branch, rollback ready |
| Branch protection blocks legitimate code | Low | Medium | Test with sample PR first, gradual enforcement |
| Jaeger traces too verbose | Low | Low | Configure sampling ratio (10%) |

---

## Next Phase (Apr 21-28): Phase 3 Governance Rollout

After this sprint completes:
- **Apr 21-28**: Team training + soft launch (warnings only)
- **Apr 25-May 2**: Hard enforcement (blocks on critical failures)
- **May 2+**: Full governance + monitoring

---

## Checkpoints

- **Monday EOD (Apr 15)**: Track 1 & 2 & 3 setup complete
- **Wednesday EOD (Apr 17)**: Track 1 complete, Track 2 testing, Track 3 instrumentation
- **Friday EOD (Apr 21)**: All 3 tracks complete + sprint retrospective

---

**Sprint Status**: 🟢 READY TO START (April 15, 0900 UTC)
**Owner**: @kushin77
**Tracking**: GitHub Projects / Milestones
**Next Update**: April 15 EOD stance
