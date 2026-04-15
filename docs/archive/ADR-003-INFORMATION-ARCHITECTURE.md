# ADR-003: Five-Level Information Architecture & Root Zero-Sprawl Policy

**Status**: ACCEPTED  
**Date**: April 16, 2026  
**Author**: Architecture Team  
**Category**: Information Architecture, Governance  
**Related Issues**: #376 (full structure refactor), #380 (governance framework)

---

## Problem Statement

The kushin77/code-server repository has severe structural sprawl:
- **~280 markdown files in root** (docs, plans, reports, guides, ADRs, runbooks mixed together)
- **~157 scripts at root or directly under `/scripts`** (phases, operations, deploys, maintenance mixed)
- **Multiple similarly-named files** with unclear canonical source (deployment-log vs DEPLOYMENT-LOG, status vs STATUS)
- **No consistent depth policy** - some docs are root-level, others 3 levels deep with no rationale

**Impact**:
- Search/grep noise - 280 root files = hard to find canonical docs
- Navigation confusion - contributors unsure where to place new files
- Merge friction - every doc addition debates folder placement
- Weak governance - no policy = no CI enforcement possible
- Production readiness - looks unprofessional and unmaintained

---

## Context & Constraints

### Current Baseline
```
code-server/
├── ~280 .md files (mixed types: ADRs, reports, plans, guides, runbooks)
├── scripts/
│   ├── ~157 scripts total
│   ├── Many Phase-X files (phase-1.sh, phase-2.sh, phase-6-deployment.sh)
│   ├── Operations (backup.sh, restore.sh, failover.sh)
│   ├── Utilities (_common/, health/, vpc/)
│   └── Mixed naming (dash-separated, underscores, inconsistent)
├── terraform/
│   ├── ~20 .tf files (phases, modules, main)
│   └── Minimal organization (Phase-specific naming)
├── docker-compose files
│   ├── Caddyfile
│   ├── Caddyfile.onprem
│   ├── Caddyfile.simple
│   ├── docker-compose.yml
│   ├── docker-compose.git-proxy.yml
│   └── (and variants)
└── Dockerfile variants
    ├── Dockerfile
    ├── Dockerfile.caddy
    ├── Dockerfile.code-server
    └── (and more)
```

### Constraints
1. **Cannot break references** - All relative paths (in scripts, configs) must remain valid or use redirects
2. **Preserve git history** - Refactoring should not rewrite history (can use git-mv)
3. **Backwards compatibility** - Entry points (make, terraform, docker-compose) remain at root
4. **Production consistency** - New files created TODAY must follow policy (can defer refactor of legacy files)

---

## Decision: Five-Level Mandatory Depth Policy

### Canonical Folder Taxonomy

#### 1. Documentation (5-level depth)
```
docs/
├── architecture/          # ADRs, design documents, diagrams
│   ├── adr-001-cloudflare-tunnel.md
│   ├── adr-002-configuration-composition.md
│   └── diagrams/          # Mermaid, PlantUML, etc
├── guides/                # User guides, tutorials, onboarding
│   ├── getting-started.md
│   ├── development/       # Dev setup guides
│   ├── operations/        # Ops runbooks
│   └── infrastructure/    # Infrastructure guides
├── runbooks/              # Incident response playbooks (5 levels)
│   ├── backup-failure.md
│   ├── database/
│   │   ├── replication-lag.md
│   │   └── failover.md
│   └── application/
│       ├── crash-loop.md
│       └── memory-leak.md
├── api/                   # API documentation
│   ├── endpoints.md
│   ├── authentication.md
│   └── rate-limiting.md
├── deployment/            # Deployment & release notes
│   ├── release-notes/
│   ├── change-log.md
│   └── deployment-guide.md
└── compliance/            # Security & compliance docs
    ├── security-policy.md
    ├── secrets-management.md
    └── audit-logging.md
```

**Root-level doc allowlist** (< 10 files max):
- `README.md` - Project overview
- `CONTRIBUTING.md` - Contribution guide
- `LICENSE` - License file
- `SECURITY.md` - Security disclosure (CVE policy)
- `GOVERNANCE.md` - Governance framework reference
- (max 5 more strategic docs)

#### 2. Scripts (5-level depth)
```
scripts/
├── _common/               # Shared utilities (no depth limit)
│   ├── config.sh
│   ├── logging.sh
│   └── retry.sh
├── entrypoints/           # Primary execution entry points (root level OK)
│   ├── deploy.sh          # Main deploy script
│   ├── health-check.sh    # Health monitoring
│   ├── backup.sh          # Backup entry point
│   └── restore.sh         # Restore entry point
├── deploy/                # Deployment phases (3-level depth)
│   ├── phase-1/           # Phase 1 deployment
│   │   ├── security-hardening.sh
│   │   ├── credential-rotation.sh
│   │   └── ci-validation.sh
│   ├── phase-2/           # Phase 2 deployment
│   │   ├── governance-setup.sh
│   │   └── policy-enforcement.sh
│   └── ... (phases 3-N)
├── operations/            # Operational tasks (3-level depth)
│   ├── backup/
│   │   ├── full-backup.sh
│   │   ├── incremental-backup.sh
│   │   └── verify-backup.sh
│   ├── failover/
│   │   ├── trigger-failover.sh
│   │   ├── verify-failover.sh
│   │   └── rollback-failover.sh
│   └── maintenance/
│       ├── cleanup.sh
│       ├── gc.sh
│       └── optimize.sh
├── testing/               # Test & validation scripts (3-level depth)
│   ├── unit-tests.sh
│   ├── integration/
│   │   ├── test-endpoints.sh
│   │   └── test-vpn.sh
│   └── load-testing/
│       └── locust-runner.sh
├── infrastructure/        # Infrastructure & IaC scripts (3-level depth)
│   ├── vpc/
│   ├── dns/
│   └── monitoring/
└── utilities/             # Utility scripts (2-level depth)
    ├── format-logs.sh
    ├── generate-report.sh
    └── cleanup.sh
```

**Root-level script allowlist** (< 5 files max):
- `Makefile` or `makefile.sh` - Make/shell entry point
- Main bootstrap script (if needed)

#### 3. Infrastructure Code (5-level depth)
```
terraform/
├── modules/               # Reusable modules (2-level depth)
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/
│   ├── database/
│   └── monitoring/
├── environments/          # Environment-specific configs (3-level depth)
│   ├── production/
│   │   ├── main.tf
│   │   ├── terraform.tfvars
│   │   └── variables.tf
│   ├── staging/
│   └── development/
├── phases/                # Phase-based deployment (3-level depth)
│   ├── phase-1/
│   │   ├── security.tf
│   │   └── ci.tf
│   ├── phase-2/
│   │   ├── governance.tf
│   │   └── policy.tf
│   └── ... (phases 3-N)
└── shared/                # Shared config (2-level depth)
    ├── variables.tf
    ├── providers.tf
    └── outputs.tf
```

#### 4. Configuration & Templates (Minimal root sprawl)
```
config/                    # All config files in depth
├── caddy/
│   ├── Caddyfile.tpl      # Template
│   ├── Caddyfile.prod     # Production (generated)
│   └── Caddyfile.onprem   # On-prem (generated)
├── docker-compose/
│   ├── docker-compose.tpl  # Template
│   ├── docker-compose.prod # Production
│   └── extensions/         # Service extensions
├── environment/
│   ├── .env.example        # Template (no real values)
│   ├── .env.production     # (gitignored, deployment-only)
│   └── secrets-template.yml
└── monitoring/
    ├── prometheus/
    ├── grafana/
    └── alertmanager/
```

**Root-level config allowlist** (< 5 files):
- `docker-compose.yml` or `docker-compose.tpl` (production entry point)
- `.env.example` (template only, no real values)
- `Caddyfile` or `Caddyfile.tpl` (production entry point)
- `terraform.tf` or `main.tf` (entry point)

#### 5. Testing & Quality (3-level depth)
```
tests/
├── unit/
│   ├── governance/
│   ├── health-checks/
│   └── security/
├── integration/
│   ├── vpn-endpoint-scan/
│   ├── api-contracts/
│   └── database/
├── load-testing/
│   ├── locust/
│   └── k6/
└── fixtures/
    ├── mock-data.json
    └── test-configs/
```

---

## Governance & Enforcement

### Phase 1: Soft Enforcement (This week, April 16-22)
- ✅ Taxonomy approved and documented
- ⚠️ CI warns on new files placed in root (advisory messages only)
- ✅ Contributors educated via PR comments
- ✅ Contribution guide updated with examples

### Phase 2: Hard Enforcement (Week of April 23)
- 🔴 CI blocks merge if new `.md` files placed in root (except allowlist)
- 🔴 CI blocks new script at `/scripts/` root (must go into subdir)
- 🔴 CI blocks terraform `.tf` files at root (must use `/terraform/`)
- ✅ Exceptions/waivers require architecture approval + issue justification

### Phase 3: Structure Refactoring (Weeks 7-9, after #380 enforcement proven)
- Move existing root `.md` files to `/docs/` (with git-mv to preserve history)
- Reorganize `/scripts/` using git-mv
- Create redirects for any relative paths that break
- Update all references (in scripts, CI, documentation)

---

## CI Enforcement Rules

### NEW files created after April 16:
```yaml
# .github/workflows/information-architecture-gate.yml
- Markdown files (.md):
  - ALLOWED root: README.md, CONTRIBUTING.md, LICENSE, SECURITY.md
  - DEFAULT: must go in /docs or subdir
  - BLOCKED: root root-level docs (FAIL)

- Scripts (.sh):
  - ALLOWED root: entrypoints/ only (deploy.sh, health-check.sh, backup.sh, restore.sh)
  - DEFAULT: must go in /scripts/deploy/, /scripts/ops/, /scripts/test/, etc
  - BLOCKED: root-level .sh files (FAIL)

- Terraform (.tf):
  - ALLOWED root: terraform.tf only (entry point)
  - DEFAULT: must go in /terraform/ directory tree
  - BLOCKED: root-level .tf files (FAIL)

- Configuration:
  - ALLOWED root: Caddyfile.tpl, docker-compose.tpl, .env.example
  - DEFAULT: variants go in /config/ subdir
  - BLOCKED: variants at root (FAIL)
```

### LEGACY files (before April 16):
- Do not enforce during Phase 1/2 (advisory only)
- Refactored in Phase 3 with audit trail preserved

---

## Related Decisions

### ADR-001: Cloudflare Tunnel Architecture
- Files: `/docs/architecture/adr-001-cloudflare-tunnel.md` ✅

### ADR-002: Configuration Composition Pattern
- Files: `/docs/architecture/adr-002-configuration-composition.md` ✅

### ADR-003: Information Architecture (THIS DECISION)
- Policy: `/GOVERNANCE.md` section on structure
- Enforcement: `.github/workflows/information-architecture-gate.yml`
- Phase refactor: Issue #376 (Weeks 7-9)

---

## Consequences

### Positive
- ✅ New contributors understand folder policy immediately
- ✅ CI enforces consistency without subjective debate
- ✅ Search/grep much cleaner (280 root files → < 10)
- ✅ Governance compliance traceable in CI logs
- ✅ Repository looks professional and well-maintained
- ✅ Link rot reduced (consistent depth = predictable URLs)

### Negative
- ⚠️ Phase 3 refactor is multi-week project (3 weeks estimated)
- ⚠️ Relative path breakage risk (mitigated by git-mv + testing)
- ⚠️ Contributor friction during transition (phase 2 grace period helps)

### Risks & Mitigations
| Risk | Mitigation |
|------|-----------|
| **Phase 3 refactor breaks script entry points** | Use git-mv only; update Makefile/terraform entry points; test on staging |
| **CI gate too strict (false positives)** | Phase 1 is warnings-only; tune thresholds based on feedback; allow waivers |
| **Contributors resist new structure** | Educate early (Phase 1); document rationale in runbook; celebrate wins |
| **Relative paths break** | Build link-checking CI gate; create redirect/symlink map; document migration guide |

---

## Decision Rationale

This 5-level depth policy balances:
1. **Discoverability** - Every file type has a clear home (no "where do I put this?" confusion)
2. **Governance** - CI can enforce without human judgment
3. **Backwards compatibility** - Entry points remain at root; can defer legacy refactoring
4. **Production readiness** - Professional structure signals maturity; required for scaled teams

---

## Approval Checklist

- [x] Architecture team reviewed
- [ ] Security team reviewed  
- [ ] DevOps team reviewed
- [ ] Governance team (issue #380) reviewed
- [ ] Epic #375 (Elite Program) updated

---

## References

- **Issue #376**: Enforce 5-level production information architecture
- **Issue #375**: Elite Enterprise Environment Program (epic)
- **Issue #380**: Unified code governance framework
- **Related**: #373 (Caddyfile consolidation), #382 (script organization)

---

**Next Steps**:
1. Phase 1: Soft enforcement + education (April 16-22)
2. Phase 2: Hard enforcement in CI (April 23+)
3. Phase 3: Structure refactoring (Weeks 7-9)
4. Issue #382: Canonical script organization (post-Phase 3)
