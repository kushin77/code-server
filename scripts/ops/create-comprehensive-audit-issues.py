#!/usr/bin/env python3
"""
Comprehensive GitHub Issue Creator for Audit Findings
Creates detailed issues for all identified errors, problems, and technical debt.
Requires GITHUB_TOKEN environment variable to be set.
"""

import os
import sys
import json
import requests
from typing import List, Tuple
from datetime import datetime

# Configuration
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
GITHUB_REPO = os.environ.get("GITHUB_REPO", "kushin77/code-server")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
GITHUB_API_URL = "https://api.github.com"

class GitHubIssueCreator:
    """Creates GitHub issues with validation and error handling"""
    
    def __init__(self, token: str, repo: str):
        self.token = token
        self.repo = repo
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"token {token}",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "Audit-Issue-Creator"
        })
        self.created_issues = []
        self.failed_issues = []
        
    def validate_token(self) -> bool:
        """Validate GitHub token"""
        try:
            response = self.session.get(f"{GITHUB_API_URL}/user")
            return response.status_code == 200
        except Exception as e:
            print(f"❌ Token validation failed: {e}")
            return False
    
    def create_issue(self, title: str, body: str, labels: List[str], 
                    assignees: List[str] = None) -> bool:
        """Create a GitHub issue"""
        if not assignees:
            assignees = []
        
        payload = {
            "title": title,
            "body": body,
            "labels": labels,
            "assignees": assignees
        }
        
        if DRY_RUN:
            print(f"\n📋 [DRY RUN] Would create issue:")
            print(f"   Title: {title}")
            print(f"   Labels: {', '.join(labels)}")
            return True
        
        try:
            response = self.session.post(
                f"{GITHUB_API_URL}/repos/{self.repo}/issues",
                json=payload
            )
            
            if response.status_code == 201:
                issue_data = response.json()
                issue_num = issue_data["number"]
                issue_url = issue_data["html_url"]
                print(f"✅ Created issue #{issue_num}: {title}")
                print(f"   URL: {issue_url}")
                self.created_issues.append((issue_num, title))
                return True
            else:
                error_msg = response.json().get("message", f"Status {response.status_code}")
                print(f"❌ Failed to create issue: {title}")
                print(f"   Error: {error_msg}")
                self.failed_issues.append((title, error_msg))
                return False
        except Exception as e:
            print(f"❌ Exception creating issue: {title}")
            print(f"   Error: {e}")
            self.failed_issues.append((title, str(e)))
            return False
    
    def print_summary(self):
        """Print creation summary"""
        print("\n" + "="*70)
        print(f"AUDIT ISSUES CREATION SUMMARY - {datetime.now().isoformat()}")
        print("="*70)
        print(f"✅ Successfully created: {len(self.created_issues)} issues")
        for issue_num, title in self.created_issues:
            print(f"   - #{issue_num}: {title}")
        
        if self.failed_issues:
            print(f"\n❌ Failed to create: {len(self.failed_issues)} issues")
            for title, error in self.failed_issues:
                print(f"   - {title}")
                print(f"     {error}")


def main():
    """Main entry point"""
    
    if not GITHUB_TOKEN and not DRY_RUN:
        print("❌ GITHUB_TOKEN environment variable not set")
        print("\nTo create issues, set the token:")
        print("  export GITHUB_TOKEN='your_token_here'")
        print("  python3 scripts/ops/create-comprehensive-audit-issues.py")
        print("\nOr preview issues in DRY_RUN mode:")
        print("  DRY_RUN=true python3 scripts/ops/create-comprehensive-audit-issues.py")
        sys.exit(1)
    
    if DRY_RUN:
        print("🧪 DRY RUN MODE - Issues will NOT be created")
        print(f"   Would create issues in repo: {GITHUB_REPO}\n")
    
    creator = GitHubIssueCreator(GITHUB_TOKEN, GITHUB_REPO)
    
    if not DRY_RUN:
        print(f"🔐 Using GitHub token for repo: {GITHUB_REPO}")
        if not creator.validate_token():
            print("❌ Invalid GitHub token or API unavailable")
            sys.exit(1)
        print("✅ Authentication successful\n")
    else:
        print()
    
    # Define all audit issues
    issues = [
        # ===== CRITICAL: INFRASTRUCTURE & CONNECTIVITY =====
        (
            "[INFRA] Replica Host (192.168.168.32) Connection Timeout",
            """The replica host `192.168.168.32` is currently unreachable via SSH (Port 22 timeout). This prevents cluster-wide operations and failover validation.

## Problem
- SSH connection times out attempting to connect to replica host
- Cluster shutdown report shows replica status as "Not accessible"
- Prevents deployment and health checks on replica infrastructure

## Evidence
- [CLUSTER-SHUTDOWN-REPORT-2026-04-27.md](CLUSTER-SHUTDOWN-REPORT-2026-04-27.md) - Primary host shutdown successful, replica "not accessible"
- Last successful connection unknown; network connectivity suspected

## Impact
- Cannot execute failover procedures
- Cluster resilience posture unknown
- Infrastructure audit incomplete

## Suggested Action
1. Verify host power status and network connectivity
2. Check firewall/security group rules for SSH (port 22)
3. Verify SSH key deployment on replica host
4. If host is decommissioned, update infrastructure documentation
5. Establish out-of-band connectivity verification""",
            ["P1", "audit-finding", "infrastructure", "automated"]
        ),
        
        # ===== CRITICAL: RUNTIME TOOLING =====
        (
            "[OPS] Missing Runtime Tooling: Docker and Kubectl",
            """Core deployment tools (`docker` and `kubectl`) are missing or not in the system PATH. This prevents troubleshooting, container inspection, and cluster management.

## Problem
- `docker` command not found; Docker is not installed
- `kubectl` command not found; Kubernetes CLI not available
- Prevents live container status verification
- Blocks Kubernetes Phase 14 completion and validation

## Evidence
- Command `docker ps -a` exits with code 127 (command not found)
- Command `kubectl get pods -A` exits with code 127 (command not found)

## Impact
- Cannot troubleshoot runtime failures
- Cannot view container logs or resource usage
- Cannot manage or inspect Kubernetes cluster
- Deployment and incident response significantly delayed

## Suggested Action
1. Install Docker: `sudo apt install docker.io`
2. Install Kubectl: `sudo snap install kubectl`
3. Verify installations: `docker --version && kubectl version`
4. Add user to docker group if needed: `sudo usermod -aG docker $USER`""",
            ["P1", "audit-finding", "operations", "automated"]
        ),
        
        # ===== CRITICAL: SECURITY =====
        (
            "[SEC] NPM Dependency Vulnerabilities: Ongoing Remediation",
            """At least 6 NPM/yarn vulnerabilities have been identified. Remediation scripts exist but require execution and ongoing monitoring.

## Problem
- Recent commits show fixing 6 identified vulnerabilities
- Overrides were added but root cause remediation incomplete
- No supply-chain security scanning in CI/CD
- No automated dependency upgrade process

## Evidence
- Commit bf54fc59: "Fix all 6 vulnerabilities"
- Commit 768b058d: "Add vulnerability overrides"
- pnpm-lock.yaml contains override configurations

## Impact
- Production runtime exposed to known vulnerabilities
- Supply chain attack surface unmitigated
- Compliance violations (depends on org requirements)

## Suggested Action
1. Complete npm audit remediation: `npm audit fix`
2. Integrate SAST scanning (npm audit) in CI/CD pipeline
3. Set up Dependabot for automated dependency updates
4. Create vulnerability disclosure process
5. Add CVE tracking dashboard to monitoring""",
            ["P1", "audit-finding", "security", "automated"]
        ),
        
        # ===== HIGH: INFRASTRUCTURE PARITY =====
        (
            "[INFRA] Primary-Replica Cluster Parity Validation Missing",
            """The cluster lacks automated validation to ensure configuration parity between primary (192.168.168.31) and replica (192.168.168.32) hosts.

## Problem
- Configuration drift undetected between cluster nodes
- No automated parity checks during deployment
- Stale documentation causing deployment errors
- Prevents consistent failover validation

## Evidence
- COMPREHENSIVE-GAP-ANALYSIS.md identifies "Deployment errors due to stale documentation"
- Primary host has 13 running containers; replica status unknown
- No documented parity validation procedure

## Impact
- Silent configuration drift during updates
- Failover procedures unpredictable
- Recovery time objective (RTO) cannot be verified

## Suggested Action
1. Create cluster parity validation script:
   - Compare docker-compose configurations
   - Verify all services deployed on both hosts
   - Check environment variable consistency
2. Implement configuration drift detection
3. Add automated nightly parity tests to CI/CD
4. Document expected parity state in runbook""",
            ["P1", "audit-finding", "infrastructure", "automated"]
        ),
        
        # ===== HIGH: SERVICE READINESS =====
        (
            "[OPS] Service Readiness Timeouts During E2E Testing",
            """E2E and load testing sequences encounter intermittent service readiness timeouts and "Failed to start services" errors during testing.

## Problem
- Services fail to reach readiness within timeout during E2E tests
- Intermittent database and message broker initialization failures
- Test execution blocked; unclear if application or test infrastructure issue

## Evidence
- test-e2e-load.sh logs "Service did not become ready within ${timeout}s"
- Repeated failures during chaos testing and load test execution
- Error message: "Failed to start services"

## Impact
- E2E test suite unreliable
- Load testing blocked
- Service startup profile unknown

## Suggested Action
1. Implement exponential backoff retry logic in service startup checks
2. Extend readiness probe timeouts from current value to 120s
3. Add container health check logging to identify slow startup services
4. Create pre-flight diagnostic script to test service startup
5. Profile service startup times to set realistic timeouts""",
            ["P1", "audit-finding", "operations", "automated"]
        ),
        
        # ===== HIGH: ENGINEERING HARDENING =====
        (
            "[DEBT] Engineering Hardening: 74+ Scripts Missing Trap Handlers",
            """Approximately 74 operational and deployment scripts lack structured error handling (trap handlers). This can lead to silent failures and partial state corruption.

## Problem
- Only 10/65+ operational scripts implement standard error traps
- Scripts can fail silently, leaving infrastructure in unknown state
- No consistent error logging across the codebase
- CI linting in strict mode fails

## Evidence
- PHASE2-ERROR-HANDLING-SUMMARY.md reports "14% coverage" (10/65+ scripts)
- scripts/ci/lint-error-handling.sh exits with code 1 in all-scripts check
- 10 critical scripts have traps; 55+ remaining scripts lack them

## Impact
- Deployment failures go unnoticed
- Partial cluster state corruption possible
- Difficult to debug failures in CI/CD pipeline
- Cascading failures from unhandled errors

## Suggested Action
1. Phase 2: Add `trap 'exit' ERR` handlers to all remaining 55+ scripts
2. Integrate linting into pre-commit hooks
3. Create automated remediation tool
4. Document error handling best practices in SSOT guide
5. Add error handling to deployment pipeline validation

## Standard Pattern
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'cleanup' EXIT""",
            ["P2", "audit-finding", "engineering", "automated"]
        ),
        
        # ===== HIGH: CI/CD ENFORCEMENT =====
        (
            "[CI] Error Handling Lint Check Failures in Strict Mode",
            """The CI/CD pipeline's error handling lint check fails when running in strict mode, indicating many scripts do not meet repository hardening standards.

## Problem
- Strict linting mode exits with non-zero status
- Repository-wide error handling compliance enforcement incomplete
- Pre-deployment validation script exits with expected failure

## Evidence
- scripts/ci/lint-error-handling.sh runs but returns exit code 1
- Script successfully checks 10 critical scripts but fails on "Checking all operational scripts"
- Error handling pattern: 100% compliance for critical scripts; ~14% for ops scripts

## Impact
- Cannot enforce consistent error handling across codebase
- CI/CD gate is permissive; poor error handling can be deployed
- Difficult to identify non-compliant scripts for remediation

## Suggested Action
1. Create pre-commit hook integration
2. Generate report of all non-compliant scripts
3. Prioritize scripts by deployment criticality
4. Create automated refactoring tool for trap handler insertion
5. Add required CI step before deployment""",
            ["P2", "audit-finding", "ci-cd", "automated"]
        ),
        
        # ===== MEDIUM: IAC & CONFIGURATION =====
        (
            "[IAC] Terraform Version Outdated (v1.8.0 vs v1.14.9)",
            """The local environment is using Terraform `v1.8.0`. The latest stable version is `v1.14.9`, which includes important provider compatibility fixes and performance improvements.

## Problem
- Terraform version is 6 minor releases behind
- May encounter provider compatibility issues
- Performance and security improvements not available

## Evidence
- terraform version output: "Terraform v1.8.0"
- Latest stable: "Terraform v1.14.9"
- Download: https://www.terraform.io/downloads.html

## Suggested Action
1. Download and install Terraform v1.14.9 from https://www.terraform.io/downloads.html
2. Verify installation: `terraform version`
3. Run `terraform init` in affected directories to migrate state
4. Re-run terraform plan to verify compatibility""",
            ["P2", "audit-finding", "iac", "automated"]
        ),
        
        (
            "[IaC] Terraform Configuration Missing Root Context",
            """Running `terraform plan` from root directory fails with "No configuration files" error, requiring manual context switching to subdirectories.

## Problem
- IaC is split across terraform/environments/private/ and other subdirectories
- No root-level terraform wrapper or orchestration layer
- Developers must remember to switch directories before running terraform

## Evidence
- Running `terraform plan` in root: "Error: No configuration files"
- Terraform files in: terraform/environments/{private,air-gapped,federated}
- No terraform/ root directory .tf files

## Impact
- Confusing user experience; developers must know directory structure
- Difficult to run unified terraform operations
- Difficult to manage state across environments

## Suggested Action
1. Create terraform wrapper script at root: `terraform-wrapper.sh`
   - Auto-detects environment from current directory or CLI args
   - Switches to correct environment subdirectory
   - Passes arguments through to terraform

2. Create Makefile targets for common operations

3. Document environment switching procedure in terraform/README.md""",
            ["P2", "audit-finding", "iac", "automated"]
        ),
        
        # ===== MEDIUM: CONFIGURATION MANAGEMENT =====
        (
            "[CONFIG] Environment Variable SSOT Consolidation Incomplete",
            """Environment variables are sourced from multiple locations (terraform, docker-compose, shell scripts), violating DRY principles and causing deployment drift.

## Problem
- Variables defined in: terraform variables.tf, docker-compose.yml, .env files, shell scripts
- Changes must be manually replicated across files
- Configuration drift causes deployment inconsistencies
- Phase 1 partial fix: created scripts/_common/config.env (60+ variables)

## Evidence
- AUDIT_REMEDIATION_PLAN.md marks "Environment Variable SSOT - TODO"
- Multiple sources for same variables (e.g., POSTGRES_HOST defined in multiple files)
- Partial solution in Phase 1 consolidates to single config.env

## Impact
- Difficult to understand current configuration state
- Changes in one location don't propagate
- Deployment procedures fragile and error-prone

## Suggested Action
1. Complete consolidation of all env vars to scripts/_common/config.env
2. Create environment profile system:
   - config.env.base (common vars)
   - config.env.dev / config.env.staging / config.env.prod
3. Update docker-compose.yml to source config.env
4. Update terraform to read config.env
5. Add CI/CD validation step: verify all vars are defined

## Phase Status
- Phase 1: Partial (60+ vars consolidated)
- Phase 2: Pending (remaining vars consolidation)
- Phase 3: Pending (profile system implementation)""",
            ["P2", "audit-finding", "configuration", "automated"]
        ),
        
        (
            "[IaC] Docker Compose File Consolidation Strategy",
            """Multiple docker-compose files exist (~20+) without clear consolidation strategy, causing duplication and maintenance burden.

## Problem
- Files scattered across root and subdirectories
- Overlapping service definitions and environment overrides
- Unclear precedence of override files
- Maintenance burden: each file must be updated independently

## Evidence
- docker-compose.yml (base, ~35 services)
- docker-compose.enterprise.yml
- docker-compose.override.yml
- docker-compose.redpanda.yml
- Plus environment-specific: .ai.yml, .edge-agent.yml, .observability.yml, etc.

## Suggested Action
1. Consolidate using compose override patterns:
   - Base file: docker-compose.yml (common services)
   - Override files: docker-compose.override.yml (dev overrides)
   - Profile-specific: docker-compose.{profile}.yml (prod/staging)

2. Define clear compose file hierarchy:
   - Which files are applied in which order
   - Service precedence rules

3. Create docker-compose profiles feature:
   - `docker compose --profile observability up` for monitoring stack
   - `docker compose --profile ai up` for ML services

4. Document consolidation in docker/README.md""",
            ["P2", "audit-finding", "iac", "automated"]
        ),
        
        # ===== MEDIUM: DOCUMENTATION =====
        (
            "[DOCS] Missing Service Health Monitoring & Init Container Documentation",
            """Critical operational documentation is missing for service health monitoring and init container deployment patterns, causing knowledge gaps and operational errors.

## Problem
- No runbook for troubleshooting service health failures
- Init container lifecycle not documented
- Common failure scenarios lack debugging procedures
- New operators lack operational context

## Evidence
- TODO in CODE_REVIEW_CONTAINER_DEPLOYMENT.md:
  - "TODO: Add Service Health Monitoring"
  - "TODO: Document Init Container Strategy"

## Impact
- Incident response delayed; operators must guess troubleshooting steps
- Init container failures cause deployment cascades
- Knowledge loss if original implementers unavailable

## Suggested Action
1. Create health-check.md operational guide:
   - Service health check procedures
   - Common failure patterns and resolutions
   - Log location reference

2. Create init-container-strategy.md:
   - Init container lifecycle explanation
   - When to use init vs sidecar
   - Dependency ordering rules

3. Add troubleshooting runbook:
   - Pod startup failures
   - Service readiness timeouts
   - Database connectivity issues
   - Message broker initialization errors

4. Update CODE_REVIEW_CONTAINER_DEPLOYMENT.md with findings""",
            ["P2", "audit-finding", "documentation", "automated"]
        ),
        
        # ===== MEDIUM: KUBERNETES MIGRATION =====
        (
            "[K8S] Kubernetes Migration Phase 14: Runtime Validation Blocked by Missing Tools",
            """Kubernetes migration is in Phase 14, but validation and troubleshooting cannot proceed due to missing `kubectl` binary and incomplete documentation.

## Problem
- `kubectl` command not available; K8s CLI tools not installed
- Cannot inspect pods, logs, or cluster state
- Phase 14 completion status unclear without pod inspection capability
- Migration readiness cannot be validated

## Evidence
- Command `kubectl get pods -A` exits with code 127
- K8s migration tracked in K8S-MIGRATION-PHASE14-STATUS.md
- Phase 15 (Advanced Testing) awaits Phase 14 completion

## Impact
- K8s migration completion blocked
- Cannot verify pod deployment status
- Incident response and debugging significantly degraded

## Suggested Action
1. Install kubectl: `sudo snap install kubectl`
2. Configure kubeconfig for target cluster
3. Create K8s readiness checklist:
   - All pods in desired namespace running
   - Resource requests/limits configured
   - Health checks passing
4. Document phase transition criteria and blockers
5. Verify all Phase 14 acceptance criteria before proceeding to Phase 15""",
            ["P2", "audit-finding", "kubernetes", "automated"]
        ),
        
        # ===== MEDIUM: TECHNICAL DEBT =====
        (
            "[APP] Activity Feed & Agent Runtime: Recurring WebSocket/Ingest Errors",
            """Static analysis reveals recurring `WebSocket error`, `Ingest error`, and `Execution error` patterns in application code. These indicate areas of poor error handling and resilience.

## Problem
- Frequent WebSocket connection failures
- Data ingest errors not properly recovered
- Execution errors cause cascading failures

## Evidence
- apps/activity_feed/main.py:
  - logger.error(f"WebSocket error: {e}")
  - logger.error(f"Ingest error: {e}")

- apps/agent-runtime/main.py:
  - logger.error(f"Execution error: {e}")
  - WebSocket error handling: ws.onerror = (error) => { console.error(...) }

## Impact
- Service reliability degraded
- Error visibility but no recovery
- End user experience impacted by transient failures

## Suggested Action
1. Implement robust reconnection logic:
   - Exponential backoff for failed connections
   - Max retry limits with circuit breaker
   - Graceful degradation when reconnection fails

2. Enhance telemetry:
   - Track error frequency and patterns
   - Alert on error rate spikes
   - Create runbook for common error scenarios

3. Add structured logging:
   - Include context (user ID, transaction ID, etc.)
   - Timestamp and severity level
   - Stack trace for errors""",
            ["P2", "audit-finding", "application", "automated"]
        ),
        
        (
            "[DEBT] Historical Code Duplication: App Directory Consolidation",
            """Recent audit found high-severity duplication in app directories. Similar naming inconsistencies may exist in other module directories.

## Problem
- Deprecated app directory naming (apps/reputation-engine, apps/edge_agent) duplicated canonical names
- Import ambiguity from multiple directories
- Maintenance burden from duplicate implementations

## Evidence
- Fixed in commit e9c9236e:
  - Deleted deprecated hyphen-named reputation-engine (canonical: reputation_engine)
  - Deleted deprecated underscore-named edge_agent (canonical: edge-agent)
- High-severity duplication from workspace audit

## Impact
- Code confusion and inconsistency
- Import ambiguity and potential runtime errors
- Maintenance burden from duplicate code

## Suggested Action
1. Audit remaining app directories for naming inconsistencies
2. Run comprehensive deduplication analysis: `scripts/ci/fix-codebase-deduplication.sh`
3. Verify no duplicate imports in docker-compose.yml
4. Implement automated deduplication checks in CI/CD:
   - Prevent commits with duplicate directory names
   - Enforce consistent naming (kebab-case or snake_case)
5. Document canonical naming convention in ARCHITECTURE.md""",
            ["P2", "audit-finding", "engineering", "automated"]
        ),
    ]
    
    # Create all issues
    for title, body, labels in issues:
        creator.create_issue(title, body, labels)
    
    # Print summary
    creator.print_summary()


if __name__ == "__main__":
    main()
