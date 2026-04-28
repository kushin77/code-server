#!/usr/bin/env bash
# @description Manually trigger issue creation for audited problems
# Requires GITHUB_TOKEN or GCP GSM access
# Secret name in GSM: github-fine-grained-token

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"
source "$SCRIPT_DIR/_common/github-api-client.sh"

readonly REPO="kushin77/code-server"

create_issue() {
  local title="$1"
  local body="$2"
  local priority="$3"
  
  log_info "Creating issue: $title..."

  # Ensure we have a token from GSM or ENV
  local token
  token=$(github_get_token) || {
    log_error "Cannot create issue: GitHub token not found in ENV or GCP GSM"
    return 1
  }
  
  local labels="[\"audit-finding\", \"$priority\", \"automated\"]"
  local payload
  payload=$(python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "body": sys.argv[2], "labels": json.loads(sys.argv[3])}))' "$title" "$body" "$labels")
  
  # Override github_api_call dependency on global GITHUB_TOKEN if github_get_token is used
  GITHUB_TOKEN="$token" github_api_call POST "/repos/$REPO/issues" "$payload" || log_error "Failed to create issue: $title"
}

# Issue 1: Replica Host
create_issue "[INFRA] Replica Host (192.168.168.32) Connection Timeout" \
"The replica host `192.168.168.32` is currently unreachable via SSH (Port 22 timeout). This prevents cluster-wide operations and failover validation.

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

# Issue 3: Terraform Upgrade
create_issue "[IAC] Terraform Version Outdated (v1.8.0 vs v1.14.9)" \
"The local environment is using Terraform `v1.8.0`. The latest stable version is `v1.14.9`.

**Suggested Action:**
- Upgrade Terraform and verify provider compatibility." "P3"

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
