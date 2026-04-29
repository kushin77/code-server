# Lessons Learned & Enhancement Recommendations
**Enterprise Overlay Deployment Initiative — April 29, 2026**

---

## Executive Summary

This session identified and closed a 3-service deployment gap (Appsmith, testing-service, control-plane) and iteratively debugged healthcheck failures across two Docker hosts. The work revealed systemic gaps in deployment automation, healthcheck definitions, and operational documentation. This document captures lessons and proposes concrete enhancements.

**Key Statistics:**
- Services deployed: 9 enterprise + 39 Terraform-managed = 48 total
- Hosts verified: 2 (primary 192.168.168.31, replica 192.168.168.42)
- Issues debugged: 7 major (Vault protocol mismatch, Nexus timeout, image tag drift, etc.)
- Time to resolution: iterative across 3 commits (9ad55b8d being latest)
- Cross-host consistency: confirmed after all fixes applied

---

## Part 1: Lessons Learned

### 1. Healthcheck Probes Must Be Image-Aware
**Problem:** Vault healthcheck used `curl` which wasn't installed in the image; failed silently with exit code 1.
**Root Cause:** Assumed all base images include curl; didn't validate before writing healthcheck CMD.
**Impact:** Service marked unhealthy even though container was fully running.
**Learning:** Healthcheck definitions are fragile contracts with image contents. 

### 2. Protocol Mismatches Are Silent Failures
**Problem:** Vault healthcheck attempted HTTPS when container runs HTTP-only dev mode; timeouts silently reported as "unhealthy."
**Root Cause:** No validation that `VAULT_ADDR` matched actual container configuration.
**Impact:** Second-level debugging required; confused "container broken" with "probe broken."
**Learning:** Protocol choices in healthchecks (curl, redis-cli, vault status) imply specific runtime configs.

### 3. Startup Timing Assumptions Are App-Specific
**Problem:** Nexus (Java) took 60+ seconds to start; generic `start_period: 30s` caused restart loops.
**Root Cause:** Assumed all services start at similar speeds; didn't profile startup by app type.
**Impact:** Artifact repository continuously restarted, blocking orchestration.
**Learning:** Java, Node.js (complex), and Python services have vastly different startup curves; one-size-fits-all timeouts fail.

### 4. Image Tag Specificity Is Critical for Reproducibility
**Problem:** `vault:latest` pulled successfully in development but no longer exists on Docker Hub; compose would silently fail during redeploy.
**Root Cause:** Floating tags used in production code.
**Impact:** Deployment reproducibility broken; silent failures on new hosts.
**Learning:** Every image reference must include explicit version; no `latest` or floating tags in infrastructure code.

### 5. Container Ownership Conflicts Require Explicit Cleanup
**Problem:** Stale containers from prior runs (hashed names) conflicted with new compose project ownership.
**Root Cause:** Docker-compose doesn't evict pre-existing containers; assumes clean slate.
**Impact:** Compose fails with port conflicts or orphaned references.
**Learning:** Idempotent deployments require explicit container cleanup, not assumed parity.

### 6. Cross-Host Consistency Cannot Be Assumed
**Problem:** Primary and replica hosts diverged in container state after initial deploy.
**Root Cause:** Replicated by manual SSH commands without built-in consistency checks.
**Impact:** Discovered post-deployment; required re-running all fixes on both hosts.
**Learning:** Symmetric deployments need automated parity verification, not manual replication.

### 7. Service Dependencies Are Implicit in Networking
**Problem:** Testing-service, control-plane, multimodal-ai depend on postgres/vault/minio but no explicit `depends_on` in compose.
**Root Cause:** Services live on external `services` network; dependencies resolved by hostname lookup.
**Impact:** Startup order issues if dependencies boot after dependents; race conditions possible.
**Learning:** External network deployments need documented dependency graphs and maybe activation gates.

### 8. Build Reproducibility Requires Source in Repo
**Problem:** testing-service, multimodal-ai, edge-agent had to be built on deployment hosts; no centralized registry.
**Root Cause:** Custom images never pushed to registry; Dockerfiles/source only in repo.
**Impact:** Each host must re-build; no layer caching across hosts; slow deployments.
**Learning:** Custom images should be pre-built and pushed to registry; on-host builds are for dev only.

---

## Part 2: Recommended Enhancements (Priority Order)

### Priority 1: Critical for Production Stability

#### 1.1 Healthcheck Definition Framework & Documentation
**Objective:** Eliminate silent healthcheck failures by documenting proven patterns per service type.

**Deliverables:**
- [docs/operations/HEALTHCHECK-PATTERNS.md](docs/operations/HEALTHCHECK-PATTERNS.md) — reference guide
  - Java services (Nexus, GitLab): `start_period: 90s`, `interval: 30s`, `timeout: 10s`, use application-native probes
  - Python services (FastAPI): `start_period: 40s`, HTTP `/health` endpoint, bundled curl
  - Go services: binary healthchecks, no external tools needed
  - Node.js: Depends on framework; FastAPI equivalent for most; 50s startup grace
  - Each pattern includes: rationale, example compose snippet, troubleshooting checklist

**Effort:** 4 hours (research + documentation)
**Owner:** DevOps/Platform team
**Success Metric:** All new services use patterns from this guide; zero healthcheck regressions in next 2 deployments

---

#### 1.2 Image Tag Versioning Policy & Validation
**Objective:** Enforce explicit version pins; prevent `latest` or floating tags in production.

**Deliverables:**
- Pre-commit hook: `scripts/git-hooks/validate-image-versions.sh`
  - Scans docker-compose*.yml for tags matching `[A-Za-z0-9_-]+:(?!.*\d)` (flagging non-numeric tags)
  - Blocks commits with floating tags; suggests explicit versions
  - Exception whitelist for images where version is dynamic (e.g., local build tags)

- Config file: `.dockertagpolicy`
  - Defines allowlist (hashicorp/vault:1.13.0 ✓, vault:latest ✗)
  - Auto-suggests next stable version for flagged images

**Effort:** 6 hours (hook logic + integration testing)
**Owner:** DevOps/Platform team
**Success Metric:** All commits rejected until tags are versioned; no image reference drift

---

#### 1.3 Idempotent Deployment Script
**Objective:** Safe, reproducible multi-host deployment with built-in cleanup and consistency checks.

**Deliverables:**
- Script: `scripts/deploy-enterprise-idempotent.sh`
  ```bash
  ./scripts/deploy-enterprise-idempotent.sh --target=primary --mode=dry-run
  ./scripts/deploy-enterprise-idempotent.sh --target=both --mode=apply
  ```
  - Steps:
    1. Validate environment (SSH access, docker-compose binary, .env files)
    2. Fetch current container state (names, tags, health)
    3. Explicit cleanup: `docker rm -f [stale containers]`
    4. Render docker-compose with current env vars (validation gate)
    5. Bring services up with compose (`docker-compose up -d`)
    6. Wait-for-health loop (5 min timeout per service)
    7. Post-deploy validation (all services running, no restart loops)
    8. Diff report: what changed, what stayed same

- Integration: callable from Terraform via `local-exec` or standalone
- Dry-run mode: shows exactly what would happen without executing

**Effort:** 12 hours (bash scripting + error handling + testing on both hosts)
**Owner:** DevOps/Platform team
**Success Metric:** Deployment time < 5 min per host; zero race conditions or stale container issues

---

### Priority 2: Operational Visibility & Automation

#### 2.1 Cross-Host Consistency Verification
**Objective:** Automated parity checks to catch divergence early.

**Deliverables:**
- Script: `scripts/verify-cross-host-consistency.sh`
  - Runs on both hosts via SSH; collects:
    - Service count, names, image tags, health states
    - Memory/CPU limits, exposed ports, env var fingerprints
  - Compares and reports differences
  - Can be scheduled as cron job or part of CI/CD pipeline

- Example output:
  ```
  PRIMARY (192.168.168.31):   9 services, vault:healthy, artifact:starting
  REPLICA (192.168.168.42):   9 services, vault:healthy, artifact:starting
  ✓ Service counts match
  ✓ Image tags identical
  ✓ Health states synchronized
  ```

- Non-match example:
  ```
  PRIMARY: code-server-testing:Up (healthy)
  REPLICA: code-server-testing:MISSING
  ✗ Action: Re-run deployment on replica
  ```

**Effort:** 5 hours (SSH collection + diff logic)
**Owner:** DevOps/Platform team
**Success Metric:** Scheduled daily; alerts on any divergence

---

#### 2.2 Healthcheck Event Streaming & Observability
**Objective:** Centralized logs of healthcheck probe results (not just final state).

**Deliverables:**
- Log shipper (Promtail/Filebeat) or Docker daemon event handler
  - Stream `docker inspect` health state changes to Loki/ELK
  - Query example: `{service="code-server-vault"} | "health"`
  - Alert on repeated failures, sudden transitions

- Alternative simpler approach: cron job that polls `docker inspect` and logs to syslog
  ```bash
  # Every 2 min: docker inspect all services, append state + timestamp to /var/log/docker-health.log
  */2 * * * * docker inspect $(docker ps -q) --format '{{.Name}}\t{{json .State.Health}}' >> /var/log/docker-health.log
  ```

**Effort:** 8 hours (shipper config + alerting rules) or 3 hours (cron + syslog)
**Owner:** Observability/SRE team
**Success Metric:** Real-time visibility into health probe failures; can replay last 7 days of events

---

### Priority 3: Deployment Process Improvements

#### 3.1 Staged Rollout Procedure
**Objective:** Reduce blast radius by deploying to canary → replica → primary with health gates.

**Deliverables:**
- Procedure: `docs/operations/STAGED-ROLLOUT-PROCEDURE.md`
  - Stage 0 (Dry-run): `terraform plan -target=canary` on development host
  - Stage 1 (Canary): Deploy to secondary host (non-critical); wait 5 min for stability
  - Stage 2 (Replica): Deploy to replica if canary stable; cross-host consistency check
  - Stage 3 (Primary): Deploy to primary only after replica healthy
  - Each stage has health gates (all services must be healthy before proceeding)
  - Rollback procedure if any stage fails

- Manual workflow (can be automated later):
  ```bash
  ./scripts/stage-rollout.sh stage=canary
  # Manual approval + 5 min observation
  ./scripts/stage-rollout.sh stage=replica
  # Manual approval + consistency check
  ./scripts/stage-rollout.sh stage=primary
  ```

**Effort:** 8 hours (procedure doc + script + testing)
**Owner:** DevOps/Platform team
**Success Metric:** First deploy using staged rollout completes without manual debugging; zero incidents on primary

---

#### 3.2 Service Dependency Map & Validation
**Objective:** Document implicit dependencies; validate startup order.

**Deliverables:**
- Diagram: `docs/architecture/SERVICE-DEPENDENCY-MAP.md`
  - ASCII or Mermaid diagram showing:
    - PostgreSQL ← code-server-postgres (data tier)
    - Vault ← code-server-vault (secrets tier)
    - Redis ← code-server-redis (cache tier)
    - Services depending on each (via `POSTGRES_HOST`, `VAULT_ADDR`, etc.)
  - Lists hard requirements vs soft recommendations

- Validation script: `scripts/validate-service-dependencies.sh`
  - Parses docker-compose.enterprise.yml
  - Checks that all referenced services (via env vars, hostnames) are defined
  - Alerts on missing dependencies
  - Suggests `depends_on` additions (advisory; external network still works without them)

**Effort:** 5 hours (diagram + validation script)
**Owner:** Architecture/Platform team
**Success Metric:** Clear understanding of startup order; no race conditions on new deployments

---

### Priority 4: Image Management & CI/CD

#### 4.1 Docker Image Registry Strategy
**Objective:** Centralized registry for all custom images; automated builds on repo commit.

**Deliverables:**
- Registry setup (choose one):
  - Option A: Harbor (self-hosted, full-featured)
  - Option B: GitLab Container Registry (free if already using GitLab)
  - Option C: AWS ECR (if cloud-native)

- CI/CD pipeline: `.github/workflows/build-and-push-images.yml` (GitHub) or `.gitlab-ci.yml`
  - Trigger: on push to `main` branch
  - Build matrix: code-server-testing, code-server-control-plane, code-server-multimodal-ai, code-server-activity-feed, code-server-edge-agent, code-server-reputation-engine
  - Tag scheme: `registry.example.com/code-server/testing:latest` + `testing:v1.0.0` + `testing:sha-abc123`
  - Push to registry
  - Update docker-compose.enterprise.yml to reference registry images (not local builds)

- Result: On-host builds eliminated; images pulled from registry; consistent across all environments

**Effort:** 12 hours (registry setup + CI/CD pipeline + testing)
**Owner:** DevOps/Platform team
**Success Metric:** Images available in registry 2 min after commit; no local builds required on deployment hosts

---

#### 4.2 Automated Image Tag Updates
**Objective:** Keep base images (Python, Node, Go) updated; alert on critical CVEs.

**Deliverables:**
- Dependabot/Renovate config: `.github/dependabot.yml`
  - Auto-PRs for base image updates (python:3.11-slim → python:3.12-slim)
  - Review & merge gate; re-build images on update
  - Security alerts for CVEs in dependencies

- Manual alternative: Weekly cron job to check for base image updates
  ```bash
  # Weekly: scan for new python:3.11-slim, notify if available
  ```

**Effort:** 4 hours (config + testing)
**Owner:** Security/Platform team
**Success Metric:** Images updated within 1 week of base image release; zero critical CVEs in deployed images

---

### Priority 5: Documentation & Runbooks

#### 5.1 Enterprise Overlay Operational Runbook
**Objective:** Comprehensive guide for deploying, troubleshooting, and maintaining all 9 services.

**Deliverables:**
- Document: `docs/operations/ENTERPRISE-OVERLAY-RUNBOOK.md` — 50+ page runbook including:

  **Sections:**
  1. Prerequisites (env setup, secrets in GSM, SSH keys, docker-compose binary)
  2. Pre-deployment checklist (network connectivity, available disk, .env files)
  3. Deployment procedure (step-by-step with validation gates)
  4. Service-specific configuration (ports, env vars, healthchecks)
  5. Health verification (curl tests, compose ps output interpretation)
  6. Troubleshooting matrix:
     - Symptom: "code-server-vault reports unhealthy"
       - Root causes: protocol mismatch, timeout, VAULT_ADDR env var not set
       - Debugging commands: `docker inspect`, `docker logs`, `vault status` inside container
       - Fixes: see healthcheck patterns, restart with corrected env
     - Symptom: "code-server-artifact-repo keeps restarting"
       - Root causes: insufficient memory, port conflict, Nexus startup timeout
       - Fixes: increase `memory_limit`, verify ports, extend `start_period`
     - [15+ more scenarios based on this session's debugging]
  7. Rollback procedures (docker-compose down, restore previous compose file, restart)
  8. Monitoring & alerting (healthcheck integration, metrics endpoints, log aggregation)
  9. Capacity planning (resource requirements per service, scaling considerations)
  10. Security checklist (env var redaction, secret rotation, network isolation)

- Success criteria: New engineer can deploy without escalation by following this runbook

**Effort:** 20 hours (writing + internal review + validation on fresh deployment)
**Owner:** Platform/SRE team + architecture review
**Success Metric:** Used successfully by new team member; zero steps skipped

---

## Part 3: Implementation Roadmap

### Phase 1 (Week 1): Critical Stability
1. **Priority 1.1** - Healthcheck patterns doc (4h)
2. **Priority 1.2** - Image tag validation pre-commit hook (6h)
3. **Priority 1.3** - Idempotent deployment script (12h)

**Total:** 22 hours (roughly 3 days for 1 person or 1.5 days for 2 people)
**Blocker:** None; can proceed in parallel
**Validation:** Run idempotent script on both hosts; verify no regressions

### Phase 2 (Week 2): Visibility & Consistency
4. **Priority 2.1** - Cross-host consistency verification (5h)
5. **Priority 2.2** - Healthcheck event streaming (3-8h depending on approach)
6. **Priority 3.1** - Staged rollout procedure (8h)

**Total:** 16-21 hours (2 days for team of 2)
**Blocker:** Phase 1 should complete first
**Validation:** Schedule consistency checks as cron; test staged rollout on non-critical environment

### Phase 3 (Week 3): Registry & Automation
7. **Priority 3.2** - Service dependency mapping (5h)
8. **Priority 4.1** - Docker image registry & CI/CD (12h)
9. **Priority 4.2** - Dependabot automation (4h)

**Total:** 21 hours (3 days for team of 2)
**Blocker:** Phase 1 should complete first; registry should be chosen early
**Validation:** All custom images built and pushed; deployment uses registry references

### Phase 4 (Week 4): Documentation
10. **Priority 5.1** - Comprehensive operational runbook (20h)

**Total:** 20 hours (2.5-3 days with internal review)
**Blocker:** Phases 1-3 should be complete so runbook reflects implemented tools
**Validation:** Test runbook with new team member; measure deployment time reduction

---

## Part 4: Success Metrics & Verification

### Key Performance Indicators (KPIs)
1. **Deployment Time**: < 5 minutes per host (current: ~15-20 min with debugging)
2. **Healthcheck False-Positives**: 0 (current: 2 per session)
3. **Cross-Host Divergence Incidents**: 0 (current: 1 per session)
4. **Image Rebuild Time**: Eliminated via registry (current: 3-5 min per host)
5. **Mean Time to Resolution (MTTR)**: < 5 min for standard issues (current: 20-30 min)
6. **Deployment Confidence**: New engineer can deploy without escalation (current: requires expert)

### Measurement Plan
- **Before Enhancements (Baseline):**
  - Log next 3 deployments: time, debugging steps, issues encountered
  - Calculate average values

- **After Enhancements (6 weeks):**
  - Run same 3 deployment scenarios using new tools/procedures
  - Compare metrics against baseline
  - Target: 50% reduction in deployment time, 100% reduction in healthcheck issues

---

## Part 5: Open Questions & Future Work

1. **Image Registry Choice**: Harbor vs GitLab Registry vs ECR? (needs architecture decision)
2. **Healthcheck Centralization**: Should we implement Prometheus healthcheck exporter instead of log streaming? (higher visibility but more complex)
3. **Multi-Datacenter**: How do we apply these patterns across 3+ environments? (staging, canary, prod)
4. **Secrets Management**: Current env files work, but should we use AWS Secrets Manager / Google Secret Manager? (out of scope for this iteration)
5. **Horizontal Scaling**: If we need 5+ replicas, how does staged rollout change? (defer to future)

---

## Appendix A: Commit History (This Session)

```
9ad55b8d - Refine enterprise healthchecks for stable convergence
8146d3da - Fix vault healthcheck: HTTP protocol + system curl dependency
dc8a4648 - Stabilize enterprise compose: versioned images, build directives, memory caps
55983c02 - Deploy 3 missing enterprise services (appsmith, testing-service, control-plane)
```

---

## Appendix B: Reference Implementation Examples

### Example: Healthcheck Patterns (from docker-compose.enterprise.yml)
```yaml
# ✓ CORRECT: Java service (Nexus) - extended startup grace
code-server-artifact-repo:
  image: sonatype/nexus3:3.60.0
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8081/service/rest/v1/status"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 90s  # ← Java needs ~60s startup

# ✓ CORRECT: Python service (FastAPI) - built-in health endpoint
code-server-testing:
  image: code-server-testing:latest
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8888/health"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 40s  # ← FastAPI needs ~30s startup

# ✓ CORRECT: Vault - native CLI probe, HTTP override
code-server-vault:
  image: hashicorp/vault:1.13.0
  healthcheck:
    test: ["CMD", "sh", "-c", "VAULT_ADDR=http://127.0.0.1:8200 vault status"]
    interval: 30s
    timeout: 10s
    retries: 3
    start_period: 30s

# ✗ WRONG: Floating tag (reproducibility broken)
code-server-gitlab:
  image: gitlab/gitlab-ce:latest  # NO!

# ✓ CORRECT: Explicit version
code-server-gitlab:
  image: gitlab/gitlab-ce:16.7.1
```

### Example: Pre-Commit Hook Snippet
```bash
#!/bin/bash
# scripts/git-hooks/validate-image-versions.sh

if git diff --cached --name-only | grep -q 'docker-compose.*\.yml'; then
  if git diff --cached | grep -E '^\+.*image:.*:(latest|master|main|develop)' ; then
    echo "❌ ERROR: Floating image tags not allowed in production compose files"
    echo "   Use explicit versions: image: service:1.2.3"
    exit 1
  fi
fi
exit 0
```

---

## Appendix C: Recommended Reading

- Docker Healthcheck Best Practices: https://docs.docker.com/engine/reference/builder/#healthcheck
- Docker Compose Version Support: https://docs.docker.com/compose/compose-file/
- Java Application Startup Profiling: https://spring.io/guides/gs/spring-boot-docker/
- Kubernetes Probes (inspiration for healthcheck patterns): https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

---

**Document Version:** 1.0  
**Last Updated:** April 29, 2026  
**Reviewed By:** [Platform Team]  
**Next Review:** May 13, 2026  
