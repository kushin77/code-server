## QA Session Isolation and Test Data Management

### Objective
Ensure QA test sessions are isolated from production users and all test data is cleaned up after each run.

### Problem Statement
Without proper isolation:
1. QA tests may interfere with real user sessions
2. Test data may accumulate and waste storage
3. Failed tests may leave orphaned resources
4. Production metrics may be skewed by test traffic

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    QA Session Isolation                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐     ┌──────────────────────┐          │
│  │ Production Sessions  │     │ QA Test Sessions     │          │
│  │                      │     │                      │          │
│  │ • Real user traffic  │     │ • qa@kushnir.cloud   │          │
│  │ • Persistent data    │     │ • Ephemeral data     │          │
│  │ • Metrics included   │     │ • Metrics excluded   │          │
│  │ • Long-lived         │     │ • Short-lived        │          │
│  └──────────────────────┘     └──────────────────────┘          │
│             │                           │                        │
│             │     ┌─────────────────────┤                        │
│             │     │                                              │
│             ▼     ▼                                              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Redis Session Store                    │   │
│  │                                                           │   │
│  │  session:user:akushnir@...  ─────────────────▶ PERSISTENT │   │
│  │  session:qa:qa@kushnir.cloud ─────────────────▶ EPHEMERAL │   │
│  │                                                  (TTL: 1h) │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation

#### 1. QA Session Prefix

**oauth2-proxy configuration** (`oauth2-proxy.cfg`):

```ini
# QA sessions get shorter TTL and distinct prefix
# This requires custom session handling or middleware
```

**session-broker update** (`apps/session-broker/src/index.ts`):

```typescript
// Detect QA user and apply isolation rules
const isQAUser = (email: string) => email.startsWith('qa@') || email.includes('qa-test');

function createSession(userEmail: string) {
  const prefix = isQAUser(userEmail) ? 'qa:' : 'user:';
  const ttl = isQAUser(userEmail) ? 3600 : 86400; // 1h vs 24h
  
  return {
    sessionKey: `session:${prefix}${userEmail}`,
    ttl
  };
}
```

#### 2. Test Data Namespace

All QA-created resources should be namespaced:

```typescript
// tests/e2e/fixtures/test-data.ts

const QA_PREFIX = `qa-test-${Date.now()}`;

export function createTestWorkspace(): string {
  return `${QA_PREFIX}-workspace`;
}

export function createTestFile(): string {
  return `${QA_PREFIX}-file.txt`;
}

export function isQAResource(name: string): boolean {
  return name.startsWith('qa-test-');
}
```

#### 3. Cleanup Script

**File**: `scripts/ci/cleanup-qa-resources.sh`

```bash
#!/usr/bin/env bash
# @file        scripts/ci/cleanup-qa-resources.sh
# @module      ci/e2e
# @description Clean up all QA test resources after E2E test run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

REDIS_HOST="${REDIS_HOST:-redis}"
QA_SESSION_PATTERN="session:qa:*"
QA_WORKSPACE_PATTERN="qa-test-*"
DRY_RUN="${DRY_RUN:-1}"

cleanup_redis_sessions() {
  log_info "Cleaning up QA sessions from Redis..."
  
  local keys
  keys=$(redis-cli -h "${REDIS_HOST}" KEYS "${QA_SESSION_PATTERN}" 2>/dev/null || echo "")
  
  if [[ -z "${keys}" ]]; then
    log_info "No QA sessions found in Redis"
    return 0
  fi
  
  local count
  count=$(echo "${keys}" | wc -l)
  log_info "Found ${count} QA sessions to clean up"
  
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "[DRY-RUN] Would delete:"
    echo "${keys}"
  else
    echo "${keys}" | xargs redis-cli -h "${REDIS_HOST}" DEL
    log_info "Deleted ${count} QA sessions"
  fi
}

cleanup_workspaces() {
  log_info "Cleaning up QA workspaces..."
  
  # List QA workspaces (adjust path as needed)
  local workspace_dir="${WORKSPACE_BASE:-/var/lib/code-server/workspaces}"
  
  if [[ ! -d "${workspace_dir}" ]]; then
    log_warn "Workspace directory not found: ${workspace_dir}"
    return 0
  fi
  
  find "${workspace_dir}" -maxdepth 1 -type d -name "${QA_WORKSPACE_PATTERN}" | while read -r ws; do
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log_info "[DRY-RUN] Would delete workspace: ${ws}"
    else
      rm -rf "${ws}"
      log_info "Deleted workspace: ${ws}"
    fi
  done
}

cleanup_containers() {
  log_info "Cleaning up orphaned QA containers..."
  
  # Find containers with QA label
  local containers
  containers=$(docker ps -a --filter "label=qa-test=true" --format "{{.ID}}" 2>/dev/null || echo "")
  
  if [[ -z "${containers}" ]]; then
    log_info "No QA containers found"
    return 0
  fi
  
  local count
  count=$(echo "${containers}" | wc -l)
  log_info "Found ${count} QA containers to clean up"
  
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log_info "[DRY-RUN] Would remove containers:"
    echo "${containers}"
  else
    echo "${containers}" | xargs docker rm -f
    log_info "Removed ${count} QA containers"
  fi
}

main() {
  log_info "Starting QA resource cleanup (DRY_RUN=${DRY_RUN})"
  
  cleanup_redis_sessions
  cleanup_workspaces
  cleanup_containers
  
  log_info "QA resource cleanup complete"
}

main "$@"
```

#### 4. Playwright Cleanup Hook

**File**: `tests/e2e/fixtures/cleanup.ts`

```typescript
import { test as base } from '@playwright/test';

export const test = base.extend({
  // Auto-cleanup after each test
  autoCleanup: [async ({}, use) => {
    const createdResources: string[] = [];
    
    // Provide resource tracking
    await use({
      track: (resourceId: string) => createdResources.push(resourceId),
      resources: createdResources
    });
    
    // Cleanup after test
    for (const resource of createdResources) {
      console.log(`Cleaning up: ${resource}`);
      // API call to delete resource
    }
  }, { auto: true }]
});
```

#### 5. Metrics Exclusion

**prometheus.yml** update:

```yaml
scrape_configs:
  - job_name: 'oauth2-proxy'
    static_configs:
      - targets: ['oauth2-proxy:4180']
    metric_relabel_configs:
      # Exclude QA user metrics from dashboards
      - source_labels: [user]
        regex: 'qa@kushnir\.cloud'
        action: drop
```

### Definition of Done

- [ ] QA sessions use distinct Redis key prefix
- [ ] QA sessions have shorter TTL (1h vs 24h)
- [ ] Test data uses `qa-test-` namespace prefix
- [ ] Cleanup script removes all QA resources
- [ ] Cleanup runs automatically after E2E test suite
- [ ] QA traffic excluded from production metrics
- [ ] No orphaned resources after 24h

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `QA_SESSION_TTL` | `3600` | QA session TTL in seconds |
| `QA_RESOURCE_PREFIX` | `qa-test-` | Prefix for all QA resources |
| `CLEANUP_DRY_RUN` | `1` | Dry run cleanup (no delete) |

Parent: #982
Depends on: #983, #984 (QA account created and configured)
