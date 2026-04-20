## Child Issues Created

All child issues have been created and linked to this EPIC.

### Setup & Configuration (P0)

| # | Title | Status |
|---|-------|--------|
| #983 | Create qa@kushnir.cloud Google Workspace user | Not started |
| #984 | Configure QA user OAuth whitelist + GSM credentials | Not started |

### Infrastructure (P1)

| # | Title | Status |
|---|-------|--------|
| #985 | VPN-gated E2E test execution framework | Not started |
| #991 | QA session isolation and test data management | Not started |
| #992 | QA metrics, reporting, and CI gate integration | Not started |

### Test Coverage - 100x Rigor (P1)

| # | Title | Target Tests |
|---|-------|--------------|
| #986 | E2E - OAuth login flow comprehensive validation | 20+ tests |
| #987 | E2E - Appsmith portal feature testing suite | 30+ tests |
| #988 | E2E - IDE launch and workspace operations | 25+ tests |
| #989 | E2E - Session persistence and failover scenarios | 15+ tests |
| #990 | E2E - Error handling and edge case coverage | 20+ tests |

**Total Target**: 110+ E2E tests (current: 4)

### Execution Order (Dependency-Aware)

```
Phase 1 - QA Account Setup (P0, blocking):
  #983 → Create Google Workspace user
  #984 → Configure OAuth whitelist + GSM (depends on #983)

Phase 2 - Infrastructure:
  #985 → VPN-gated test execution (parallel)
  #991 → Session isolation (parallel)
  #992 → Metrics and CI gate (parallel)

Phase 3 - Test Implementation (depends on Phase 1+2):
  #986 → OAuth login tests (first - establishes auth fixtures)
  #987 → Appsmith portal tests (depends on #986 fixtures)
  #988 → IDE operation tests (depends on #987)
  #989 → Session/failover tests (depends on #988)
  #990 → Error/edge case tests (last - covers all surfaces)
```

### Cross-References

- Parent EPIC: #954 (HA Load Balancing)
- Related: #964 (E2E Playwright tests)
- Blocked by: Google Workspace admin access for #983

### Next Steps

1. **Owner action required**: Create qa@kushnir.cloud via Google Admin Console
2. Store password in GSM: `gcloud secrets create qa-user-password`
3. Update `allowed-emails.txt` with `qa@kushnir.cloud`
4. Run initial login test to verify setup
