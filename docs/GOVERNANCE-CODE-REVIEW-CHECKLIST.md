# Code Governance Review Checklist

Use this checklist during code review to ensure all governance standards are met.

## ✅ Shell Script Review

- [ ] **Header metadata present**
  - Includes `@file:` describing the script
  - Includes `@description:` (2-3 sentences)
  - Includes `@module:` (logical namespace)

- [ ] **Strict mode enabled**
  - `set -euo pipefail` present early in script
  - `IFS=$'\n\t'` configured if needed

- [ ] **No hardcoded values**
  - IPs use `${PROD_HOST}`, `${REPLICA_HOST}`, or env variables
  - Ports use `${SERVICE_PORT}`, `${POSTGRES_PORT}`, etc.
  - Credentials use `${SECRET_NAME}` from .env or Vault
  - Paths use `${SCRIPT_DIR}` or relative paths

- [ ] **Error handling**
  - All external commands protected by error handlers
  - `set -e` ensures failures exit script
  - No silent failures (exit codes always indicate status)

- [ ] **Logging**
  - Uses `log_info`, `log_error`, `log_warn` from `_common/logging.sh`
  - No raw `echo` or `printf` for operational output
  - Structured log messages (what/why/action)

- [ ] **Exit codes documented**
  - Comment block explains expected exit codes
  - 0 = success; non-zero = failure
  - Specific codes for different failure modes if applicable

- [ ] **ShellCheck passes**
  - Run locally: `shellcheck -S warning myscript.sh`
  - No HIGH severity issues
  - OK to suppress specific checks with `# shellcheck disable=SC...` if justified

## ✅ Docker & Container Review

- [ ] **Image base is pinned**
  - `FROM ubuntu:22.04` (not `ubuntu:latest`)
  - `FROM golang:1.21-alpine` (not `golang:latest`)
  - Build args parameterized: `ARG VERSION=1.2.3`

- [ ] **No secrets in layers**
  - No `RUN echo $SECRET` commands
  - No credentials hardcoded in Dockerfile
  - Build secrets use `--mount=type=secret`

- [ ] **Multi-stage build (if applicable)**
  - `FROM ... AS builder` for intermediate stages
  - Final image is lean (no build tools in production)

- [ ] **Scanned for vulnerabilities**
  - Trivy reports 0 HIGH/CRITICAL CVEs
  - Run: `trivy image myimage:tag`

## ✅ Configuration File Review (YAML/JSON/TOML)

- [ ] **No hardcoded secrets**
  - Gitleaks passes (no secret patterns)
  - Credentials are `${VAR}` references
  - Run: `gitleaks detect --source .`

- [ ] **Parameterized values**
  - Ports/hosts/domains use `${VAR}` syntax
  - Comments explain each variable
  - Defaults documented

- [ ] **Proper formatting**
  - YAMLLint passes: `yamllint -d default config.yml`
  - JSON valid: `jq . config.json > /dev/null`
  - TOML parseable

- [ ] **Immutable versions**
  - Docker image tags are explicit (not `latest`)
  - Dependency versions pinned
  - Kubernetes manifests use specific image SHAs

## ✅ Terraform Review

- [ ] **Provider versions pinned**
  - `required_version = ">= 1.0, < 2.0"`
  - Each provider specifies version constraints
  - No `~>` without upper bound

- [ ] **Input validation**
  - All `variable` blocks have `validation` rules
  - Type constraints specified
  - Descriptions clear

- [ ] **Sensitive values marked**
  - Passwords/tokens have `sensitive = true`
  - Output filtering configured

- [ ] **Code formatted**
  - `terraform fmt -recursive .` passes
  - Spacing consistent

- [ ] **TFSec passes**
  - No HIGH/CRITICAL security issues
  - Run: `tfsec terraform/`

## ✅ GitHub Workflow Review

- [ ] **No hardcoded secrets**
  - Uses GitHub Secrets (org or repo level)
  - No credentials in workflow YAML
  - Run: `gitleaks detect --source .`

- [ ] **Reusable patterns extracted**
  - Common build/test steps in `.github/workflows/_shared/`
  - No duplicate step definitions

- [ ] **Idempotent**
  - Safe to re-run workflow multiple times
  - No side effects from double execution
  - Handles existing resources gracefully

- [ ] **Timeout boundaries set**
  - `timeout-minutes: 30` on long jobs
  - Individual step timeouts for external calls

- [ ] **Clear success criteria**
  - Workflow name describes what it does
  - Job names are self-explanatory
  - README or comment explains expected outputs

## ✅ Code Duplication Review

- [ ] **No duplicated logic blocks**
  - Functions extracted for repeated patterns
  - Common code moved to shared modules
  - jscpd duplication < 5%

- [ ] **Dead code removed**
  - knip shows < 2% unused code
  - Deprecated functions marked with header
  - Clear removal date if legacy

- [ ] **DRY (Don't Repeat Yourself)**
  - Similar scripts consolidated
  - Configuration shared via includes/templates
  - Avoid copy-paste patterns

## ✅ General Code Quality

- [ ] **Comments explain why, not what**
  - "Why does this retry?" not "This retries"
  - Complex logic has comments
  - Comments kept current with code

- [ ] **Error messages are helpful**
  - Include context (what failed, why, what to do)
  - Not cryptic error codes
  - Guide operators toward resolution

- [ ] **Logging is structured**
  - Correlation IDs included (if applicable)
  - Timestamps from logging framework, not hardcoded
  - Severity levels (INFO, WARN, ERROR, DEBUG) correct

- [ ] **Backwards compatible**
  - No breaking changes to CLI args
  - Config file changes additive (not removing fields)
  - Migration path documented if needed

- [ ] **Performance acceptable**
  - No obvious N+1 queries
  - No unnecessary loops or recursion
  - Timeout/retry logic for external calls

## ✅ Operational Review

- [ ] **Runbook updated**
  - Deployment procedure documented
  - Troubleshooting section includes this change
  - Rollback procedure clear

- [ ] **Alerting configured (if applicable)**
  - New metrics have associated alerts
  - Alert thresholds documented
  - Escalation path clear

- [ ] **Monitoring dashboards updated**
  - Metrics are visible post-deployment
  - Useful for on-call debugging
  - Links to runbook included

- [ ] **Feature flag present (if needed)**
  - New functionality can be disabled without code rollback
  - Gradual rollout strategy documented
  - Kill switch is obvious

## 🚩 Red Flags (Block Merge If Present)

- ❌ Hardcoded credentials, API keys, or tokens
- ❌ Base images with `latest` tag
- ❌ `set -e` missing in shell scripts
- ❌ Error handling with `|| true` (silencing failures)
- ❌ Hardcoded IP addresses without parameterization
- ❌ gitleaks/TFSec/Checkov failures
- ❌ No exit code documentation in shell scripts
- ❌ Duplicate code that should be extracted
- ❌ No test coverage for new functionality
- ❌ Breaking changes without migration path

## ⚠️ Yellow Flags (Discuss Before Merge)

- ⚠️ New script without header metadata
- ⚠️ YAMLLint warnings (non-blocking but recommend fixing)
- ⚠️ Code duplication < 10% (watch, extract if pattern repeats)
- ⚠️ ShellCheck warnings (can suppress with `# shellcheck disable=...` if justified)
- ⚠️ Complex logic without comments
- ⚠️ No tests added for new code paths
- ⚠️ Runbook not updated
- ⚠️ Deprecation period for old code not documented

## 🟢 Approved (Ready to Merge)

- ✅ All governance standards met
- ✅ Red flags resolved
- ✅ Yellow flags discussed and approved (with comments if overridden)
- ✅ Tests passing (unit + integration)
- ✅ Security scans clean
- ✅ Code review approval from 1+ engineer
- ✅ Ready for production deployment

---

**Quick Links**:
- [CODE-GOVERNANCE-FRAMEWORK.md](./CODE-GOVERNANCE-FRAMEWORK.md) - Full policy
- [GOVERNANCE-WAIVERS-AND-DEBT.md](./GOVERNANCE-WAIVERS-AND-DEBT.md) - Approved exceptions
- [SHELL-SCRIPT-TEMPLATE.sh](../scripts/_templates/SHELL-SCRIPT-TEMPLATE.sh) - Script boilerplate

**For Questions**: Ask in #eng-infrastructure or @architecture-team
