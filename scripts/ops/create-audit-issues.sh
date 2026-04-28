#!/usr/bin/env bash
# @description Manually trigger issue creation for audited problems
# Requires GITHUB_TOKEN to be set in environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="kushin77/code-server"

create_issue() {
  local title="$1"
  local body="$2"
  local priority="$3"
  
  log_info "Creating issue: $title..."
  
  local labels="[\"audit-finding\", \"$priority\", \"automated\"]"
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "body": sys.argv[2], "labels": json.loads(sys.argv[3])}))' "$title" "$body" "$labels")
  
  github_api_call POST "/repos/$REPO/issues" "$payload" || log_error "Failed to create issue: $title"
}

# Issue 1: Replica Host
create_issue "[INFRA] Replica Host (192.168.168.32) Connection Timeout" \
"The replica host `192.168.168.32` is currently unreachable via SSH (Port 22 timeout). This prevents cluster-wide operations and failover validation.

**Evidence:**
- Reported in [CLUSTER-SHUTDOWN-REPORT-2026-04-27.md](https://github.com/$REPO/blob/main/CLUSTER-SHUTDOWN-REPORT-2026-04-27.md)

**Suggested Action:**
- Verify host power status.
- Check firewall/security group rules." "P1"

# Issue 2: Script Hardening
create_issue "[DEBT] Engineering Hardening: 74+ Scripts Missing Trap Handlers" \
"Approximately 74 operational and deployment scripts lack structured error handling (trap handlers). This can lead to silent failures and partial state corruption.

**Evidence:**
- Reported in [PHASE2-ERROR-HANDLING-SUMMARY.md](https://github.com/$REPO/blob/main/artifacts/PHASE2-ERROR-HANDLING-SUMMARY.md)

**Suggested Action:**
- Implement `trap` handlers across identified scripts." "P2"

# Issue 3: Terraform Upgrade
create_issue "[IAC] Terraform Version Outdated (v1.8.0 vs v1.14.9)" \
"The local environment is using Terraform `v1.8.0`. The latest stable version is `v1.14.9`.

**Suggested Action:**
- Upgrade Terraform and verify provider compatibility." "P3"

# Issue 4: Tools Missing
create_issue "[OPS] Missing Runtime Tooling: Docker and Kubectl" \
"Core deployment tools (`docker` and `kubectl`) are missing or not in the system PATH. This prevents troubleshooting and manual intervention.

**Suggested Action:**
- Install `docker.io` and `kubectl` binaries." "P1"

# Issue 5: Service Readiness
create_issue "[OPS] Service Readiness Timeouts During E2E Testing" \
"E2E and load testing sequences encounter intermittent service readiness timeouts and \"Failed to start services\" errors.

**Evidence:**
- Reported in [test-e2e-load.sh](https://github.com/$REPO/blob/main/scripts/test-e2e-load.sh#L111)
- Affects database and message broker initialization

**Suggested Action:**
- Implement exponential backoff retry logic
- Extend readiness probe timeouts
- Add container health check logging" "P1"

# Issue 6: App Errors
create_issue "[APP] Activity Feed & Agent Runtime: Recurring WebSocket/Ingest Errors" \
"Static analysis reveals recurring \`WebSocket error\`, \`Ingest error\`, and \`Execution error\` patterns.

**Evidence:**
- Code paths in \`apps/activity_feed/main.py\` and \`apps/agent-runtime/main.py\`.

**Suggested Action:**
- Implement robust reconnection logic and enhance telemetry." "P2"

# Issue 7: CI/CD Enforcement
create_issue "[CI] Error Handling Lint Check Failures in Strict Mode" \
"The CI/CD pipeline's error handling lint check fails when running in strict mode, indicating many scripts do not meet repository hardening standards.

**Evidence:**
- Identified in [scripts/ci/lint-error-handling.sh](https://github.com/$REPO/blob/main/scripts/ci/lint-error-handling.sh)
- Only 10/65+ operational scripts have proper error traps

**Suggested Action:**
- Phase 2: Add trap handlers to remaining 55+ scripts
- Integrate linting into pre-commit hooks
- Create automated remediation where possible" "P2"

# Issue 8: Documentation Gaps
create_issue "[DOCS] Missing Service Health Monitoring & Init Container Documentation" \
"Critical operational documentation is missing for:
- Service health monitoring strategy
- Init container deployment patterns
- Troubleshooting procedures for common failures

**Evidence:**
- TODOs in [CODE_REVIEW_CONTAINER_DEPLOYMENT.md](https://github.com/$REPO/blob/main/CODE_REVIEW_CONTAINER_DEPLOYMENT.md)

**Suggested Action:**
- Create health-check.md operational guide
- Document init container lifecycle
- Add runbooks for common failure scenarios" "P2"

# Issue 9: Environment Configuration SSOT
create_issue "[CONFIG] Environment Variable SSOT Consolidation Incomplete" \
"Environment variables are sourced from multiple locations (terraform, docker-compose, shell scripts), violating DRY principles and causing deployment drift.

**Evidence:**
- Identified in [AUDIT_REMEDIATION_PLAN.md](https://github.com/$REPO/blob/main/AUDIT_REMEDIATION_PLAN.md)
- Partially addressed in Phase 1 via [scripts/_common/config.env](https://github.com/$REPO/blob/main/scripts/_common/config.env)

**Suggested Action:**
- Consolidate remaining env sources to single config.env
- Create environment profile system (dev/staging/prod)
- Validate consistency in CI/CD pipeline" "P2"

# Issue 10: Docker Compose Consolidation
create_issue "[IaC] Docker Compose File Consolidation Strategy" \
"Multiple docker-compose files exist (~20+) without clear consolidation strategy, causing duplication and maintenance burden.

**Files:**
- docker-compose.yml (base)
- docker-compose.enterprise.yml
- docker-compose.override.yml
- docker-compose.redpanda.yml
- Plus environment-specific variants

**Suggested Action:**
- Consolidate using compose override patterns
- Define clear compose file hierarchy
- Create environment-specific compose profiles" "P2"

# Issue 11: Terraform Configuration Context
create_issue "[IAC] Terraform Configuration Missing Root Context" \
"Running \`terraform plan\` from root directory fails with \"No configuration files\" error, requiring manual context switching.

**Evidence:**
- IaC split across [terraform/environments/private/](https://github.com/$REPO/tree/main/terraform/environments/private/) and other subdirectories
- No root-level terraform wrapper or orchestration

**Suggested Action:**
- Create terraform wrapper script with auto-context detection
- Document environment-specific deployment procedures
- Add makefile targets for common terraform operations" "P2"

# Issue 12: Dependency Vulnerability Management
create_issue "[SEC] NPM Dependency Vulnerabilities: Ongoing Remediation" \
"At least 6 NPM/yarn vulnerabilities have been identified in recent commits. Remediation scripts exist but require execution.

**Evidence:**
- Commit [bf54fc59](https://github.com/$REPO/commit/bf54fc59): Fix all 6 vulnerabilities
- Commit [768b058d](https://github.com/$REPO/commit/768b058d): Add vulnerability overrides

**Suggested Action:**
- Complete npm audit remediation
- Integrate supply-chain security scanning in CI/CD
- Set up automated dependency upgrade workflows (Dependabot)" "P1"

# Issue 13: Infrastructure Parity Testing
create_issue "[INFRA] Primary-Replica Cluster Parity Validation Missing" \
"The cluster lacks automated validation to ensure configuration parity between primary (192.168.168.31) and replica (192.168.168.32) hosts.

**Impact:**
- Prevents consistent failover validation
- Configuration drift undetected
- Stale documentation causing deployment errors

**Suggested Action:**
- Create cluster parity validation script
- Implement configuration drift detection
- Add automated nightly parity tests" "P1"

# Issue 14: Technical Debt: Code Duplication
create_issue "[DEBT] Historical Code Duplication: App Directory Consolidation" \
"Recent audit found high-severity duplication in app directories (apps/reputation-engine vs apps/reputation_engine, apps/edge_agent).

**Evidence:**
- Fixed in commit [e9c9236e](https://github.com/$REPO/commit/e9c9236e)
- Indicates potential for similar issues in other module directories

**Suggested Action:**
- Audit remaining app directories for naming inconsistencies
- Run comprehensive deduplication analysis
- Implement automated deduplication checks in CI/CD" "P2"

# Issue 15: Kubernetes Migration Readiness
create_issue "[K8S] Kubernetes Migration Phase 14: Runtime Validation Blocked by Missing Tools" \
"K8s migration is in Phase 14, but validation cannot proceed due to missing \`kubectl\` binary and incomplete documentation.

**Evidence:**
- kubectl not installed locally
- Phase 14 completion status unclear without pod inspection capability

**Suggested Action:**
- Install kubectl and kubeconfig management
- Create K8s migration readiness checklist
- Document phase transition criteria and blockers" "P2"

log_info "All comprehensive audit issues queued for creation."
