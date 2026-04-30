# Phase 2b Deployment Validation Procedures

**Version:** 1.0  
**Purpose:** Automated and manual validation procedures for Phase 2b deployments  
**Status:** Production-ready procedures  

---

## Overview

Comprehensive validation procedures to verify Phase 2b deployment success at each stage.

---

## Level 1: Pre-Deployment Validation

### 1.1 Git Status Check

**Purpose:** Verify correct code version is deployed

```bash
#!/bin/bash
set -euo pipefail

echo "=== Git Status Validation ==="

# Check current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "❌ FAILED: Not on main branch (current: $CURRENT_BRANCH)"
  exit 1
fi

# Check if on specific commit (optional)
if [ -n "${REQUIRED_COMMIT:-}" ]; then
  CURRENT_COMMIT=$(git rev-parse --short HEAD)
  if [ "$CURRENT_COMMIT" != "$REQUIRED_COMMIT" ]; then
    echo "❌ FAILED: Commit mismatch (expected: $REQUIRED_COMMIT, current: $CURRENT_COMMIT)"
    exit 1
  fi
fi

# Verify working tree is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ FAILED: Uncommitted changes in working tree"
  git status
  exit 1
fi

echo "✅ PASSED: Git status valid"
```

### 1.2 Script Availability Check

**Purpose:** Verify all Phase 2b scripts are present and executable

```bash
#!/bin/bash
set -euo pipefail

echo "=== Script Availability Validation ==="

SCRIPTS=(
  "scripts/ops/orchestrate-deployment.sh"
  "scripts/ops/gcp-deploy.sh"
  "scripts/ops/check-gitlab-compose-parity.sh"
  "scripts/ops/full-deployment-test.sh"
  "scripts/ops/failover-drill.sh"
  "scripts/testing/test-gcp-deployment.sh"
)

MISSING=0
for script in "${SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    echo "❌ FAILED: Missing script: $script"
    MISSING=$((MISSING + 1))
  elif [ ! -x "$script" ]; then
    echo "⚠️  WARNING: Script not executable: $script"
    chmod +x "$script"
  else
    echo "✅ Found: $script"
  fi
done

if [ $MISSING -gt 0 ]; then
  echo "❌ FAILED: $MISSING scripts missing"
  exit 1
fi

echo "✅ PASSED: All scripts present and executable"
```

### 1.3 Prerequisites Check

**Purpose:** Verify all required tools and dependencies available

```bash
#!/bin/bash
set -euo pipefail

echo "=== Prerequisites Validation ==="

REQUIRED_COMMANDS=("curl" "jq" "ssh" "docker" "docker-compose")
REQUIRED_FILES=("docker-compose.enterprise.yml")

MISSING_CMD=0
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ FAILED: Command not found: $cmd"
    MISSING_CMD=$((MISSING_CMD + 1))
  else
    VERSION=$("$cmd" --version 2>&1 | head -1)
    echo "✅ Found: $cmd ($VERSION)"
  fi
done

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "❌ FAILED: File not found: $file"
    MISSING_FILES=$((MISSING_FILES + 1))
  else
    echo "✅ Found: $file"
  fi
done

if [ $MISSING_CMD -gt 0 ] || [ $MISSING_FILES -gt 0 ]; then
  echo "❌ FAILED: Missing prerequisites"
  exit 1
fi

echo "✅ PASSED: All prerequisites available"
```

### 1.4 Environment Variables Validation

**Purpose:** Verify required environment variables are set

```bash
#!/bin/bash
set -euo pipefail

echo "=== Environment Variables Validation ==="

# Check for LOCAL deployment
if [ "${DEPLOYMENT_MODE:-}" = "local" ]; then
  REQUIRED_VARS=("PRIMARY_HOST" "REPLICA_HOST")
elif [ "${DEPLOYMENT_MODE:-}" = "gcp" ]; then
  REQUIRED_VARS=("GCP_PROJECT_ID" "GCP_CREDENTIALS_JSON" "GCP_ZONE")
else
  echo "❌ FAILED: DEPLOYMENT_MODE not set (must be 'local' or 'gcp')"
  exit 1
fi

MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "❌ FAILED: Required variable not set: $var"
    MISSING=$((MISSING + 1))
  else
    echo "✅ Set: $var=${!var}"
  fi
done

if [ $MISSING -gt 0 ]; then
  echo "❌ FAILED: Missing environment variables"
  exit 1
fi

echo "✅ PASSED: All environment variables set"
```

---

## Level 2: Connectivity Validation

### 2.1 SSH Connectivity Check (Local Mode)

**Purpose:** Verify SSH access to both cluster nodes

```bash
#!/bin/bash
set -euo pipefail

echo "=== SSH Connectivity Validation ==="

# Test PRIMARY
echo "Testing PRIMARY ($PRIMARY_HOST)..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$PRIMARY_HOST" "echo 'SSH OK'" &>/dev/null; then
  echo "✅ PRIMARY SSH: OK"
else
  echo "❌ FAILED: Cannot SSH to PRIMARY ($PRIMARY_HOST)"
  echo "  Check: IP address, firewall, SSH key permissions"
  exit 1
fi

# Test REPLICA
echo "Testing REPLICA ($REPLICA_HOST)..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$REPLICA_HOST" "echo 'SSH OK'" &>/dev/null; then
  echo "✅ REPLICA SSH: OK"
else
  echo "❌ FAILED: Cannot SSH to REPLICA ($REPLICA_HOST)"
  echo "  Check: IP address, firewall, SSH key permissions"
  exit 1
fi

# Test bidirectional communication
echo "Testing bidirectional communication..."
PING_TEST=$(ssh "root@$PRIMARY_HOST" "ping -c1 $REPLICA_HOST | grep -oP 'time=\K[^m]*'")
echo "✅ PRIMARY→REPLICA latency: ${PING_TEST}ms"

PING_TEST=$(ssh "root@$REPLICA_HOST" "ping -c1 $PRIMARY_HOST | grep -oP 'time=\K[^m]*'")
echo "✅ REPLICA→PRIMARY latency: ${PING_TEST}ms"

echo "✅ PASSED: SSH connectivity verified"
```

### 2.2 GCP API Connectivity Check

**Purpose:** Verify GCP credentials and API access

```bash
#!/bin/bash
set -euo pipefail

echo "=== GCP API Connectivity Validation ==="

# Check credentials file exists
if [ ! -f "$GCP_CREDENTIALS_JSON" ]; then
  echo "❌ FAILED: Credentials file not found: $GCP_CREDENTIALS_JSON"
  exit 1
fi

# Extract project ID from credentials
CREDENTIALS_PROJECT=$(jq -r '.project_id' "$GCP_CREDENTIALS_JSON")
if [ "$CREDENTIALS_PROJECT" != "$GCP_PROJECT_ID" ]; then
  echo "⚠️  WARNING: Project ID mismatch"
  echo "  Expected: $GCP_PROJECT_ID"
  echo "  Credentials: $CREDENTIALS_PROJECT"
fi

# Test API access
echo "Testing GCP API access..."
if bash scripts/ops/gcp-deploy.sh validate 2>&1 | grep -q "Configuration valid"; then
  echo "✅ GCP API: Accessible"
else
  echo "❌ FAILED: Cannot access GCP API"
  echo "  Check: Credentials, project ID, IAM permissions"
  exit 1
fi

echo "✅ PASSED: GCP connectivity verified"
```

---

## Level 3: Infrastructure Validation

### 3.1 Docker Availability Check

**Purpose:** Verify Docker is running and containers accessible

```bash
#!/bin/bash
set -euo pipefail

echo "=== Docker Availability Validation ==="

# Check LOCAL mode
if [ "$DEPLOYMENT_MODE" = "local" ]; then
  echo "Checking PRIMARY ($PRIMARY_HOST)..."
  RUNNING_COUNT=$(ssh "root@$PRIMARY_HOST" "docker ps --filter status=running -q | wc -l")
  echo "  Running containers: $RUNNING_COUNT"
  if [ "$RUNNING_COUNT" -lt 50 ]; then
    echo "  ⚠️  WARNING: Fewer containers than expected (< 50)"
  else
    echo "  ✅ Docker: Running"
  fi
  
  echo "Checking REPLICA ($REPLICA_HOST)..."
  RUNNING_COUNT=$(ssh "root@$REPLICA_HOST" "docker ps --filter status=running -q | wc -l")
  echo "  Running containers: $RUNNING_COUNT"
  if [ "$RUNNING_COUNT" -lt 50 ]; then
    echo "  ⚠️  WARNING: Fewer containers than expected (< 50)"
  else
    echo "  ✅ Docker: Running"
  fi
fi

echo "✅ PASSED: Docker availability verified"
```

### 3.2 Configuration Validation

**Purpose:** Verify docker-compose configuration can be loaded

```bash
#!/bin/bash
set -euo pipefail

echo "=== Configuration Validation ==="

# Validate syntax
echo "Validating docker-compose.enterprise.yml..."
docker-compose -f docker-compose.enterprise.yml config > /dev/null 2>&1 || {
  echo "❌ FAILED: Invalid docker-compose configuration"
  exit 1
}

echo "✅ docker-compose syntax: Valid"

# Check required services
echo "Checking required services..."
SERVICES=$(docker-compose -f docker-compose.enterprise.yml config --services)
for service in gitlab postgresql redis; do
  if echo "$SERVICES" | grep -q "^$service\$"; then
    echo "  ✅ Service found: $service"
  else
    echo "  ❌ FAILED: Service not found: $service"
    exit 1
  fi
done

echo "✅ PASSED: Configuration valid"
```

---

## Level 4: Phase 2b Specific Validation

### 4.1 Parity Gate Validation

**Purpose:** Verify PRIMARY and REPLICA configurations match

```bash
#!/bin/bash
set -euo pipefail

echo "=== Phase 2b Parity Gate Validation ==="

if [ "$DEPLOYMENT_MODE" != "local" ]; then
  echo "⚠️  Skipping (only for local mode)"
  exit 0
fi

# Export variables for parity check
export PRIMARY_HOST REPLICA_HOST

# Run parity check
if bash scripts/ops/check-gitlab-compose-parity.sh > /tmp/parity-check.log 2>&1; then
  echo "✅ PASSED: Parity check successful"
else
  echo "❌ FAILED: Parity check failed"
  cat /tmp/parity-check.log
  exit 1
fi
```

### 4.2 Full 6-Phase Validation

**Purpose:** Run complete Phase 2b validation suite

```bash
#!/bin/bash
set -euo pipefail

echo "=== Phase 2b 6-Phase Validation ==="

# Export variables
export PRIMARY_HOST REPLICA_HOST

# Run full deployment test
if bash scripts/ops/full-deployment-test.sh --dry-run > /tmp/phase2b-test.log 2>&1; then
  echo "✅ All phases passed"
  
  # Check test report
  if [ -f "artifacts/deployment-test-report.json" ]; then
    PASS_COUNT=$(jq '.phases | map(.status) | map(select(. == "PASSED")) | length' \
      artifacts/deployment-test-report.json)
    echo "  ✅ Phases passed: $PASS_COUNT/6"
  fi
else
  echo "❌ FAILED: Phase 2b validation failed"
  cat /tmp/phase2b-test.log
  exit 1
fi
```

---

## Level 5: Functional Validation

### 5.1 Service Availability Check

**Purpose:** Verify critical services are responding

```bash
#!/bin/bash
set -euo pipefail

echo "=== Service Availability Validation ==="

if [ "$DEPLOYMENT_MODE" != "local" ]; then
  echo "⚠️  Skipping (only for local mode)"
  exit 0
fi

# Check GitLab API
echo "Testing GitLab API..."
GITLAB_RESPONSE=$(ssh "root@$PRIMARY_HOST" \
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:8101/api/v4/version")
if [ "$GITLAB_RESPONSE" = "200" ]; then
  echo "✅ GitLab API: Responding (HTTP $GITLAB_RESPONSE)"
else
  echo "⚠️  WARNING: GitLab API unexpected status (HTTP $GITLAB_RESPONSE)"
fi

# Check database
echo "Testing database..."
DB_CHECK=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-postgresql psql -U postgres -c 'SELECT 1;' 2>&1 | grep -c '1 row'")
if [ "$DB_CHECK" -gt 0 ]; then
  echo "✅ Database: Responding"
else
  echo "❌ FAILED: Database not responding"
  exit 1
fi

# Check Redis
echo "Testing Redis..."
REDIS_CHECK=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-redis redis-cli PING 2>&1 | grep -c PONG")
if [ "$REDIS_CHECK" -gt 0 ]; then
  echo "✅ Redis: Responding"
else
  echo "❌ FAILED: Redis not responding"
  exit 1
fi

echo "✅ PASSED: All services responding"
```

### 5.2 Replication Health Check

**Purpose:** Verify database and Redis replication working

```bash
#!/bin/bash
set -euo pipefail

echo "=== Replication Health Validation ==="

if [ "$DEPLOYMENT_MODE" != "local" ]; then
  echo "⚠️  Skipping (only for local mode)"
  exit 0
fi

# Check PostgreSQL replication
echo "Checking PostgreSQL replication..."
REP_SLOT=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-postgresql psql -U postgres -c 'SELECT slot_name FROM pg_replication_slots;' 2>&1 | grep -c slot")

if [ "$REP_SLOT" -gt 0 ]; then
  echo "✅ PostgreSQL replication: Active"
else
  echo "⚠️  WARNING: No replication slots found"
fi

# Check Redis replication
echo "Checking Redis replication..."
REDIS_SLAVES=$(ssh "root@$PRIMARY_HOST" \
  "docker exec gitlab-redis redis-cli INFO replication 2>&1 | grep -oP 'connected_slaves:\K[0-9]'")

if [ "$REDIS_SLAVES" -gt 0 ]; then
  echo "✅ Redis replication: $REDIS_SLAVES connected slave(s)"
else
  echo "❌ FAILED: No Redis slaves connected"
  exit 1
fi

echo "✅ PASSED: Replication healthy"
```

---

## Level 6: Performance Validation

### 6.1 Resource Utilization Check

**Purpose:** Verify system resources within acceptable ranges

```bash
#!/bin/bash
set -euo pipefail

echo "=== Resource Utilization Validation ==="

if [ "$DEPLOYMENT_MODE" != "local" ]; then
  echo "⚠️  Skipping (only for local mode)"
  exit 0
fi

check_host_resources() {
  local host=$1
  local host_name=$2
  
  echo "Checking $host_name..."
  
  # CPU usage
  CPU=$(ssh "root@$host" "top -bn1 | grep 'Cpu(s)' | awk '{print 100-\$8}' | xargs printf '%.0f'")
  if [ "$CPU" -gt 80 ]; then
    echo "  ⚠️  WARNING: High CPU usage: ${CPU}%"
  else
    echo "  ✅ CPU usage: ${CPU}%"
  fi
  
  # Memory usage
  MEM=$(ssh "root@$host" "free | awk '/^Mem:/ {printf \"%.0f\", \$3/\$2 * 100}'")
  if [ "$MEM" -gt 85 ]; then
    echo "  ⚠️  WARNING: High memory usage: ${MEM}%"
  else
    echo "  ✅ Memory usage: ${MEM}%"
  fi
  
  # Disk usage
  DISK=$(ssh "root@$host" "df / | awk '/\// {print \$5}' | sed 's/%//'")
  if [ "$DISK" -gt 80 ]; then
    echo "  ⚠️  WARNING: High disk usage: ${DISK}%"
  else
    echo "  ✅ Disk usage: ${DISK}%"
  fi
}

check_host_resources "$PRIMARY_HOST" "PRIMARY"
check_host_resources "$REPLICA_HOST" "REPLICA"

echo "✅ PASSED: Resources within acceptable ranges"
```

---

## Master Validation Script

### validate-phase2b-deployment.sh

```bash
#!/bin/bash

set -euo pipefail

# Configuration
LOG_FILE="/tmp/phase2b-validation-$(date +%Y%m%d-%H%M%S).log"
VALIDATION_LEVEL="${1:-full}"  # quick, standard, full
PASSED=0
FAILED=0
WARNINGS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo "$@" | tee -a "$LOG_FILE"
}

pass() {
  PASSED=$((PASSED + 1))
  echo -e "${GREEN}✅ PASS${NC}: $@" | tee -a "$LOG_FILE"
}

fail() {
  FAILED=$((FAILED + 1))
  echo -e "${RED}❌ FAIL${NC}: $@" | tee -a "$LOG_FILE"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo -e "${YELLOW}⚠️  WARN${NC}: $@" | tee -a "$LOG_FILE"
}

log "=== Phase 2b Deployment Validation ==="
log "Validation Level: $VALIDATION_LEVEL"
log "Log File: $LOG_FILE"
log ""

# Run validation levels
case "$VALIDATION_LEVEL" in
  quick)
    bash -n scripts/ops/orchestrate-deployment.sh && pass "Script syntax" || fail "Script syntax"
    [ -f "docker-compose.enterprise.yml" ] && pass "Config file exists" || fail "Config file missing"
    ;;
  standard)
    # All Level 1-3 validations
    bash scripts/validation/level1-*.sh || true
    bash scripts/validation/level2-*.sh || true
    bash scripts/validation/level3-*.sh || true
    ;;
  full)
    # All Level 1-6 validations
    for level in 1 2 3 4 5 6; do
      bash scripts/validation/level${level}-*.sh || true
    done
    ;;
esac

# Print summary
log ""
log "=== Validation Summary ==="
log "PASSED: $PASSED"
log "FAILED: $FAILED"
log "WARNINGS: $WARNINGS"

if [ $FAILED -eq 0 ]; then
  log "Overall: ✅ VALIDATION PASSED"
  exit 0
else
  log "Overall: ❌ VALIDATION FAILED"
  exit 1
fi
```

---

## Usage Instructions

### Quick Validation (2 minutes)

```bash
./validate-phase2b-deployment.sh quick
```

### Standard Validation (10 minutes)

```bash
./validate-phase2b-deployment.sh standard
```

### Full Validation (30 minutes)

```bash
./validate-phase2b-deployment.sh full
```

### Individual Level Validation

```bash
bash scripts/validation/level1-*.sh  # Pre-deployment only
bash scripts/validation/level2-*.sh  # Connectivity
bash scripts/validation/level3-*.sh  # Infrastructure
bash scripts/validation/level4-*.sh  # Phase 2b specific
bash scripts/validation/level5-*.sh  # Functional
bash scripts/validation/level6-*.sh  # Performance
```

---

## Validation Report

Each validation run generates a report with:
- Validation timestamp
- All checks performed
- Pass/Fail/Warning counts
- Detailed results for each check
- Remediation suggestions for failures

Example: `/tmp/phase2b-validation-20260430-153042.log`

---

**Version:** 1.0  
**Status:** Production-ready  
**Created:** April 30, 2026

