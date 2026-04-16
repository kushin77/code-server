# P2 #419-430 Consolidation Sprint - Integrated Implementation Plan

**Status**: IN PROGRESS (April 15, 2026)  
**Scope**: 12 unassigned P2 consolidation items blocking production deployment  
**Effort**: 4-6 hours to complete all items  
**Owner**: Infrastructure Automation  

---

## CRITICAL PATH DEPENDENCY CHAIN

```
#419 (Alert Rules) ──┐
#420 (Caddy + ACME)  ├─→ #421 (Deploy Script) ──→ #422 (HA) ──→ PRODUCTION READY
#425 (Container) ─────┤
#429 (Observability) ─┤
#423 (CI Workflows) ──┘

#428 (Renovate) = parallel track
#430 (Kong)      = parallel track
```

---

## WORK ITEMS - PRIORITIZED

### 🔴 **BLOCKING - MUST COMPLETE FIRST**

#### P2 #421 - Eliminate 263-script sprawl → single idempotent deploy entrypoint
**Status**: NOT STARTED  
**Effort**: 1 hour  
**Critical**: YES - blocks all deployments

**Deliverables**:
1. `scripts/deploy-unified.sh` - SINGLE entry point for all deployment phases
   - Auto-detect environment (prod/on-prem/staging)
   - Load inventory from `inventory/infrastructure.yaml`
   - Execute phases sequentially or by selection
   - Full rollback support
   - Audit trail (who/when/what deployed)

2. `scripts/_deploy-phases/phase-1-init.sh` - Network + VM prep
3. `scripts/_deploy-phases/phase-2-infra.sh` - Docker, storage, networking
4. `scripts/_deploy-phases/phase-3-services.sh` - Core services (code-server, db, cache)
5. `scripts/_deploy-phases/phase-4-observability.sh` - Prometheus, Grafana, Loki, Jaeger
6. `scripts/_deploy-phases/phase-5-security.sh` - Vault, Falco, OPA, RBAC
7. `scripts/_deploy-phases/phase-6-ha.sh` - Patroni, Redis Sentinel, Keepalived
8. `scripts/_deploy-phases/phase-7-gateways.sh` - Kong, Caddy, oauth2-proxy

3. `scripts/rollback.sh` - Full production rollback
4. `docs/DEPLOYMENT-UNIFIED.md` - Operational manual

**Acceptance**:
- [ ] Single `./scripts/deploy-unified.sh` command deploys entire stack
- [ ] All 263 phase scripts consolidated into 7 phase modules
- [ ] Rollback tested on replica environment
- [ ] Audit logging captures all deployments
- [ ] Deployment takes 13-20 minutes (on-prem)

---

#### P2 #419 - Consolidate 9 alert rule files into SSOT with SLO burn rate
**Status**: NOT STARTED  
**Effort**: 45 minutes  
**Depends On**: None  

**Current State**:
- `alert-rules.yml` (legacy)
- `alert-rules-production-simple.yml`
- `alert-rules-telemetry.yml`
- `alert-rules-phase-6-slo-sli.yml`
- `alert-rules-gaps-374.yml`
- + 4 more scattered files

**Deliverables**:
1. `monitoring/alert-rules-master.yml` - SINGLE source of truth
   - P0 alerts: 15 items (production critical)
   - P1 alerts: 25 items (operational urgent)
   - P2 alerts: 35 items (quality metrics)
   - SLO burn rate rules (99.99% availability target)
   - Integrated with Prometheus recording rules

2. `monitoring/alert-rules-loader.sh` - Load and validate
3. Deprecate all 9 scatter files (move to `archive/`)

**Acceptance**:
- [ ] All 75+ alerts consolidated into single file
- [ ] SLO burn rate rules present (error rate, latency, availability)
- [ ] Prometheus validation passes (`promtool check rules`)
- [ ] AlertManager configured to use master file
- [ ] All 9 old files archived/deprecated

---

#### P2 #420 - Consolidate 6 Caddyfile variants + implement ACME DNS-01 TLS
**Status**: NOT STARTED  
**Effort**: 1 hour  
**Current Caddyfiles**:
- `config/caddy/Caddyfile` (production HTTPS)
- `config/caddy/Caddyfile.onprem` (on-prem HTTP)
- `config/caddy/Caddyfile.simple` (dev minimal)
- `config/caddy/Caddyfile.tpl` (template)
- + 2 more environment-specific

**Deliverables**:
1. `config/caddy/Caddyfile.tpl` - SINGLE template
   - Environment variables: CADDY_MODE (prod/onprem/dev)
   - Environment variables: APEX_DOMAIN, TLS_MODE (acme/internal/none)
   - Makefile: `make render-caddy ENV=prod` → generate variants
   - All 6 variants generated from template, NOT committed

2. `config/caddy/Caddyfile.acme` - ACME DNS-01 configuration
   - Route53, Cloudflare, GoDaddy DNS providers
   - Automatic cert renewal (90 days)
   - DNSSEC support

3. Makefile targets:
   ```makefile
   render-caddy ENV=prod              # Generate Caddyfile (HTTPS + ACME)
   render-caddy ENV=onprem            # Generate Caddyfile.onprem (HTTP only)
   render-caddy ENV=simple            # Generate Caddyfile.simple (dev)
   validate-caddy                     # Validate all Caddyfiles
   ```

**Acceptance**:
- [ ] Single Caddyfile.tpl template
- [ ] All 6 variants generated, not committed
- [ ] ACME DNS-01 configured for all providers
- [ ] Cert auto-renewal working
- [ ] `caddy validate` passes all variants

---

#### P2 #425 - Container hardening - network segmentation, security contexts, resource limits
**Status**: PARTIAL (resource limits done)  
**Effort**: 30 minutes  
**Depends On**: #421 (deploy script)

**Deliverables**:
1. Security contexts in docker-compose.yml
   - read_only root filesystem (where possible)
   - no_new_privs: true (drop CAP_SYS_ADMIN)
   - cap_drop: ["ALL"], cap_add: [minimal set per service]
   - user: non-root (1000:1000 for app services)

2. Network segmentation
   - code-server: on 'enterprise' network only
   - ollama: on 'enterprise' network (internal only)
   - databases: on 'database' network only (not internet-facing)
   - Prometheus: on 'monitoring' network only

3. Resource limits (updated from current)
   - code-server: 4GB / 2GB reserved
   - postgres: 2GB / 512MB reserved
   - redis: 1GB / 256MB reserved
   - prometheus: 512MB / 256MB reserved
   - grafana: 512MB / 256MB reserved

**Acceptance**:
- [ ] All services have security context
- [ ] No service runs as root
- [ ] Network segmentation enforced
- [ ] Resource limits validated
- [ ] Docker security scan passes

---

### 🟡 **HIGH PRIORITY - DO NEXT**

#### P2 #429 - Enterprise observability - blackbox exporter, runbooks, SLO dashboard, Loki retention
**Status**: PARTIAL (dashboards exist)  
**Effort**: 1 hour  
**Depends On**: #419 (alert rules)

**Deliverables**:
1. Blackbox exporter for external endpoint monitoring
   - HTTP checks for code-server, Ollama
   - TCP checks for postgres, redis
   - DNS checks for all domains
   - TLS cert expiry checks

2. Runbooks for top 20 alerts
   - P0 alerts: 5 runbooks (production critical)
   - P1 alerts: 10 runbooks (operational)
   - P2 alerts: 5 runbooks (quality)
   - Location: `docs/runbooks/<alert-name>.md`

3. SLO dashboard
   - Availability: 99.99% target
   - Latency: p99 < 100ms target
   - Error rate: < 0.1% target
   - Cache hit rate: > 75% target

4. Loki retention policy
   - Application logs: 90 days
   - Security logs: 1 year
   - Debug logs: 30 days

**Acceptance**:
- [ ] Blackbox exporter deployed and monitoring 10+ endpoints
- [ ] 20 runbooks created and linked to alerts
- [ ] SLO dashboard visible in Grafana
- [ ] Loki retention policies enforced

---

#### P2 #422 - Primary/replica HA - Patroni, Redis Sentinel, HAProxy VIP, Cloudflare health failover
**Status**: PARTIAL (Patroni config exists, not deployed)  
**Effort**: 1.5 hours  
**Depends On**: #421 (deploy script), #425 (container hardening)

**Deliverables**:
1. Patroni HA orchestration (PostgreSQL)
   - Primary: 192.168.168.31
   - Replica: 192.168.168.42
   - Automatic failover on primary failure
   - Replication lag monitoring

2. Redis Sentinel cluster (Redis HA)
   - Primary: 192.168.168.31:6379
   - Replica: 192.168.168.42:6379
   - 3-node Sentinel quorum
   - 30-second down detection

3. HAProxy / Keepalived VIP
   - VIP: 192.168.168.30 (Keepalived managed)
   - Automatic failover if primary down
   - Virtual IP floating between hosts

4. Cloudflare health checks
   - Primary endpoint health probe
   - Automatic DNS failover to replica on primary failure
   - Tested RTO: < 5 minutes

**Acceptance**:
- [ ] Patroni handles primary failover
- [ ] Redis Sentinel auto-promotes replica
- [ ] VIP fails over to replica in < 30 seconds
- [ ] Cloudflare DNS failover tested
- [ ] Data replication lag < 1 second

---

#### P2 #423 - Consolidate 34 CI workflows - eliminate duplicates, fix broken VPN/Harbor workflows
**Status**: NOT STARTED  
**Effort**: 1 hour  
**Location**: `.github/workflows/`

**Current State**: 34 workflows with high duplication

**Deliverables**:
1. `.github/workflows/pipeline-master.yml` - SINGLE CI entry point
   - Trigger: push to main/feature branches
   - Stages: lint → test → build → security → deploy
   - VPN detection and Harbor registry auth
   - Linux-only validation (no Windows references)

2. `.github/workflows/reusable-*.yml` - Reusable workflow modules
   - `reusable-lint.yml` (shellcheck, terraform validate, yamllint)
   - `reusable-test.yml` (unit + integration + chaos tests)
   - `reusable-build.yml` (Docker image build + push to GHCR)
   - `reusable-security.yml` (SAST scan, container scan, CVE check)
   - `reusable-deploy.yml` (staging/prod deployment)

3. Consolidate 34 workflows into 5 reusable modules
   - Delete: duplicate workflows
   - Archive: broken VPN/Harbor workflows to `archived/`

**Acceptance**:
- [ ] Single master pipeline
- [ ] All 5 reusable modules working
- [ ] No duplicate workflows
- [ ] VPN/Harbor auth working (if still needed)
- [ ] CI pipeline time: < 15 minutes

---

### 🟢 **PARALLEL TRACK**

#### P2 #428 - Enterprise Renovate - digest pinning, CVE auto-alerts as P0
**Status**: NOT STARTED  
**Effort**: 45 minutes

**Deliverables**:
1. `.renovaterc` configuration
   - Digest pinning for all images (sha256)
   - Auto-update patch/minor versions
   - CVE vulnerabilities → P0 issues automatically
   - Terraform module updates
   - GitHub Actions pin to specific commits

2. Vault integration for secrets rotation
   - Database passwords: 90-day rotation
   - API tokens: 30-day rotation
   - TLS certs: 90-day rotation

**Acceptance**:
- [ ] Renovate PR created for each update
- [ ] CVE detected and auto-filed as P0
- [ ] All images digests pinned
- [ ] Secrets rotated on schedule

---

#### P2 #430 - Kong hardening - consolidate kong-db, rate limiting, restrict Admin API
**Status**: NOT STARTED  
**Effort**: 30 minutes

**Deliverables**:
1. Kong database consolidation
   - kong-db service secured
   - Connection pooling configured
   - Replication to replica node

2. Rate limiting policies
   - Per-user: 1000 req/min
   - Per-IP: 10000 req/min
   - Burst: 100 req/sec

3. Admin API restrictions
   - Require API key authentication
   - RBAC: only infrastructure team access
   - TLS enforcement

**Acceptance**:
- [ ] Kong Admin API secured
- [ ] Rate limiting enforced
- [ ] Database replicated
- [ ] All policies tested

---

## EXECUTION ORDER

### Phase 1 (Now) - Consolidation Foundation
1. **#421** - Deploy script consolidation (1 hour) — **CRITICAL PATH**
2. **#419** - Alert rule consolidation (45 min)
3. **#420** - Caddyfile consolidation + ACME (1 hour)

### Phase 2 (After Phase 1) - Hardening & HA
4. **#425** - Container hardening (30 min)
5. **#422** - Primary/replica HA (1.5 hours)

### Phase 3 (Parallel) - Observability & Security
6. **#429** - Enterprise observability (1 hour)
7. **#423** - CI workflow consolidation (1 hour)
8. **#428** - Renovate hardening (45 min)
9. **#430** - Kong hardening (30 min)

### Total Effort: 6.5 hours for all 9 items

---

## QUALITY GATES (PRODUCTION-FIRST)

Before merging any consolidation work:

✅ **Immutability**: All config files in git, no manual steps  
✅ **Idempotency**: Deploy script safe to run multiple times  
✅ **Zero Duplication**: No overlapping logic or config  
✅ **No Breakage**: All existing deployments work  
✅ **Tested Rollback**: Rollback procedure documented and tested  
✅ **Documentation**: Runbooks for all operational procedures  
✅ **Audit Trail**: All deployments logged with who/when/what  
✅ **Security**: No hardcoded secrets, all in Vault  

---

## SUCCESS CRITERIA

- [ ] All 9 items consolidated and committed
- [ ] Single `./scripts/deploy-unified.sh` deploys entire stack (13-20 min)
- [ ] Production-ready deployment scripts (no manual steps)
- [ ] All deployments immutable and reversible (git history)
- [ ] Zero duplication across codebase
- [ ] 100% on-prem ready (Cloudflare, VIP failover, HA working)
- [ ] CI/CD pipeline fast and reliable (< 15 min)
- [ ] Enterprise observability complete (SLOs, runbooks, alerts)

---

**Next Action**: Start with P2 #421 (deploy script consolidation)
