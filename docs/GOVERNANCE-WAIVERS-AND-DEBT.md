# Code Governance Waivers & Debt Tracking

**Document Purpose**: Audit trail for all approved governance waivers and active governance debt.  
**Last Updated**: April 15, 2026  
**Owner**: Architecture Team  

---

## ACTIVE WAIVERS

### Waiver #001: Phase-Based Script Legacy Support

| Field | Value |
|-------|-------|
| **Standard Violated** | Script naming convention (phase-based vs. canonical) |
| **Issue** | Deprecation period for 150+ legacy phase-*.sh scripts still in active use |
| **Why** | Cannot migrate all scripts simultaneously; operators need gradual transition |
| **Duration** | 90 days from April 15, 2026 → **Expires July 15, 2026** |
| **Risk** | Continued operational ambiguity; duplicate capability implementations |
| **Owner** | @devops-team |
| **Approval** | Architecture team, Security team |
| **Conditions** | - Must have explicit deprecation header on each legacy script<br/>- Must have canonical replacement script created<br/>- Runbooks updated to point to canonical scripts<br/>- Removal date clearly documented |
| **Status** | ACTIVE |

---

## GOVERNANCE DEBT BACKLOG

### Debt #001: Hardcoded IPs in Phase-7 Scripts

| Field | Value |
|-------|-------|
| **Standard** | No hardcoded IP addresses (use `${PROD_HOST}` from env.sh) |
| **Affected Files** | scripts/deploy-phase-7*.sh (4 files) |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Makes deployment scripts brittle; hard to manage multi-host scenarios |
| **Target Fix Date** | May 15, 2026 |
| **Owner** | @devops-team |
| **Estimated Effort** | 2 hours |
| **Status** | OPEN |
| **Waiver** | Covered under Waiver #001 (phase-based deprecation period) |
| **Remediation Path** | Extract to parameterized canonical script under scripts/deploy/ |

### Debt #002: Duplicate Logging Implementations

| Field | Value |
|-------|-------|
| **Standard** | Use `_common/logging.sh` for all log output (no `echo` or `printf` directly) |
| **Affected Files** | 8 scripts with inline log functions |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Inconsistent log format; makes centralized aggregation harder |
| **Target Fix Date** | May 30, 2026 |
| **Owner** | @devops-team |
| **Estimated Effort** | 3 hours |
| **Status** | OPEN |
| **Waiver** | None (should be fixed before next release) |
| **Remediation Path** | Replace all inline log functions with `log_info`, `log_error`, `log_warn` calls |

### Debt #003: Multiple Docker Compose Variants

| Field | Value |
|-------|-------|
| **Standard** | Single source of truth for service definitions (docker-compose.tpl renders into variants) |
| **Affected Files** | docker-compose.yml, docker-compose.git-proxy.yml, docker-compose.ssh-proxy.yml, Dockerfile.* (5 variants) |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Maintenance burden; difficult to track which version is production |
| **Target Fix Date** | June 30, 2026 |
| **Owner** | @devops-team, @infrastructure |
| **Estimated Effort** | 8 hours |
| **Status** | OPEN |
| **Waiver** | None |
| **Remediation Path** | Consolidate to docker-compose.tpl with environment-based overrides |

### Debt #004: Caddyfile Variants (4 Copies)

| Field | Value |
|-------|-------|
| **Standard** | Single parameterized template → rendered variants |
| **Affected Files** | Caddyfile, Caddyfile.onprem, Caddyfile.simple, Caddyfile.tpl |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Configuration drift; changes must be manually applied to all variants |
| **Target Fix Date** | June 15, 2026 |
| **Owner** | @devops-team |
| **Estimated Effort** | 4 hours |
| **Status** | OPEN |
| **Waiver** | None |
| **Remediation Path** | Use only Caddyfile.tpl; enforce `make render-config` before commit |

### Debt #005: Missing Alert Coverage

| Field | Value |
|-------|-------|
| **Standard** | All critical operational modes must have alerts (#374) |
| **Affected Areas** | Backup failures, SSL cert expiry, container restarts, replication lag, disk space, Ollama GPU |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Silent failures; incidents discovered reactively |
| **Target Fix Date** | May 1, 2026 |
| **Owner** | @observability-team |
| **Estimated Effort** | 4 hours |
| **Status** | IN PROGRESS (Issue #374) |
| **Waiver** | None |
| **Remediation Path** | Add Prometheus alert rules via #374 |

### Debt #006: No End-to-End Traceability

| Field | Value |
|-------|-------|
| **Standard** | All requests correlated by trace ID from edge (Cloudflare) to container |
| **Affected Scope** | Entire request/response pipeline |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Slow incident debugging (> 30 min MTTR) |
| **Target Fix Date** | July 1, 2026 |
| **Owner** | @observability-team |
| **Estimated Effort** | 30 hours (major feature) |
| **Status** | OPEN (Issue #377) |
| **Waiver** | None |
| **Remediation Path** | Implement Cloudflare trace header propagation + Jaeger integration |

### Debt #007: Repository Root Sprawl

| Field | Value |
|-------|-------|
| **Standard** | Max 10 markdown files in root; all docs in docs/ hierarchy |
| **Current State** | ~280 markdown files in root |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Contributor confusion; weak governance |
| **Target Fix Date** | September 1, 2026 |
| **Owner** | @architecture-team |
| **Estimated Effort** | 16 hours (mass migration) |
| **Status** | OPEN (Issue #376) |
| **Waiver** | None |
| **Remediation Path** | Organize into docs/ hierarchy; enforce with CI checks |

### Debt #008: Script Sprawl (157 at Root)

| Field | Value |
|-------|-------|
| **Standard** | Max 20 canonical scripts at scripts/ root; deprecated in archive/ |
| **Current State** | ~157 scripts at root of scripts/ |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Execution ambiguity; operator doesn't know which script to run |
| **Target Fix Date** | August 1, 2026 |
| **Owner** | @devops-team |
| **Estimated Effort** | 12 hours |
| **Status** | OPEN (Issue #382) |
| **Waiver** | Covered under Waiver #001 (phase-based deprecation) |
| **Remediation Path** | Consolidate into canonical scripts; move deprecated to archive/ |

### Debt #009: Duplicate Issue Tracks

| Field | Value |
|-------|-------|
| **Standard** | One canonical GitHub issue per workstream |
| **Examples** | GOV-010 in both #308 and #339; GOV-011 in #307 and #341 |
| **Date Discovered** | April 15, 2026 |
| **Impact** | Split execution; conflicting acceptance criteria |
| **Target Fix Date** | May 15, 2026 |
| **Owner** | @scrum-master |
| **Estimated Effort** | 3 hours |
| **Status** | OPEN (Issue #379) |
| **Waiver** | None |
| **Remediation Path** | Merge duplicates; close superseded issues with canonical cross-link |

---

## METRICS & TRENDS

### Governance Compliance Trend
```
Week Ending | Violations | Waivers | Debt Items | Trend
------------|-----------|---------|------------|-------
Apr 8       | N/A       | N/A     | N/A        | Baseline
Apr 15      | 15        | 1       | 9          | ↑ (Framework activated)
Apr 22      | TBD       | -       | TBD        | Tracking...
May 1       | TBD       | -       | TBD        | Tracking...
```

### Remediation SLA

| Priority | Target | Status |
|----------|--------|--------|
| **P0** (Blocking) | Resolved within 48 hours | N/A (none open) |
| **P1** (High) | Resolved within 2 weeks | Tracking |
| **P2** (Medium) | Resolved within 4 weeks | Debt #005, #006 |
| **P3** (Low) | Resolved within 8 weeks | Debt #007, #008 |

---

## APPROVED WAIVERS (ARCHIVED)

*This section will accumulate as waivers expire and are archived.*

---

## GLOSSARY

| Term | Meaning |
|------|---------|
| **Waiver** | Approved exception to a governance standard with time-limited duration and conditions |
| **Governance Debt** | Known violation of a governance standard with documented remediation path |
| **Silent Failure** | Issue that doesn't fail CI/tests but violates operational best practice |
| **Drift** | Deviation from canonical source of truth (e.g., manual changes without updating template) |
| **Remediation SLA** | Target time to fix a governance violation from discovery date |

---

**Document Owner**: Architecture Team  
**Last Reviewed**: April 15, 2026  
**Next Review**: April 29, 2026 (biweekly)
