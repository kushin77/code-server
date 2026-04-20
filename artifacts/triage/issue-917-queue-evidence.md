Issue #917 queueing evidence

Validated implementation surface:
- Session broker now normalizes and persists queue metadata.
- Launches include `queueLane`, `queueReason`, `queuePosition`, `queueEnqueuedAt`, and `queueEstimatedWaitSeconds` where applicable.
- Queued sessions are surfaced in the frontend session view with lane, position, ETA, and queued-state messaging.
- Priority lane selection is available in the launch UI.

Focused validation:
- session-broker tests: 7/7 passed
- frontend tests: 10/10 passed

Test commands:
- `node .\node_modules\vitest\vitest.mjs --run src/session-data-profile.spec.ts src/session-queue.spec.ts src/session-access-control.spec.ts`
- `node .\node_modules\vitest\vitest.mjs --run src/pages/__tests__/EphemeralSessions.test.ts src/utils/__tests__/multiRepoRollout.test.ts`

Relevant code paths:
- `apps/session-broker/src/index.ts`
- `apps/session-broker/src/session-queue.ts`
- `apps/session-broker/src/session-policy.ts`
- `apps/session-broker/migrations/001_session_isolation_schema.sql`
- `apps/frontend/src/types/index.ts`
- `apps/frontend/src/pages/EphemeralSessions.tsx`
- `apps/frontend/src/pages/ephemeralSessionsUtils.ts`

Note:
- This artifact records the queue behavior and validation currently present in the repository.