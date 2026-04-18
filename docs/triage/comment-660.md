Epic triage linkage update:

- Child issue #671 remains active and has active CI instability blockers.
- Added blocker references for agent execution:
  - #687 P1 CI stabilization for feat/671 monorepo branch
  - #688 P0 production portal OAuth callback redeploy unblock

Execution guidance for parallel agents:
- Treat #687 as pre-merge quality gate for monorepo refactor rollout.
- Treat #688 as production runtime correctness gate for auth routing before cutover confidence.

No issue close requested yet because acceptance criteria are not complete for #671 and blocker issues are open.
