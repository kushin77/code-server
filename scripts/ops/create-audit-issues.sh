#!/usr/bin/env bash
# @description Manually trigger issue creation for audited problems
# Requires GITHUB_TOKEN to be set in environment

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="kushin77/code-server"

terraform_version_needs_audit() {
  python3 - <<'PY'
import json
import pathlib
import re
import subprocess
import sys

versions_tf = pathlib.Path("terraform/versions.tf")
if not versions_tf.exists():
  sys.exit(0)

match = re.search(r'required_version\s*=\s*"([^"]+)"', versions_tf.read_text())
if not match:
  sys.exit(0)

constraint_text = match.group(1)
constraints = []
for raw_part in constraint_text.split(','):
  part = raw_part.strip()
  if not part:
    continue
  op, version = part.split(None, 1)
  constraints.append((op, tuple(int(piece) for piece in version.split('.'))))

try:
  version_json = subprocess.check_output(["terraform", "version", "-json"], text=True)
  installed = tuple(int(piece) for piece in json.loads(version_json)["terraform_version"].split('.'))
except Exception:
  sys.exit(1)

def satisfies(installed_version, operator, expected_version):
  if operator == '>=':
    return installed_version >= expected_version
  if operator == '>':
    return installed_version > expected_version
  if operator == '<=':
    return installed_version <= expected_version
  if operator == '<':
    return installed_version < expected_version
  if operator in ('=', '=='):
    return installed_version == expected_version
  return True

needs_audit = any(not satisfies(installed, operator, expected) for operator, expected in constraints)
sys.exit(0 if needs_audit else 1)
PY
}

create_issue() {
  local title="$1"
  local body="$2"
  local priority="$3"
  
  log_info "Creating issue: $title..."
  
  local labels="[\"audit-finding\", \"$priority\", \"automated\"]"
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "body": sys.argv[2], "labels": json.loads(sys.argv[3])}))' "$title" "$body" "$labels")
  
  github_api_call POST "/repos/$REPO/issues" "$payload" || log_error "Failed to create issue: $title"
}

# Issue 1: Replica Host
create_issue "[INFRA] Replica Host (${REPLICA_HOST:-unconfigured}) Connection Timeout" \
"The replica host `${REPLICA_HOST:-unconfigured}` is currently unreachable via SSH (Port 22 timeout). This prevents cluster-wide operations and failover validation.

**Evidence:**
- Reported in [CLUSTER-SHUTDOWN-REPORT-2026-04-27.md](https://github.com/$REPO/blob/main/CLUSTER-SHUTDOWN-REPORT-2026-04-27.md)

**Suggested Action:**
- Verify host power status.
- Check firewall/security group rules." "P1"

# Issue 2: Script Hardening
create_issue "[DEBT] Engineering Hardening: 74+ Scripts Missing Trap Handlers" \
"Approximately 74 operational and deployment scripts lack structured error handling (trap handlers). This can lead to silent failures and partial state corruption.

**Evidence:**
- Reported in [PHASE2-ERROR-HANDLING-SUMMARY.md](https://github.com/$REPO/blob/main/artifacts/PHASE2-ERROR-HANDLING-SUMMARY.md)

**Suggested Action:**
- Implement `trap` handlers across identified scripts." "P2"

# Issue 3: Terraform Version Drift
if terraform_version_needs_audit; then
  create_issue "[IAC] Terraform CLI Version Outside Repo Constraint" \
"The locally installed Terraform CLI version does not satisfy the bounded constraint declared in `terraform/versions.tf`.

**Suggested Action:**
- Align the local Terraform CLI version with the repo constraint.
- Re-run Terraform validation and provider compatibility checks." "P3"
else
  log_info "Skipping Terraform CLI audit issue: local version satisfies repo constraint."
fi

# Issue 4: Tools Missing
create_issue "[OPS] Missing Runtime Tooling: Docker and Kubectl" \
"Core deployment tools (`docker` and `kubectl`) are missing or not in the system PATH. This prevents troubleshooting and manual intervention.

**Suggested Action:**
- Install `docker.io` and `kubectl` binaries." "P1"

# Issue 5: App Errors
create_issue "[APP] Activity Feed & Agent Runtime: Recurring WebSocket/Ingest Errors" \
"Static analysis reveals recurring `WebSocket error`, `Ingest error`, and `Execution error` patterns.

**Evidence:**
- Code paths in `apps/activity_feed/main.py` and `apps/agent-runtime/main.py`.

**Suggested Action:**
- Implement robust reconnection logic and enhance telemetry." "P2"

log_info "All issues queued for creation."
