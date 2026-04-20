## VPN-Gated E2E Test Execution Framework

### Objective
Enforce VPN connectivity as a prerequisite for E2E test execution against production endpoints (kushnir.cloud, ide.kushnir.cloud).

### Problem Statement
Production endpoints are protected and should only be accessible via VPN. E2E tests currently lack VPN validation, which means:
1. Tests may silently fail due to network issues (not actual bugs)
2. Non-VPN environments produce false negatives
3. CI runners need VPN configuration to test production

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VPN-Gated E2E Test Flow                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐     ┌──────────────┐     ┌────────────────┐   │
│  │ Test Runner  │────▶│ VPN Check    │────▶│ Test Execution │   │
│  │ (CI/Local)   │     │ Preflight    │     │ (if VPN OK)    │   │
│  └──────────────┘     └──────────────┘     └────────────────┘   │
│                              │                                   │
│                       ┌──────┴──────┐                           │
│                       │ VPN Status? │                           │
│                       └──────┬──────┘                           │
│                     ┌────────┼────────┐                         │
│                     │                 │                         │
│                 Connected         Not Connected                  │
│                     │                 │                         │
│              ┌──────┴──────┐   ┌──────┴──────┐                  │
│              │ Continue    │   │ Skip/Fail   │                  │
│              │ with tests  │   │ with message│                  │
│              └─────────────┘   └─────────────┘                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation

#### 1. VPN Preflight Check Script

**File**: `scripts/ci/check-vpn-connectivity.sh`

```bash
#!/usr/bin/env bash
# @file        scripts/ci/check-vpn-connectivity.sh
# @module      ci/e2e
# @description Verify VPN connectivity before E2E test execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

VPN_CHECK_HOST="${VPN_CHECK_HOST:-192.168.168.31}"
VPN_CHECK_TIMEOUT="${VPN_CHECK_TIMEOUT:-5}"
REQUIRE_VPN="${REQUIRE_VPN:-1}"

check_vpn_connectivity() {
  log_info "Checking VPN connectivity to ${VPN_CHECK_HOST}..."
  
  if ping -c 1 -W "${VPN_CHECK_TIMEOUT}" "${VPN_CHECK_HOST}" > /dev/null 2>&1; then
    log_info "✓ VPN connectivity verified (${VPN_CHECK_HOST} reachable)"
    return 0
  else
    log_warn "✗ VPN connectivity failed (${VPN_CHECK_HOST} unreachable)"
    return 1
  fi
}

check_endpoint_reachability() {
  local endpoint="${1:-https://kushnir.cloud}"
  log_info "Checking endpoint reachability: ${endpoint}..."
  
  if curl -sf --connect-timeout "${VPN_CHECK_TIMEOUT}" "${endpoint}/health" > /dev/null 2>&1; then
    log_info "✓ Endpoint reachable: ${endpoint}"
    return 0
  else
    log_warn "✗ Endpoint unreachable: ${endpoint}"
    return 1
  fi
}

main() {
  local vpn_ok=0
  local endpoints_ok=0
  
  # Check VPN connectivity
  if check_vpn_connectivity; then
    vpn_ok=1
  fi
  
  # Check endpoint reachability
  if check_endpoint_reachability "https://kushnir.cloud" && \
     check_endpoint_reachability "https://ide.kushnir.cloud"; then
    endpoints_ok=1
  fi
  
  # Determine outcome
  if [[ "${vpn_ok}" -eq 1 && "${endpoints_ok}" -eq 1 ]]; then
    log_info "✓ All VPN checks passed - safe to run E2E tests"
    echo "VPN_READY=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  elif [[ "${REQUIRE_VPN}" -eq 1 ]]; then
    log_error "✗ VPN checks failed - E2E tests blocked"
    log_error "Connect to VPN or set REQUIRE_VPN=0 to skip check"
    echo "VPN_READY=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 1
  else
    log_warn "⚠ VPN checks failed but REQUIRE_VPN=0 - proceeding anyway"
    echo "VPN_READY=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi
}

main "$@"
```

#### 2. Playwright Fixture with VPN Assertion

**File**: `tests/e2e/fixtures/vpn-gate.ts`

```typescript
import { test as base, expect } from '@playwright/test';

const REQUIRE_VPN = process.env.REQUIRE_VPN !== '0';
const VPN_CHECK_URL = process.env.VPN_CHECK_URL || 'https://kushnir.cloud/health';

export const test = base.extend({
  vpnConnected: async ({}, use) => {
    if (REQUIRE_VPN) {
      // Verify VPN connectivity before each test
      const response = await fetch(VPN_CHECK_URL, { 
        method: 'HEAD',
        signal: AbortSignal.timeout(5000)
      }).catch(() => null);
      
      if (!response?.ok) {
        throw new Error(`VPN check failed: ${VPN_CHECK_URL} unreachable. Connect to VPN or set REQUIRE_VPN=0`);
      }
    }
    await use(true);
  },
});

export { expect };
```

#### 3. GitHub Actions Workflow Integration

**Update**: `.github/workflows/e2e-tests.yml`

```yaml
name: E2E Tests

on:
  workflow_dispatch:
    inputs:
      require_vpn:
        description: 'Require VPN connectivity'
        type: boolean
        default: true

jobs:
  vpn-preflight:
    runs-on: [self-hosted, vpn-connected]  # Self-hosted runner with VPN
    outputs:
      vpn_ready: ${{ steps.check.outputs.VPN_READY }}
    steps:
      - uses: actions/checkout@v4
      - name: Check VPN connectivity
        id: check
        run: bash scripts/ci/check-vpn-connectivity.sh
        env:
          REQUIRE_VPN: ${{ inputs.require_vpn && '1' || '0' }}

  e2e-tests:
    needs: vpn-preflight
    if: needs.vpn-preflight.outputs.vpn_ready == 'true'
    runs-on: [self-hosted, vpn-connected]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install dependencies
        run: pnpm install
      - name: Run E2E tests
        run: pnpm exec playwright test
        env:
          E2E_USER_EMAIL: ${{ secrets.QA_USER_EMAIL }}
          E2E_USER_PASSWORD: ${{ secrets.QA_USER_PASSWORD }}
          REQUIRE_VPN: '1'
```

### CI Runner Requirements

For VPN-gated tests to work in CI:

1. **Self-hosted runner** with VPN client installed
2. **VPN auto-connect** on runner startup
3. **VPN health monitoring** to detect disconnections
4. **Fallback strategy** for VPN outages (skip tests vs fail)

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REQUIRE_VPN` | `1` | Enforce VPN check before tests |
| `VPN_CHECK_HOST` | `192.168.168.31` | Host to ping for VPN check |
| `VPN_CHECK_TIMEOUT` | `5` | Timeout in seconds |
| `VPN_CHECK_URL` | `https://kushnir.cloud/health` | HTTP endpoint to check |

### Definition of Done

- [ ] `scripts/ci/check-vpn-connectivity.sh` created and executable
- [ ] VPN check integrated into Playwright fixture
- [ ] E2E workflow updated with VPN preflight job
- [ ] Self-hosted runner configured with VPN (or instructions documented)
- [ ] Tests skip gracefully when VPN unavailable (with clear message)
- [ ] Documentation updated with VPN requirements

### Security Considerations

- VPN credentials MUST be stored securely (not in repo)
- Self-hosted runner MUST be in trusted network
- VPN connection logs SHOULD be retained for audit

Parent: #982
