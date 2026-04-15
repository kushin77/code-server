# Script Consolidation Framework (P2 #421)
# ═════════════════════════════════════════════════════════════════════════════
# Unified Deployment Orchestration replacing 290 scattered shell scripts

## Problem Statement
- **Before**: 290 shell scripts scattered across 15+ directories
  - scripts/deploy/ (4 files)
  - scripts/install/ (5 files)
  - scripts/dev/ (5 files)
  - scripts/governance/ (4 files)
  - scripts/ci/ (3 files)
  - scripts/hardening/ (2 files)
  - scripts/health/ (2 files)
  - scripts/lib/ (7 files)
  - scripts/_common/ (8 files)
  - Root level (19 files)
  - scripts/_archive/ (60+ historical files)

- **Issues**:
  - No single entry point (users confused which script to run)
  - Inconsistent naming, argument passing, error handling
  - Code duplication across scripts
  - Difficult to maintain (changes needed in multiple places)
  - Hard to version/release

## Solution: Unified Deploy Framework

### Single Entry Point
```bash
./deploy.sh <command> [options]
```

### Command Mapping

#### Phase Management (Phase-based deployments)
```bash
./deploy.sh deploy-phase 7              # Deploy phase N
./deploy.sh deploy-all                  # All phases sequentially
./deploy.sh verify-phase 7              # Verify phase N health

Replaces:
  scripts/deploy/phase-7-deployment.sh
  scripts/deploy/phase-7b-*.sh
  scripts/deploy/phase-7c-*.sh
  etc. (all 26 phase-specific scripts)
```

#### Infrastructure Management
```bash
./deploy.sh provision                   # Initial infrastructure provisioning
./deploy.sh configure                   # Apply IaC (Terraform)
./deploy.sh up [SERVICES]               # Start Docker services
./deploy.sh down                        # Stop services
./deploy.sh restart SERVICE             # Restart specific service
./deploy.sh status                      # Show service health

Replaces:
  scripts/deploy/infrastructure-setup.sh
  scripts/ci/terraform-plan.sh
  scripts/ci/terraform-apply.sh
  scripts/health/docker-compose-check.sh
  Manual 'docker-compose' commands
```

#### Operations
```bash
./deploy.sh backup [OPTIONS]            # Backup database + configs
./deploy.sh restore BACKUP_ID           # Restore from backup
./deploy.sh health-check [--detailed]   # Full health checks

Replaces:
  scripts/governance/backup-*.sh
  scripts/governance/restore-*.sh
  scripts/health/health-check.sh
  scripts/health/liveness-check.sh
```

#### Security
```bash
./deploy.sh secrets-scan                # Scan for hardcoded secrets
./deploy.sh security-audit              # Run hardening audit
./deploy.sh vault-init                  # Initialize Vault (production)

Replaces:
  scripts/hardening/scan-secrets.sh
  scripts/hardening/security-audit.sh
  scripts/governance/vault-*.sh
```

#### Development
```bash
./deploy.sh dev-env                     # Setup local dev environment
./deploy.sh test                        # Run full test suite
./deploy.sh lint                        # Run linting + formatting

Replaces:
  scripts/dev/local-setup.sh
  scripts/dev/dev-compose.sh
  scripts/ci/run-tests.sh
  scripts/ci/run-linting.sh
```

### Library Functions Organization
```
scripts/
  ├── lib/                              # Shared functions (sourced by deploy.sh)
  │   ├── docker.sh       # Docker/compose utilities
  │   ├── terraform.sh    # Terraform execution
  │   ├── kubernetes.sh   # K8s operations
  │   └── utils.sh        # General utilities
  │
  ├── commands/           # Individual command implementations
  │   ├── deploy-phase.sh
  │   ├── provision.sh
  │   ├── backup.sh
  │   ├── security-audit.sh
  │   └── ...
  │
  ├── _common/            # Utilities (logging, colors, etc.)
  │   ├── colors.sh
  │   └── utils.sh
  │
  └── _archive/           # Historical (deprecated)
      └── historical/
```

### Benefits of Unified Framework

1. **Single Entry Point**: `./deploy.sh help` shows all available commands
2. **Consistent Interface**: Same argument/option pattern for all commands
3. **Reduced Duplication**: Shared utilities in `scripts/lib/`
4. **Better Error Handling**: Centralized logging + error management
5. **Easier Versioning**: One script version to track
6. **Simpler Documentation**: Single command reference
7. **CI/CD Integration**: One pipeline target instead of many scripts
8. **Easier Onboarding**: New developers learn one interface

### Environment Variable Control

All commands respect consistent environment variables:

```bash
# Deployment environment
ENVIRONMENT=production    # production | onprem | development

# Execution mode
DRY_RUN=true             # Show what would run (no-op)
VERBOSE=true             # Show all commands
AUTO_APPROVE=true        # Skip interactive prompts

# Logging
LOG_LEVEL=debug          # debug | info | warn | error

# Target hosts
REMOTE_HOST=192.168.168.31
SSH_USER=akushnir

# Terraform
TERRAFORM_VARS=production.tfvars
TF_AUTO_APPROVE=true

# Docker
DOCKER_COMPOSE_FILE=docker-compose.yml
SERVICES=code-server,postgres,redis
```

### Migration Path

#### Phase 1: Framework Establishment (CURRENT)
- ✅ Create unified `deploy.sh` entry point
- ✅ Document command mapping
- ✅ Create `scripts/lib/` shared utilities
- ✅ Create `scripts/commands/` individual commands

#### Phase 2: Command Migration (ONGOING)
- 🔄 Refactor existing scripts into modular commands
- 🔄 Update CI/CD pipelines to use `./deploy.sh`
- 🔄 Add comprehensive `scripts/lib/` functions
- 🔄 Archive obsolete scripts in `scripts/_archive/`

#### Phase 3: Testing & Documentation (PENDING)
- 📋 Test all commands in CI/CD
- 📋 Update README with `./deploy.sh` documentation
- 📋 Create command-specific runbooks
- 📋 Remove archived scripts from repository

### Usage Examples

```bash
# Local development
./deploy.sh dev-env                          # Setup local environment
./deploy.sh up --services code-server,postgres
./deploy.sh test                             # Run tests

# Staging/Testing
./deploy.sh deploy-phase 14 --dry-run        # Preview what would happen
./deploy.sh verify-phase 14                  # Check if phase healthy

# Production Deployment
./deploy.sh remote plan                      # Show what would change
./deploy.sh remote apply --auto-approve      # Deploy with safety checks
./deploy.sh remote status                    # Verify successful

# Operations
./deploy.sh health-check --detailed          # Full system checks
./deploy.sh backup                           # Backup everything
./deploy.sh logs prometheus 100              # Show recent logs

# Security & Maintenance
./deploy.sh secrets-scan                     # Find hardcoded secrets
./deploy.sh security-audit                   # Run hardening checks
./deploy.sh vault-init                       # Setup secure secrets mgmt
```

### Backward Compatibility

Existing scripts in root (e.g., `deploy-phase-7.sh`) remain functional until migrated.
Recommend using `./deploy.sh` for new work and CI/CD pipelines.

### Success Metrics

- [ ] All 26 phase deployments callable via `./deploy.sh deploy-phase N`
- [ ] All operational commands (backup/restore/health-check) working
- [ ] All CI/CD pipelines migrated to use `./deploy.sh`
- [ ] 290 scattered scripts reduced to < 50 in `scripts/` directory
- [ ] Performance equivalent or faster than scattered scripts
- [ ] Zero regressions in existing deployments

### Next Steps

1. **Review** this consolidation plan with team
2. **Create** script library functions incrementally
3. **Test** each command against actual infrastructure
4. **Migrate** CI/CD pipelines one by one
5. **Archive** validated scripts in `scripts/_archive/`
6. **Document** final command reference in README.md
