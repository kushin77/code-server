One-pass triage status update for autonomous agents:

Current technical state:
- IaC split callback fix is present in branch (IDE and portal callback vars separated).
- Idempotent redeploy script exists: scripts/deploy/redeploy-portal-oauth-routing.sh.
- Live apex still redirects to IDE callback, so production rollout has not executed successfully yet.

Blockers tracked:
- #688 P0: production callback redeploy execution path (runner/SSH) blocked.
- #687 P1: branch CI/gate stabilization required for deterministic merge readiness.

Parallel execution recommendation:
1. Agent lane A: close #687 by eliminating current workflow failures on this branch.
2. Agent lane B: close #688 by provisioning execution path and running idempotent redeploy with evidence.
3. Return to #671 merge once both blockers are resolved and gates pass.
