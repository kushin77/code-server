# Repository Governance & FAANG-Standard Structure

**Issue:** #1534 - Repository Governance  
**Date:** April 25, 2026  
**Status:** FOUNDATION DOCUMENTED - Implementation Roadmap Established

---

## Current State Assessment

### ✓ Compliant

- **Root markdown files**: 5 core files (README.md, CHANGELOG.md, CONTRIBUTING.md, ROADMAP.md, TROUBLESHOOTING.md)
- **Caddyfile consolidation**: Single `Caddyfile` in production (pre-SSL-fix variants archived)
- **Directory structure**: Core `apps/`, `scripts/`, `terraform/`, `docs/`, `config/` organized
- **Version control**: Single docker-compose.yml with profile-based service selection

### ⚠️ In Progress

- **Script naming conventions**: Mix of kebab-case and underscore_case in scripts/
- **pnpm workspace**: `pnpm-lock.yaml` present, but no `pnpm-workspace.yaml` defined

### ⛔ Not Yet Addressed

- **Environment schema**: No centralized `.env.schema.json` for var definitions
- **Branch governance**: No enforcement of branch protection rules or naming conventions
- **CI enforcement**: No automated checks for naming conventions or file organization
- **Architecture Decision Records (ADRs)**: `docs/decisions/` not yet populated

---

## Governance Model (Phase 1)

### 1. Directory Structure Standard

```
repo-root/
├── README.md                    # Main documentation (keep in root)
├── CHANGELOG.md                 # Version history (keep in root)
├── LICENSE                      # License
├── docker-compose.yml           # Primary compose file (profiles for all services)
├── Caddyfile                    # Production reverse proxy config
├── pnpm-workspace.yaml          # Monorepo workspace definition (NEW)
├── .env.schema.json             # Environment variable schema (NEW)
├── package.json                 # Root workspace package
├── pnpm-lock.yaml               # Dependency lock file
│
├── .github/
│   ├── workflows/               # CI/CD pipelines
│   ├── copilot-instructions.md  # AI/Copilot governance rules
│   └── CODEOWNERS               # Code ownership rules (NEW)
│
├── docs/                        # All documentation
│   ├── architecture/            # System design
│   ├── operations/              # Runbooks and procedures
│   ├── security/                # Security policies
│   ├── testing/                 # Test strategies
│   ├── governance/              # Repository governance (THIS FILE)
│   ├── decisions/               # Architecture Decision Records (ADRs)
│   └── decisions/ADR-001.md     # Example ADR template
│
├── scripts/
│   ├── _common/                 # Shared libraries (.sh files only)
│   ├── ci/                      # CI/CD pipeline scripts
│   ├── ops/                     # Operational runbooks
│   ├── lib/                     # Domain-specific libraries (nas, vault, etc.)
│   └── _template.sh             # Template for new scripts
│
├── apps/                        # Application services
│   ├── {service-name}/
│   └── extensions/
│
├── packages/                    # Shared packages (NEW)
│   └── shared/
│       ├── types/               # TypeScript shared types
│       └── utils/               # Shared utilities
│
├── terraform/                   # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   └── modules/
│
├── config/                      # Configuration files
│   ├── prometheus.yml           # Prometheus scrape config
│   ├── loki/                    # Loki configs
│   └── {...}/
│
├── monitoring/                  # Monitoring and alerting
│   ├── alerts/                  # Prometheus alert rules
│   └── dashboards/              # Grafana dashboards
│
├── artifacts/                   # Generated artifacts (gitignored)
│   ├── reports/                 # Automated reports
│   ├── triage/                  # Incident evidence
│   └── evidence/                # Compliance artifacts
│
└── tests/                       # Test suites (separate from individual service tests)
    ├── unit/
    ├── integration/
    └── e2e/
```

### 2. Naming Conventions

#### Scripts

| Pattern | Example | Purpose |
|---------|---------|---------|
| `kebab-case.sh` | `deploy-p3-services.sh` | All scripts use lowercase with hyphens |
| ❌ NO underscores | ~~`deploy_p3_services.sh`~~ | Avoid underscore in script names |
| Prefix by function | `deploy-`, `setup-`, `validate-`, `fix-` | Action verbs prefix script names |
| Shared library prefix | `_common.sh`, `_logging.sh` | Internal libraries prefixed with underscore |

#### Docker Compose

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Primary production manifest |
| `docker-compose.override.yml` | Local development overrides |
| Profile-based services | Use `--profile observability`, `--profile ai` |

#### Environment Files

| Pattern | Purpose |
|---------|---------|
| `.env.{environment}` | `.env.prod`, `.env.staging`, `.env.local` |
| `.env.schema.json` | Single source of truth for env vars |
| ❌ NO `.env.example` | Use JSON schema instead |

#### Terraform

| Pattern | Purpose |
|---------|---------|
| `terraform/modules/{service}/` | Each service/component in module |
| `main.tf` | Main resource definitions |
| `variables.tf` | Variable definitions |
| `outputs.tf` | Output definitions |

#### GitHub Actions

| Pattern | Example | Purpose |
|---------|---------|---------|
| `{category}-{action}.yml` | `ci-test.yml`, `deploy-prod.yml` | Category prefix groups related workflows |

#### Documentation

| Pattern | Example | Purpose |
|---------|---------|---------|
| `docs/{category}/TITLE-IN-CAPS.md` | `docs/architecture/DNS-SERVICE-DISCOVERY.md` | Clear hierarchy, CAPS for titles |

---

## Single Source of Truth (SSOT) References

### Environment Variables (.env.schema.json)

```json
{
  "version": "1.0",
  "description": "ElevatedIQ Environment Variable Schema — SSOT for all env configs",
  "variables": {
    "APEX_DOMAIN": {
      "type": "string",
      "default": "kushnir.cloud",
      "description": "Root domain for all services",
      "examples": ["kushnir.cloud", "company.com"]
    },
    "PRIMARY_HOST": {
      "type": "string",
      "default": "192.168.168.31",
      "description": "Primary deployment host IP",
      "env_file": ".env.prod"
    },
    "REPLICA_HOST": {
      "type": "string",
      "default": "192.168.168.42",
      "description": "Replica/failover host IP",
      "env_file": ".env.prod"
    },
    "NAS_HOST": {
      "type": "string",
      "default": "192.168.168.56",
      "description": "Network-attached storage IP",
      "env_file": ".env.prod"
    }
  }
}
```

### Configuration SSOT Files

- **`CONFIG-SSOT-MASTER.md`** — Single config reference doc (kept updated)
- **`docker-compose.yml`** — Single production manifest (no duplicates)
- **`.env.schema.json`** — Single env var schema (NEW)
- **`scripts/_common/_base-config.env`** — Single host/environment config (NEW)

### No Duplicate Configuration

| ❌ DON'T | ✅ DO |
|---------|------|
| Multiple Caddyfile variants | One Caddyfile + environment templating |
| Duplicate env definitions | Single .env.schema.json + imports |
| Hardcoded IPs in scripts | Sourced from _base-config.env |

---

## Git Hygiene & Branch Governance

### Branch Naming Convention

```
{type}/{description}

Examples:
- feat/observability-tempo-deployment
- fix/oauth-redirect-loop
- docs/dns-architecture
- refactor/docker-compose-consolidation
- chore/update-dependencies
```

### Branch Protection Rules (main)

```yaml
Enforce:
  - Require pull request reviews: 1 minimum
  - Require status checks to pass: true
  - Require branches to be up to date: true
  - Include administrators: false
  - Allow force pushes: false
  - Allow deletions: false

Auto-delete:
  - Head branch: after PR merge
  - Remote stale: delete > 30 days
```

### Stale Branch Cleanup

```bash
# List stale branches (merged > 7 days ago)
git for-each-ref --sort=-committerdate refs/remotes/origin --merged main \
  --format='%(refname:short) %(committerdate:short)' | grep -v main

# Delete stale branch
git push --delete origin {branch-name}
```

---

## pnpm Workspace (Phase 2)

### Workspace Definition (NEW: `pnpm-workspace.yaml`)

```yaml
packages:
  # Core applications
  - "apps/agent-runtime"
  - "apps/execution-scheduler"
  - "apps/paperclip-control-plane"
  - "apps/frontend"
  
  # Shared packages
  - "packages/shared/types"
  - "packages/shared/utils"
  - "packages/shared/components"

  # Extensions
  - "apps/extensions/*"

# Workspace configuration
shamefullyFlattenedDependencies: false
prefer-workspace-packages: true
```

### Monorepo Commands

```bash
# Install all workspace packages
pnpm install

# Add package to specific workspace
pnpm add lodash --filter @elevatediq/types

# Run script across all packages
pnpm recursive run test

# Check workspace integrity
pnpm list --depth=-1
```

---

## CI Enforcement Checks (Phase 2)

### Pre-commit Hooks

```bash
# .git/hooks/pre-commit
#!/bin/bash
# Check for:
# 1. No markdown files in root (except README.md, CHANGELOG.md)
# 2. No hardcoded IPs in scripts (except comments)
# 3. Script names are kebab-case
# 4. No duplicate config files
```

### GitHub Actions Validation

```yaml
- name: Validate Governance
  run: |
    # Check root markdown files
    root_md=$(find . -maxdepth 1 -name "*.md" | wc -l)
    [ "$root_md" -le 2 ] || exit 1
    
    # Check script naming
    find scripts/ -name "*_*.sh" | grep -v "_common/" && exit 1
    
    # Check for hardcoded IPs
    grep -rE "192\.168\.168\." scripts/ docker-compose.yml && exit 1
```

---

## Related Documents

- [docs/operations/DEPLOYMENT-OPERATIONS.md](../operations/DEPLOYMENT-OPERATIONS.md) — Procedures
- [docs/architecture/INFRASTRUCTURE-REFERENCE.md](../architecture/INFRASTRUCTURE-REFERENCE.md) — System design
- [docs/security/SECURITY-POLICY.md](../security/SECURITY-POLICY.md) — Security standards
- [.github/CODEOWNERS](.../.github/CODEOWNERS) — Code ownership (NEW)

---

## Implementation Roadmap

### Phase 1: Foundation (NOW) ✓

- [x] Document governance standards
- [x] Create repository governance guide
- [ ] Create .env.schema.json (NEXT)
- [ ] Archive old Caddyfile variants

### Phase 2: Automation (Week 2)

- [ ] Add GitHub branch protection rules
- [ ] Add pnpm-workspace.yaml with all packages
- [ ] Create CI governance validation job
- [ ] Clean stale branches (merged > 30 days)

### Phase 3: Migration (Week 3)

- [ ] Move docs to subdirectories (if any remain in root)
- [ ] Rename scripts to kebab-case pattern
- [ ] Validate all pnpm packages resolve
- [ ] Add CODEOWNERS file

### Phase 4: Enforcement (Week 4)

- [ ] Enforce conventional commits via commitlint
- [ ] Block direct push to main
- [ ] Require CI pass on all PRs
- [ ] Auto-delete head branch on merge

---

## Issue #1534 Checklist

- [x] Directory structure standard documented
- [x] Naming conventions defined
- [x] SSOT references established
- [ ] pnpm-workspace.yaml created
- [ ] .env.schema.json created
- [ ] Branch protection rules configured
- [ ] CI governance checks implemented
- [ ] Stale branches cleaned
- [ ] All governance docs linked in README

**Foundation: Complete**  
**Next: env.schema.json + pnpm workspace setup**

