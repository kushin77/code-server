# Code-Server-Enterprise Governance & Guardrails

**Document Version**: 1.0  
**Last Updated**: April 14, 2026  
**Status**: GOVERNING DOCUMENT - All development must comply

---

## Table of Contents

1. [Mission & Principles](#mission--principles)
2. [Development Standards](#development-standards)
3. [Repository Structure Rules](#repository-structure-rules)
4. [Code Quality Requirements](#code-quality-requirements)
5. [Configuration Management](#configuration-management)
6. [Documentation Requirements](#documentation-requirements)
7. [Deployment & Operations](#deployment--operations)
8. [Governance Enforcement](#governance-enforcement)

---

## Mission & Principles

### Core Mission

**Production-grade infrastructure-as-code for on-premises code-server deployment with enterprise security, observability, and operational excellence.**

### Guiding Principles

| Principle | Definition | Enforcement |
|-----------|-----------|---------------|
| **Zero Tolerance for Duplication** | Single source of truth for every concept | Code reviews reject duplicated files/configs |
| **Progressive Disclosure** | Simple at surface, complex infrastructure hidden | Root files stay clean, details in modules |
| **Production First** | All code assumes it will run in production | Staging === Production; no "dev-only" shortcuts |
| **Observability Built-In** | Every component is monitored, logged, alerted | No unobserved code paths |
| **Security by Default** | Secure configurations are defaults, insecure requires justification | TLS/auth/RBAC always on unless explicitly disabled for testing |
| **Documentation Equals Code** | Outdated docs are broken code | Docs reviewed with every code change |

---

## Development Standards

### 1. Commit Standards

All commits MUST follow conventional commits format:

```
<type>(<scope>): <subject>

<body with context>

Fixes #123
Relates-to #456
```

**Allowed Types**:
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code changes without functional changes
- `test`: Test additions/modifications
- `docs`: Documentation changes
- `config`: Configuration/IaC changes
- `ci`: CI/CD pipeline changes
- `chore`: Maintenance (dependencies, tooling)

**Requirements**:
- Subject line: imperative mood, lowercase, no period, max 50 chars
- Body: explain WHAT and WHY, not HOW
- References: Link to issues using `Fixes #`, `Relates-to #`, `Closes #`
- One commit per logical change (no mixing features with fixes)

**Example**:
```
config: consolidate docker-compose variants into base + overrides

Previously docker-compose had 8 variant files with 95% code duplication.
Now uses single base file with production/monitoring overrides via
docker-compose.override.yml for cleaner source control.

This reduces from 1200 lines across 8 files to 400 lines base + 100 lines per variant.

Fixes #456
```

### 2. Branch Strategy

- **main**: Production-ready code only
  - Protected branch: requires PR, 1 approval, all checks pass
  - Always fast-forward merge
  - Never force-push
  - Revert-safe: every commit must be independently deployable

- **develop**: Integration branch for features
  - Base for feature PRs
  - Tests must pass
  - 1 approval required

- **Feature branches**: `feature/<issue-number>-<short-description>`
  - Example: `feature/123-docker-compose-consolidation`
  - Limited lifetime: delete after merge
  - Rebase before merge, no merge commits

### 3. Pull Request Standards

**Every change requires a PR. No exceptions.**

**Checklist (MUST include in PR body)**:

```markdown
## Change Summary
<!-- What changed and why? -->

## Verification
- [ ] Tests added/updated
- [ ] Docs updated
- [ ] No duplicated code/configs
- [ ] Linting passes
- [ ] No hardcoded secrets
- [ ] Backwards compatible OR migration documented

## Deployment Impact
- [ ] No infrastructure downtime required
- [ ] Database migrations: YES/NO
- [ ] Config changes: YES/NO
- [ ] Requires manual steps: YES/NO (describe)

## Reviewers
- @akushnir (code)
- @reviewer2 (architecture) (if infrastructure changes)
```

**Review Standards**:
- 1 approval minimum before merge
- Address ALL comments before merge (approve > re-request review cycle)
- Discussions: separate from blocking comments
- Approver must verify checks pass before merge

### 4. Testing Requirements

| Code Type | Coverage Minimum | Requirement |
|-----------|------------------|-------------|
| Application Code (.py/.js/.ts) | 80% | Unit + integration tests |
| Infrastructure (Terraform) | 100% | Validate + plan approved |
| Shell Scripts | 50% | Critical paths tested manually |
| Documentation | N/A | Link validation, no stale URLs |

**Testing Automation**:
- All tests run on PR commit
- CI/CD blocks merge if tests fail
- Tests must be reproducible locally: `make test` or equivalent

---

## Repository Structure Rules

### 1. Root Directory Rules

**Purpose**: Root is the entrypoint. Keep it CLEAN.

**Allowed in Root** (max 15 files):
- `README.md` - Repo overview
- `.gitignore`, `.gitattributes` - Git configuration
- `Makefile` - Common commands (make test, make deploy)
- `Dockerfile` - Primary application image
- `docker-compose.yml` - Development stack (see [Container Orchestration](#container-orchestration))
- `terraform.tfvars` - Terraform variables
- `LICENSE` - License file

**Never in Root**:
- ❌ Phase-numbered files (phase-14.tf, phase-15.yaml)
- ❌ Variant files (docker-compose.production.yml, Caddyfile.new)
- ❌ Status documents (PHASE-14-EXECUTION-STATUS.md)
- ❌ Old/backup files (*.bak, *.old, terraform-backup/)
- ❌ Tangential docs (EXAMPLE_DEVELOPER_GRANT.sh, CRASH_SCAN_SUMMARY.md)

These belong in subdirectories per section below.

### 2. Directory Structure (Max 5 Levels Deep)

```
code-server-enterprise/
├── README.md                    # 📋 Repo overview & quick start
├── Makefile                     # 🔧 Common operations
├── LICENSE
├── .gitignore
│
├── docs/                        # 📚 ALL documentation
│   ├── README.md               # Docs index
│   ├── GOVERNANCE.md           # This file
│   ├── ARCHITECTURE.md
│   ├── GETTING-STARTED.md
│   ├── CONTRIBUTING.md
│   ├── guides/
│   │   ├── DEPLOYMENT.md
│   │   ├── LOCAL-DEVELOPMENT.md
│   │   ├── TROUBLESHOOTING.md
│   │   └── SSH-REMOTE-ACCESS.md
│   ├── adc/                    # Architecture Decision Records
│   │   ├── ADR-001-CLOUDFLARE-TUNNEL.md
│   │   └── ADR-002-POSTGRES-HA.md
│   ├── runbooks/
│   │   ├── README.md
│   │   ├── INCIDENT-RESPONSE.md
│   │   ├── DEPLOYMENT-RUNBOOK.md
│   │   └── ROLLBACK-PLAYBOOK.md
│   └── archived/              # Old docs (read-only)
│       └── PHASE-14-SUMMARY.md
│
├── terraform/                   # 🏗️ Infrastructure as Code
│   ├── README.md              # Terraform overview & usage
│   ├── main.tf                # Primary configuration (single source of truth)
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Output definitions
│   ├── terraform.tfvars       # Active variable values
│   ├── terraform.tfvars.example
│   ├── _locals.tf             # Local values
│   ├── versions.tf            # Provider requirements
│   │
│   ├── modules/               # Reusable Terraform modules
│   │   ├── containers/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── networking/
│   │   ├── observability/
│   │   ├── security/
│   │   └── storage/
│   │
│   ├── environments/           # Environment-specific configs
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── production.tfvars
│   │
│   └── hosts/                  # Host-specific deployments
│       ├── 192.168.168.31.tfvars
│       └── 192.168.168.30.tfvars
│
├── docker/                      # 🐳 Docker images & compose
│   ├── docker-compose.yml      # Base definition (anchored)
│   ├── docker-compose.override.yml  # Development overrides
│   ├── docker-compose.prod.yml  # Production overrides
│   │
│   ├── images/
│   │   ├── code-server/
│   │   │   ├── Dockerfile
│   │   │   ├── entrypoint.sh
│   │   │   └── README.md
│   │   ├── caddy/
│   │   ├── ssh-proxy/
│   │   └── monitoring/
│   │
│   ├── configs/                # Container configs
│   │   ├── code-server-config.yaml
│   │   ├── caddy/Caddyfile
│   │   ├── prometheus/prometheus.yml
│   │   ├── prometheus/alert-rules.yml
│   │   ├── alertmanager/alertmanager.yml
│   │   └── grafana/grafana-datasources.yml
│   │
│   └── volumes/                # Docker volume definitions
│       └── README.md
│
├── scripts/                     # 🛠️ Operational scripts
│   ├── README.md              # Script index
│   ├── Makefile               # Script targets
│   │
│   ├── install/
│   │   ├── setup.sh           # First-time setup
│   │   ├── setup-deps.sh      # Dependency installation
│   │   └── setup-db.sh        # Database initialization
│   │
│   ├── deploy/
│   │   ├── deploy-iac.sh      # Deploy terraform changes
│   │   ├── deploy-containers.sh
│   │   └── deploy-all.sh      # Orchestrated deployment
│   │
│   ├── health/
│   │   ├── health-check.sh    # Comprehensive health checks
│   │   └── validate-config.sh # Configuration validation
│   │
│   ├── maintenance/
│   │   ├── backup.sh
│   │   ├── restore.sh
│   │   └── cleanup.sh
│   │
│   ├── dev/
│   │   ├── setup-local.sh     # Local dev environment
│   │   ├── onboard-dev.sh     # Developer onboarding
│   │   └── fix-common-issues.sh
│   │
│   └── lib/                    # Shared script functions
│       ├── logger.sh          # Logging utilities
│       ├── error-handler.sh   # Error handling
│       └── common.sh          # Common functions
│
├── src/                         # 💻 Application source code
│   ├── python/
│   │   ├── api/
│   │   ├── models/
│   │   └── utils/
│   ├── frontend/
│   └── backend/
│
├── tests/                       # 🧪 Test suites
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   ├── fixtures/
│   └── conftest.py
│
├── .github/                     # GitHub configuration
│   ├── workflows/              # CI/CD pipelines
│   │   ├── test.yml
│   │   ├── lint.yml
│   │   ├── deploy.yml
│   │   └── security-scan.yml
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE/
│
├── .pre-commit-config.yaml     # Pre-commit hooks
├── .tflint.hcl                 # Terraform linting
├── Dockerfile                  # Primary image (if monolithic)
├── docker-compose.yml          # Development docker compose
├── terraform.tfvars            # Active terraform variables
│
└── archived/                    # 🗂️ Old code (read-only)
    ├── README.md
    ├── phase-13-iac/
    ├── gpu-attempts/
    └── deprecated-configs/
```

**Key Rules**:

1. **No phase-numbered files in subdirectories**
   - Phases are completed work, not current structure
   - Archive to `archived/phase-14-summary/` instead

2. **No variant files in main dirs**
   - Use environment-specific overrides (prod, staging, dev)
   - Docker compose: base + override pattern
   - Terraform: environment vars, not separate files

3. **Max 5 levels deep**
   - Level 1: Category (docker, terraform, scripts, docs)
   - Level 2: Type (images, modules, deploy, health)
   - Level 3: Specific (code-server, prometheus, install)
   - Level 4: Files or minor subcategories
   - Level 5: Only for large projects (avoid)

4. **Every directory has README.md**
   - Explains purpose, contents, usage
   - Links to relevant docs
   - Lists entry points

### 3. Container Orchestration Rules

**Single Source of Truth**: `docker/docker-compose.yml`

**Composition Pattern**:
```yaml
# docker/docker-compose.yml - BASE DEFINITION (shared by all)
version: '3.8'
services:
  code-server:
    image: codercom/code-server:${VERSION}
    # All common code-server config here
    # NO overrides, NO variants per-environment
```

**Overrides** (environment-specific):
```yaml
# docker/docker-compose.override.yml - DEVELOPMENT (apply when docker-compose up)
services:
  code-server:
    environment:
      - PASSWORD=dev-password-123
    ports:
      - "8080:8080"  # Expose to host for dev

# docker/docker-compose.prod.yml - PRODUCTION (explicit: docker-compose -f docker-compose.yml -f docker-compose.prod.yml)
services:
  code-server:
    environment:
      - PASSWORD=${CS_PASSWORD}  # From .env secret
    # No ports exposed (behind Caddy)
```

**Variants Banned**:
- ❌ docker-compose.production.yml
- ❌ docker-compose-phase-15.yml
- ❌ docker-compose-monitoring.yml (use service: monitoring section instead)

### 4. Configuration Management Rules

**Configuration Source Hierarchy** (highest priority first):
1. Environment variables (runtime overrides)
2. `.env` file (secrets, local dev)
3. Configuration files (yaml, json)
4. Application defaults

**Never**:
- Hardcode secrets in configs
- Keep credentials in git (even if private)
- Multiple config files for same service
- Version-specific configs (v1.2-config.yml)

**Example** (Prometheus):
```yaml
# docker/configs/prometheus/prometheus.yml
global:
  scrape_interval: ${PROMETHEUS_SCRAPE_INTERVAL:-15s}
  
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
      
  - job_name: 'code-server'
    static_configs:
      - targets: ['code-server:${CODESERVER_METRIC_PORT:-7999}']
```

**Terraform Config Rules**:
- All IaC configuration in `terraform/`
- Variable defaults in `variables.tf`
- Environment overrides in `environments/*.tfvars`
- Host-specific in `hosts/*.tfvars`
- No hardcoded values in modules

---

## Code Quality Requirements

### 1. File Headers (MANDATORY)

Every file type must have metadata headers:

**Terraform** (.tf):
```hcl
################################################################################
# Module: containers
# Description: Docker container infrastructure for code-server deployment
# Usage: Include in main.tf via module "containers" block
# References: 
#   - Docs: docs/guides/DEPLOYMENT.md
#   - ADR: docs/adc/ADR-001-CLOUDFLARE-TUNNEL.md
# Author: @akushnir
# Last Updated: 2026-04-14
################################################################################

terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Implementation follows...
```

**Shell Scripts** (.sh):
```bash
#!/bin/bash
################################################################################
# Script: deploy-iac.sh
# Purpose: Deploy terraform changes to production host
# Usage: ./scripts/deploy/deploy-iac.sh [environment] [extra-args]
# Examples:
#   ./scripts/deploy/deploy-iac.sh production
#   ./scripts/deploy/deploy-iac.sh staging -auto-approve
# Requirements: 
#   - SSH access to deployment host
#   - Terraform >= 1.6
#   - jq, curl installed
# Notes:
#   - Always requires plan approval unless -auto-approve passed
#   - Logs to logs/terraform-$(date +%s).log
# References:
#   - docs/guides/DEPLOYMENT.md
#   - docs/runbooks/DEPLOYMENT-RUNBOOK.md
# Exit Codes:
#   - 0: Success
#   - 1: Terraform error
#   - 2: Invalid arguments
################################################################################

set -euo pipefail

# Implementation follows...
```

**YAML Config** (.yml / .yaml):
```yaml
################################################################################
# Config: prometheus.yml
# Purpose: Prometheus scrape targets and global settings
# Usage: Mounted at /etc/prometheus/prometheus.yml in Prometheus container
# References:
#   - docs/guides/DEPLOYMENT.md
#   - terraform/modules/observability/main.tf
# Author: @akushnir
# Last Updated: 2026-04-14
# Notes:
#   - Scrape interval is configurable via PROMETHEUS_SCRAPE_INTERVAL env var
#   - Alert rules loaded from alert-rules.yml via rule_files
################################################################################

global:
  scrape_interval: 15s
  # Config continues...
```

**Python** (.py):
```python
"""
Module: health_check
Purpose: System health validation and reporting
Usage: python -m health_check --verbose
Classes:
    HealthChecker: Main health check orchestrator
Functions:
    check_docker_health(): Verify Docker daemon
    check_terraform_state(): Validate terraform state
References:
    - docs/guides/TROUBLESHOOTING.md
    - scripts/health/validate-config.sh
Author: @akushnir
Last Updated: 2026-04-14
"""
```

### 2. Inline Code Comments

**REQUIRED for**:
- Complex business logic
- Non-obvious decisions
- Infrastructure-as-code policy enforcement
- Security-sensitive code

**Format**:
```bash
# CONTEXT: What is this doing?
# WHY: Why are we doing it this way?
# REFERENCE: Where is this documented?
some_command "$parameter"
```

**Example**:
```terraform
# CONTEXT: Force recreation of code-server container when image changes
# WHY: Ensures latest patches/security fixes are always deployed
# REFERENCE: docs/guides/DEPLOYMENT.md#image-update-strategy
docker_image.code_server.id
->
docker_container.code_server
```

### 3. README.md in Every Directory

**Minimum Contents**:
```markdown
# [Directory Name]

## Purpose
What does this directory contain? Why does it exist?

## Structure
```
directory/
├── subdir1/ - Purpose
├── file1.tf - Purpose
└── file2.sh - Purpose
```

## Getting Started
How do I use this? What's the entry point?

## Examples
Common usage patterns

## Troubleshooting
Common issues and fixes

## See Also
- [Related doc](../docs/GUIDE.md)
- [Related script](../scripts/deploy/deploy.sh)
```

---

## Documentation Requirements

### 1. Documentation Standards

**All documentation must**:
- ✅ Be in `docs/` directory (not root, not scattered)
- ✅ Use Markdown with GitHub-flavored syntax
- ✅ Include Table of Contents (ToC) for files > 100 lines
- ✅ Link to related files (relative paths)
- ✅ Include examples where applicable
- ✅ List dependencies/prerequisites
- ✅ Indicate last update date and author
- ✅ Have clear "See Also" section

**Never**:
- ❌ Place status documents in root (Phase-14-STATUS.md)
- ❌ Keep outdated copies (Caddyfile.new, .bak files)
- ❌ Skip examples and prerequisites
- ❌ Use absolute URLs for internal links

### 2. ADR (Architecture Decision Records)

When making significant architectural decisions, create an ADR in `docs/adc/`:

**Format**:
```markdown
# ADR-003: Decision Title

**Date**: 2026-04-14  
**Status**: IMPLEMENTED (Approved | Proposed | Superseded)  
**Deciders**: @akushnir, @reviewer

## Context
What decision did we need to make? Why now?

## Decision
What did we decide? One sentence summary.

## Rationale
Why this decision? What alternatives were considered?

## Consequences
What will follow from this decision?
- Positive: ...
- Negative: ...
- Requirements: ...

## Alternatives Considered
- Option A: Why we rejected it
- Option B: Why we rejected it

## Related
- Implements: docs/guides/...
- Supersedes: ADR-001 (if applicable)
```

### 3. Runbooks

Every operational procedure must have a runbook in `docs/runbooks/`:

**Structure**:
```markdown
# Runbook: [Procedure Name]

**Severity**: Critical | High | Medium | Low  
**Time to Complete**: X minutes  
**Requires Approvals**: Yes | No  

## Prerequisites
- [ ] Docker running
- [ ] SSH access to host
- [ ] Terraform state accessible

## Steps
1. First step
   ```bash
   command_to_run
   ```
   Expected output: ...

2. Second step
   ...

## Verification
How to verify the runbook succeeded

## Rollback
If it fails, how do we revert?

## Troubleshooting
If X happens, do Y
If Z happens, do W
```

---

## Deployment & Operations

### 1. Deployment Standards

**Mandatory Workflow**:

1. **Local Validation**
   ```bash
   make test
   make lint
   make validate-config
   ```

2. **Create PR** with link to issue
   - Include deployment impact assessment
   - List any backwards compatibility concerns

3. **Code Review** (1 approval minimum)
   - +1 code review
   - +1 infra review (if IaC changes)

4. **Build & Test** (CI/CD)
   - All checks pass (GitHub Actions)
   - No security vulnerabilities

5. **Merge to main**
   - Use squash merge for feature branches
   - Ensure commit message follows conventions

6. **Deploy to Staging**
   - Automatic after main merge
   - Run smoke tests

7. **Deploy to Production**
   - Manual approval required
   - Via: `make deploy-prod`
   - Document in #deployments Slack channel

**Never**:
- Deploy directly from branches
- Bypass code review
- Force-push to main
- Run terraform apply locally (use SSH to 192.168.168.31)

### 2. Operational Rules

**Monitoring**:
- All services monitored by Prometheus
- All alerts routed through AlertManager
- SLOs defined in docs/SLO-DEFINITIONS.md

**Scheduled Maintenance**:
- Weekly backup verification
- Monthly security scan
- Quarterly capacity planning

**Incident Response**:
- Follows docs/runbooks/INCIDENT-RESPONSE.md
- All incidents logged in GitHub Issues with label: incident
- Post-mortems within 48 hours (critical) or 1 week (others)

---

## Governance Enforcement

### 1. Automated Enforcement

**Pre-commit Hooks** (local):
- Shell script linting (shellcheck)
- Terraform validation (terraform validate)
- YAML linting (yamllint)
- Secret scanning (gitleaks)
- Prevent duplicate file commits

**.github/workflows/** (CI/CD):
- Run on every PR
- Block merge if any fail
- Required checks: test, lint, tf-validate, secret-scan

**Code Review Bot** (configured in CONTRIBUTING.md):
- Requests architecture review for terraform changes
- Blocks merges of phase-numbered files
- Warns about duplicate config files

### 2. Manual Governance

**Monthly Structure Review**:
- @akushnir audits repo structure
- Identifies new duplicates/violations
- Creates issues to consolidate

**Quarterly Documentation Audit**:
- Verify all docs are current
- Check for stale status documents
- Update archived/ directory

**Annual Architecture Review**:
- Assess overall design
- Identify technical debt
- Plan major refactoring

### 3. Violation Handling

**Duplication Detected** (files/configs):
- Issue created, labeled: structural-debt
- PR must consolidate before reference feature work accepted
- Deadline: within 2 sprints

**Path Violations** (files in wrong location):
- Auto-flagged in code review
- Must move to correct location
- No exceptions except archived/

**Missing Documentation**:
- Code review blocks merge
- Required: headers, inline comments, README updates

**Configuration Inconsistency**:
- Terraform plan must show no unintended changes
- Multiple envs must have consistent structure
- Override mechanism required to be obvious

---

## References

- [Repository Structure Details](FOLDER-STRUCTURE.md)
- [Consolidation Plan](../CONSOLIDATION-PLAN.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Architecture Documentation](ARCHITECTURE.md)
- [Deployment Guide](guides/DEPLOYMENT.md)

---

**This document is GOVERNING for the kushin77/code-server-enterprise repository.**  
**All team members must read and acknowledge understanding before contributing.**  
**Changes to this document require discussion and consensus.**
