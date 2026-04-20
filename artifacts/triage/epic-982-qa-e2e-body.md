## EPIC: QA User & Comprehensive E2E Testing Infrastructure

### Objective
Create a dedicated QA user `qa@kushnir.cloud` in Google Workspace and build comprehensive E2E testing infrastructure to achieve 100x testing rigor for the kushnir.cloud OAuth → Appsmith → IDE authentication path.

### Background
Current state:
- `allowed-emails.txt` only contains 2 personal accounts (akushnir@bioenergystrategies.com, kushin77@gmail.com)
- E2E test specs exist but lack a dedicated QA service account
- No automated credential rotation or session management for E2E testing
- VPN-based test execution not enforced
- Test coverage limited to smoke tests, not comprehensive feature validation

### Parent Domain
- **Google Workspace Admin**: `akushnir@bioenergystrategies.com` (domain admin for kushnir.cloud)
- **OAuth Provider**: Google OIDC via oauth2-proxy
- **Target Platform**: kushnir.cloud (Appsmith portal + IDE)

### Child Issues

#### Setup & Configuration
- [ ] #983 - Create qa@kushnir.cloud Google Workspace user
- [ ] #984 - Configure QA user OAuth whitelist + GSM credentials
- [ ] #985 - VPN-gated E2E test execution framework

#### Test Coverage (100x Rigor)
- [ ] #986 - E2E: OAuth login flow comprehensive validation
- [ ] #987 - E2E: Appsmith portal feature testing suite
- [ ] #988 - E2E: IDE launch and workspace operations
- [ ] #989 - E2E: Session persistence and failover scenarios
- [ ] #990 - E2E: Error handling and edge case coverage

#### Infrastructure & CI
- [ ] #991 - QA session isolation and test data management
- [ ] #992 - QA metrics, reporting, and CI gate integration

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                      QA Testing Infrastructure                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────┐ │
│  │ Google       │     │ GSM          │     │ GitHub Actions       │ │
│  │ Workspace    │────▶│ Secrets      │────▶│ CI Runner            │ │
│  │ qa@kushnir   │     │ QA creds     │     │ (VPN-connected)      │ │
│  └──────────────┘     └──────────────┘     └──────────────────────┘ │
│                                                       │              │
│                                                       ▼              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Playwright Test Runner                     │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │   │
│  │  │ Auth Tests  │  │ Portal Tests│  │ IDE Tests           │   │   │
│  │  │ oauth-login │  │ appsmith    │  │ code-server         │   │   │
│  │  │ csrf        │  │ features    │  │ workspace           │   │   │
│  │  │ session     │  │ navigation  │  │ extensions          │   │   │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                       │              │
│                                                       ▼              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Target Environment                         │   │
│  │  kushnir.cloud → oauth2-proxy → Appsmith → session-broker    │   │
│  │                                    ↓                          │   │
│  │                              ide.kushnir.cloud                │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Test Categories (100x Coverage Target)

| Category | Current | Target | Priority |
|----------|---------|--------|----------|
| OAuth login flows | 2 tests | 20+ tests | P0 |
| Appsmith portal features | 0 tests | 30+ tests | P1 |
| IDE operations | 0 tests | 25+ tests | P1 |
| Session/failover | 2 tests | 15+ tests | P0 |
| Error handling | 0 tests | 20+ tests | P1 |
| Performance/load | 0 tests | 10+ tests | P2 |
| **Total** | **4 tests** | **120+ tests** | - |

### Security Requirements

1. **QA credentials MUST be stored in GSM** (Google Secret Manager)
2. **QA user MUST have minimal permissions** (no admin access)
3. **QA sessions MUST be isolated** from production user sessions
4. **Test data MUST be cleaned up** after each test run
5. **VPN MUST be required** for test execution against production endpoints

### Definition of Done

- [ ] qa@kushnir.cloud user exists and can authenticate to kushnir.cloud
- [ ] QA credentials stored in GSM and injected into CI
- [ ] VPN-gated test execution enforced in CI workflow
- [ ] Test coverage increased from 4 to 100+ tests
- [ ] All test categories have comprehensive coverage
- [ ] CI gate prevents merges with test failures
- [ ] Test metrics dashboard available
- [ ] QA session isolation verified

### Elite Engineering Alignment

| Principle | Implementation |
|-----------|----------------|
| 7. Testing & QA (100x) | Comprehensive E2E suite covering all user flows |
| 14. Endpoint & SSO Validation | QA account simulates real user interaction patterns |
| 5. Security (Fort Knox) | GSM-stored credentials, VPN-gated execution |
| 8. GitHub Integration | CI gate blocks merges on test failure |
| 1. Infrastructure Control | Tests validate idempotent redeploy outcomes |

### Priority
P0 - QA infrastructure is prerequisite for production-readiness validation

### Cross-References
- Parent: #954 (HA EPIC)
- Related: #964 (E2E Playwright tests)
- Blocked by: Google Workspace admin access
