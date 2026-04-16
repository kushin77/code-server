# Scripts Directory — Canonical Operational Entrypoints

**Last Updated**: April 2026  
**Issue**: [#382 — Canonical Operational Entrypoints](https://github.com/kushin77/code-server/issues/382)  
**Status**: Reorganized — phase-based scripts deprecated (EOL: 2026-07-14)

> 💡 **TIP**: Use Ctrl+F to search for the operation you need.

---

## 🎯 QUICK START — CANONICAL TASK MAP

| Task | Canonical Script | Production-Safe? | Notes |
|------|-----------------|-----------------|-------|
| Deploy to production | `scripts/deploy.sh` | ✅ Yes | Requires SSH to 192.168.168.31 |
| Health check all services | `scripts/health/health-check.sh` | ✅ Yes | Non-destructive |
| Backup all data | `scripts/backup.sh` | ✅ Yes | Creates timestamped archive |
| Disaster recovery test | `scripts/disaster-recovery-procedures.sh` | ⚠️ Coordinated | Maintenance window required |
| Chaos testing | Deprecated — use `scripts/phase-7e-chaos-testing.sh` redirect | ⚠️ Coordinated | Staging only |
| Rollback from incident | `git revert <sha> && git push origin main` | ✅ Yes | CI/CD deploys automatically |
| Credential rotation | `scripts/rotate-godaddy-api-key.sh` | ⚠️ Coordinated | Requires maintenance window |
| Validate configs | `scripts/automated-iac-validation.sh` | ✅ Yes | CI-safe |
| Check VPN connectivity | `scripts/lib/vpn.sh` | ✅ Yes | Read-only |
| Global quality gate | `scripts/lib/global-quality-gate.sh` | ✅ Yes | CI gate |
| Security hardening | `scripts/audit-logging.sh` | ⚠️ Coordinated | Affects running containers |
| User management | `scripts/admin-sessions-invalidate.sh` | ⚠️ Coordinated | Invalidates active sessions |
| VSCode process monitor | `scripts/vscode-handle-monitor.sh` | ✅ Yes | Read-only diagnostic |
| VSCode memory dashboard | `scripts/vscode-memory-dashboard.sh` | ✅ Yes | Read-only diagnostic |
| Ollama initialize | `scripts/ollama-init.sh health` | ✅ Yes | Idempotent |

---

## 📋 Script Capability Matrix

| Script | Run Anytime? | Maintenance Window? | One-Time Setup? |
|--------|-------------|--------------------|-----------------| 
| `health/health-check.sh` | ✅ | — | — |
| `backup.sh` | ✅ | — | — |
| `deploy.sh` | ✅ | — | — |
| `ollama-init.sh` | ✅ | — | — |
| `automated-iac-validation.sh` | ✅ | — | — |
| `lib/vpn.sh` | ✅ | — | — |
| `lib/global-quality-gate.sh` | ✅ | — | — |
| `disaster-recovery-procedures.sh` | — | ✅ | — |
| `rotate-godaddy-api-key.sh` | — | ✅ | — |
| `audit-logging.sh` | — | ✅ | — |
| `bootstrap-node.sh` | — | — | ✅ |
| `automated-oauth-configuration.sh` | — | — | ✅ |

---

## 📂 Scripts by Category

### 🚀 Deploy

```bash
scripts/deploy.sh                          # Main production orchestrator
scripts/deploy-ha-primary-production.sh   # HA primary deployment
scripts/deploy-keepalived.sh              # VRRP/keepalived
scripts/deploy-cloudflare-tunnel.sh       # Cloudflare tunnel
scripts/deploy-falco.sh                   # Falco security
scripts/deploy-github-runners.sh          # GitHub Actions runners
scripts/automated-deployment-orchestration.sh  # Full orchestration
```

### 🏥 Health & Validation

```bash
scripts/health/health-check.sh            # Canonical health check
scripts/health/verify-all-phases-ready.sh # Phase readiness
scripts/automated-iac-validation.sh       # IaC validation
scripts/backup-validator.sh               # Backup integrity
scripts/backup-verify-production.sh       # Production backup verify
```

### 🔒 Security

```bash
scripts/audit-logging.sh                  # Audit log setup
scripts/configure-egress-filtering.sh     # Egress rules
scripts/lib/secrets.sh                    # Secrets management
scripts/rotate-godaddy-api-key.sh         # Credential rotation
scripts/automated-oauth-configuration.sh  # OAuth setup
```

### 💾 Backup & Recovery

```bash
scripts/backup.sh                         # Create backup
scripts/disaster-recovery-procedures.sh  # DR runbook
```

### 🔧 Maintenance & Ops

```bash
scripts/admin-sessions-invalidate.sh      # Invalidate sessions
scripts/cleanup-container-overlap.sh      # Container cleanup
scripts/deduplicate-env.sh               # Dedup env vars
scripts/collect-baselines.sh             # Perf baseline collection
```

### 🖥️ VSCode Process Management (Manual Only)

```bash
scripts/launch-vscode-budgeted.bat        # Launch with 1GB heap cap (Windows)
scripts/vscode-handle-monitor.sh          # Process health monitor
scripts/vscode-memory-dashboard.sh        # Memory dashboard
scripts/vscode-terminal-reaper.ps1        # Idle terminal cleanup (prompts before kill)
```

### 🧰 Lib / Shared

```bash
scripts/lib/global-quality-gate.sh        # CI quality gate
scripts/lib/vpn.sh                        # VPN connectivity check
scripts/lib/secrets.sh                    # Secrets loading
scripts/lib/env.sh                        # Environment setup
scripts/lib/check-no-ips.sh              # IP leakage check
```

### 🤖 AI / Ollama

```bash
scripts/ollama-init.sh health             # Health check
scripts/ollama-init.sh pull-models        # Pull all models
scripts/ollama-init.sh list               # List models
scripts/ollama-init.sh index              # Build repo index
scripts/ollama-init.sh status             # Full status
```

---

## ⚠️ Deprecated Scripts

23 phase-based scripts are **deprecated** with 90-day EOL (2026-07-14).  
See [`DEPRECATED-SCRIPTS.md`](../DEPRECATED-SCRIPTS.md) for the full replacement mapping.

**Examples:**
- `scripts/deploy-phase-7-complete.sh` → `scripts/deploy.sh`
- `scripts/phase-7e-chaos-testing.sh` → coordinate via maintenance window
- `scripts/deploy-phase-8-secrets-management.sh` → `scripts/lib/secrets.sh`

---

## 🛡️ CI Enforcement

The global quality gate (`scripts/lib/global-quality-gate.sh`) warns when new commits introduce phase-based script naming patterns. New scripts **must** use the capability-based naming convention:

```
✅ Good: scripts/deploy/rollback.sh
✅ Good: scripts/security/rotate-credentials.sh
❌ Reject: scripts/deploy-phase-27-new-thing.sh
❌ Reject: scripts/phase-27-setup.sh
```

---

## 📋 Adding New Scripts

1. Choose the correct category directory
2. Use descriptive verb-noun naming: `verb-noun.sh` (e.g., `rotate-credentials.sh`)
3. Add `set -euo pipefail` at top
4. Add `--help` flag
5. Mark as Production-Safe or Coordinated in this README
6. Add entry to the QUICK START table above

---

*Last updated: April 2026 | Issue: #382*

- `health-check.sh` - Comprehensive health verification ✅ ACTIVE
- `docker-health-monitor.sh` - Real-time Docker container health ✅ ACTIVE
- `restore.sh` - Backup restoration ✅ ACTIVE
- `validate.sh` - Configuration and deployment validation ✅ ACTIVE
- `cleanup.sh` - Clean up resources and logs ✅ ACTIVE

---

### 🏗️ DEVOPS & INFRASTRUCTURE (Setup & Management)

Operational scripts for infrastructure, networking, and system management:

- `manage-users.sh` - Create/update/delete system users ✅ ACTIVE
- `setup-cloudflare-tunnel.sh` - Configure Cloudflare tunnel access ✅ ACTIVE
- `automated-dns-configuration.sh` - Manage DNS records ✅ ACTIVE
- `automated-iac-validation.sh` - Validate infrastructure-as-code ✅ ACTIVE
- `deploy-iac.ps1` - Windows PowerShell IaC deployment ✅ ACTIVE
- `deploy-iac.sh` - Shell version for Linux/Mac ✅ ACTIVE
- `fix-docker-compose.sh` - Repair docker-compose configuration ✅ ACTIVE
- `fix-github-auth.sh` - Troubleshoot GitHub authentication ✅ ACTIVE
- `fix-onprem.sh` - Fix on-premises deployment issues ✅ ACTIVE
- `fix-product-json.sh` - Correct product.json configuration ✅ ACTIVE

---

### 🔐 SECURITY & COMPLIANCE

Security audit and compliance verification:

- `security-audit.sh` - Run security audit checks ✅ ACTIVE
- `audit-logging.sh` - Configure audit logging ✅ ACTIVE
- `audit-compliance-report.sh` - Generate compliance report (✅ ACTIVE, requires credentials)
- `CRASH_VULNERABILITY_SCAN.md` - Vulnerability scan procedures (documentation)
- `CRASH_QUICK_REFERENCE.md` - Quick reference for incident handling (documentation)

---

### 📊 MONITORING & OBSERVABILITY

Monitoring, metrics, and observability:

- `p0-monitoring-bootstrap.sh` - Initialize monitoring stack ✅ ACTIVE
- `load-test.sh` - Run performance load testing ✅ ACTIVE
- `stress-test-suite.sh` - Run stress testing suite ✅ ACTIVE
- `pre-flight-checklist.sh` - Pre-deployment verification ✅ ACTIVE
- `post-deployment-validation.sh` - Post-deployment verification ✅ ACTIVE

---

### 🧪 TESTING & VALIDATION

Tests, validation, and quality checks:

- `validate-config.sh` - Validate all configuration files ✅ ACTIVE
- `CRASH_SCAN_SUMMARY.md` - Summarize dependency scan results (documentation)
- `fix-compose.py` - Python utility to fix docker-compose (requires Python)
- `ci-merge-automation.ps1` - Automated CI/CD merge logic ✅ ACTIVE
- `admin-merge.ps1` - Administrative merge operations ✅ ACTIVE

---

### 🐳 CONTAINER & DEPLOYMENT MANAGEMENT

Container orchestration and deployments:

- `docker-compose.yml` - Main container orchestration ✅ ACTIVE
- `docker-compose.production.yml` - Production overrides ✅ ACTIVE
- `Dockerfile` - Application container definition ✅ ACTIVE
- `Dockerfile.code-server` - code-server specific container ✅ ACTIVE
- `Dockerfile.caddy` - Caddy reverse proxy container ✅ ACTIVE
- `Dockerfile.ssh-proxy` - SSH proxy container ✅ ACTIVE

---

### 🛠️ DEVELOPER UTILITIES & SETUP

Development environment and utility scripts:

- `setup-local.sh` - Local development environment setup ✅ ACTIVE
- `onboard-dev.sh` - Developer onboarding automation ✅ ACTIVE
- `troubleshoot-docker.sh` - Docker troubleshooting ✅ ACTIVE
- `troubleshoot-network.sh` - Network connectivity troubleshooting ✅ ACTIVE
- `fix-common-issues.sh` - Common issue fixes ✅ ACTIVE
- `DEV_ONBOARDING.md` - Onboarding guide (documentation) ✅ ACTIVE
- `CONTRIBUTING.md` - Contribution guidelines (documentation) ✅ ACTIVE

---

### 📦 DEPRECATED & ARCHIVED

**Phase 13-20 Artifacts** (Successfully completed in production, retained for reference):

- `phase-13-*.sh` - Phase 13 implementation scripts (30+ files) 📦 ARCHIVED
- `phase-14-*.sh` - Phase 14 monitoring setup (15+ files) 📦 ARCHIVED
- `phase-15-*.sh` - Phase 15 microservices (20+ files) 📦 ARCHIVED
- `phase-16-*.sh` - Phase 16 security hardening (25+ files) 📦 ARCHIVED
- `phase-17-*.sh` - Phase 17 performance optimization (12+ files) 📦 ARCHIVED
- `phase-18-*.sh` - Phase 18 disaster recovery (18+ files) 📦 ARCHIVED
- `phase-19-*.sh` - Phase 19 scalability (22+ files) 📦 ARCHIVED
- `phase-20-*.sh` - Phase 20 final verification (10+ files) 📦 ARCHIVED
- `gpu-phase-1-*.sh` - GPU implementation Phase 1 (8+ files) 📦 ARCHIVED
- `gpu-*.sh` - GPU optimization scripts (Complete as of Phase 21) 📦 ARCHIVED

**Location**: See `archived/` directory for full phase history.

---

### 🗑️ SCRIPTS TO REMOVE

The following scripts are redundant or superseded. **Target for deletion after verifying no active dependencies:**

- `fix-common-issues.sh` (superseded by troubleshoot-*.sh collection)
- Duplicate `deploy-*.sh` variants
- Old `test-*.sh` files (replaced by CI/CD pipelines)
- Legacy `migrate-*.sh` scripts (migrations are in code)

> **Before deletion**: Search repo for any references to these scripts. Confirm with team.

---

## 📁 SUBDIRECTORIES

### `/ci/`

CI/CD related scripts:
- `admin-merge.ps1` - Administrative merge for protected branches
- `ci-merge-automation.ps1` - Automated CI/CD workflows

### `/deploy/`

Deployment-specific scripts:
- `deploy.sh` - Main orchestration
- `deploy-iac.sh` - Infrastructure deployment
- `deploy-containers.sh` - Container deployment

### `/dev/`

Developer utilities:
- `setup-local.sh` - Local environment setup
- `onboard-dev.sh` - Developer onboarding
- Various troubleshoot-*.sh utilities

### `/health/`

Health checks and validation:
- `health-check.sh` - Comprehensive health verification
- `validate-config.sh` - Configuration validation
- `validate.sh` - General validation

### `/lib/`

Shared libraries (source in your scripts):

**Planned** (Phase 1, Task 1.6):
- `logging.sh` - Standard logging functions
- `utils.sh` - Common utility functions  
- `error-handler.sh` - Error handling and retry logic

**Usage in scripts**:
```bash
source "${SCRIPT_DIR}/../lib/logging.sh"
log_info "Starting deployment..."
log_error "Deployment failed!"
```

### `/maintenance/`

Backup, restore, cleanup:
- `backup.sh` - Create backups
- `restore.sh` - Restore from backup
- `cleanup.sh` - Clean up resources

---

## 📖 HOW TO USE THIS INDEX

### Finding a Script

Use **Ctrl+F** (or **Cmd+F**) to search:

```
Looking for deploy?  → Search: "deploy" → Found: deploy.sh, deploy-iac.sh, etc.
Need health check?   → Search: "health" → Found: health-check.sh, docker-health-monitor.sh
Want to test?        → Search: "test" → Found: load-test.sh, stress-test-suite.sh, pre-flight-checklist.sh
```

### Running a Script

Most scripts support help:

```bash
./path/to/script.sh --help           # Show usage
./path/to/script.sh --verbose        # Verbose output
./path/to/script.sh --dry-run        # Dry run (if supported)
```

### Common Operations

```bash
# Check system health
./health-check.sh

# Backup data
./backup.sh

# Deploy to production
./deploy.sh --environment=production --auto-approve

# Run load test
./load-test.sh --duration=300 --concurrency=50

# Setup new developer
./onboard-dev.sh --username=newdev --team=backend
```

---

## 🏗️ SCRIPT STANDARDS

### Header Template

Every script should include:

```bash
#!/bin/bash
################################################################################
# [Category]: script-name.sh
# Purpose: [Clear one-line description]
# Usage: ./scripts/category/script-name.sh [OPTIONS]
# Examples:
#   ./scripts/deploy/deploy.sh --environment=prod --auto-approve
#   ./scripts/health/health-check.sh --verbose
# Requirements: [System dependencies like docker, terraform, etc.]
# Exit Codes: 0=success, 1=general error, 2=usage error, N=specific error
# References: [Links to docs, runbooks, ADRs]
# Author: @username
# Last Updated: YYYY-MM-DD
################################################################################

set -euo pipefail

# Source libraries
source "$(dirname "$0")/../lib/logging.sh" || exit 1
```

### Error Handling

All scripts should include:

```bash
# Exit on error
set -euo pipefail

# Trap errors
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

# Cleanup on exit
trap 'cleanup' EXIT

cleanup() {
  # Remove temp files, close connections, etc.
}
```

### Logging

Use standard logging (Phase 1, Task 1.6):

```bash
log_debug "Detailed debug information"
log_info "Normal operational message"
log_warn "Warning - something unexpected"
log_error "Error - something failed"
log_fatal "Fatal error - terminating"
```

---

## ❓ FAQ

### Q: Where do I find the backup script?
**A**: Use Ctrl+F to search for "backup" → `./backup.sh`

### Q: How do I deploy to production?
**A**: `./deploy.sh --environment=production --auto-approve` or see deploy.sh --help

### Q: My Docker containers won't start, where's the troubleshooting script?
**A**: Try `./troubleshoot-docker.sh` or `./health-check.sh --verbose` to diagnose

### Q: Can I write my own script?
**A**: Yes! Follow the header template and error handling above. Place in appropriate category. Add entry to this README.

### Q: What's in `/archived`?
**A**: Previous phase implementations (phases 13-20, GPU work). Keep for reference but don't use in production.

### Q: How do I update this README?
**A**: Scripts are self-documenting. When you add/change a script, update this index.

### Q: Which scripts are safe to run in production?
**A**: Scripts marked with ✅ ACTIVE are production-approved. Others are development-only or archived.

### Q: Do I need Docker to run these?
**A**: Most deployment/health/container scripts require Docker. Dev scripts usually don't. Check script help text.

---

## 📞 SUPPORT & TROUBLESHOOTING

### Before you dive in:

1. **Read the script's help**: `./script-name.sh --help`
2. **Check the header**: Comments at top explain purpose, usage, requirements
3. **Search this index**: Ctrl+F to find similar scripts
4. **Run in dry-run mode**: `./script-name.sh --dry-run` (if supported)
5. **Check the logs**: Most scripts log to stdout + file log

### Getting help:

- See corresponding `/doc/runbooks/` for operational procedures
- See `/INCIDENT-RUNBOOKS.md` for incident response
- Check GitHub issues for documented problems
- Review recent PRs for context
- Reach out to #devops on Slack

---

**Note**: This index is automatically maintained. When scripts are added/removed/changed, update this README accordingly.

Last Verified: April 14, 2026
make backup              # Create backup
make test                # Run tests
make lint                # Lint code
make help                # Show all targets
```

## Troubleshooting Scripts

### Script Won't Run

```bash
# Check permissions
ls -la scripts/deploy/deploy-iac.sh

# Make executable
chmod +x scripts/deploy/deploy-iac.sh
```

### Command Not Found

```bash
# Source library failed - check path:
source "$(dirname "$0")/../lib/common.sh"
# Try: bash scripts/deploy/deploy-iac.sh (not ./scripts/...)
```

### Dependencies Missing

```bash
# Install missing packages
./scripts/install/setup-deps.sh

# Or manually:
apt-get install terraform jq curl shellcheck
```

## Script Development Standards

All scripts MUST follow [CODE-QUALITY-STANDARDS.md](../docs/CODE-QUALITY-STANDARDS.md):

✅ **Required**:
- File header with Purpose/Usage/Examples
- Exit on error: `set -euo pipefail`
- Source shared libraries: `source ../lib/common.sh`
- Document exit codes (0=success, 1-3=errors)
- Logging: `log_info "message"`, `log_error "error"`

❌ **Never**:
- Hardcode passwords or secrets
- Silent failures (always log errors)
- Phase-numbered scripts (consolidate)
- Duplicate functionality (use lib/ functions)

## Maintenance

**Owner**: @akushnir  
**Last Updated**: April 14, 2026  
**Status**: Active

---

## Related

- [../Makefile](../Makefile) - Script targets
- [../docs/guides/DEPLOYMENT.md](../docs/guides/DEPLOYMENT.md)
- [../docs/CODE-QUALITY-STANDARDS.md](../docs/CODE-QUALITY-STANDARDS.md)
- [../docs/runbooks/](../docs/runbooks/)
