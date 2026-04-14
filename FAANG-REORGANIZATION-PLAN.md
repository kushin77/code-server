# FAANG-Style Repository Reorganization Plan
**Code-Server-Enterprise Repository Structure Overhaul**

**Status**: PROPOSAL  
**Priority**: HIGH (Prerequisite for governance mandate)  
**Timeline**: 3-4 weeks (phased implementation)  
**Effort**: ~40-50 hours  

---

## 1. EXECUTIVE SUMMARY

### Current State: 6/10 Health Score
- ✅ Application code is clean (backend/, frontend/)
- ✅ Documentation is comprehensive (docs/)
- ❌ Root directory has 200+ files (unmaintainable)
- ❌ scripts/ has 200+ files with no organization
- ❌ Terraform configuration scattered across root + subdirectories
- ❌ 25+ status reports (excessive)
- ❌ 8+ docker-compose variants (duplication)

### Target State: 9/10 Health Score
- ✅ All application code in `/src`
- ✅ All configuration in `/config`
- ✅ All infrastructure in `/infra`
- ✅ All documentation organized by type
- ✅ All scripts indexed by purpose
- ✅ Root directory: Only 15-20 files (README, LICENSE, Makefile, etc.)

---

## 2. PROPOSED FAANG-STYLE STRUCTURE (5 Levels Deep)

```
code-server-enterprise/
│
├── README.md                          Project overview
├── LICENSE                            Apache 2.0
├── Makefile                          Build targets (dev, test, deploy, clean)
├── .github/                          GitHub templates
│   ├── workflows/                   CI/CD pipelines
│   ├── ISSUE_TEMPLATE/              Issue templates
│   └── PULL_REQUEST_TEMPLATE/       PR templates
│
├── .gitignore                         Ignore rules (logs, binaries, certs)
├── .editorconfig                      Editor standards (tabs, line endings)
├── docker-compose.yml                ACTIVE only (not variants)
├── .env                              Production env (secret-masked)
│
└── src/                              ★ APPLICATION CODE
    ├── backend/                      Python/FastAPI application
    │   ├── main.py                   Entry point
    │   ├── requirements.txt          Dependencies
    │   ├── Dockerfile                Container definition
    │   ├── .env.example              Example env file
    │   ├── src/
    │   │   ├── api/
    │   │   │   ├── __init__.py
    │   │   │   ├── routes/           REST endpoints
    │   │   │   │   ├── users.py
    │   │   │   │   ├── auth.py
    │   │   │   │   └── ...
    │   │   │   ├── models/           Pydantic request/response
    │   │   │   └── dependencies.py   FastAPI dependencies
    │   │   │
    │   │   ├── db/
    │   │   │   ├── database.py       SQLAlchemy connection
    │   │   │   ├── models.py         ORM schema (users, roles, etc.)
    │   │   │   └── migrations/       Alembic migrations
    │   │   │
    │   │   ├── auth/
    │   │   │   ├── oauth2.py         OAuth2 provider logic
    │   │   │   ├── jwt.py            JWT token handling
    │   │   │   └── permissions.py    RBAC authorization
    │   │   │
    │   │   ├── middleware/
    │   │   │   ├── logging.py        Request/response logging
    │   │   │   ├── tracing.py        OpenTelemetry tracing
    │   │   │   └── security.py       Security headers
    │   │   │
    │   │   ├── utils/
    │   │   │   ├── logger.py         Logging utilities
    │   │   │   ├── validators.py     Input validators
    │   │   │   └── exceptions.py     Custom exceptions
    │   │   │
    │   │   ├── tasks/
    │   │   │   ├── celery_app.py     Celery configuration
    │   │   │   └── background_jobs.py Async task definitions
    │   │   │
    │   │   ├── tests/
    │   │   │   ├── conftest.py       pytest fixtures
    │   │   │   ├── test_auth.py      Auth tests
    │   │   │   ├── test_api.py       API tests
    │   │   │   └── integration/      Integration tests
    │   │   │
    │   │   └── __init__.py
    │   │
    │   └── docs/
    │       └── BACKEND.md            Backend API documentation
    │
    ├── frontend/                      React/TypeScript application
    │   ├── package.json               Dependencies
    │   ├── vite.config.ts            Build configuration
    │   ├── tsconfig.json             TypeScript config
    │   ├── .env.example               Example env file
    │   ├── index.html                Entry HTML
    │   ├── src/
    │   │   ├── main.tsx              React entry
    │   │   ├── App.tsx               Root component
    │   │   ├── index.css             Tailwind imports
    │   │   │
    │   │   ├── pages/                Page-level components
    │   │   │   ├── Login.tsx
    │   │   │   ├── Dashboard.tsx
    │   │   │   ├── UserManagement.tsx
    │   │   │   └── ...
    │   │   │
    │   │   ├── components/           Reusable components
    │   │   │   ├── Header.tsx
    │   │   │   ├── Sidebar.tsx
    │   │   │   ├── Button.tsx
    │   │   │   └── ...
    │   │   │
    │   │   ├── hooks/                Custom React hooks
    │   │   │   ├── useAuth.ts
    │   │   │   ├── useFetch.ts
    │   │   │   └── ...
    │   │   │
    │   │   ├── types/                TypeScript interfaces
    │   │   │   ├── user.ts
    │   │   │   ├── api.ts
    │   │   │   └── ...
    │   │   │
    │   │   ├── services/             API client services
    │   │   │   ├── auth.ts
    │   │   │   ├── user.ts
    │   │   │   └── api.ts            Axios instance
    │   │   │
    │   │   ├── store/                State management (if using Redux)
    │   │   │   ├── slices/
    │   │   │   ├── store.ts
    │   │   │   └── hooks.ts
    │   │   │
    │   │   ├── utils/                Frontend utilities
    │   │   │   ├── formatters.ts
    │   │   │   ├── validators.ts
    │   │   │   └── helpers.ts
    │   │   │
    │   │   └── tests/
    │   │       ├── components/
    │   │       ├── hooks/
    │   │       └── integration/
    │   │
    │   └── docs/
    │       └── FRONTEND.md           Frontend component docs
    │
    └── shared/                        Shared utilities (optional)
        ├── constants.ts              Shared constants
        ├── types.ts                  Shared TypeScript types
        └── utils.ts                  Shared utility functions

│
├── infra/                            ★ INFRASTRUCTURE & DEPLOYMENT
    │
    ├── docker/
    │   ├── code-server/
    │   │   ├── Dockerfile            code-server container
    │   │   ├── entrypoint.sh          Init script
    │   │   └── config.yaml            code-server config
    │   │
    │   ├── caddy/
    │   │   ├── Dockerfile            Caddy reverse proxy
    │   │   └── Caddyfile             Load balancing config
    │   │
    │   ├── ollama/
    │   │   └── Dockerfile            Ollama LLM server
    │   │
    │   └── base.Dockerfile           Multi-stage base image
    │
    ├── kubernetes/                    (If K8s deployment added later)
    │   ├── manifests/
    │   ├── helm-charts/
    │   └── kustomize/
    │
    ├── terraform/
    │   ├── README.md                 Terraform deployment guide
    │   ├── versions.tf               Required provider versions
    │   ├── provider.tf               Cloud provider config
    │   │
    │   ├── main/                     Production configuration
    │   │   ├── main.tf               Primary resource definitions
    │   │   ├── variables.tf          Input variables
    │   │   ├── locals.tf             Local values (consolidations)
    │   │   ├── outputs.tf            Output values
    │   │   └── terraform.tfvars      Production variables
    │   │
    │   ├── modules/                  Reusable modules
    │   │   ├── compute/
    │   │   │   ├── main.tf
    │   │   │   ├── variables.tf
    │   │   │   └── outputs.tf
    │   │   │
    │   │   ├── networking/
    │   │   │   ├── main.tf
    │   │   │   ├── variables.tf
    │   │   │   └── outputs.tf
    │   │   │
    │   │   ├── security/
    │   │   │   ├── main.tf
    │   │   │   ├── variables.tf
    │   │   │   └── outputs.tf
    │   │   │
    │   │   └── monitoring/
    │   │       ├── main.tf
    │   │       ├── variables.tf
    │   │       └── outputs.tf
    │   │
    │   ├── environments/
    │   │   ├── staging/
    │   │   │   └── terraform.tfvars  Staging variables
    │   │   │
    │   │   └── production/
    │   │       └── terraform.tfvars  Production variables
    │   │
    │   └── scripts/
    │       ├── plan.sh               Run terraform plan
    │       ├── apply.sh              Run terraform apply
    │       ├── destroy.sh            Run terraform destroy
    │       └── validate.sh           Validate configuration
    │
    └── monitoring/
        ├── prometheus/
        │   ├── prometheus.yml        Metrics collection
        │   └── alerts.yml            Alert rule definitions
        │
        ├── grafana/
        │   ├── datasources.yml       Data source configs
        │   └── dashboards/           Dashboard JSON files
        │
        ├── alertmanager/
        │   ├── config.yml            Alert routing
        │   └── templates/
        │
        └── observability.md          Monitoring architecture

│
├── config/                           ★ CONFIGURATION & SECRETS
    │
    ├── docker-compose.yml            Main composition (keep here + root symlink)
    ├── docker-compose.override.yml   Dev overrides
    │
    ├── caddy/
    │   ├── Caddyfile                 Main (keep here + root symlink)
    │   └── Caddyfile.env             Environment-based variants
    │
    ├── env/
    │   ├── .env.example              Example (check-in safe)
    │   ├── .env.production           [GITIGNORED] Prod secrets
    │   ├── .env.staging              [GITIGNORED] Staging variables
    │   └── .env.development          [LOCAL] Dev variables
    │
    ├── secrets/                      [GITIGNORED] Runtime secrets
    │   ├── .README                   "Store SSL certs, API keys here"
    │   └── tls/
    │       ├── cert.pem              HTTPS certificate
    │       ├── key.pem               Private key
    │       └── ca.pem                CA certificate
    │
    └── nginx/                        (If nginx used instead of Caddy)
        ├── nginx.conf                Main config
        └── conf.d/                   Snippet configs

│
├── scripts/                          ★ OPERATIONAL SCRIPTS (INDEXED)
    │
    ├── README.md                     ★★★ SCRIPT INDEX (CRITICAL)
    │   ├── Quick reference table of all scripts
    │   ├── Categorized by purpose
    │   ├── Active vs deprecated status
    │   └── Examples of how to use each
    │
    ├── lifecycle/                    Infrastructure lifecycle
    │   ├── deploy.sh                 Deploy containers
    │   ├── undeploy.sh               Stop and remove containers
    │   ├── restart.sh                Restart services
    │   ├── health-check.sh           Verify all services healthy
    │   └── status.sh                 Show current state
    │
    ├── operations/                   Daily operations
    │   ├── backup.sh                 Backup databases/data
    │   ├── restore.sh                Restore from backup
    │   ├── update-dependencies.sh    Update all containers
    │   ├── cleanup-old-logs.sh       Rotate and archive logs
    │   └── inspect-logs.sh           Search logs across containers
    │
    ├── security/                     Security & access management
    │   ├── manage-users.sh           Add/remove users
    │   ├── rotate-secrets.sh         Rotate API keys
    │   ├── audit-access.sh           List who accessed what
    │   └── enable-mfa.sh             Enable MFA for user
    │
    ├── monitoring/                   Observability & debugging
    │   ├── view-metrics.sh           Query Prometheus
    │   ├── tail-logs.sh              Follow logs from containers
    │   ├── performance-report.sh     Generate perf analysis
    │   ├── trace-request.sh          Trace single request
    │   └── docker-health-monitor.sh  Monitor container health
    │
    ├── testing/                      Validation & testing
    │   ├── test-connectivity.sh      Test all ports accessible
    │   ├── load-test.sh              Run load test
    │   ├── integration-test.sh       Run E2E tests
    │   ├── smoke-test.sh             Quick sanity check
    │   └── validate-config.sh        Validate all configs
    │
    ├── development/                  Developer utilities
    │   ├── setup-local-dev.sh        Setup local dev environment
    │   ├── watch-logs.sh             Watch logs in real-time
    │   ├── rebuild-container.sh       Rebuild single container
    │   └── exec-container.sh         Execute command in container
    │
    ├── cicd/                         CI/CD pipeline scripts
    │   ├── run-tests.sh              Run full test suite
    │   ├── build-and-push.sh         Build images and push to registry
    │   ├── run-linters.sh            Run code quality checks
    │   └── security-scan.sh          Scan for vulnerabilities
    │
    └── archived/                     [DEPRECATED]
        ├── DEPRECATED.md             List of deprecated scripts
        ├── phase-13-*.sh             (Documented but not executed)
        ├── phase-14-*.sh
        ├── ... through phase-20-*.sh
        └── README                    Why these were archived

│
├── docs/                             ★ DOCUMENTATION (BY PURPOSE)
    │
    ├── README.md                     Documentation index
    │
    ├── reference/                    API & system reference
    │   ├── API.md                    REST API endpoints
    │   ├── DATABASE_SCHEMA.md        Database tables & relationships
    │   ├── CONFIGURATION.md          All configurable parameters
    │   └── ARCHITECTURE.md           System design & components
    │
    ├── guides/                       How-to guides
    │   ├── GETTING_STARTED.md        Quick start for new devs
    │   ├── LOCAL_DEVELOPMENT.md      Setup dev environment
    │   ├── DEPLOYMENT.md             How to deploy to prod
    │   ├── TROUBLESHOOTING.md        Common issues & fixes
    │   └── SCALING.md                How to scale system
    │
    ├── operations/                   Operational runbooks
    │   ├── INCIDENT_RESPONSE.md      How to handle outages
    │   ├── BACKUP_RECOVERY.md        Backup & recovery procedures
    │   ├── MAINTENANCE_WINDOWS.md    Scheduled maintenance
    │   ├── PERFORMANCE_TUNING.md     Optimization guidelines
    │   └── UPGRADING.md              Version upgrade process
    │
    ├── security/                     Security documentation
    │   ├── SECURITY_POLICY.md        Vulnerability disclosure
    │   ├── RBAC_GUIDE.md             Role-based access control
    │   ├── AUDIT_LOGGING.md          Audit trail documentation
    │   └── SECRETS_MANAGEMENT.md     Managing secrets & certs
    │
    ├── architecture/                 Architecture Decision Records
    │   ├── ADR-000-TEMPLATE.md       Template for new ADRs
    │   ├── ADR-001-CLOUDFLARE-TUNNEL.md
    │   ├── ADR-002-DATABASE-CHOICE.md
    │   ├── ADR-003-MONITORING-STACK.md
    │   ├── ADR-004-CONSOLIDATION-PATTERNS.md
    │   ├── ADR-005-COMPOSITION-INHERITANCE.md
    │   └── README.md                 ADR index
    │
    ├── phases/                       Phase-specific documentation
    │   ├── phase-14-summary.md       P14 final summary (KEEP)
    │   ├── phase-21-summary.md       P21 final summary (KEEP)
    │   └── README.md                 "Legacy phases archived, see ../archived/"
    │
    ├── slos/
    │   ├── AVAILABILITY_SLO.md       99.9% uptime target
    │   ├── LATENCY_SLO.md            <100ms p99 target
    │   └── ERROR_BUDGET.md           Error budget tracking
    │
    ├── CONTRIBUTING.md               Code review standards
    ├── GOVERNANCE.md                 Repository governance
    ├── CODINGSTYLE.md                Code style guide
    ├── TESTING.md                    Test strategy
    ├── CHANGELOG.md                  Version history
    └── GLOSSARY.md                   Terminology reference

│
├── tests/                            ★ TEST SUITE (CENTRALIZED)
    │
    ├── unit/                         Unit tests (fast)
    │   ├── test_auth.py
    │   ├── test_utils.py
    │   └── ...
    │
    ├── integration/                  Integration tests (medium)
    │   ├── test_api_endpoints.py
    │   ├── test_database.py
    │   └── ...
    │
    ├── e2e/                          End-to-end tests (slow)
    │   ├── test_full_flow.py
    │   ├── test_login_flow.py
    │   └── ...
    │
    ├── fixtures/                     Test data and fixtures
    │   ├── sample_users.json
    │   ├── sample_roles.json
    │   └── ...
    │
    ├── conftest.py                   pytest configuration
    └── README.md                     Test documentation

│
├── archived/                         ★ HISTORICAL ARTIFACTS
    │
    ├── README.md                     Guide to archived materials
    │
    ├── docker-compose-variants/      Old docker-compose files (reference only)
    │   ├── docker-compose.production.yml
    │   ├── docker-compose.base.yml
    │   └── README.md                 Why these were superseded
    │
    ├── terraform-old/                Phase 13-19 Terraform (reference only)
    │   ├── phase-13/
    │   ├── phase-14/
    │   └── README.md                 Why these were superseded
    │
    ├── scripts-phase-13-19/          Deprecated scripts (reference only)
    │   ├── README.md                 Index of deprecated scripts
    │   ├── phase-13-*.sh
    │   ├── phase-14-*.sh
    │   └── ... through phase-20-*.sh
    │
    ├── status-reports/               Historical status/exec reports
    │   ├── PHASE-14-COMPLETION.md    Final Phase 14 report
    │   ├── PHASE-21-COMPLETION.md    Final Phase 21 report
    │   ├── 2026-04-10-status.md      Dated checkpoints (reference)
    │   └── README.md                 How to search archived reports
    │
    ├── designs/                      Prototype designs (pre-Phase 14)
    │   ├── gpu-implementation/*.md
    │   ├── nas-integration/*.md
    │   └── README.md                 Why these were shelved/redesigned
    │
    ├── learning/                     Research & investigation notes
    │   ├── cloudflare-tunnel-investigation.md
    │   ├── gpu-driver-investigation.md
    │   └── README.md                 How to search learning materials
    │
    └── timeline/                     Historical timelines & planning
        ├── execution-timeline.md
        ├── milestones.md
        └── README.md

│
├── .env.example                      Example environment file (check-in)
├── .env.production                   [GITIGNORED] Prod secrets
├── .env.staging                      [GITIGNORED] Staging config
│
├── .gitignore                        Ignore rules (UPDATED)
├── .pre-commit-config.yaml           Pre-commit hook config
├── .github/
│   ├── workflows/                   CI/CD pipelines
│   ├── ISSUE_TEMPLATE/
│   ├── PULL_REQUEST_TEMPLATE/
│   └── dependabot.yml               Dependency updates
│
├── Makefile                          Build targets (EXAMPLE BELOW)
├── SECURITY.md                       Vulnerability reporting
├── CODE_OF_CONDUCT.md                Community guidelines
└── CHANGELOG.md                      Release notes

```

---

## 3. NEW FILE STANDARDS (METADATA & DOCUMENTATION)

### 3.1 Shell Script Header Template

Every shell script MUST include:

```bash
#!/bin/bash
################################################################################
#
# Script Name: deploy.sh
# Purpose: Deploy containers to production using docker-compose
# 
# Usage:
#   ./scripts/lifecycle/deploy.sh
#   ./scripts/lifecycle/deploy.sh --dry-run    # Preview changes
#   ./scripts/lifecycle/deploy.sh --force      # Force recreation
#
# Requirements:
#   - Docker daemon running
#   - SSH access to 192.168.168.31 (production host)
#   - docker-compose.yml in /config
#
# Dependencies:
#   - docker-compose
#   - docker
#   - curl (for health checks)
#
# Exit Codes:
#   0    - Successful deployment
#   1    - Deployment failed (see logs)
#   2    - Configuration invalid
#   3    - Prerequisites not met
#
# Author: Engineering Team
# Created: 2026-04-15
# Last Modified: 2026-04-15
# Version: 2.1
#
# RELATED DOCUMENTATION:
#   - docs/guides/DEPLOYMENT.md          How to deploy step-by-step
#   - docs/operations/INCIDENT_RESPONSE.md  What to do if deploy fails
#   - infra/docker/Dockerfile           Container definitions
#
# CHANGE LOG:
#   v2.1 (2026-04-15) - Add --force flag, improve error messages
#   v2.0 (2026-04-10) - Migrate to docker-compose from docker swarm
#   v1.0 (2026-03-01) - Initial implementation
#
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/config/docker-compose.yml"
LOG_FILE="${PROJECT_ROOT}/logs/deploy-$(date +%Y%m%d-%H%M%S).log"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Source shared logging library (required)
source "${PROJECT_ROOT}/scripts/_common/logging.sh" || {
    echo "FATAL: Cannot find logging library at scripts/_common/logging.sh"
    exit 1
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

validate_prerequisites() {
    # Check requirements
    # Return 3 if not met
}

# ... rest of script ...
```

### 3.2 Python Module Header Template

Every Python module MUST include:

```python
"""
Script/Module Name: auth.py

Purpose:
    Provide JWT token generation, validation, and OAuth2 provider logic
    for authentication and authorization.

Usage:
    from src.auth.jwt import generate_token, verify_token
    
    token = generate_token(user_id=123)
    user_id = verify_token(token)

Dependencies:
    - PyJWT (for JWT operations)
    - cryptography (for signing)
    - fastapi (for dependency injection)

RELATED DOCUMENTATION:
    - docs/reference/API.md                  REST API endpoints
    - docs/security/RBAC_GUIDE.md           Role-based access control
    - docs/guides/LOCAL_DEVELOPMENT.md      Dev setup instructions

CHANGE LOG:
    v2.1 (2026-04-15) - Add support for RS256 algorithm
    v2.0 (2026-04-10) - Migrate from HS256 to RS256
    v1.0 (2026-03-01) - Initial implementation

Author: Engineering Team
Created: 2026-04-15
Last Modified: 2026-04-15
Version: 2.1
"""

from typing import Optional, Dict, Any
import logging
from datetime import datetime, timedelta

# Configure logging
logger = logging.getLogger(__name__)

class JWTManager:
    """Handles JWT token lifecycle (generation, validation, refresh).
    
    Attributes:
        secret_key (str): Signing key for tokens
        algorithm (str): JWT signing algorithm (default: HS256)
        expiry_minutes (int): Token expiration in minutes
        
    RELATED CLASSES:
        - OAuth2Provider (uses JWTManager for token handling)
        - PermissionManager (validates token claims)
    """
    
    def __init__(self, secret_key: str, algorithm: str = "HS256"):
        """Initialize JWT manager.
        
        Args:
            secret_key (str): Secret key for signing tokens
            algorithm (str): Algorithm for signing (HS256, RS256, etc.)
        """
        # Implementation
```

### 3.3 TypeScript Component Header Template

Every TypeScript component MUST include:

```typescript
/**
 * Component Name: LoginForm.tsx
 *
 * Purpose:
 *   Displays login form with email/password fields and handles
 *   authentication flow including MFA challenge if enabled.
 *
 * Usage:
 *   import LoginForm from '@/components/LoginForm'
 *   
 *   <LoginForm onSuccess={() => navigate('/dashboard')} />
 *
 * Props:
 *   - onSuccess: Callback fired after successful login
 *   - initialEmail: Pre-populate email field (optional)
 *   - redirectTo: URL to redirect after login (optional)
 *
 * State Management:
 *   - Uses useAuth() hook for authentication logic
 *   - Uses Redux via useAppDispatch() for global auth state
 *
 * Related Components:
 *   - components/MFAChallenge.tsx    MFA verification form
 *   - pages/Login.tsx                Page wrapper
 *   - services/auth.ts               API calls
 *   - types/api.ts                   API response types
 *
 * ACCESSIBILITY:
 *   - WCAG 2.1 AA compliant
 *   - Keyboard navigable (Tab order: email → password → submit)
 *   - Screen reader friendly (aria-labels on all inputs)
 *   - Error messages announced to screen readers
 *
 * TESTING:
 *   - See tests/components/LoginForm.test.tsx
 *   - Coverage: 92% (4 branch misses in error handling)
 *
 * Change Log:
 *   v2.1 (2026-04-15) - Add MFA option support
 *   v2.0 (2026-04-10) - Migrate from class to functional component
 *   v1.0 (2026-03-01) - Initial implementation
 *
 * Author: Engineering Team
 * Created: 2026-04-15
 * Last Modified: 2026-04-15
 * Version: 2.1
 */

import React, { useState, useCallback } from 'react'
import { useAuth } from '@/hooks/useAuth'
import { useAppDispatch } from '@/store/hooks'
import * as api from '@/services/auth'

interface LoginFormProps {
  onSuccess?: () => void
  initialEmail?: string
  redirectTo?: string
}

/**
 * LoginForm: Renders login form and handles authentication
 * @param props - Component props
 * @returns React component
 * 
 * ERROR HANDLING:
 *   - Catches network errors and displays user-friendly message
 *   - Logs all errors to console for debugging
 *   - Retries failed requests up to 3 times
 */
export const LoginForm: React.FC<LoginFormProps> = ({
  onSuccess,
  initialEmail = '',
  redirectTo = '/dashboard'
}) => {
  // ... implementation ...
}

export default LoginForm
```

### 3.4 Terraform Module Header Template

```hcl
# ============================================================================
# Terraform Module: compute
# ============================================================================
#
# Purpose:
#   Provision compute resources (EC2/VMs, security groups, networking)
#   for code-server application deployment
#
# Input Variables:
#   - instance_type (string): EC2 instance type (default: t3.xlarge)
#   - availability_zones (list): AZs to deploy in (default: 2)
#   - environment (string): Deployment environment (staging/production)
#
# Outputs:
#   - instance_ids: List of instance IDs
#   - security_group_id: ID of security group
#   - vpc_id: ID of VPC
#
# Usage Example:
#   module "compute" {
#     source = "./modules/compute"
#     
#     instance_type = "t3.xlarge"
#     environment = "production"
#     
#     tags = {
#       Application = "code-server"
#       Environment = "production"
#     }
#   }
#
# RELATED MODULES:
#   - networking/ (provides VPC & subnets)
#   - security/   (provides security groups)
#   - monitoring/ (adds CloudWatch monitoring)
#
# DOCUMENTATION:
#   - docs/reference/CONFIGURATION.md       All configurable values
#   - docs/guides/DEPLOYMENT.md             How to deploy
#   - infra/terraform/README.md             Terraform setup guide
#
# CHANGE LOG:
#   v2.1 (2026-04-15) - Add support for GPU instances
#   v2.0 (2026-04-10) - Migrate from t2 to t3 instances
#   v1.0 (2026-03-01) - Initial implementation
#
# LAST MODIFIED: 2026-04-15
# VERSION: 2.1
# AUTHOR: Engineering Team
#
# ============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "instance_type" {
  description = "EC2 instance type (e.g., t3.xlarge, m5.2xlarge)"
  type        = string
  default     = "t3.xlarge"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "Instance type must be valid AWS instance type"
  }
}

# ... more resources ...
```

### 3.5 YAML Configuration Header Template

```yaml
###############################################################################
#
# File Name: prometheus.yml
# Purpose: Configure Prometheus metrics scraping and retention
# 
# Usage:
#   - Mounted in Prometheus container at /etc/prometheus/prometheus.yml
#   - Reload with: curl -X POST http://localhost:9090/-/reload
#   - Validate with: promtool check config prometheus.yml
#
# Key Sections:
#   - global:       Default scrape interval & timeout
#   - scrape_configs: What to monitor and how
#   - alerting:     AlertManager integration
#   - rule_files:   Alert rule definitions
#
# RELATED DOCUMENTATION:
#   - docs/reference/CONFIGURATION.md       All config options
#   - docs/operations/MONITORING_STACK.md   How monitoring works
#   - infra/monitoring/README.md            Monitoring architecture
#
# CHANGE LOG:
#   v2.1 (2026-04-15) - Add scrape_interval=15s for better granularity
#   v2.0 (2026-04-10) - Add Ollama metrics scraping
#   v1.0 (2026-03-01) - Initial implementation
#
# AUTHOR: Engineering Team
# CREATED: 2026-04-15
# LAST_MODIFIED: 2026-04-15
# VERSION: 2.1
#
###############################################################################

# Global settings
global:
  scrape_interval: 15s          # Default scrape interval
  evaluation_interval: 15s      # How often to evaluate alert rules
  external_labels:
    monitor: code-server-enterprise
    environment: production

# Where to send alerts
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093     # AlertManager instance

# Load alert rules
rule_files:
  - 'alert-rules.yml'           # Alert rule definitions

# What to scrape and how
scrape_configs:
  # Prometheus itself
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']
  
  # Application metrics
  - job_name: code-server
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 30s         # Override global interval
    
  # More scrape configs...
```

---

## 4. BUILD & TEST AUTOMATION (Makefile)

Create `Makefile` at root level:

```makefile
################################################################################
# Makefile - Build, test, and deployment targets for code-server-enterprise
#
# Common Targets:
#   make help              Show all available targets
#   make dev               Start dev environment locally
#   make test              Run all tests
#   make lint              Check code quality
#   make build             Build Docker images
#   make deploy            Deploy to production
#   make clean             Clean up local artifacts
#
# Example:
#   make lint test build
#   make deploy ENV=staging
#
################################################################################

.PHONY: help dev test lint build deploy clean

help:
	@grep -E '^[a-z-]+:.*##' Makefile | \
		awk -F'[:#]' '{printf "%-20s %s\n", $$1, $$3}'

dev:              ## Start local development environment
	@echo "Starting development environment..."
	docker-compose -f config/docker-compose.yml -f config/docker-compose.override.yml up -d
	@echo "Development environment ready at http://localhost:8080"

test:             ## Run all test suites (unit, integration, E2E)
	@echo "Running unit tests..."
	pytest tests/unit/ -v
	@echo "Running integration tests..."
	pytest tests/integration/ -v

lint:             ## Check code quality (pylint, eslint, shellcheck)
	@echo "Linting Python code..."
	pylint src/backend/src/
	@echo "Linting TypeScript code..."
	npm run lint --prefix src/frontend/
	@echo "Checking shell scripts..."
	shellcheck scripts/**/*.sh

build:            ## Build Docker images
	@echo "Building Docker images..."
	docker build -t code-server:latest -f infra/docker/code-server/Dockerfile .
	docker build -t caddy:custom -f infra/docker/caddy/Dockerfile .

deploy:           ## Deploy to production (use ENV=staging for staging)
	@echo "Deploying to production..."
	scripts/lifecycle/deploy.sh

clean:            ## Clean up temporary files and Docker artifacts
	@echo "Cleaning up..."
	rm -rf logs/
	docker system prune -f
	find . -type d -name __pycache__ -exec rm -r {} +
	find . -type d -name .pytest_cache -exec rm -r {} +
```

---

## 5. REORGANIZATION ROADMAP (4 WEEKS)

### WEEK 1: Planning & Preparation
- [ ] Day 1-2: Create all new directories (no file moves yet)
- [ ] Day 3: Create README.md files for each directory
- [ ] Day 4: Add header templates to style guide
- [ ] Day 5: Update .gitignore with new patterns

**Deliverables**:
- Empty directory structure ready
- .gitignore updated
- Team trained on new structure

### WEEK 2: Core Application & Infrastructure Code
- [ ] Move backend/ to src/backend/
- [ ] Move frontend/ to src/frontend/
- [ ] Move terraform/ to infra/terraform/
- [ ] Move docker files to infra/docker/
- [ ] Create config/ directory with consolidations
- [ ] Update imports (files point to new locations)

**Deliverables**:
- Application code reorganized
- CI/CD pipelines updated
- All tests passing

### WEEK 3: Scripts & Documentation
- [ ] Create scripts/README.md with complete index
- [ ] Reorganize scripts/ by category
- [ ] Move docs to new docs/ structure
- [ ] Create scripts/_common/logging.sh shared library
- [ ] Archive deprecated scripts to archived/scripts-phase-13-19/

**Deliverables**:
- scripts/README.md (searchable index)
- All scripts have proper headers
- All documentation reorganized

### WEEK 4: Final Cleanup & Verification
- [ ] Archive all historical reports to archived/
- [ ] Verify all file symlinks work (docker-compose, Caddyfile at root)
- [ ] Update ALL file headers/metadata
- [ ] Create root-level Makefile
- [ ] Run full test suite to verify everything works
- [ ] Update deployment scripts to use new paths

**Deliverables**:
- Clean root directory (15-20 files only)
- All tests passing
- Full documentation of new structure

---

## 6. BEFORE/AFTER COMPARISON

### BEFORE: Root Directory (200+ files)
```
📂 code-server-enterprise/
├── 8x docker-compose*.yml        ← Duplicates
├── 4x Caddyfile*                ← Duplicates
├── 200+ scattered files at root ← Unnavigable
├── 25+ status reports           ← Unnecessary
├── 100+ phase artifacts         ← Outdated
├── scripts/ (unmaintainable)    ← 200+ files, no index
├── docs/                        ← Scattered, not by purpose
├── backend/                     ← Good
├── frontend/                    ← Good
└── [No structure beyond this]
```

**Health**: 6/10 ⚠️

### AFTER: Organized Repository (FAANG-style)
```
📂 code-server-enterprise/
├── README.md                    ← Start here
├── LICENSE
├── Makefile                     ← Dev targets
├── .gitignore                   ← Updated
├── docker-compose.yml           ← Keep here + config/
├── Caddyfile                    ← Keep here + config/
│
├── src/                         ← Application code (clean)
│   ├── backend/                 ── Python/FastAPI
│   ├── frontend/                ── React/TypeScript
│   └── shared/                  ── Shared utilities
│
├── infra/                       ← Infrastructure (organized)
│   ├── docker/                  ── Container definitions
│   ├── terraform/               ── IaC configuration
│   └── monitoring/              ── Observability stack
│
├── config/                      ← All configurations
│   ├── env/                     ── Environment files
│   ├── secrets/                 ── Runtime secrets (gitignored)
│   ├── docker-compose.yml       ── Main composition
│   └── caddy/                   ── Caddy configuration
│
├── scripts/                     ← Organized by purpose (indexed!)
│   ├── README.md                ── 🌟 Complete script index
│   ├── lifecycle/               ── Deployment
│   ├── operations/              ── Daily ops
│   ├── security/                ── Access mgmt
│   ├── monitoring/              ── Observability
│   ├── testing/                 ── Validation
│   ├── development/             ── Dev utilities
│   ├── cicd/                    ── Pipeline scripts
│   ├── _common/                 ── Shared libraries
│   └── archived/                ── Deprecated
│
├── docs/                        ← Organized by purpose
│   ├── reference/               ── API, schema, config
│   ├── guides/                  ── How-to documentation
│   ├── operations/              ── Runbooks & procedures
│   ├── security/                ── Security policies
│   ├── architecture/            ── ADRs (decisions)
│   ├── phases/                  ── P14 & P21 summaries
│   └── slos/                    ── SLA/SLO targets
│
├── tests/                       ← Centralized test suite
│   ├── unit/
│   ├── integration/
│   ├── e2e/
│   └── fixtures/
│
└── archived/                    ← Historical artifacts (reference only)
    ├── docker-compose-variants/
    ├── terraform-old/
    ├── scripts-phase-13-19/
    ├── status-reports/
    └── designs/
```

**Health**: 9/10 ✅

---

## 7. IMPLEMENTATION CHECKLIST

### Pre-Implementation
- [ ] Get team approval on new structure
- [ ] Schedule 1-hour team training session on new organization
- [ ] Create backup of entire repo
- [ ] Create new branch `refactor/repo-reorganization`

### Directory Creation
- [ ] Create all new directories (scripts/lifecycle/, docs/guides/, etc.)
- [ ] Create README.md in each directory
- [ ] Update .gitignore

### Code Migration (Tests Running)
- [ ] Move application code (src/backend/, src/frontend/)
- [ ] Move infrastructure code (infra/terraform/, infra/docker/)
- [ ] Move test suite (tests/)
- [ ] Update all imports and references
- [ ] Run tests → all green before proceeding

### Scripts Organization
- [ ] Create scripts/README.md with complete index
- [ ] Move scripts to category directories
- [ ] Add headers to ALL script files
- [ ] Archive deprecated scripts
- [ ] Test: Can team find any script? (scripts/README.md lookup successful)

### Documentation Reorganization
- [ ] Reorganize docs/ by purpose
- [ ] Create docs/reference/README.md, docs/guides/README.md, etc.
- [ ] Update doc links in all other files
- [ ] Test: Can team navigate docs easily?

### Header Addition (ALL FILES)
- [ ] Add headers to all .sh scripts (50+ files)
- [ ] Add headers to all .py modules (100+ files)
- [ ] Add headers to all .ts/.tsx components (100+ files)
- [ ] Add headers to all Terraform files (20+ files)
- [ ] Add headers to all YAML configs (10+ files)

### Final Cleanup
- [ ] Create root Makefile with build targets
- [ ] Archive superseded files (archived/)
- [ ] Create symlinks: docker-compose.yml → config/
- [ ] Create symlinks: Caddyfile → config/caddy/
- [ ] Update CI/CD pipelines (.github/workflows/)
- [ ] Update deployment scripts (scripts/lifecycle/)

### Testing & Verification
- [ ] Run full test suite (unit + integration + E2E)
- [ ] Run `docker-compose up` from new location
- [ ] Run `terraform validate` from new location
- [ ] Verify scripts can find dependencies
- [ ] Manual test: New dev can setup environment using GETTING_STARTED.md
- [ ] Verify git operations work (commits, PRs, merges)

### Documentation & Training
- [ ] Update CONTRIBUTING.md with new structure walkthrough
- [ ] Update README.md with quick navigation guide
- [ ] Document how to add new scripts/files
- [ ] Record quick video tour of new structure (5 min)
- [ ] Schedule 1-hour team training on using new structure

### Merge & Rollout
- [ ] Create PR with all changes
- [ ] Get 2 approvals (tech lead + DevOps lead)
- [ ] Merge to main
- [ ] Tag as v2.0.0 (major version bump)
- [ ] Update deployment documentation
- [ ] Monitor first 3 deployments for issues

---

## 8. SUCCESS CRITERIA

### Code Organization ✅
- [ ] Root directory has ≤20 files (currently 200+)
- [ ] All code properly categorized (src/, infra/, config/, etc.)
- [ ] No duplicate docker-compose or Caddyfile files (keep only active)
- [ ] All deprecated files archived with explanation

### Documentation ✅
- [ ] Every file has metadata header (script, module, component, config)
- [ ] Docs organized by purpose (reference/, guides/, operations/, etc.)
- [ ] scripts/README.md provides searchable index of all scripts
- [ ] Every major component documented in docs/reference/

### Navigability ✅
- [ ] New developer can navigate repo in <5 minutes
- [ ] Finding any script takes <30 seconds (via scripts/README.md)
- [ ] Finding any documentation takes <1 minute (via docs/README.md)
- [ ] CI/CD unchanged (backward compatible)

### Quality Metrics ✅
- [ ] 100% of test suite passing
- [ ] 0 broken references (no #GH-XXX placeholders)
- [ ] 0 orphaned files (everything has a home)
- [ ] .gitignore prevents log files, binaries, secrets from checking in

### Team Adoption ✅
- [ ] Team members use new script organization (logs show usage)
- [ ] New team members complete setup faster (track time)
- [ ] Zero questions about "where do I find X?" (in first month)

---

## 9. RISK MITIGATION

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Breaking CI/CD pipelines | Medium | High | Test in isolated branch first, update paths incrementally |
| Paths in scripts break | High | High | Create test suite for path references, update gradually |
| Team confusion | Medium | Medium | Train 1 hour, provide quick-start guide, be available |
| Incomplete migration | Low | Medium | Use checklist, verify each section before moving on |
| Performance regression | Low | Low | No code changes, just reorganization (same Docker setup) |

**Mitigation Strategy**:
1. Use feature branch, don't merge until 100% tested
2. Test each section independently before final merge
3. Have rollback plan (git revert to old commit)
4. Schedule for low-risk time (not during critical ops)

---

## 10. ESTIMATED EFFORT & TIMELINE

| Phase | Task | Hours | Notes |
|-------|------|-------|-------|
| **Week 1** | Directory setup, .gitignore | 8 | 1-2 hours/day |
| **Week 2** | Code migration, CI/CD updates | 20 | Test frequently, verify tests pass |
| **Week 3** | Scripts org, doc reorganization | 15 | Add headers to 300+ files |
| **Week 4** | Cleanup, verification, training | 12 | Final QA, team training |
| **TOTAL** | | **55 hours** | ~2 weeks of dev time (full-time focus) |

**Timeline**: 4 weeks if 1 engineer at 50% allocation, or 2 weeks if 1 engineer at 100% allocation

---

## 11. NEXT STEPS

1. **Get Approval**: Share this plan with tech lead & DevOps lead
2. **Schedule Work**: Block 2-4 weeks on engineering roadmap
3. **Create Branch**: `git checkout -b refactor/repo-reorganization`
4. **Follow Checklist**: Implement using section 7 checklist
5. **Get Review**: Have 2 senior engineers review before merge
6. **Merge & Tag**: Tag as v2.0.0
7. **Deploy**: Use new structure in deployments
8. **Monitor**: Watch first 3 deployments for issues
9. **Celebrate**: Team wins on cleaner, more maintainable repo!

---

## FINAL NOTES

This reorganization **improves navigability dramatically without changing any code logic**. All existing tests continue to work with updated paths. The main benefit is:

✅ **Before**: "Where do I find X?" → Dig through 200+ files  
✅ **After**: "Where do I find X?" → Check proper directory (scripts/, docs/, infra/, etc.)

The metadata headers also provide **self-documenting code** - any new engineer can read a script header and understand what it does, when it was last updated, and how to use it.

**This is a significant quality-of-life improvement for the entire team.**

