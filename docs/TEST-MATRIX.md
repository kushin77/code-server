# Test Matrix

Purpose: living inventory of test coverage by service and test tier. This is the SSOT for identifying gaps, linking issue trackers, and deciding whether a feature is ready to ship.

## Policy

- Every production-facing service needs at least one smoke test.
- User-facing surfaces need an authenticated E2E path.
- Public endpoints need load coverage.
- Contract surfaces need specification or contract validation.
- Coverage thresholds must be enforced in CI for shared libraries and service code.

## Current Inventory

Coverage is based on visible repo test files, recorded resilience artifacts, and the current service registry.

| Service / surface | Unit | Integration | Contract | Smoke | E2E (Playwright) | Load (k6 / burst) | Chaos | Coverage % | Gap issue(s) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Backend service modules (`workspace-context-hub`, `session`, `feature-flags`, `ai`) | Yes | Partial | No | No | No | No | No | 35% | #884, #886 |
| Frontend session and rollout utilities (`session-sync`, `multiRepoRollout`, `auth-sw-register`) | Yes | Partial | No | No | Partial | No | No | 45% | #887 |
| Shared policy modules (`policy-bundle-verifier`, `opa-policy-service`, `revocation-broker`, `session-bootstrap-enforcer`, `correlation-audit-fabric`, `tenant-profile-manager`, `shared-workspace-acl`, `ephemeral-workspace-lifecycle`) | Yes | Yes | Partial | N/A | N/A | N/A | Partial | 80% | #884 |
| Production edge / auth path (`code-server`, `oauth2-proxy`, `caddy`, `session-broker`) | Partial | Partial | Partial | Yes | Yes | Yes | Partial | 80% | #889 |
| `token-microservice` | No | No | No | No | No | No | No | 10% | #884, #886 |
| Failover and continuity path | Partial | Partial | No | Yes | Yes | Partial | Partial | 70% | #886 |

## Observed Test Surfaces

### Backend unit coverage

- [apps/backend/src/services/workspace-context-hub/__tests__/service.test.ts](../apps/backend/src/services/workspace-context-hub/__tests__/service.test.ts)
- [apps/backend/src/services/session/__tests__/migration.test.ts](../apps/backend/src/services/session/__tests__/migration.test.ts)
- [apps/backend/src/services/feature-flags/__tests__/feature-flags.test.ts](../apps/backend/src/services/feature-flags/__tests__/feature-flags.test.ts)
- [apps/backend/src/services/ai/__tests__/router.test.ts](../apps/backend/src/services/ai/__tests__/router.test.ts)
- [apps/backend/src/services/ai/__tests__/indexing.test.ts](../apps/backend/src/services/ai/__tests__/indexing.test.ts)
- [apps/backend/src/services/ai/__tests__/indexing-quality.test.ts](../apps/backend/src/services/ai/__tests__/indexing-quality.test.ts)

### Frontend unit coverage

- [apps/frontend/src/utils/__tests__/ws-session-handoff.test.ts](../apps/frontend/src/utils/__tests__/ws-session-handoff.test.ts)
- [apps/frontend/src/utils/__tests__/session-sync.test.ts](../apps/frontend/src/utils/__tests__/session-sync.test.ts)
- [apps/frontend/src/utils/__tests__/session-keepalive.test.ts](../apps/frontend/src/utils/__tests__/session-keepalive.test.ts)
- [apps/frontend/src/utils/__tests__/session-indexeddb-store.test.ts](../apps/frontend/src/utils/__tests__/session-indexeddb-store.test.ts)
- [apps/frontend/src/utils/__tests__/multiRepoRollout.test.ts](../apps/frontend/src/utils/__tests__/multiRepoRollout.test.ts)
- [apps/frontend/src/utils/__tests__/auth-sw-register.test.ts](../apps/frontend/src/utils/__tests__/auth-sw-register.test.ts)

### Shared module conformance coverage

- [tests/unit/policy-bundle-verifier/conformance.spec.ts](../tests/unit/policy-bundle-verifier/conformance.spec.ts)
- [tests/unit/opa-policy-service/conformance.spec.ts](../tests/unit/opa-policy-service/conformance.spec.ts)
- [tests/unit/revocation-broker/enforcement.spec.ts](../tests/unit/revocation-broker/enforcement.spec.ts)
- [tests/unit/session-bootstrap-enforcer/bootstrap.spec.ts](../tests/unit/session-bootstrap-enforcer/bootstrap.spec.ts)
- [tests/unit/correlation-audit-fabric/audit.spec.ts](../tests/unit/correlation-audit-fabric/audit.spec.ts)
- [tests/unit/tenant-profile-manager/hierarchy.spec.ts](../tests/unit/tenant-profile-manager/hierarchy.spec.ts)
- [tests/unit/shared-workspace-acl/conformance.spec.ts](../tests/unit/shared-workspace-acl/conformance.spec.ts)
- [tests/unit/ephemeral-workspace-lifecycle/conformance.spec.ts](../tests/unit/ephemeral-workspace-lifecycle/conformance.spec.ts)

### E2E and resilience coverage

- [tests/e2e/specs/oauth-login.spec.ts](../tests/e2e/specs/oauth-login.spec.ts)
- [tests/e2e/specs/kushnir-cloud-appsmith-login.spec.ts](../tests/e2e/specs/kushnir-cloud-appsmith-login.spec.ts)
- [tests/e2e/specs/authenticated-session-persistence.spec.ts](../tests/e2e/specs/authenticated-session-persistence.spec.ts)
- [tests/e2e/specs/failover-session-continuity.spec.ts](../tests/e2e/specs/failover-session-continuity.spec.ts)
- [artifacts/triage/resilience-campaign.md](../artifacts/triage/resilience-campaign.md)
- Failover continuity evidence artifact: `artifacts/triage/failover-continuity-20260419.md` (generated in CI artifacts when continuity checks run)

### Public edge load coverage

- [scripts/ci/run-public-edge-burst.sh](../scripts/ci/run-public-edge-burst.sh)

## Gap Trackers

- #879 is the parent issue for the matrix itself and the CI enforcement gate.
- #884 tracks OpenAPI 3.1 contract enforcement for internal APIs.
- #878 tracks SLO burn-rate alerting and error budget enforcement.
- #890 will track matrix CI enforcement for coverage thresholds and per-service gates.
- #889 will track the remaining user-facing E2E/load/chaos coverage gaps.

## CI Policy

The matrix is only useful if it is enforced.

- Add unit coverage thresholds for shared libraries and service modules.
- Current CI thresholds: backend unit coverage >= 35%, frontend utility coverage >= 45%.
- Add a smoke gate for deployment validation.
- Require a linked test-matrix row for any new production-facing feature or code change.
- Fail PRs that add a new service or surface without a matching test plan.

## Review Cadence

- Update the matrix whenever a new test file, service, or user-facing surface lands.
- Reconcile the matrix with the service registry after service topology changes.
- Review the gap trackers during weekly planning until coverage stabilizes.