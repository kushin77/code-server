# Code Quality & Documentation Standards

**Applies To**: ALL code, configuration, and scripts in kushin77/code-server-enterprise  
**Status**: MANDATORY  
**Last Updated**: April 14, 2026  

---

## Table of Contents

1. [File Headers](#file-headers)
2. [Inline Comments](#inline-comments)
3. [README Standards](#readme-standards)
4. [Code Structure](#code-structure)
5. [Configuration Comments](#configuration-comments)
6. [Link & Reference Standards](#link--reference-standards)
7. [Changelog & Version Management](#changelog--version-management)

---

## File Headers

Every file type must have a standardized header. This serves as:
- **Quick reference**: What is this file?
- **Navigation**: Where do I find docs?
- **Maintenance**: Who last touched this? When?
- **Dependencies**: What does this need?

### Terraform (.tf) Files

**Mandatory Location**: At the top of every .tf file

```hcl
################################################################################
# Module: [Module Name]
# Purpose: One-sentence description of what this module/file does
# 
# Usage: Include in main.tf or other parent configuration
# Example:
#   module "containers" {
#     source = "./modules/containers"
#     
#     # Input variables...
#   }
#
# Input Variables:
#   - var_name (type): Description
#   - another_var (type): Description
#
# Outputs:
#   - output_name: Description of what is output
#
# Resources Created:
#   - aws_instance.main
#   - aws_security_group.app
#
# References:
#   - Terraform Module Docs: https://registry.terraform.io/...
#   - Design Decision: docs/adc/ADR-002-ARCHITECTURE.md
#   - Related Configuration: terraform/environments/*.tfvars
#   - Deployment Guide: docs/guides/DEPLOYMENT.md
#
# Dependencies:
#   - Docker provider >= 3.0
#   - Terraform >= 1.6
#
# Security Considerations:
#   - No hardcoded secrets (use variables and environments)
#   - Security groups restrict access to essentials
#   - SSH keys managed via var, never embedded
#
# Notes:
#   - This module is reusable across environments
#   - State is managed at parent level
#   - Requires manual approval before apply on production
#
# Author: @akushnir
# Last Updated: 2026-04-14
# Change Log:
#   - 2026-04-14: Consolidated from 3 separate modules
#   - 2026-04-10: Added security group configurations
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

**Header Elements**:
- ✅ **Module/File Name**: Clearly identify what this is
- ✅ **Purpose**: One-liner description
- ✅ **Usage**: How to use this (code example if complex)
- ✅ **Input Variables**: Parameters this accepts
- ✅ **Outputs**: What does it produce?
- ✅ **Resources Created**: List of infrastructure being created
- ✅ **References**: Links to docs, related files, ADRs
- ✅ **Dependencies**: External requirements
- ✅ **Security Considerations**: Any security implications
- ✅ **Notes**: Operational info, caveats, future work
- ✅ **Author**: Who wrote this?
- ✅ **Last Updated**: When did maintenance happen?
- ✅ **Change Log**: Major changes (last 3-5 entries)

### Shell Scripts (.sh)

**Mandatory Location**: At the top, before shebang or immediately after

```bash
#!/bin/bash
################################################################################
# [Category]: script-name.sh
# 
# Purpose: [One-sentence description of what this script does]
# 
# Usage: [How to invoke this script]
#   ./scripts/category/script-name.sh [required-arg] [optional-arg]
#   ./scripts/category/script-name.sh --help
#
# Examples:
#   # Deploy infrastructure to production
#   ./scripts/deploy/deploy-iac.sh production
#
#   # Preview changes without applying
#   ./scripts/deploy/deploy-iac.sh staging --plan-only
#
#   # Force full recreation of containers
#   ./scripts/deploy/deploy-containers.sh --force-recreate
#
# Arguments:
#   arg1 (required): Description of required argument
#   arg2 (optional, default: 'value'): Description of optional argument
#   --flag: Description of boolean flag
#
# Environment Variables:
#   SSH_HOST [required]: SSH host (default: $SSH_HOST, fallback: 192.168.168.31)
#   SSH_USER [required]: SSH username (default: $SSH_USER, fallback: akushnir)
#   LOG_DIR [optional]: Directory for logs (default: ./logs)
#   DEBUG [optional]: Set to 1 for debug output
#
# Output:
#   - Logs written to: logs/script-name-$(date +%s).log
#   - Exit code 0 on success, 1-3 on errors
#
# Prerequisites:
#   - Bash 4.0+
#   - terraform >= 1.6
#   - Docker daemon running
#   - SSH access to deployment host
#   - jq for JSON parsing
#   - curl for HTTP operations
#   - Functions from scripts/lib/common.sh and scripts/lib/logger.sh
#
# Exit Codes:
#   0 - Successful execution
#   1 - Terraform/deployment error
#   2 - Invalid arguments or missing prerequisites
#   3 - SSH connection failed
#   4 - Configuration validation failed
#
# Features:
#   - Automatic rollback on failure (if --rollback-on-failure set)
#   - Health checks after deployment
#   - Logging to both console and file
#   - Dry-run mode (--dry-run)
#
# Notes:
#   - This script requires production approval before apply
#   - Always creates backup before making changes
#   - Can be run from CI/CD with override environment variables
#   - Idempotent: safe to run multiple times
#
# Related Scripts:
#   - scripts/deploy/deploy-containers.sh - Complementary script
#   - scripts/health/health-check.sh - Health verification
#   - scripts/lib/common.sh - Shared functions
#
# Troubleshooting:
#   - If "SSH connection failed": Check SSH_HOST and SSH_USER variables
#   - If "terraform not found": Install terraform >= 1.6
#   - If "State lock timeout": Wait 5min for previous operation or manually unlock
#
# References:
#   - Deployment Guide: docs/guides/DEPLOYMENT.md
#   - Deployment Runbook: docs/runbooks/deployment/DEPLOYMENT-RUNBOOK.md
#   - Troubleshooting: docs/guides/TROUBLESHOOTING.md
#   - Terraform Docs: https://www.terraform.io/docs/
#
# Security:
#   - Never hardcode SSH passwords (use SSH keys)
#   - Mask secrets in log output
#   - Validate all inputs before execution
#   - Run with minimal required privileges
#
# Author: @akushnir
# Last Updated: 2026-04-14
# Change Log:
#   - 2026-04-14: Added --dry-run capability
#   - 2026-04-10: Consolidated phase-specific scripts into unified script
#   - 2026-04-01: Initial version
################################################################################

set -euo pipefail  # Strict mode: exit on error, undefined vars, pipe failures

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" || { echo "ERROR: Cannot source common.sh"; exit 2; }
source "${SCRIPT_DIR}/lib/logger.sh" || { echo "ERROR: Cannot source logger.sh"; exit 2; }

# Initialize
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="${LOG_DIR:-./logs}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME%.*}-$(date +%s).log"

# Implementation follows...
```

**Header Elements**:
- ✅ **Shebang**: `#!/bin/bash` (or appropriate shell)
- ✅ **Category**: scripts/category/
- ✅ **Script Name**: File name
- ✅ **Purpose**: One-liner
- ✅ **Usage**: Exact invocation syntax
- ✅ **Examples**: 3-4 real-world examples
- ✅ **Arguments**: All parameters and flags
- ✅ **Environment Variables**: Required and optional env vars
- ✅ **Output**: Where logs go, exit codes
- ✅ **Prerequisites**: All dependencies
- ✅ **Exit Codes**: Detailed error codes
- ✅ **Features**: Capabilities (dry-run, rollback, etc.)
- ✅ **Notes**: Operational info
- ✅ **Related Scripts**: Cross-references
- ✅ **Troubleshooting**: Common issues
- ✅ **References**: Documentation links
- ✅ **Security**: Security implications
- ✅ **Author**: Who wrote this?
- ✅ **Last Updated**: Maintenance date
- ✅ **Change Log**: Recent changes

### YAML Configuration (.yml / .yaml)

**Mandatory Location**: At the top of file (as YAML comment block)

```yaml
################################################################################
# Config: [Component Name]
# Purpose: [What does this configuration do?]
#
# Usage: [How is this file used?]
#   - Mounted as: /etc/prometheus/prometheus.yml
#   - Referenced by: terraform/modules/observability/main.tf
#   - Loaded by: prometheus container on startup
#
# Sections:
#   global: Global settings for all jobs
#   scrape_configs: Target configuration for metric scraping
#   rule_files: Alert rule definitions
#   alerting: AlertManager integration
#
# Parameters:
#   - scrape_interval (string, default: 15s): How often to scrape targets
#   - evaluation_interval (string, default: 15s): How often to evaluate alerts
#   - retention (duration, default: 15d): How long to keep metrics
#
# Environment Variables:
#   - PROMETHEUS_SCRAPE_INTERVAL: Override scrape_interval
#   - PROMETHEUS_RETENTION: Override retention period
#   - PROMETHEUS_LOG_LEVEL: Set log level (debug, info, warn, error)
#
# Related Files:
#   - docker/configs/prometheus/alert-rules.yml: Alert definitions
#   - terraform/modules/observability/main.tf: Terraform config
#   - docs/guides/DEPLOYMENT.md: Deployment guide
#
# Notes:
#   - Targets are service-discovery enabled via Docker labels
#   - Alert rules loaded from external file (rule_files section)
#   - HTTPS is configured but can be disabled via environment variable
#   - Retention is 15 days for production (configurable per environment)
#
# Security:
#   - Basic auth enabled for all scrape targets
#   - TLS verification required (except localhost)
#
# References:
#   - Prometheus Docs: https://prometheus.io/docs/prometheus/latest/
#   - Configuration Guide: https://prometheus.io/docs/prometheus/latest/configuration/
#   - Service Discovery: docker/README.md
#
# Author: @akushnir
# Last Updated: 2026-04-14
# Change Log:
#   - 2026-04-14: Added retention configuration
#   - 2026-04-10: Enabled HTTPS verification
################################################################################

global:
  scrape_interval: ${PROMETHEUS_SCRAPE_INTERVAL:-15s}
  evaluation_interval: 15s
  external_labels:
    cluster: 'code-server-enterprise'
    environment: '${ENVIRONMENT:-development}'

# Implementation follows...
```

### Python Files (.py)

**Mandatory Location**: Module-level docstring at top

```python
"""
Module: health_check

Purpose:
    Health check utilities for code-server infrastructure validation.

Classes:
    HealthChecker: Main orchestrator for all health checks
    DockerHealthCheck: Docker daemon and container health validation
    TerraformHealthCheck: Terraform state and configuration validation

Functions:
    check_system_health(): Run all health checks
    check_docker_health(): Verify Docker daemon functionality
    check_terraform_state(): Validate terraform state integrity
    check_services(verbose=False): Check all running services

Usage:
    As Python module:
        from health_check import HealthChecker
        checker = HealthChecker()
        checker.run_all_checks()

    As CLI:
        python -m health_check --verbose
        python -m health_check --skip-docker

Examples:
    Check all services with verbose output:
        python health_check.py --verbose

    Check only Terraform state:
        python health_check.py --check terraform

    Generate JSON output for monitoring:
        python health_check.py --format json > health-report.json

Environment Variables:
    DEBUG: Set to 1 for debug output
    LOG_LEVEL: Set to DEBUG, INFO, WARN, ERROR
    DOCKER_HOST: Docker daemon socket (default: unix:///var/run/docker.sock)
    TF_LOG: Terraform log level (TRACE, DEBUG, INFO, WARN, ERROR)

Requirements:
    - Python 3.8+
    - docker library (pip install docker)
    - terraform >= 1.6
    - jq (external command)
    - curl (external command)

Dependencies:
    - modules/docker_utils.py: Docker interaction utilities
    - modules/terraform_utils.py: Terraform state utilities
    - config/health_check_config.yaml: Configuration parameters

References:
    - Troubleshooting Guide: docs/guides/TROUBLESHOOTING.md
    - Health Check Runbook: docs/runbooks/health-check/
    - Docker SDK: https://docker-py.readthedocs.io/
    - Terraform: https://www.terraform.io/docs/

Exit Codes:
    0 - All checks passed
    1 - One or more checks failed
    2 - Configuration error
    3 - Missing dependencies

Notes:
    - Idempotent: safe to run multiple times
    - Non-blocking: continues on individual check failures
    - Verbose mode provides detailed diagnostic information
    - JSON output suitable for parsing by monitoring tools

Security:
    - No credentials stored in code (loaded from environment)
    - Docker socket access validated
    - Terraform state permissions verified

Author: @akushnir
Last Updated: 2026-04-14
Change Log:
    - 2026-04-14: Added JSON output format
    - 2026-04-10: Initial implementation
"""

import logging
import sys
from typing import Dict, List

# Implementation follows...
```

### Dockerfile

**Mandatory Location**: At top as comment block

```dockerfile
################################################################################
# Dockerfile: code-server
#
# Purpose: Custom code-server image with enterprise features
#
# Base Image: codercom/code-server:4.115.0
#
# Features:
#   - Custom entrypoint with initialization hooks
#   - Pre-installed extensions for Python, Terraform, Docker
#   - Security scanning tools integrated
#   - Enterprise authentication support
#
# Build Arguments:
#   VERSION: code-server version (default: 4.115.0)
#   BUILD_DATE: Build timestamp
#   VCS_REF: Git commit SHA
#
# Environment Variables (at runtime):
#   PASSWORD: Code-server password (required)
#   SUDO_PASSWORD: Sudo password (required)
#   CODE_SERVER_PORT: Port to listen on (default: 8080)
#   EXTENSIONS: Space-separated list of extensions to install
#   EXAMPLE: CODE_SERVER_PORT=9000 PASSWORD=mysecret
#
# Usage:
#   docker build -t code-server:custom .
#   docker run -d -p 8080:8080 -e PASSWORD=mysecret code-server:custom
#
# Related Files:
#   - entrypoint.sh: Initialization script
#   - docker/docker-compose.yml: Orchestration
#   - docs/guides/DEPLOYMENT.md: Deployment guide
#
# Author: @akushnir
# Last Updated: 2026-04-14
################################################################################

FROM codercom/code-server:4.115.0

# Implementation follows...
```

---

## Inline Comments

Comments in code should explain **WHY**, not **WHAT**. The code shows WHAT; comments explain WHY.

### ❌ Bad Comments (Explain WHAT the code does)

```bash
# Loop through all servers
for server in "${servers[@]}"; do
  # Call the deploy function
  deploy "$server"
done
```

### ✅ Good Comments (Explain WHY and provide context)

```bash
# CONTEXT: Deploy to each server sequentially to detect early failures
# WHY: Parallel deployment would be faster but makes it harder to identify
#      which host caused a failure. Sequential is safer for production.
# REFERENCE: docs/runbooks/deployment/DEPLOYMENT-RUNBOOK.md#sequential-deployment
for server in "${servers[@]}"; do
  deploy "$server"
done
```

### Comment Format

Use this format for non-trivial logic:

```bash
# CONTEXT: [What are we doing at high level?]
# WHY: [Why are we doing it this way instead of alternatives?]
# REFERENCE: [Docs/ADR/issue explaining this decision]
# GOTCHA: [Any subtle issues or edge cases?]
code_goes_here
```

### Examples

**Terraform Example**:
```hcl
# CONTEXT: Force recreation when image changes to always get latest patches
# WHY: Cached images may have security vulnerabilities. Always pulling ensures
#      we deploy with the latest security updates.
# REFERENCE: docs/adc/ADR-002-IMAGE-UPDATE-STRATEGY.md
# GOTCHA: This means deployments will be slower but more secure. Cannot be disabled
#         except for emergency/testing via -refresh=false (not recommended)
triggers = {
  image_id = docker_image.code_server.id
}
```

**Shell Script Example**:
```bash
# CONTEXT: Wait for database before starting application
# WHY: Application will crash immediately if database isn't ready.
#      Exponential backoff prevents hammering database during startup.
# REFERENCE: docs/runbooks/deployment/DEPLOYMENT-RUNBOOK.md#startup-sequence
# GOTCHA: Max 30 second delay; if DB still not ready, we fail (better than
#         hanging forever or crashing immediately)
wait_for_db_with_backoff 30 seconds || {
  log_error "Database not ready after 30 seconds"
  exit 1
}
```

### Rules

- Comment complex business logic
- Comment non-obvious infrastructure decisions
- Comment security-sensitive code
- DON'T comment obvious code: `x = x + 1  # Increment x`
- DON'T comment what the code does: `docker ps  # List running containers`
- DO comment WHY we chose this approach
- DO reference documentation where decisions are explained

---

## README Standards

**Every directory must have a README.md** that explains:

### Minimum Contents

```markdown
# [Directory Name]

**Purpose**: One-sentence description of what this directory contains.

## Structure

Brief description of the layout:

\`\`\`
directory/
├── subdirectory/ - Purpose of this subdirectory
├── file1.tf - What this file does
├── file2.sh - What this script does
└── README.md - This file
\`\`\`

## Getting Started

How do I use the contents of this directory?

\`\`\`
Example commands or workflows
\`\`\`

## Important Files

| File | Purpose | When to use |
|------|---------|------------|
| main.tf | Primary configuration | Always loaded first |
| variables.tf | Input parameters | Define new variables here |

## Common Tasks

### Task 1: Do something

Steps to accomplish this task:

\`\`\`bash
command_to_run
\`\`\`

### Task 2: Do something else

Steps:

\`\`\`bash
another_command
\`\`\`

## Troubleshooting

### Issue: Something goes wrong
**Cause**: Why this happens  
**Solution**: How to fix it

### Issue: Another problem
**Cause**: Why  
**Solution**: How to fix

## See Also

- [Related documentation](../docs/GUIDE.md)
- [Related script](../scripts/deploy/deploy.sh)
- [External reference](https://example.com)

## Maintenance

**Owner**: @username  
**Last Updated**: 2026-04-14  
**Known Issues**: None currently
```

### Directory-Specific Examples

**docs/README.md**:
```markdown
# Documentation

**Purpose**: All project documentation centralized here.

## Structure

- **guides/**: Step-by-step operational guides
- **adc/**: Architecture Decision Records
- **runbooks/**: Operational procedures
- **archived/**: Historical documentation

## Quick Navigation

- New to the project? Start with [GETTING-STARTED.md](GETTING-STARTED.md)
- Want to deploy? See [guides/DEPLOYMENT.md](guides/DEPLOYMENT.md)
- Need to troubleshoot? See [guides/TROUBLESHOOTING.md](guides/TROUBLESHOOTING.md)
- Architectural questions? See [adc/](adc/)
```

**scripts/README.md**:
```markdown
# Scripts

**Purpose**: Operational and maintenance scripts organized by category.

## Structure

- **install/**: Installation and setup
- **deploy/**: Deployment automation
- **health/**: Health checks and validation
- **maintenance/**: Backup, restore, cleanup
- **dev/**: Development utilities
- **ci/**: CI/CD operations
- **lib/**: Shared functions (source these in your scripts)

## Using Scripts

All scripts have built-in help:

\`\`\`bash
./scripts/category/script-name.sh --help
\`\`\`

## Common Operations

### Deploy infrastructure

\`\`\`bash
make deploy-iac-prod  # See Makefile for targets
\`\`\`

### Check health

\`\`\`bash
./scripts/health/health-check.sh --verbose
\`\`\`

## Script Development

When adding a new script:
1. Place in appropriate category directory
2. Add full header documentation (see CODE-QUALITY-STANDARDS.md)
3. Source `scripts/lib/common.sh` and `scripts/lib/logger.sh`
4. Test locally before committing
5. Add target to scripts/Makefile
```

**terraform/README.md**:
```markdown
# Terraform Configuration

**Purpose**: Infrastructure-as-code for entire code-server deployment.

## Structure

- **main.tf**: Single source of truth (all resources defined here)
- **variables.tf**: Input variable definitions
- **outputs.tf**: Output definitions
- **modules/**: Reusable Terraform modules
- **environments/**: Environment-specific variable overrides
- **hosts/**: Host-specific variable overrides

## Getting Started

### Initialize Terraform

\`\`\`bash
cd terraform
terraform init
\`\`\`

### Plan changes

\`\`\`bash
terraform plan -var-file=environments/production.tfvars
\`\`\`

### Apply changes

\`\`\`bash
terraform apply -var-file=environments/production.tfvars
\`\`\`

## Environment Variable Hierarchy

Variables are resolved in this order (highest precedence first):

1. Command-line: `terraform apply -var="foo=bar"`
2. Environment files: `environments/*.tfvars`
3. Host-specific: `hosts/*.tfvars`
4. Variable defaults: `variables.tf`

When deploying to production host 192.168.168.31:

\`\`\`bash
terraform apply \\
  -var-file=environments/production.tfvars \\
  -var-file=hosts/192.168.168.31.tfvars
\`\`\`

## Modules

Reusable modules for common infrastructure:

- **modules/containers/**: Docker container orchestration
- **modules/networking/**: Network configuration
- **modules/security/**: Security groups and policies
- **modules/observability/**: Monitoring and logging

## Important Files to Understand

| File | Purpose |
|------|---------|
| main.tf | All resources - read this first |
| variables.tf | Parameters - see what's configurable |
| outputs.tf | What gets exported |
| versions.tf | Provider requirements |
```

---

## Code Structure

### Terraform Organization

**Single Source of Truth**:
```hcl
# terraform/main.tf - EVERYTHING goes here (not separate .tf files)

# Providers
terraform {
  required_providers { ... }
}

provider "docker" { ... }

# Resources Section 1: Containers
resource "docker_image" "code_server" { ... }
resource "docker_container" "code_server" { ... }

# Resources Section 2: Networking
resource "docker_network" "enterprise" { ... }

# Modules
module "monitoring" {
  source = "./modules/observability"
  ...
}
```

**Bad** (code scattered across files):
```
terraform/
├── main.tf - Some resources
├── containers.tf - Container resources
├── networking.tf - Network resources (DON'T DO THIS)
└── phase-20.tf - Phase-specific resources
```

### Script Structure

```bash
#!/bin/bash
################################################################################
# [Header - see header section above]
################################################################################

set -euo pipefail

# 1. CONFIGURATION - Define constants and defaults
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${LOG_DIR:-./logs}"

# 2. SOURCE DEPENDENCIES - Source other scripts/libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logger.sh"

# 3. FUNCTION DEFINITIONS - Define reusable functions
validate_inputs() {
  # Validate arguments
}

preflight_checks() {
  # Check prerequisites
}

main_operation() {
  # Do the main work
}

cleanup() {
  # Clean up on exit
}

# 4. MAIN EXECUTION
main() {
  log_info "Starting $SCRIPT_NAME"
  
  preflight_checks || exit 2
  validate_inputs "$@" || exit 2
  main_operation "$@" || exit 1
  
  log_info "$SCRIPT_NAME completed successfully"
}

# Execute main, cleanup on exit
trap cleanup EXIT
main "$@"
```

---

## Configuration Comments

Every configuration file should have inline comments explaining non-obvious settings:

### ✅ Good Configuration Comments

```yaml
# prometheus.yml

global:
  # Scrape every 15 seconds - balance between freshness and load
  # Override with PROMETHEUS_SCRAPE_INTERVAL environment variable
  scrape_interval: ${PROMETHEUS_SCRAPE_INTERVAL:-15s}
  
  # Evaluate alert rules every 15 seconds
  # Must be <= global.scrape_interval
  evaluation_interval: 15s
  
  # Keep metrics for 15 days - balance between history and disk space
  # Production default; override in environments/*.tfvars
  retention: 15d
```

### ✅ Configuration Comments for Infrastructure

```hcl
# terraform/variables.tf

variable "code_server_memory" {
  type        = string
  description = "Memory limit for code-server container (e.g., '2g', '4g')"
  default     = "2g"
  
  # Developer notes explaining the choice
  # Why 2g? Code-server typically uses 400-600MB. Set to 2g for:
  # - Workspace growth (users add more files)
  # - Extension overhead (each extension uses memory)
  # - Safety margin to prevent OOM kills
  # Override to 4g if experiencing slowdowns with large workspaces
  # Reference: https://github.com/coder/code-server/issues/7065
}
```

---

## Link & Reference Standards

### Internal Documentation Links

Use **relative paths**. Never absolute URLs.

✅ **Good**:
```markdown
See [Deployment Guide](docs/guides/DEPLOYMENT.md)
See [ADR-001](docs/adc/ADR-001-CLOUDFLARE-TUNNEL.md)
Related: [../scripts/deploy/deploy-iac.sh](../scripts/deploy/deploy-iac.sh)
```

❌ **Bad**:
```markdown
See https://github.com/kushin77/code-server-enterprise/docs/guides/DEPLOYMENT.md
See /docs/adc/ADR-001.md
See the deployment doc
```

### Code References in Comments

Link to the code being referenced:

```bash
# Source the common functions before using them
# Reference: scripts/lib/common.sh:log_info()
source "${SCRIPT_DIR}/lib/common.sh"
```

### External Reference Standards

For external references (Terraform registry, Docker Hub, etc.):

```hcl
# REFERENCE (with version):
# - Terraform Docker Provider: https://registry.terraform.io/providers/kreuzwerker/docker/3.0.2
# - Docker Image: https://hub.docker.com/_/prometheus (v2.48.0)
```

---

## Changelog & Version Management

### File Changelog Section

In file headers, maintain recent change history:

```
Change Log:
  - 2026-04-14: Added consolidated docker-compose base configuration
  - 2026-04-10: Refactored monitoring configuration from 3 files to single module
  - 2026-04-01: Initial configuration
```

### Version File Example

For released artifacts, use version file:

```
VERSION=1.0.0-alpha.1

# Format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
# MAJOR: Breaking changes to API/deployment
# MINOR: New features, backwards compatible
# PATCH: Bug fixes only
# PRERELEASE: alpha, beta, rc (pre-release)
# BUILD: Build metadata (ignored for precedence, shown in reports)

# Examples:
# 1.0.0 - Production release
# 1.0.0-rc.1 - Release candidate 1
# 1.1.0-alpha.1 - Next version pre-release
# 1.0.0+build.123 - Build metadata
```

---

## Linting & Automated Checks

These standards are enforced by:

**Pre-commit hooks** (`make lint-local`):
- Shell script linting (shellcheck)
- Terraform format (terraform fmt)
- YAML linting (yamllint)
- Document link validation

**CI/CD checks** (.github/workflows/):
- All of the above
- Block merge on violations
- Generate lint reports

---

## Exceptions

### When Comments are Optional

- Simple variable assignments
- Obvious operations (arithmetic, string concatenation)
- Self-documenting code with clear names

### When Headers are Optional

- Small utility files (< 50 lines) that are obviously simple
- Test files (covered by test documentation)
- Generated files (e.g., from templates)

**But default to including them** - extra clarity never hurts.

---

## Checklist: Code Quality Review

Before committing, verify:

- [ ] File has proper header with Purpose/Usage/References
- [ ] Complex logic has inline comments explaining WHY
- [ ] All directories have README.md
- [ ] Internal links are relative paths
- [ ] External references have full URLs with versions
- [ ] No hardcoded secrets
- [ ] Change log in header is recent
- [ ] Author and Last Updated are current
- [ ] Code follows single source of truth principle
- [ ] No duplicate configurations
- [ ] Configuration parameters are documented

---

**Remember**: Documentation IS code. Write it with the same care and precision as production code.
