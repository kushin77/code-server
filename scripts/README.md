# Scripts Directory - Complete Index

**Last Updated**: April 14, 2026
**Status**: Organized & Indexed (Phase 1 Task 1.1)
**Total Scripts**: 250+

> 💡 **TIP**: Use Ctrl+F (or Cmd+F) to search this page for any script name.

---

## 🎯 QUICK START - FIND WHAT YOU NEED

| Need To... | Script | Time | Status |
|-----------|--------|------|--------|
| Deploy to production | `./deploy.sh` | 5 min | ✅ ACTIVE |
| Check if healthy | `./health-check.sh` | 2 min | ✅ ACTIVE |
| Backup all data | `./backup.sh` | 15 min | ✅ ACTIVE |
| Run load tests | `./load-test.sh` | 30 min | ✅ ACTIVE |
| Manage a user | `./manage-users.sh` | 10 min | ✅ ACTIVE |
| Setup Cloudflare tunnel | `./setup-cloudflare-tunnel.sh` | 15 min | ✅ ACTIVE |
| Validate configs | `./validate.sh` | 5 min | ✅ ACTIVE |

---

## 📚 SCRIPTS BY CATEGORY

### 🚀 CORE OPERATIONAL (Active - Use These)

### Using Scripts

All scripts have built-in help:

```bash
./scripts/category/script-name.sh --help
```

### Common Operations

```bash
# Setup environment
make install
./scripts/install/setup.sh

# Check health
make health-check
./scripts/health/health-check.sh --verbose

# Deploy infrastructure
make deploy-iac-prod
./scripts/deploy/deploy-iac.sh production

# View all targets
make --help
```

## Script Categories

### Install Scripts

First-time setup and dependency installation.

```bash
./scripts/install/setup.sh          # Full setup
./scripts/install/setup-deps.sh     # Just dependencies
./scripts/install/setup-db.sh       # Just database
```

### Deploy Scripts

Deployment automation for infrastructure and containers.

```bash
./scripts/deploy/deploy-iac.sh production     # Terraform
./scripts/deploy/deploy-containers.sh         # Docker
./scripts/deploy/deploy-all.sh                # Both
```

### Health Scripts

Health checks, monitoring, validation.

```bash
./scripts/health/health-check.sh --verbose    # Full report
./scripts/health/validate-config.sh           # Validation
```

### Maintenance Scripts

Backup, restore, cleanup, maintenance tasks.

```bash
./scripts/maintenance/backup.sh               # Create backup
./scripts/maintenance/restore.sh              # Restore backup
./scripts/maintenance/cleanup.sh              # Clean up
```

**Core operational scripts** for production use:

- `deploy.sh` - Main deployment orchestration ✅ ACTIVE
- `backup.sh` - Automated backup creation ✅ ACTIVE
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
