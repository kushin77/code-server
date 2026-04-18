Status triage update (autonomous execution ready):

- Created blocker issue #688 (P0): production portal OAuth callback redeploy blocked by missing execution path (runner/SSH), with immutable + idempotent acceptance criteria.
- Using existing blocker issue #687 (P1): CI gate stabilization for feat/671 monorepo branch with concrete failing run seeds and acceptance criteria.

Execution facts captured:
- Live apex callback still misroutes to IDE callback.
- Idempotent redeploy script exists and validates locally.
- Current repo self-hosted runner count is 0; self-hosted jobs queue indefinitely.

Program dependency mapping:
- #688 blocks production auth correctness and deploy confidence.
- #687 blocks branch gate completion required for autonomous merge readiness.

Recommended sequencing for parallel agents:
1. Complete #687 to restore deterministic CI baseline.
2. Complete #688 to execute production callback redeploy and verify live redirects.
