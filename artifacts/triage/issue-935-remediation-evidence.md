# Issue #935 Remediation Evidence

Generated: "2026-04-20T00:45:28Z"

## Scope implemented
- Standardized pointer-only retired stub:
  - scripts/docker-compose.yml
- Retired and redirected active config surface:
  - config/systemd/terminal-output-optimizer.service
    - canonical replacement pointer: config/systemd/latency-monitor.service
- Retired and redirected active status ledger:
  - docs/status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md
    - canonical replacements: config/issues/agent-execution-manifest.json and docs/status/README.md
- Removed active-path references from:
  - Makefile
  - docs/ops/PORTAL-OAUTH-GCP-GSM-BOOTSTRAP-695.md
  - docs/status/README.md
  - config/issues/agent-execution-manifest.json
  - .github/workflows/validate-issue-governance.yml
- Added regression guard:
  - scripts/ci/check-do-not-use-config-surfaces.sh
  - .github/workflows/do-not-use-config-surfaces-guard.yml

## Validation
Command:
- bash scripts/ci/check-do-not-use-config-surfaces.sh

Result:
- PASS (Do-not-use config surface guard passed)

Artifact:
- artifacts/triage/issue-935-do-not-use-config-surfaces.log
