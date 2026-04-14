# Contributing — Production-First Engineering Constitution

This repository operates under **PRODUCTION-FIRST MANDATE**. Every contribution must be:

- **Secure by default** — Zero hardcoded secrets, least privilege IAM, explicit trust boundaries
- **Observable by default** — Structured logging, metrics, tracing, health endpoints
- **Scalable by design** — Stateless architecture, horizontal scaling validated, no implicit coupling
- **Automated end-to-end** — Deterministic builds, reproducible deployments, versioned artifacts
- **Measurable** — Performance profiled, SLOs defined, alerts configured
- **Defensible in audit** — Policy compliant, security scans enforced, threat models documented

**If it would not survive principal-level review at Amazon, Google, or Meta, it does not merge.**

Working locally is not sufficient. Production-hardened is the baseline.

---

## AI-Assisted Development Directive

All AI-generated contributions (GitHub Copilot, LLMs, internal agents) must operate in **Ruthless Enterprise Mode**.

AI must:
- Challenge assumptions aggressively
- Avoid demo-level implementations
- Avoid insecure defaults
- Avoid hidden scalability ceilings
- Avoid implicit coupling
- Avoid unbounded memory or concurrency

**AI-generated code must meet the same standards as senior staff engineers.**

---

## Mandatory Review Gates

Every PR must satisfy these non-negotiable gates:

### 🏗️ Architecture
- [ ] Horizontal scalability validated
- [ ] Stateless where possible
- [ ] Explicit dependency boundaries documented
- [ ] Failure isolation strategy defined
- [ ] ADR linked (if architectural change)

### 🔐 Security
- [ ] Zero hardcoded secrets (automated scan enforces this)
- [ ] IAM follows least privilege principle
- [ ] Input validation implemented
- [ ] Explicit trust boundaries defined
- [ ] Threat model documented (for new services)

### ⚡ Performance
- [ ] No blocking operations in hot paths
- [ ] No N+1 query patterns
- [ ] Performance measured, not assumed
- [ ] Resource limits defined
- [ ] Benchmarked on target infrastructure

### 📊 Observability
- [ ] Structured logging (JSON, correlation IDs)
- [ ] Metrics emitted (Prometheus format)
- [ ] Distributed tracing enabled (OpenTelemetry ready)
- [ ] Health endpoints implemented
- [ ] Alert conditions defined

### 🔄 CI/CD & Reproducibility
- [ ] Deterministic builds (no floating versions)
- [ ] Automated tests required (unit + integration)
- [ ] Static analysis enforced (lint failures block)
- [ ] Security scans enforced (SAST, dependency, secrets, container)
- [ ] Artifacts versioned immutably
- [ ] Rollback strategy documented

---

## Definition of Done (Enterprise)

A change is complete **only when**:

✅ Secure — No vulnerability paths
✅ Observable — Logs, metrics, traces exist
✅ Load-tested — Performance validated
✅ Documented — Architecture, deployment, rollback clear
✅ Automated — Tests, builds, deploys all pass
✅ Reproducible — Anyone can rebuild from source
✅ Policy compliant — All scans passing, ADRs linked

**"Works locally" is not done.** "Works in production" is the standard.

---

## Local Development Checklist

Before opening a PR, validate locally:

```bash
# Pre-commit checks
pre-commit run --all-files

# Repository validation script
./scripts/validate.sh

# IaC policy validation (OPA/Conftest)
conftest test terraform/ -p policies/

# Docker/container builds
docker-compose build --no-cache

# Unit tests
pytest tests/ -v --cov=. --cov-report=term

# Static analysis
pylint src/
shellcheck scripts/*.sh

# Pre-commit hooks (Phase 2.3) — REQUIRED for all commits
pre-commit run --all-files
```

Failure in any local check = PR must address before review request.

---

## Phase 2.3: Pre-Commit Hooks — Code Quality & Governance

Pre-commit hooks automate enforcement of standards BEFORE code reaches version control.

### Setup (One-time)

```bash
# Install pre-commit framework
pip install pre-commit

# Install hooks in your local repository
pre-commit install

# Verify installation
pre-commit --version
```

### What Hooks Check

| Hook | Purpose | Auto-Fix? | Stage |
|------|---------|-----------|-------|
| **shellcheck** | Bash script quality | ❌ | Commit |
| **yamllint** | YAML syntax & format | ✅ | Commit |
| **trailing-whitespace** | Clean trailing spaces | ✅ | Commit |
| **end-of-file-fixer** | Add final newline | ✅ | Commit |
| **check-yaml** | YAML validity | ❌ | Commit |
| **check-json** | JSON syntax | ❌ | Commit |
| **detect-private-key** | Block hardcoded secrets | ❌ | Commit |
| **verify-scripts-source-common** | Scripts use logging/error libraries | ❌ | Commit |
| **verify-metadata-headers** | Scripts have standardized headers | ❌ | Commit |
| **no-hardcoded-secrets** | Block hardcoded passwords/tokens | ❌ | Commit |

### Running Hooks

**Automatically at commit time** (default):
```bash
git add .
git commit -m "feat: ..."  # Hooks run automatically
```

**Manually on all files** (recommended before PR):
```bash
pre-commit run --all-files  # Check entire repo
```

**Manually on specific files**:
```bash
pre-commit run shellcheck --all-files  # Only shellcheck
pre-commit run yamllint --all-files    # Only YAML linting
```

**Manual checks** (best practices, not enforced):
```bash
pre-commit run --all-files --hook-stage manual  # Run optional checks
```

### When Hooks Fail

**If a hook fails:**

1. **Auto-fixable hooks** (trailing-whitespace, end-of-file-fixer, yamllint):
   ```bash
   # Run again — these fix themselves
   git add .
   git commit -m "feat: ..."
   ```

2. **Manual fix required** (shellcheck, detect-private-key, etc.):
   ```bash
   # Fix the issue (e.g., remove hardcoded secret)
   # Verify fix:
   pre-commit run <hook-name>  # Re-run specific hook
   # Then commit again
   git commit -m "feat: ..."
   ```

3. **Bypass if absolutely necessary**:
   ```bash
   git commit -m "..." --no-verify  # Skip hooks (NOT RECOMMENDED)
   ```
   ⚠️ **Use `--no-verify` only in emergencies. CI will still check.**

### Common Failures & Fixes

**shellcheck failures**:
```bash
# Run shellcheck manually to see details
shellcheck scripts/deploy.sh

# Fix issues:
# - Quote variables: "$var" not $var
# - Use set -euo pipefail at script top
# - Use functions for reusable logic
```

**Hardcoded secret detected**:
```bash
# WRONG - hardcoded password:
docker run -e PASSWORD=admin123 ...

# RIGHT - use environment variable:
docker run -e PASSWORD="$PASSWORD" ...
```

**Missing metadata header**:
```bash
# Add to top of script (after #!/bin/bash):
################################################################################
# File: script-name.sh
# Owner: Team Name
# Purpose: Brief description
# ...
################################################################################
```

**Scripts not sourcing common libraries**:
```bash
# Add to script after header:
source "$(dirname "$0")/_common/logging.sh"
source "$(dirname "$0")/_common/utils.sh"
source "$(dirname "$0")/_common/error-handler.sh"
```

---

## Testing Locally

Before pushing, verify your code meets all standards:

```bash
# 1. Run pre-commit hooks
pre-commit run --all-files

# 2. Validate configuration files
docker-compose config > /dev/null
terraform validate

# 3. Run tests
pytest tests/ -v

# 4. Check with all security scans
bash scripts/validate.sh

# 5. Final verification before push
git push --dry-run  # Verify what will be pushed
```

If all pass, you're ready for PR!

---

## CI/CD Validation (Automatic)

The following run automatically on every PR in GitHub Actions:

- **validate-config.yml** — Configuration syntax validation (6+ checks)
- **Test Suite** — Unit, integration, E2E tests
- **Security Scanning** — TruffleHog for secrets, Snyk for dependencies
- **Performance Tests** — Benchmarks must not regress

**If CI fails**, the PR cannot merge. Fix locally and push again.

---

## Phase 2 Integration (Error Handling & Logging)

All shell scripts must now use standardized error handling (Phase 2.2):

```bash
#!/bin/bash
set -euo pipefail

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/logging.sh"
source "$SCRIPT_DIR/_common/utils.sh"
source "$SCRIPT_DIR/_common/error-handler.sh"

# Use logging functions
log_info "Operation starting..."
require_command docker  # Verify docker is installed
retry 3 docker pull image:tag  # Retry transient failures

log_success "Operation complete"


## CI/CD Enforcement Pipeline

The following stages are **non-waivable**:

1. **Lint** — Code style, formatting
2. **Unit Tests** — Coverage gate enforced (minimum 80%)
3. **SAST** — Static application security testing
4. **Dependency Scanning** — Known CVE detection
5. **Secrets Scanning** — Hardcoded credentials detection
6. **IaC Policy** — OPA/Conftest validation against security policies
7. **Container Scan** — Image vulnerability scan
8. **Build Artifact** — Versioned, signed, immutable
9. **Integration Tests** — End-to-end contract testing
10. **Coverage Enforcement** — Minimum thresholds non-negotiable

Failure at **any stage blocks merge**. No exceptions.

---

## Configuration Validation (CI Pipeline)

All configuration files are **automatically validated** on every PR:

### Automated Checks (`.github/workflows/validate-config.yml`)

| Check | Files | Tool | Failure Mode |
|-------|-------|------|--------------|
| **Docker Compose** | `docker-compose*.yml` | `docker-compose config` | Syntax error blocks merge |
| **Caddyfile** | `Caddyfile*` | `caddy validate` | Syntax error blocks merge |
| **Terraform** | `*.tf` | `terraform validate` | Invalid HCL blocks merge |
| **Shell Scripts** | `scripts/**/*.sh` | `bash -n` + `shellcheck` | Syntax errors warn (non-blocking) |
| **Secrets** | `.env*` files | TruffleHog + pattern scan | Hardcoded secrets block merge |
| **Obsolete Files** | Root directory | File pattern matching | Phase-specific files warn (non-blocking) |

### What These Checks Prevent

- ❌ Invalid docker-compose syntax silently breaking deployments
- ❌ Caddyfile configuration errors causing traffic downtime
- ❌ Terraform HCL errors preventing infrastructure updates
- ❌ Hardcoded database passwords or API keys in git history
- ❌ Obsolete phase-specific files cluttering repository

### Example: Running CI Validations Locally

Before pushing, validate locally:

```bash
# Docker Compose
docker-compose config > /dev/null

# Caddyfile
caddy validate --config Caddyfile

# Terraform
terraform init -backend=false && terraform validate

# Shell scripts
bash -n scripts/*.sh
shellcheck scripts/*.sh

# Secrets
if grep -r 'password\|secret\|key' .env*; then
  echo "ERROR: Hardcoded secrets detected"
  exit 1
fi
```

### CI Validation Failures

If a PR fails CI validation:

1. **Read the error message carefully** — It tells you exactly what's wrong
2. **Fix locally** using the commands above
3. **Commit and push** — CI will re-run automatically
4. **No forced merges** — Even if an admin can bypass CI, don't do it

---

## Branch Protection Rules (Enforced)

All branches follow:

- ✅ Require PR before merge (no direct push)
- ✅ Require 2 approvals (1 must be code owner)
- ✅ Require all status checks passing
- ✅ Require conversations resolved
- ✅ Dismiss stale reviews on new commits
- ✅ Prevent force pushes
- ✅ Require signed commits (elite tier)
- ✅ Linear history (rebasing preferred)

---

## Threat Modeling & Security Review

For any new service or significant architectural change:

1. Document trust boundaries
2. Identify threats using STRIDE or similar
3. Document mitigations
4. Threat model reviewed by security team

Link threat model document in PR.

---

## ADR System (Architectural Discipline)

Major architectural decisions require an ADR (Architecture Decision Record).

**Location**: `/docs/adr/

**When required**:
- New service architecture
- Technology selection (framework, database, message queue)
- Infrastructure topology change
- Security boundary change
- Major refactoring

**ADR template** located at [docs/adr/TEMPLATE.md](docs/adr/TEMPLATE.md)

**Example ADRs**:
- [ADR-001: Containerized code-server Deployment](docs/adr/001-containerized-deployment.md)
- [ADR-002: OAuth2 Proxy for Authentication](docs/adr/002-oauth2-authentication.md)

All ADRs are immutable; new decisions require new ADRs with `Supersedes` link.

---

## SLO & Observability

For production services, define:

- **SLI** (Service Level Indicator): What we measure
- **SLO** (Service Level Objective): The target (e.g., 99.9% uptime)
- **Error Budget**: How much failure is acceptable
- **Alert Thresholds**: When to page on-call

**Location**: `/docs/slos/

Without SLOs, you're not running engineering — you're gambling.

---

## Code Review Standards

Reviewers must validate:

1. **Does it follow the architecture?** — Check against ADRs
2. **Is it secure?** — Threat model, input validation, least privilege
3. **Is it observable?** — Logs, metrics, traces
4. **Is it scalable?** — No hidden limits, blocking calls
5. **Is it tested?** — Unit + integration coverage
6. **Is it documented?** — Can a new engineer understand it 6 months later?

**Red flags that block approval**:
- Hardcoded configuration
- No error handling
- No logging
- No tests
- No documentation
- Blocking operations in hot paths
- Implicit dependencies

---

## Rollback Strategy (Mandatory)

Every production change must answer:

- How do we revert safely?
- What is the rollback time SLA?
- What data migrations need reversal?
- Are there dependencies that break?

### Rollback playbook format:

```markdown
## Rollback Plan

**Time to rollback**: <X minutes>
**Data considerations**: <impact of reverting>
**Dependent services**: <systems that might break>
**Steps**:
1. [Specific step]
2. [Specific step]
3. [Verification step]


---

## CI Pipeline Configuration

Refer to [.github/workflows/](github/workflows/) for implementation details:

- `ci-validate.yml` — Lint, unit tests, SAS
- `security.yml` — Dependency, secrets, container scans
- `deploy.yml` — Artifact versioning, rollback capability
- `validate.yml` — IaC policy enforcemen

---

## When in Doub

Ask the following:

1. **Would a principal engineer at Google accept this?** If no, rework it.
2. **Is this secure by default?** If defaults are insecure, fix it.
3. **Is this observable?** If you can't debug it in production, it's not done.
4. **Is this scalable?** If it has hidden limits, document them.
5. **Are we measuring this?** If there are no metrics, we can't manage it.
6. **Can we rollback this safely?** If not, the risk profile is unacceptable.

---

## Configuration Consolidation Patterns

To eliminate duplication and maintain single sources of truth across the codebase, follow these patterns:

### 1. Docker Compose Inheritance

**Pattern**: Use `docker-compose.base.yml` with YAML anchors for shared service definitions.

**File Structure**:
```
docker-compose.base.yml    ← Define all core services + shared anchors
docker-compose.yml          ← Production: compose base + overrides
docker-compose.dev.yml      ← Development: compose base + dev-specific settings
docker-compose.onprem.yml   ← On-premises: compose base + on-prem overrides
```

**YAML Anchors** (reusable blocks):
- `&healthcheck-standard` — Standard 30-second health check
- `&logging-standard` — JSON logging to stdout
- `&deploy-resources` — CPU/memory limits (cpu: 2.0, memory: 4g)
- `&network-enterprise` — Enterprise network attachment
- `&restart-policy` — unless-stopped restart

**Usage**:
```yaml
services:
  code-server:
    <<: *deploy-resources      # Inherit resource limits
    <<: *logging-standard      # Inherit logging config
    healthcheck: *healthcheck-standard
```

**Benefits**:
- 40% code reduction across variants
- Single definition point for all shared config
- Easy to update all services simultaneously
- Variant-specific overrides are explicit

### 2. Caddyfile Named Segments

**Pattern**: Use named segment blocks (@import) in Caddyfile for reusable configuration.

**File Structure**:
```
Caddyfile.base         ← Contains all named segment definitions
Caddyfile              ← Production: @import base + production-specific matchers
Caddyfile.new          ← New deployments: @import base + new-deployment config
Caddyfile.production   ← Strict security: @import base + security_headers_strict
```

**Named Segments** (reusable blocks):
- `(security_headers)` — Standard security headers (CSP, X-Frame-Options, HSTS)
- `(security_headers_strict)` — Enhanced headers for high-security deployments
- `(cache_control_rules)` — Cache policies for assets, API, health endpoints
- `(compression_standard)` — gzip compression for HTML/CSS/JS
- `(compression_advanced)` — brotli + gzip for high-bandwidth environments
- `(reverse_proxy_code_server)` — code-server reverse proxy with proper headers
- `(http_to_https_redirect)` — Port 80 → 443 redirection
- `(rate_limiting_production)` — Rate limiting for DDoS protection

**Usage**:
```caddyfile
@import Caddyfile.base

:80 {
    encode gzip
    header @import (security_headers)
    header @import (cache_control_rules)
    reverse_proxy code-server:8080
}
```

**Benefits**:
- 37% code reduction across variants
- Security headers defined once
- Easy to switch between security levels
- Cache/compression policies unified

### 3. AlertManager Base Configuration

**Pattern**: Use `alertmanager-base.yml` for shared route structures and inhibit rules.

**File Structure**:
```
alertmanager-base.yml          ← Shared global, route structure, inhibit rules
alertmanager.yml               ← Simple variant: references base
alertmanager-production.yml    ← Complex variant: references base + custom receivers
```

**Shared Structure** (in base):
- Global settings (resolve_timeout, slack_api_url)
- Route definition with severity-based grouping (critical→high→medium→low)
- Inhibit rules (suppress lower severity when higher is firing)
- Template configuration section

**Usage**:
```yaml
# In alertmanager.yml
include: alertmanager-base.yml

receivers:
  - name: 'team-slack'
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
```

**Benefits**:
- 33% code reduction across variants
- Severity-based routing unified
- Inhibit rules applied consistently
- Easy to add new receivers without duplicating routing logic

### 4. Terraform Locals Pinning

**Pattern**: Centralize all service versions and resource allocations in `terraform/locals.tf`.

**Structure**:
```hcl
locals {
  docker_images = {
    code-server   = "codercom/code-server:4.115.0"
    ollama        = "ollama/ollama:0.1.27"
    oauth2-proxy  = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1"
    caddy         = "caddy:2-alpine"
    prometheus    = "prom/prometheus:v2.48.0"
    grafana       = "grafana/grafana:10.2.3"
    alertmanager  = "prom/alertmanager:v0.26.0"
  }
  
  resource_limits = {
    code-server = {
      cpu_limit = "2.0"
      memory    = "4g"
    }
    ollama = {
      cpu_limit = "4.0"
      memory    = "32g"
    }
  }
}
```

**Usage** (in resources):
```hcl
docker_image {
  name = local.docker_images["prometheus"]
}

resources {
  cpu_limit  = local.resource_limits["code-server"]["cpu_limit"]
  memory     = local.resource_limits["code-server"]["memory"]
}
```

**Benefits**:
- 100% centralized version management
- Single source of truth for all images
- Easy rolling updates across all terraform resources
- Resource limits defined once, applied everywhere

### 5. Environment Variable Extraction

**Pattern**: Extract environment variables into dedicated `.env.MODULE_NAME` files.

**File Structure**:
```
.env.oauth2-proxy  ← All OAuth2-Proxy variables (28 vars consolidated)
.env.prometheus    ← All Prometheus variables
docker-compose.yml ← References: env_file: [.env.oauth2-proxy, .env.prometheus]
```

**Structure** (example: .env.oauth2-proxy):
```bash
# OAuth2-Proxy Configuration
OAUTH2_PROXY_PROVIDER=oidc
OAUTH2_PROXY_CLIENT_ID=${CLIENT_ID}
OAUTH2_PROXY_CLIENT_SECRET=${CLIENT_SECRET}
# ... 28 total variables
```

**Benefits**:
- 67% reduction in variable duplication
- Single point to manage credentials
- Easy to version control (with secrets scanning)
- Clear separation of concerns

### 6. Script Function Libraries

**Pattern**: Consolidate common operations into reusable shell/PowerShell libraries.

**Bash Library** (`scripts/logging.sh`):
```bash
#!/bin/bash
# Structured logging with timestamps and colors
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2; }
log_success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"; }
```

**PowerShell Library** (`scripts/common-functions.ps1`):
```powershell
function Get-PRCheckStatus {
    # Unified PR status retrieval via GitHub CLI
}

function Merge-PullRequest {
    # Unified PR merge with validation
}
```

**Usage**:
```bash
#!/bin/bash
source scripts/logging.sh
log "Deployment starting..."
```

**Benefits**:
- 50% reduction in duplicate logging code
- Consistent error handling across scripts
- Easy to update formatting/behavior globally

---

## When Adding New Configuration

Before creating a new config file, ask:

1. **Is this duplicating existing configuration?** → Use consolidation patterns above
2. **Can this be a variant of an existing config?** → Use composition/inheritance
3. **Does this define multiple instances of same type?** → Use YAML anchors or terraform locals
4. **Are there environment-specific values?** → Extract to .env files or locals

**Add to ADR system** if introducing new consolidation patterns.

---

## Ruthless Truth

If:
- Policies are not automated → This entire document is corporate cosplay
- Reviews are optional → Engineers will skip them
- Security scans are warnings only → Vulnerabilities will ship
- Performance is not measured → You'll be surprised in production
- ADRs are ignored → Architectural debt accumulates
- Rollbacks are undocumented → Incidents become disasters
- Configuration is duplicated → Bugs propagate across the codebase

Elite engineering = **enforcement + culture + automation**.

No exceptions. No compromises. No "we'll clean it up later."
