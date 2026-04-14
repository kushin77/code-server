# File Organization & Placement Guide

**Quick Reference for Where Files Belong**

Use this guide to determine the correct location for files when adding new code/configs/docs.

---

## Quick Index

**Question**: I'm adding a...

- ✏️ **Documentation**: See [Documentation Files](#documentation-files)
- 📘 **Architecture Decision**: See [ADRs](#architecture-decision-records)
- 🔧 **Operational Runbook**: See [Runbooks](#runbooks--procedures)
- 🐳 **Docker Configuration**: See [Docker & Compose](#docker--container-configs)
- 📦 **Terraform IaC**: See [Terraform Infrastructure](#terraform-infrastructure)
- 🛠️ **Script or Tool**: See [Scripts](#scripts)
- ⚙️ **Configuration Parameter**: See [Configuration Files](#configuration-files)
- 🧪 **Test**: See [Tests](#tests)
- 🔐 **Secret or Credential**: See [Secrets & Sensitive Data](#secrets--sensitive-data)

---

## Documentation Files

### Location Rule
All documentation goes in `docs/` directory. **NEVER** in root.

| Content Type | Location | Example |
|---|---|---|
| **Guides & Tutorials** | `docs/guides/` | `docs/guides/DEPLOYMENT.md` |
| **Architecture Decisions** | `docs/adc/` | `docs/adc/ADR-001-CLOUDFLARE-TUNNEL.md` |
| **Operational Runbooks** | `docs/runbooks/` | `docs/runbooks/DEPLOYMENT-RUNBOOK.md` |
| **Troubleshooting** | `docs/guides/TROUBLESHOOTING.md` | Common issues and fixes |
| **Development Setup** | `docs/guides/LOCAL-DEVELOPMENT.md` | Dev environment setup |
| **Historical/Archived** | `docs/archived/` or `archived/docs/` | Old status reports, phase summaries |
| **API Documentation** | `docs/api/` | API specs, OpenAPI files |
| **Security** | `docs/security/` | Security policies, audit trails |

### Header Template

```markdown
# [Document Title]

**Purpose**: One-sentence description
**Audience**: Who is this for? (developers, ops, everyone)
**Last Updated**: YYYY-MM-DD
**Author**: @username
**Status**: ACTIVE | DRAFT | DEPRECATED
**Related**: [Link to related docs](../path/to/doc.md)

## Table of Contents
<!-- For docs > 100 lines -->

[Content...]
```

### When to Create vs. Update

- ✅ **Create new doc** when adding a new feature/process
- ✅ **Update existing** when info changes
- ❌ **Don't** create status update documents (these go to archived/ after useful life)
- ❌ **Don't** keep variant versions (DEPLOYMENT-V1.md, DEPLOYMENT-V2.md)

---

## Architecture Decision Records

### Location
`docs/adc/ADR-###-TITLE.md`

### Template

```markdown
# ADR-###: [Decision Title]

**Date**: YYYY-MM-DD
**Status**: PROPOSED | APPROVED | IMPLEMENTED | SUPERSEDED
**Deciders**: @person1, @person2

## Context
What question did we need to answer? What are the constraints?

## Decision
What did we decide? (1-2 sentences)

## Rationale
Why this choice? What are the trade-offs?

## Consequences
Results: positive and negative

## Alternatives Considered
- Option A: Why rejected
- Option B: Why rejected

## References
- Related PR: #123
- Related Issues: #456, #789
- Supersedes: ADR-001 (if applicable)
```

### Examples

- `ADR-001-CLOUDFLARE-TUNNEL-ARCHITECTURE.md` - Cloud access strategy
- `ADR-002-POSTGRES-HA-STRATEGY.md` - Database high availability
- `ADR-003-CONTAINER-ORCHESTRATION.md` - Docker vs. Kubernetes decision

---

## Runbooks & Procedures

### Location
`docs/runbooks/[CATEGORY]/PROCEDURE-NAME.md`

### Examples
- `docs/runbooks/deployment/DEPLOYMENT-RUNBOOK.md`
- `docs/runbooks/incident-response/INCIDENT-RESPONSE.md`
- `docs/runbooks/maintenance/BACKUP-RESTORE.md`

### Template

```markdown
# Runbook: [Procedure Name]

**Severity**: CRITICAL | HIGH | MEDIUM | LOW
**Owner**: @person
**Estimated Time**: X minutes
**Requires Approvals**: Yes | No
**Last Tested**: YYYY-MM-DD

## Prerequisites
- [ ] Requirement 1
- [ ] Requirement 2

## Steps
1. First step
   ```bash
   command
   ```
   Expected: Output text

2. Second step

## Verification
How to confirm success

## Rollback
If it fails, how to revert

## Troubleshooting
- **If X happens**: Do Y
- **If Z happens**: Do W
```

---

## Docker & Container Configs

### Location Structure

```
docker/
├── docker-compose.yml          # Base definition
├── docker-compose.override.yml # Dev overrides (auto-loaded)
├── docker-compose.prod.yml     # Prod overrides (explicit: -f flag)
├── images/
│   ├── code-server/
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   └── README.md
│   ├── caddy/
│   ├── ssh-proxy/
│   └── monitoring/
├── configs/
│   ├── code-server/
│   │   └── code-server-config.yaml
│   ├── caddy/
│   │   ├── Caddyfile
│   │   └── Caddyfile.prod  # Production overrides
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert-rules.yml
│   ├── alertmanager/
│   │   └── alertmanager.yml
│   └── grafana/
│       └── grafana-datasources.yml
└── volumes/
    └── README.md
```

### Rules

| Item | Rule |
|------|------|
| **Dockerfiles** | One per image, in `docker/images/[service]/Dockerfile` |
| **Entrypoints** | In same dir as Dockerfile: `entrypoint.sh` |
| **Configuration Files** | Service-specific in `docker/configs/[service]/` |
| **Compose Files** | Base + overrides only (no phase-numbered variants) |
| **.env files** | `.env.example` as template, never commit `.env` with secrets |

### Adding a New Service

1. **Create image directory**: `docker/images/my-service/`
2. **Add Dockerfile**: `docker/images/my-service/Dockerfile`
3. **Add config** (if needed): `docker/configs/my-service/config.yaml`
4. **Update compose**: Add service to `docker/docker-compose.yml`
5. **Document**: Create `docker/images/my-service/README.md`

### Example: Adding Redis Cache

```
docker/
├── images/
│   └── redis/
│       ├── Dockerfile  (custom build with auth)
│       └── README.md   (usage docs)
├── configs/
│   └── redis/
│       └── redis.conf  (redis configuration)
└── docker-compose.yml
    services:
      redis:
        image: my-redis:latest
        build: images/redis/
        volumes:
          - ./configs/redis/redis.conf:/usr/local/etc/redis/redis.conf
```

---

## Terraform Infrastructure

### Location Structure

```
terraform/
├── main.tf                      # Single source of truth - all resources here
├── variables.tf                 # Input variable definitions
├── outputs.tf                   # Output definitions
├── versions.tf                  # Provider versions
├── _locals.tf                   # Local values
├── terraform.tfvars             # Active variable values
├── terraform.tfvars.example     # Template
├── modules/                     # Reusable modules
│   ├── containers/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── networking/
│   ├── security/
│   ├── observability/
│   └── storage/
├── environments/                # Environment-specific values
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── production.tfvars
├── hosts/                       # Host-specific values
│   ├── 192.168.168.31.tfvars
│   └── 192.168.168.30.tfvars
└── state/                       # State files (gitignored)
    └── .gitkeep
```

### Rules

| Item | Rule |
|------|------|
| **.tf files in root** | ✅ ONLY in `terraform/`, never at repo root |
| **Modules** | For reusable blocks (containers, networking, etc.) |
| **Environments** | dev.tfvars, staging.tfvars, production.tfvars |
| **Host-specific** | 192.168.168.31.tfvars for host-specific deployments |
| **Single truth** | `main.tf` is authoritative, not separate phase-*.tf files |

### Adding New Infrastructure

```hcl
# terraform/main.tf - ADD HERE (not new file)

module "my_new_feature" {
  source = "./modules/my-feature-category"

  var_name = var.var_defined_in_variables_tf
}

# terraform/variables.tf - DEFINE INPUT HERE
variable "var_name" {
  type        = string
  description = "What is this for?"
  default     = "default_value"
}

# terraform/environments/production.tfvars - OVERRIDE FOR PROD
var_name = "production_specific_value"
```

---

## Scripts

### Location Structure

```
scripts/
├── README.md              # Script index
├── Makefile               # make targets for common operations
├── install/               # Installation & setup
│   ├── setup.sh           # Main setup
│   ├── setup-deps.sh      # Dependencies
│   └── setup-db.sh        # Database
├── deploy/                # Deployment scripts
│   ├── deploy-iac.sh
│   ├── deploy-containers.sh
│   └── deploy-all.sh
├── health/                # Health checks & validation
│   ├── health-check.sh
│   └── validate-config.sh
├── maintenance/           # Backup, restore, cleanup
│   ├── backup.sh
│   ├── restore.sh
│   └── cleanup.sh
├── dev/                   # Development utilities
│   ├── setup-local.sh
│   ├── onboard-dev.sh
│   ├── fix-common-issues.sh
│   └── troubleshoot-*.sh
├── ci/                    # CI/CD operations
│   ├── admin-merge.ps1
│   └── ci-merge-automation.ps1
└── lib/                   # Shared functions
    ├── logger.sh
    ├── error-handler.sh
    └── common.sh
```

### Rules

| Item | Rule |
|------|------|
| **Purpose** | Scripts must have clear singular purpose |
| **Location** | Categorized by type (install, deploy, health, etc.) |
| **Naming** | verb-noun pattern: `deploy-iac.sh`, `health-check.sh` |
| **Header** | ALWAYS include header with usage (see [Headers](#mandatory-headers)) |
| **Reusable code** | Extract to `scripts/lib/` as shared functions |
| **Duplication** | Zero tolerance - consolidate |
| **Root directory** | ❌ NEVER - all go in `scripts/[category]/` |
| **Phase numbers** | ❌ NEVER - old phases go to archived/ |

### Header Template (Shell Scripts)

```bash
#!/bin/bash
################################################################################
# [Script Category]: script-name.sh
# Purpose: One-line description
# Usage: ./scripts/category/script-name.sh [args]
# Examples:
#   ./scripts/deploy/deploy-iac.sh production
#   ./scripts/deploy/deploy-iac.sh staging --plan-only
# Requirements:
#   - Terraform >= 1.6
#   - jq, curl
#   - SSH access to deployment host
# Notes:
#   - This requires production approval
#   - State backed up to state-backup/ before apply
# References:
#   - Deployment Guide: docs/guides/DEPLOYMENT.md
#   - Deployment Runbook: docs/runbooks/DEPLOYMENT-RUNBOOK.md
# Exit Codes:
#   - 0: Success
#   - 1: Terraform error
#   - 2: Invalid arguments
#   - 3: Missing dependencies
# Author: @akushnir
# Last Updated: 2026-04-14
################################################################################

set -euo pipefail

# Sourcing shared functions
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/logger.sh"

# Implementation...
```

### Adding New Script

1. **Determine category**: install, deploy, health, maintenance, dev, ci, lib
2. **Create file**: `scripts/[category]/script-name.sh`
3. **Add header**: Required (see above)
4. **Source shared libs**: `source scripts/lib/common.sh`
5. **Document entry points**: `make targets` in scripts/Makefile
6. **Test locally**: Before committing

---

## Configuration Files

### Location Rule

Configuration files live in `docker/configs/` organized by service:

```
docker/configs/
├── code-server/
│   └── code-server-config.yaml
├── caddy/
│   └── Caddyfile
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
├── alertmanager/
│   └── alertmanager.yml
└── grafana/
    └── grafana-datasources.yml
```

### Rules

| Item | Rule |
|------|------|
| **Service configs** | In `docker/configs/[service]/` |
| **Variants** | Use override files, not separate configs |
| **Environment vars** | In `.env.example` with comments |
| **Secrets** | NEVER in git; use env vars or external secret manager |
| **Templates** | `.example` suffix, `.tpl` is deprecated |
| **Include other configs** | Use relative paths, documented in README |

### Example: Adding MongoDB Config

```
docker/configs/
└── mongodb/
    ├── mongod.conf      # Main config
    ├── mongod.prod.conf # Production overrides
    └── README.md        # Usage documentation
```

---

## Tests

### Location Structure

```
tests/
├── conftest.py           # Pytest fixtures & configuration
├── unit/                 # Unit tests
│   ├── test_api.py
│   └── test_utils.py
├── integration/          # Integration tests
│   └── test_docker_compose.py
├── e2e/                  # End-to-end tests
│   └── test_deployment.py
├── fixtures/             # Test data
│   ├── sample-data.json
│   └── mock-responses.json
└── README.md             # Testing guide
```

### Rules

| Item | Rule |
|------|------|
| **Test location** | Match source structure in `tests/` |
| **Naming** | `test_[feature].py` or `[feature]_test.py` |
| **Coverage** | 80% minimum for application code |
| **Fixtures** | Shared test data in `tests/fixtures/` |
| **Mocking** | Use `unittest.mock` or `pytest-mock` |

---

## Secrets & Sensitive Data

### NEVER in Git

❌ Passwords, API keys, tokens, certificates, SSH keys
❌ `.env` file with real values
❌ `terraform.tfvars` with real values
❌ `*.pem`, `*.key`, `*.p12` files

### Solution

**1. Template files** (commit to git):
- `.env.example` - template with empty values
- `terraform.tfvars.example` - template variables
- `docker/configs/example.conf` - example configs

**2. Secrets storage** (do NOT commit):
- `.env` - local development secrets only
- `secrets/` - gitignored directory
- `~/.ssh/` or credential manager - SSH keys
- GitHub Secrets - for CI/CD (configure in Actions)
- External secret manager - in production

### Workflow

```bash
# 1. Create template (commit this)
cp .env.example .env

# 2. Fill with YOUR values (never commit .env)
nano .env
echo ".env" >> .gitignore

# 3. Reference in docker-compose
services:
  app:
    environment:
      - DATABASE_URL=${DATABASE_URL}  # From .env
```

---

## Migration Guide: Old Paths → New Paths

If you have code pointing to old paths, update them:

| Old Path | New Path | Type |
|----------|----------|------|
| `./Dockerfile` | `docker/images/code-server/Dockerfile` | Image definition |
| `./docker-compose.yml` | `docker/docker-compose.yml` | Compose base |
| `./Caddyfile` | `docker/configs/caddy/Caddyfile` | Proxy config |
| `./main.tf` | `terraform/main.tf` | IaC definition |
| `./scripts/deploy-iac.sh` | `scripts/deploy/deploy-iac.sh` | Deploy script |
| `./DEPLOYMENT.md` | `docs/guides/DEPLOYMENT.md` | Deployment guide |
| `./terraform-backup/` | `archived/terraform-backup/` | Historical |
| `./PHASE-14-*.md` | `archived/phase-summaries/phase-14/` | Phase docs |

---

## Quick Checklist

When adding new files:

- [ ] Put documentation in `docs/` (never root)
- [ ] Put terraform in `terraform/` (never root)
- [ ] Put docker configs in `docker/configs/`
- [ ] Put scripts in `scripts/[category]/`
- [ ] Add file header with purpose/usage/references
- [ ] Add README.md if creating new directory
- [ ] No duplicate files/config
- [ ] No phase-numbered files
- [ ] No .bak, .old, or variant files
- [ ] Secrets in `.env.example`, not real values
- [ ] Links are relative paths, not absolute URLs
- [ ] Filename is logical and lowercase
- [ ] Run `make test` and `make lint` (when implemented)

---

**Remember**: Structure enforces best practices. When in doubt, check this guide.
