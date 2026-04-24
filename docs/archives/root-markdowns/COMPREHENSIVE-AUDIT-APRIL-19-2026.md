# Comprehensive Audit Report: kushin77/code-server-enterprise
**Date**: April 19, 2026  
**Scope**: IaC Validation | Naming Conventions | Monorepo & PNPM | NAS Optimization  
**Repository**: kushin77/code-server-enterprise (on-prem at 192.168.168.31)

---

## EXECUTIVE SUMMARY

| Dimension | Status | Critical Issues | High Issues | Medium Issues |
|-----------|--------|-----------------|-------------|---------------|
| **IaC Validation** | ⚠️ NEEDS WORK | 1 | 2 | 4 |
| **Naming Conventions** | ⚠️ INCONSISTENT | 0 | 3 | 4 |
| **Monorepo & PNPM** | ✅ GOOD | 0 | 1 | 3 |
| **NAS Optimization** | ⚠️ GAPS | 1 | 2 | 3 |

**Total Actionable Issues**: 26 (1 Critical, 8 High, 14 Medium)  
**Estimated Remediation**: 40-60 hours  

---

# DIMENSION 1: IaC VALIDATION (Terraform, Docker-Compose, Kubernetes)

## 1.1 STATE MANAGEMENT — CRITICAL ISSUE

**Issue**: No Terraform backend configured (local state only)

| Property | Details |
|----------|---------|
| **Files** | [terraform/main.tf](terraform/main.tf#L1) |
| **Severity** | 🔴 CRITICAL |
| **Problem** | Terraform state is stored locally on the deploy host. In shared environments or multi-admin scenarios, this causes: race conditions, state corruption, no audit trail, no locking mechanism |
| **Current Behavior** | `terraform apply` stores state in `terraform.tfstate` (local file, unversioned) |
| **Impact** | • Loss of infrastructure state if host disk fails<br>• Multiple admins can't safely run terraform concurrently<br>• No state backup/versioning<br>• Disaster recovery impossible<br>• Violates IaC best practices |
| **Risk** | Infrastructure becomes unmanageable; recovery requires manual state reconstruction |
| **Remediation** | Configure backend (options: S3 + DynamoDB, Google Cloud Storage, Terraform Cloud, or local encrypted file)<br>For on-prem: Use encrypted NFS mount or local encrypted storage with regular backups |
| **Effort** | 4-6 hours (backend setup + state migration + testing) |
| **Priority** | P0 - FIX IMMEDIATELY |

**Recommended Fix**:
```hcl
# Add to terraform/main.tf or create terraform/backend.tf
terraform {
  backend "local" {
    path = "/var/lib/terraform/terraform.tfstate"  # Encrypted NFS mount
  }
}
```

---

## 1.2 IMMUTABILITY — HIGH ISSUE

**Issue**: Docker image references inconsistently pinned; some use tags instead of digests

| Property | Details |
|----------|---------|
| **Files** | [docker-compose.yml](docker-compose.yml#L150), [main.tf](main.tf#L80) |
| **Severity** | 🟠 HIGH |
| **Problem** | Most services use version tags (e.g., `caddy:2.7.6`), but this is not fully immutable. Image publishers can re-tag releases, causing different code to deploy on re-pull. Production deployments should use immutable image digests |
| **Current State** | • code-server: `code-server-enterprise:dev` (local tag - not reproducible)<br>• caddy: `caddy:2.7.6` (tag - could mutate)<br>• oauth2-proxy: `quay.io/oauth2-proxy/oauth2-proxy:v7.5.1` (tag)<br>• postgres: `postgres:15-alpine` (tag)<br>• ollama: `ollama/ollama:0.1.27` (tag) |
| **Impact** | • Deployments not reproducible month-to-month<br>• Security vulnerability: tag could be replaced with vulnerable version<br>• Difficult to reproduce bugs if image was re-tagged<br>• Rollback not guaranteed to restore original code |
| **Remediation** | 1. Convert all image refs to use immutable digests:<br>`image: caddy@sha256:abc123...` instead of `caddy:2.7.6`<br>2. Pin local image builds by digest in terraform<br>3. Update docker-compose generation to output digests |
| **Effort** | 6-8 hours (research digests, update all refs, validate deployments) |
| **Priority** | P1 - Fix before next release |

**Example Fix**:
```yaml
caddy:
  image: caddy:2.7.6@sha256:a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0  # immutable digest
```

---

## 1.3 VALIDATION — HIGH ISSUE

**Issue**: Variable validation gaps and inconsistencies between main.tf and terraform/variables.tf

| Property | Details |
|----------|---------|
| **Files** | [variables.tf](variables.tf#L1), [terraform/variables.tf](terraform/variables.tf#L1) |
| **Severity** | 🟠 HIGH |
| **Problem** | Two different variable definitions with conflicting constraints:<br>• Root `variables.tf` requires `code_server_password >= 12 chars`<br>• `terraform/variables.tf` requires `code_server_password >= 8 chars`<br>This creates ambiguity and validation failures in CI/CD |
| **Impact** | • Terraform apply may fail mysteriously depending on which variables.tf is used<br>• CI/CD validation inconsistent<br>• New developers confused about actual requirements |
| **Missing Validation** | • Domain format (only in root variables.tf) — MISSING in terraform/<br>• log_level enum check present but not documented<br>• ollama_num_threads: allows 0-256 but no documented rationale<br>• No validation for `workspace_path` existence<br>• No validation for `docker_host` connectivity |
| **Remediation** | 1. Consolidate to single variables.tf (choose one location)<br>2. Document all validation constraints in comments<br>3. Add regex validation for domain, docker_host, workspace_path<br>4. Add pre-flight checks for connectivity, file existence |
| **Effort** | 3-4 hours |
| **Priority** | P1 - Fix before Phase 2 |

---

## 1.4 IDEMPOTENCY — MEDIUM ISSUE

**Issue**: docker-compose.yml generated by terraform but not tracked in state

| Property | Details |
|----------|---------|
| **Files** | [docker-compose.yml](docker-compose.yml#L1) (generated), [main.tf](main.tf#L50) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | The docker-compose.yml is generated by Terraform but not as a Terraform-managed resource. This means: <br>• Manual edits to docker-compose.yml won't be detected by terraform plan<br>• Re-running terraform may silently overwrite manual changes<br>• No change tracking in terraform state |
| **Current Flow** | 1. `terraform apply` → generates docker-compose.yml<br>2. User may manually edit docker-compose.yml<br>3. `terraform apply` again → overwrites without warning |
| **Impact** | • Operators making manual adjustments lose work on next terraform apply<br>• Drift detection impossible<br>• Can't use terraform to validate current state |
| **Remediation** | Use `terraform_data` or `local_file` resource to track generated file in state, with proper error handling for manual changes |
| **Effort** | 2-3 hours |
| **Priority** | P2 - Implement next sprint |

---

## 1.5 ERROR HANDLING — MEDIUM ISSUE

**Issue**: No deployment error recovery or rollback strategy

| Property | Details |
|----------|---------|
| **Files** | [docker-compose.yml](docker-compose.yml#L1-L50) (health checks only) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | Only healthchecks defined; no automated rollback on failure. If a service fails to start or becomes unhealthy: <br>• No automatic rollback to previous working state<br>• No dependency validation before deployment<br>• Partial failures can leave system in inconsistent state |
| **Example Scenario** | 1. Caddy fails to bind port 443 (port already in use)<br>2. deployment continues anyway<br>3. Users unable to access system<br>4. Manual intervention required |
| **Current Healthchecks** | ✅ Present: code-server, ollama, oauth2-proxy, caddy, postgres, redis, etc. |
| **Missing** | • Post-health-check validation<br>• Dependency ordering (currently uses `depends_on` but loose)<br>• Automated rollback on deployment failure<br>• Smoke tests after successful deployment |
| **Remediation** | 1. Add deployment order validation in terraform<br>2. Implement smoke test suite (bash/python)<br>3. Add rollback script for failed deployments<br>4. Document failure scenarios and recovery steps |
| **Effort** | 5-7 hours |
| **Priority** | P2 - Implement before Phase 2 |

---

## 1.6 MODULE STRUCTURE — MEDIUM ISSUE

**Issue**: Terraform modules exist but not fully utilized; some configurations still in root state

| Property | Details |
|----------|---------|
| **Files** | [terraform/modules/](terraform/modules/) (dns, failover, host-hardening, keepalived, monitoring, networking, security) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | Modules exist (7 modules) but main infrastructure still in root Terraform files. This creates: <br>• Code duplication<br>• Difficult to reuse for multiple environments<br>• No clear module API/contract<br>• Version management difficult |
| **Current Structure** | • `terraform/modules/dns/` — DNS configuration<br>• `terraform/modules/failover/` — HA failover<br>• `terraform/modules/host-hardening/` — Security<br>• `terraform/modules/keepalived/` — Virtual IP management<br>• `terraform/modules/monitoring/` — Prometheus, Grafana<br>• `terraform/modules/networking/` — Network setup<br>• `terraform/modules/security/` — Security groups, policies |
| **Issue** | Root `main.tf` and variables.tf still contain service definitions instead of calling modules |
| **Impact** | • Can't easily deploy to different environments<br>• Difficult to compose infrastructure<br>• Code duplication risk |
| **Remediation** | 1. Refactor root main.tf to use modules<br>2. Create modules/code-server/ for core service<br>3. Document module inputs/outputs<br>4. Create environment-specific tfvars |
| **Effort** | 8-12 hours |
| **Priority** | P2 - Roadmap for Phase 14+ |

---

## 1.7 TESTING & VALIDATION — MEDIUM ISSUE

**Issue**: No terraform test pipeline; no validation in CI/CD

| Property | Details |
|----------|---------|
| **Files** | [Makefile](Makefile#L1), `.github/workflows/` (check structure) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | No automated terraform validation, plan review, or integration tests in CI/CD. Changes go straight to apply without test coverage |
| **Missing** | • `terraform validate` in CI<br>• `terraform plan` diff in PR comments<br>• `tflint` or `checkov` for security scanning<br>• Integration tests (e.g., verify docker-compose generated correctly)<br>• Cost estimation in plan output |
| **Current Flow** | Manual: `terraform plan` locally, review, then `terraform apply` |
| **Impact** | • Breaking changes merged without detection<br>• Security misconfigurations not caught<br>• Poor visibility into infrastructure changes<br>• High risk of outages from untested configs |
| **Remediation** | 1. Add `terraform validate` to pre-commit hooks<br>2. Add terraform plan to CI/CD pipeline<br>3. Add security scanning (checkov, tflint)<br>4. Add integration tests using `terraform test` blocks |
| **Effort** | 6-8 hours |
| **Priority** | P2 - Implement before Phase 2 |

---

## 1.8 DOCKER-COMPOSE IDEMPOTENCY — MEDIUM ISSUE

**Issue**: Some services not fully idempotent; manual cleanup sometimes required

| Property | Details |
|----------|---------|
| **Files** | [docker-compose.yml](docker-compose.yml#L1) (all services) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | `docker compose up -d` is idempotent IF all resources already exist, but: <br>• Database initialization (postgres-init.sql) only runs on first start, not on redeploy<br>• Redis and Postgres don't auto-recover from corrupted state<br>• Session broker may have stale sessions from previous run |
| **Scenario** | 1. `docker compose up -d` creates postgres with initial schema<br>2. Admin manually drops a critical table (panic mode)<br>3. `docker compose restart postgres` recreates container but postgres-init.sql doesn't run<br>4. Database stays corrupted |
| **Impact** | • Unplanned manual interventions required<br>• Data loss risk in corruption scenarios<br>• Redeploy not guaranteed to fix state issues |
| **Remediation** | 1. Make initialization idempotent (IF NOT EXISTS checks)<br>2. Add health check recovery for databases<br>3. Document manual recovery procedures<br>4. Add backup/restore automation |
| **Effort** | 4-5 hours |
| **Priority** | P2 - Document procedures now, implement recovery next sprint |

---

## 1.9 KUBERNETES — LOW ISSUE (Informational)

**Issue**: Kubernetes YAML files exist but not managed as IaC via Terraform

| Property | Details |
|----------|---------|
| **Files** | [kubernetes/](kubernetes/) (13 YAML files across phases) |
| **Severity** | 🟢 LOW (currently not deployed) |
| **Status** | Kubernetes configs exist but are reference/archival, not actively used. Current deployment uses Docker Compose only |
| **Finding** | If Kubernetes deployment planned: <br>• Convert to Terraform Kubernetes provider<br>• Add namespace and RBAC definitions<br>• Pin image digests in K8s manifests<br>• Add network policies |
| **Action** | No immediate fix needed; document as "future IaC target" |

---

# DIMENSION 2: NAMING CONVENTIONS & FAANG STRUCTURE

## 2.1 SHELL SCRIPT NAMING — HIGH ISSUE

**Issue**: Inconsistent script naming patterns (verb_noun vs verb-noun)

| Property | Details |
|----------|---------|
| **Files** | [scripts/](scripts/) (multiple) |
| **Severity** | 🟠 HIGH |
| **Problem** | Scripts follow multiple naming patterns:<br>• **kebab-case** (preferred): `nas-mount-31.sh`, `cleanup-container-overlap.sh`<br>• **verb_noun**: `automated-env-generator.sh` (inconsistent — should be noun only after verb)<br>• **phase-#-descriptive**: `phase-13-iac.sh` (mixes phase numbers with descriptive names)<br>• **abstract names**: `deploy.sh`, `validate.sh` (unclear purpose) |
| **Current Samples** | ✅ Good: `nas-mount-31.sh`, `cleanup-container-overlap.sh`, `backup.sh`<br>⚠️ Unclear: `automated-deployment-orchestration.sh` (noun too long)<br>❌ Inconsistent: `configure-oidc-phase1.sh` vs `phase-2-sanity-check.sh` |
| **Impact** | • Discoverability poor (developers can't find relevant script easily)<br>• Pattern inconsistent makes automation difficult<br>• Difficult for new team members to understand purpose |
| **Remediation** | 1. Establish standard: `<action>-<target>-<context>.sh`<br>   Examples: `mount-nas-31.sh`, `configure-oauth-phase1.sh`, `deploy-code-server.sh`<br>2. Run mass rename: `for f in scripts/*; do mv "$f" (standardized); done`<br>3. Update all references in Makefile, CI/CD, docs |
| **Effort** | 4-5 hours (rename + update references + docs) |
| **Priority** | P2 - High discoverability impact |
| **Commands** | `bash scripts/fix-naming-conventions.sh` (create script first) |

---

## 2.2 PYTHON SCRIPT NAMING — HIGH ISSUE

**Issue**: Python scripts mix snake_case and kebab-case; inconsistent pattern

| Property | Details |
|----------|---------|
| **Files** | [scripts/](scripts/) (Python scripts) |
| **Severity** | 🟠 HIGH |
| **Current Patterns** | • `phase_20_global_orchestration.py` (snake_case)<br>• `phase13-load-test.py` (kebab-case)<br>• `git-proxy-server.py` (kebab-case)<br>• `stress-test-load.py` (kebab-case)<br>• `refactor-hardcoded-ips.py` (kebab-case) |
| **Standard** | Python convention is snake_case (PEP8), but shell uses kebab-case. Repo is mixed |
| **Impact** | • Inconsistent imports if scripts are used as modules<br>• IDE autocomplete confused<br>• Style guide violations |
| **Remediation** | 1. Decide on standard:<br>   Option A: All Python as `snake_case.py` (PEP8 compliant)<br>   Option B: All scripts as `kebab-case.sh/.py` (shell convention)<br>2. Recommend: **Use kebab-case for all scripts** (consistency across repo)<br>3. Rename files:<br>   `phase_20_global_orchestration.py` → `phase-20-global-orchestration.py` |
| **Effort** | 2-3 hours (rename + update imports) |
| **Priority** | P2 - Low impact but improves consistency |

---

## 2.3 GIT BRANCH NAMING — MEDIUM ISSUE

**Issue**: Inconsistent feature branch prefix (feat/ vs feature/)

| Property | Details |
|----------|---------|
| **Files** | Git branches (check with `git branch -a`) |
| **Severity** | 🟡 MEDIUM |
| **Current Patterns** | • `feat/357-opa-conftest-baseline` (short prefix)<br>• `feature/comprehensive-p1-p2-execution-april-16` (long prefix)<br>• `feature/p1-388-iam-implementation` (long prefix)<br>• `deploy/tier2-3-infrastructure-hardening` (deploy prefix)<br>• `docs/failover-runbook` (docs prefix) |
| **Standard** | Conventional Commits uses `feat:`, so Git branch should mirror: `feat/*` |
| **Impact** | • Inconsistent branch patterns make automation difficult<br>• CI/CD branch matching rules need special handling<br>• New developers confused about which prefix to use |
| **Remediation** | 1. Establish standard: `feat/*`, `fix/*`, `docs/*`, `chore/*`, `refactor/*`, `deploy/*`<br>2. Document in CONTRIBUTING.md<br>3. Add branch naming check to pre-commit hooks |
| **Effort** | 1 hour (document + add hook) |
| **Priority** | P3 - Enforce on new branches |

---

## 2.4 TERRAFORM VARIABLE NAMING — MEDIUM ISSUE

**Issue**: Terraform locals use UPPER_SNAKE_CASE (wrong convention); should be lower_snake_case

| Property | Details |
|----------|---------|
| **Files** | [main.tf](main.tf#L50) locals block |
| **Severity** | 🟡 MEDIUM |
| **Problem** | Terraform convention is: `variable` and `locals` use **lower_snake_case**, not UPPER_SNAKE_CASE. Current code has: |
| **Current Code** | ```hcl<br>locals {<br>  service_name = "code-server-enterprise"  # ✅ Correct<br>  versions = {<br>    code_server  = "4.115.0"  # ✅ Correct<br>  }<br>}``` |
| **Finding** | Actually, locals ARE using lower_snake_case correctly ✅. No issue found. |
| **Status** | ✅ PASS — Terraform naming already follows convention |
| **Effort** | 0 hours |

---

## 2.5 DOCKERFILE NAMING — MEDIUM ISSUE

**Issue**: Multiple Dockerfiles with non-standard naming

| Property | Details |
|----------|---------|
| **Files** | `Dockerfile.code-server`, `Dockerfile.caddy`, `Dockerfile.ssh-proxy`, `Dockerfile.token-microservice` |
| **Severity** | 🟡 MEDIUM |
| **Current Pattern** | `Dockerfile.<service-name>` (dot-separated) |
| **Standard** | Docker community standard is `Dockerfile.<TARGET>` (e.g., `Dockerfile.prod`) or separate directory per Dockerfile (e.g., `docker/code-server/Dockerfile`) |
| **Impact** | • Non-standard; tools may not recognize<br>• Difficult to manage 4+ Dockerfiles in root<br>• No clear relationship between Dockerfile and service |
| **Remediation** | Create docker/ subdirectory structure:<br>```<br>docker/<br>  code-server/Dockerfile<br>  caddy/Dockerfile<br>  ssh-proxy/Dockerfile<br>  token-microservice/Dockerfile<br>```<br>Update docker-compose.yml build contexts accordingly |
| **Effort** | 2-3 hours (move files, update references) |
| **Priority** | P3 - Organizational improvement |

---

## 2.6 MAKEFILE TARGETS — MEDIUM ISSUE

**Issue**: Makefile targets use inconsistent naming (snake_case, hyphen, abbreviations)

| Property | Details |
|----------|---------|
| **Files** | [Makefile](Makefile#L1) |
| **Severity** | 🟡 MEDIUM |
| **Current Patterns** | • `compose-up`, `compose-down` (hyphenated)<br>• `test_env` (underscore)<br>• `p` (abbreviation for `plan`)<br>• `setup_remote_access`, `grant_access` (snake_case)<br>• `validate-env`, `validate-oidc-issuer-phase2-1` (long hyphenated) |
| **Standard** | Makefile targets should use **kebab-case** for multi-word targets (shell convention) |
| **Impact** | • `make ssh-31` vs `make ssh_31` confusion<br>• Help text doesn't auto-discover abbreviated targets<br>• Inconsistent across repo |
| **Remediation** | 1. Convert all targets to kebab-case: `setup_remote_access` → `setup-remote-access`<br>2. Remove abbreviations or document them explicitly<br>3. Use `.PHONY` declarations at top |
| **Effort** | 2-3 hours (rename targets, update documentation) |
| **Priority** | P3 - Improve usability |

---

# DIMENSION 3: MONOREPO & PNPM VERIFICATION

## 3.1 DEPENDENCY DUPLICATION — HIGH ISSUE

**Issue**: Common dependencies duplicated across workspaces (typescript, vitest, @types packages)

| Property | Details |
|----------|---------|
| **Files** | Multiple `package.json`: backend, frontend, session-broker, extensions |
| **Severity** | 🟠 HIGH |
| **Problem** | Same dependencies declared in multiple packages instead of hoisted to root `package.json`. pnpm workspace supports hoisting to root (`node_modules` at workspace root), but repo doesn't use it |
| **Current State** | • **typescript**: appears in backend, frontend, agent-farm, ollama-chat, session-broker (5 copies)<br>• **@types packages**: duplicated across 4+ packages<br>• **vitest**: appears in backend, frontend (2 copies)<br>• **eslint**: duplicated |
| **Impact** | • Slower installation (5+ typescript downloads instead of 1)<br>• Disk space waste (~50MB per duplicate)<br>• Version conflicts if different versions pinned<br>• Difficult to upgrade consistently |
| **pnpm Lock Analysis** | pnpm-lock.yaml shows same versions installed per-package (good for reproducibility, bad for efficiency) |
| **Remediation** | 1. Move common dev dependencies to root `package.json`: typescript, vitest, eslint, prettier, @types<br>2. Update `pnpm-workspace.yaml` to use `shamefully-hoist: true` or list shared deps in `devDependencies`<br>3. Run `pnpm install --recursive --shamefully-hoist` |
| **Effort** | 3-4 hours (identify shared deps, move to root, test, rebuild) |
| **Priority** | P1 - Reduces install time and disk usage |

---

## 3.2 LOCKFILE VALIDATION — MEDIUM ISSUE

**Issue**: No lockfile validation in CI/CD; pnpm-lock.yaml could drift from package.json

| Property | Details |
|----------|---------|
| **Files** | [pnpm-lock.yaml](pnpm-lock.yaml#L1), [package.json](package.json#L1) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | No CI/CD check to ensure pnpm-lock.yaml matches package.json definitions. Manual changes to package.json without `pnpm install` would not be caught before merge |
| **Current** | Makefile has target `validate:lockfile` that runs `bash scripts/ci/check-pnpm-lockfile.sh`, but this only runs manually |
| **Missing** | • Pre-commit hook to validate lockfile<br>• GitHub Actions to block merge if lockfile invalid<br>• Documentation of lockfile requirements |
| **Impact** | • Stale lockfile merged, causing different installs on CI vs local<br>• Version mismatches in production<br>• Difficult to troubleshoot dependency issues |
| **Remediation** | 1. Add pre-commit hook: `pnpm install --frozen-lockfile`<br>2. Add GitHub Actions workflow step: `pnpm ci`<br>3. Document lockfile update process in CONTRIBUTING.md |
| **Effort** | 2-3 hours (add hooks, document, test) |
| **Priority** | P1 - Critical for reproducibility |

---

## 3.3 CIRCULAR DEPENDENCIES — MEDIUM ISSUE

**Issue**: No check for circular dependencies between packages

| Property | Details |
|----------|---------|
| **Files** | Multiple `package.json` in workspace |
| **Severity** | 🟡 MEDIUM |
| **Problem** | No linting or CI/CD check to prevent Package A depending on Package B which depends on Package A. This would cause import errors at runtime |
| **Current State** | Appears clean (manual review only), but no automated validation |
| **Risk Scenario** | 1. `apps/backend` imports `apps/session-broker`<br>2. Developer adds `apps/session-broker` → `apps/backend` import<br>3. No error caught until runtime<br>4. CI/CD fails late in process |
| **Remediation** | 1. Use `pnpm ls --depth=0` to view dependency graph<br>2. Add `circular-dependency-plugin` to webpack build<br>3. Add `depcheck` to find unused dependencies<br>4. Document allowed import directions (e.g., session-broker can only import from lib/, never from backend) |
| **Effort** | 2-3 hours (add tooling, document rules) |
| **Priority** | P2 - Implement as linting rule |

---

## 3.4 PACKAGE SCRIPT CONSISTENCY — MEDIUM ISSUE

**Issue**: Script naming inconsistent across packages

| Property | Details |
|----------|---------|
| **Files** | [apps/backend/package.json](apps/backend/package.json), [apps/frontend/package.json](apps/frontend/package.json), etc. |
| **Severity** | 🟡 MEDIUM |
| **Problem** | Different packages define different script names for same operations: |
| **Examples** | • **Test scripts**: backend uses `test`, frontend uses `test`+`test:watch`+`test:coverage` (more complete)<br>• **Build**: backend has NO build script (!), frontend has full build pipeline<br>• **Linting**: frontend has `lint`, backend has NO lint script<br>• **Type checking**: both have `type-check` (good consistency) |
| **Impact** | • `pnpm test` doesn't test all packages<br>• Developers unsure which script to run<br>• CI/CD can't use consistent `pnpm build` across workspace |
| **Backend Issue** | `apps/backend/package.json` is severely under-defined:<br>• No build script (how does backend compile TypeScript?)<br>• No lint script (no code quality checks)<br>• Only test, test:watch, test:coverage (test-only package?) |
| **Remediation** | 1. Define standard scripts for all packages:<br>   - `test`: run unit tests<br>   - `test:watch`: run tests in watch mode<br>   - `test:coverage`: generate coverage reports<br>   - `build`: compile/bundle package<br>   - `lint`: run linter<br>   - `type-check`: run TypeScript compiler<br>   - `dev`: start development server (if applicable)<br>2. Use `pnpm -r build` to build all packages in order<br>3. Document in CONTRIBUTING.md |
| **Effort** | 3-4 hours (define scripts, implement missing tooling) |
| **Priority** | P2 - Improves developer experience and CI/CD reliability |

---

## 3.5 PNPM WORKSPACE OPTIMIZATION — MEDIUM ISSUE

**Issue**: pnpm-workspace.yaml doesn't declare all workspace members properly

| Property | Details |
|----------|---------|
| **Files** | [pnpm-workspace.yaml](pnpm-workspace.yaml) |
| **Severity** | 🟡 MEDIUM |
| **Current Content** | ```yaml<br>packages:<br>  - apps/backend<br>  - apps/frontend<br>  - apps/extensions/*<br>onlyBuiltDependencies: [] ``` |
| **Finding** | Mostly correct, but missing documentation and optimization |
| **Issues** | • No `onlyBuiltDependencies` usage (good, but document why)<br>• No workspace-specific settings (shamefully-hoist, strict-peer-dependencies)<br>• No version resolution rules for monorepo consistency |
| **Remediation** | 1. Add workspace settings:<br>```yaml<br>  shamefully-hoist: false  # Document decision<br>  strict-peer-dependencies: true  # Prevent version conflicts<br>```<br>2. Add comment explaining package structure<br>3. Document where to add new packages |
| **Effort** | 1-2 hours (add settings, document) |
| **Priority** | P3 - Documentation improvement |

---

## 3.6 VERSION PINNING — MEDIUM ISSUE

**Issue**: pnpm-lock.yaml has floating versions for some dependencies

| Property | Details |
|----------|---------|
| **Files** | [pnpm-lock.yaml](pnpm-lock.yaml#L1) |
| **Severity** | 🟡 MEDIUM |
| **Finding** | pnpm-lock.yaml properly pins all versions (version lockfile exists). ✅ PASS |
| **However** | package.json files use caret (^) and tilde (~) ranges instead of exact versions:<br>• `"typescript": "^5.4.0"` (allows 5.x.x) |
| **Impact** | • `pnpm install --frozen-lockfile` prevents upgrades (good for CI)<br>• Local developer might run `pnpm update` and get newer versions<br>• Reproducibility depends on frozen-lockfile enforcement |
| **Remediation** | 1. Document in CONTRIBUTING.md: "Always use `pnpm install` not `pnpm add` for upgrades"<br>2. Use pre-commit hook to ensure no accidental updates<br>3. Document upgrade process: `pnpm update --latest` then `pnpm install` |
| **Effort** | 1 hour (document process) |
| **Priority** | P3 - Procedural enforcement |

---

# DIMENSION 4: NAS OPTIMIZATION

## 4.1 NAS CONFIGURATION MISMATCH — CRITICAL ISSUE

**Issue**: Multiple conflicting NAS host definitions across repo

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L20), [.env.example](.env.example#L81), [main.tf](main.tf#L95) |
| **Severity** | 🔴 CRITICAL |
| **Problem** | Three different NAS configurations in different files with no clear source of truth: |
| **nas-mount-31.sh** | ```bash<br>NAS_PRIMARY="192.168.168.10"<br>NAS_SECONDARY="192.168.168.11"<br>NAS_ARCHIVE="192.168.168.12"``` |
| **.env.example** | ```bash<br>NAS_HOST=192.168.168.56<br>NAS_EXPORT_PATH=/export``` |
| **main.tf locals** | ```hcl<br>nas_host = "192.168.168.56"<br>nas_export_path = "/export"``` |
| **Impact** | • Script tries to mount from .10/.11/.12, env vars say .56<br>• Terraform uses .56<br>• Which is production? Mounting from wrong host causes outages<br>• Operators cannot determine correct NAS IP |
| **Risk** | **CRITICAL**: Mounts fail silently if wrong NAS IP used, causing container failures |
| **Remediation** | 1. **Determine SSOT** (Single Source of Truth):<br>   - Verify which NAS IP is actually in production (likely 192.168.168.56)<br>   - Document architecture: is .56 primary? Are .10/.11/.12 old configs?<br>2. Update nas-mount-31.sh to use env var: `NAS_PRIMARY="${NAS_HOST:-192.168.168.56}"`<br>3. Delete/archive old mount config references<br>4. Add NAS configuration validation to pre-flight checks |
| **Effort** | 1-2 hours (verify production, update, test) |
| **Priority** | P0 - FIX IMMEDIATELY |

---

## 4.2 NAS REDUNDANCY STRATEGY — HIGH ISSUE

**Issue**: NAS configuration mentions 3 servers but no failover strategy documented

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L20-L30) |
| **Severity** | 🟠 HIGH |
| **Problem** | nas-mount-31.sh references: <br>• `NAS_PRIMARY` (192.168.168.10)<br>• `NAS_SECONDARY` (192.168.168.11)<br>• `NAS_ARCHIVE` (192.168.168.12)<br><br>But no documentation on: <br>• Which is primary? Which is backup?<br>• What happens if primary fails?<br>• Are these synced/replicated?<br>• RAID configured?<br>• Failover is manual or automatic? |
| **Current Script** | Mounts all 3 but doesn't explain fail-over strategy |
| **Impact** | • If primary fails, unclear how to failover<br>• Data loss risk if no replication<br>• No documented SLA<br>• Disaster recovery unclear |
| **Remediation** | 1. Document NAS topology in [docs/NAS-ARCHITECTURE.md](docs/):<br>   - Primary/Secondary/Archive roles<br>   - Replication/RAID setup<br>   - Failover procedure (manual? automatic?)<br>   - RTO/RPO targets<br>2. Update nas-mount-31.sh to implement failover logic:<br>   ```bash<br>   if ping -c 1 $NAS_PRIMARY; then<br>     mount $NAS_PRIMARY<br>   elif ping -c 1 $NAS_SECONDARY; then<br>     log_warn "Primary NAS down, using secondary"<br>     mount $NAS_SECONDARY<br>   else<br>     log_fatal "All NAS servers unreachable"<br>   fi``` |
| **Effort** | 3-4 hours (document architecture, implement failover) |
| **Priority** | P1 - Critical for high availability |

---

## 4.3 NAS STORAGE CAPACITY MONITORING — HIGH ISSUE

**Issue**: No monitoring or alerting for NAS disk usage

| Property | Details |
|----------|---------|
| **Files** | Prometheus/Grafana config (check if NAS metrics exported) |
| **Severity** | 🟠 HIGH |
| **Problem** | No alerts configured for NAS storage depletion. If NAS fills up: <br>• Container deployments fail (no space for volumes)<br>• Database replication fails<br>• Model downloads for Ollama fail<br>• Workspace backups fail |
| **Current Exports** | `.env.example` references NAS paths but no monitoring:<br>```<br>/export/code-server/workspace<br>/export/code-server/profile<br>/export/ollama<br>/export/postgres/backups``` |
| **Storage Used** | Unknown (no baseline metrics) |
| **Remediation** | 1. Export NAS metrics to Prometheus:<br>   - Use `node_exporter` on NAS or host<br>   - Expose `node_filesystem_size_bytes` and `node_filesystem_free_bytes`<br>   - Scrape every 30s<br>2. Create Grafana dashboard showing:<br>   - Workspace volume % used<br>   - Ollama volume % used<br>   - Backup volume % used<br>   - Free space trend<br>3. Configure Prometheus alert rules:<br>   - Alert at 80% capacity<br>   - Critical alert at 95% capacity |
| **Effort** | 4-5 hours (setup monitoring, create dashboards, alerts) |
| **Priority** | P1 - Prevent outages |

---

## 4.4 MOUNT OPTIONS & PERMISSIONS — MEDIUM ISSUE

**Issue**: NAS mount options use different protocols (nfs4, nfs3) without documented rationale

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L35) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | nas-mount-31.sh uses mixed protocols:<br>```bash<br>models:...:/mnt/models:nfs4<br>data:...:/mnt/data:nfs4<br>backups:...:/mnt/backups:nfs3  # Why nfs3 for backups?<br>archive:...:/mnt/archive:nfs4``` |
| **Impact** | • NFSv3 is older, fewer security features (no Kerberos)<br>• Performance differences between NFS versions<br>• Inconsistent permission handling<br>• Difficult to audit access |
| **Remediation** | 1. Document why each mount uses its protocol (if intentional)<br>2. Recommend: Standardize on **NFSv4 with Kerberos** for all mounts<br>3. If NFSv3 required for backup interop, document limitation<br>4. Add mount options for security:<br>   ```bash<br>   mount -t nfs4 -o rw,hard,intr,vers=4.1,sec=krb5,timeo=60<br>   ``` |
| **Effort** | 2-3 hours (document, standardize) |
| **Priority** | P2 - Security hardening |

---

## 4.5 NAS BACKUP RETENTION POLICY — MEDIUM ISSUE

**Issue**: No documented backup retention or cleanup strategy

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L1), `.env.example` |
| **Severity** | 🟡 MEDIUM |
| **Problem** | NAS has `/export/postgres/backups` mount but no documented: <br>• How often backups run<br>• How many versions retained<br>• When old backups are purged<br>• Backup verification process<br>• Recovery time objective (RTO) |
| **Risk** | Backups accumulate indefinitely, filling NAS. Or older backups deleted without notice, breaking recovery |
| **Remediation** | 1. Document backup policy:<br>   - Frequency: Daily at 2 AM UTC<br>   - Retention: 30 days full, 7 days incremental<br>   - Verification: Weekly test restore<br>   - RTO: 1 hour for full restore, 15 min for point-in-time<br>2. Implement retention script:<br>   ```bash<br>   find /mnt/backups -name "postgres-*.sql" -mtime +30 -delete<br>   ```<br>3. Add Prometheus metric: `backup_age_days`<br>4. Add alert if backup > 24h old |
| **Effort** | 3-4 hours (document policy, implement, test restore) |
| **Priority** | P1 - Critical for disaster recovery |

---

## 4.6 NAS PERFORMANCE OPTIMIZATION — MEDIUM ISSUE

**Issue**: No caching or read-ahead strategy documented for NAS

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L1) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | NAS mounts used directly without: <br>• Local caching layer (e.g., bcache, LVM)<br>• Mount options tuned for performance (rsize, wsize, timeo)<br>• Documentation of latency expectations |
| **Example Scenario** | Workspace volume is on NAS. User edits file → NFS sync → 50ms latency each time |
| **Impact** | • Slow file operations in code-server<br>• Slow docker image pulls<br>• Database replication lag if postgres-data on NAS |
| **Remediation** | 1. Measure current NAS latency:<br>   ```bash<br>   time ls -la /mnt/data | wc -l<br>   ```<br>2. Optimize mount options:<br>   ```bash<br>   mount -o rw,hard,timeo=600,retrans=2,rsize=65536,wsize=65536<br>   ```<br>3. Consider local SSD cache for frequently accessed data:<br>   - Workspace volume: Use local SSD for profile, NAS for backups only<br>   - Ollama cache: Use local SSD for models<br>4. Document NAS latency SLA |
| **Effort** | 4-5 hours (measure, tune, benchmark, document) |
| **Priority** | P2 - Performance enhancement |

---

## 4.7 NAS ACCESS CONTROL — MEDIUM ISSUE

**Issue**: No documented access control or audit logging for NAS

| Property | Details |
|----------|---------|
| **Files** | [scripts/nas-mount-31.sh](scripts/nas-mount-31.sh#L1) (mount logic only) |
| **Severity** | 🟡 MEDIUM |
| **Problem** | NAS mounts use default permissions. No documented: <br>• Who can access which NAS export<br>• Audit logging (who accessed backups?)<br>• Encryption in transit (NFS is unencrypted by default)<br>• Regular access reviews |
| **Impact** | • Compliance violations (PII on NAS not protected)<br>• Audit trail missing for backups<br>• Unauthorized access possible (NFS has no authentication)<br>• Data exposure risk |
| **Remediation** | 1. Enable Kerberos authentication for NAS mounts (see 4.4)<br>2. Configure NAS export permissions:<br>   ```<br>   /export/backups 192.168.168.31(rw,no_root_squash,sec=krb5)<br>   /export/models 192.168.168.31(rw,no_root_squash,sec=krb5)<br>   ```<br>3. Enable audit logging on NAS (NFS ACL logs)<br>4. Document access control policy in [docs/NAS-SECURITY.md](docs/) |
| **Effort** | 3-4 hours (configure auth, document policy, audit) |
| **Priority** | P2 - Compliance requirement |

---

# SUMMARY TABLE: REMEDIATION ROADMAP

| Issue | Severity | Effort | Priority | Owner | Deadline |
|-------|----------|--------|----------|-------|----------|
| **No Terraform backend state** | 🔴 CRITICAL | 4-6h | P0 | DevOps | Immediate |
| **NAS config mismatch** | 🔴 CRITICAL | 1-2h | P0 | DevOps | Immediate |
| **Image immutability** | 🟠 HIGH | 6-8h | P1 | DevOps | Phase 2 |
| **Variable validation gaps** | 🟠 HIGH | 3-4h | P1 | DevOps | Phase 1 |
| **Shell script naming** | 🟠 HIGH | 4-5h | P2 | DevOps | Sprint 5 |
| **Python script naming** | 🟠 HIGH | 2-3h | P2 | DevOps | Sprint 5 |
| **Dependency duplication** | 🟠 HIGH | 3-4h | P1 | Frontend | Phase 1 |
| **NAS redundancy/failover** | 🟠 HIGH | 3-4h | P1 | DevOps | Phase 2 |
| **NAS monitoring** | 🟠 HIGH | 4-5h | P1 | DevOps | Phase 2 |
| **Git branch naming** | 🟡 MEDIUM | 1h | P3 | DevOps | Sprint 4 |
| **Dockerfile organization** | 🟡 MEDIUM | 2-3h | P3 | DevOps | Sprint 5 |
| **Makefile target naming** | 🟡 MEDIUM | 2-3h | P3 | DevOps | Sprint 5 |
| **Lockfile validation** | 🟡 MEDIUM | 2-3h | P1 | Frontend | Phase 1 |
| **Circular dep detection** | 🟡 MEDIUM | 2-3h | P2 | Frontend | Sprint 4 |
| **Package script consistency** | 🟡 MEDIUM | 3-4h | P2 | Frontend | Phase 2 |
| **Idempotency (docker-compose)** | 🟡 MEDIUM | 4-5h | P2 | DevOps | Phase 2 |
| **Error handling/rollback** | 🟡 MEDIUM | 5-7h | P2 | DevOps | Phase 2 |
| **NAS mount options** | 🟡 MEDIUM | 2-3h | P2 | DevOps | Phase 2 |
| **NAS backup policy** | 🟡 MEDIUM | 3-4h | P1 | DevOps | Phase 2 |
| **NAS performance** | 🟡 MEDIUM | 4-5h | P2 | DevOps | Phase 3 |
| **NAS access control** | 🟡 MEDIUM | 3-4h | P2 | DevOps | Phase 2 |
| **Terraform module refactor** | 🟡 MEDIUM | 8-12h | P2 | DevOps | Phase 14+ |
| **Testing & validation pipeline** | 🟡 MEDIUM | 6-8h | P2 | DevOps | Phase 2 |
| **PNPM workspace optimization** | 🟡 MEDIUM | 1-2h | P3 | Frontend | Sprint 4 |
| **Version pinning docs** | 🟡 MEDIUM | 1h | P3 | Frontend | Sprint 3 |
| **Kubernetes IaC** | 🟢 LOW | N/A | Future | DevOps | Phase 20+ |

---

# QUICK WINS (Can be done in 1-2 hours)

1. **Document NAS architecture** (30 min) — create docs/NAS-ARCHITECTURE.md
2. **Add branch naming hook** (30 min) — .pre-commit-config.yaml
3. **Document PNPM workspace** (30 min) — add comments to pnpm-workspace.yaml
4. **List Python scripts** and plan rename (30 min) — create scripts/rename-plan.txt
5. **Create Terraform backend.tf stub** (30 min) — add state backend template

---

# REFERENCES

- Terraform Best Practices: https://www.terraform.io/docs/cloud/state
- Conventional Commits: https://www.conventionalcommits.org/
- PNPM Workspaces: https://pnpm.io/workspaces
- NFS Security: https://linux-nfs.org/wiki/index.php/Main_Page
- Shell Style Guide: https://google.github.io/styleguide/shellstyle.html

---

**Report Generated**: April 19, 2026  
**Next Review**: After Phase 2 completion (target: May 31, 2026)
