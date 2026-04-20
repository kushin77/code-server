Issue #916 compliance evidence

Validated implementation surface:
- Backend enforces approved session data profiles at launch time.
- Session responses carry `dataProfile` and `dataProfileValidated`.
- Frontend launch form only accepts approved profiles (`synthetic`, `masked`, `redacted`).
- Session status/details render the validated profile state.

Focused validation:
- session-broker tests: 7/7 passed
- frontend tests: 10/10 passed

Test commands:
- `node .\node_modules\vitest\vitest.mjs --run src/session-data-profile.spec.ts src/session-queue.spec.ts src/session-access-control.spec.ts`
- `node .\node_modules\vitest\vitest.mjs --run src/pages/__tests__/EphemeralSessions.test.ts src/utils/__tests__/multiRepoRollout.test.ts`

Relevant code paths:
- `apps/session-broker/src/index.ts`
- `apps/session-broker/src/session-data-profile.ts`
- `apps/session-broker/migrations/001_session_isolation_schema.sql`
- `apps/frontend/src/types/index.ts`
- `apps/frontend/src/pages/EphemeralSessions.tsx`
- `apps/frontend/src/pages/ephemeralSessionsUtils.ts`

Note:
- This artifact captures the repository-side enforcement and validation proof.
- If a live sample-session evidence query is required for the final DoD gate, that still needs a running ephemeral-session environment and recorded query output.