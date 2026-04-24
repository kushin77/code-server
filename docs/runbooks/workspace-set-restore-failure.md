# Runbook: Workspace Set Restore Failure and Policy Exception

**Purpose**: Runbook: Workspace Set Restore Failure and Policy Exception runbook — operational procedure for workspace set restore failure response.

**Severity**: P1 (restore failure impacting developers) / P2 (policy exception request)  
**Owner**: Developer Platform / Security Operations  
**Date**: 2026-04-20  
**Closes**: #727 (operational runbooks for support and incident response)

---

## Scenario 1: Workspace Set Launch Fails

### Symptoms
- Portal shows launch status `failed` for a workspace set
- Developer reports "could not restore previous session"
- `artifacts/policy-reports/multi-repo-ux-conformance.jsonl` has `policy.violation_detected` events

### Diagnosis steps

```bash
# 1. Check the launch request status via API
curl -H "Authorization: Bearer $TOKEN" \
  https://ide.kushnir.cloud/api/v1/workspace-sets/$WORKSPACE_SET_ID/launch/$LAUNCH_ID

# 2. Check session restore metadata (admin)
curl -H "Authorization: Bearer $TOKEN" \
  https://ide.kushnir.cloud/api/v1/workspace-sets/$WORKSPACE_SET_ID/session-metadata

# 3. Check conformance log
tail -50 artifacts/policy-reports/multi-repo-ux-conformance.jsonl | jq .

# 4. Check session-broker logs
docker compose logs session-broker --since 30m | grep -i "restore\|error\|fallback"
```

### Resolution paths

| Root Cause | Fix |
|---|---|
| Missing repo path | Update `canonical_path` in workspace set via PUT API; notify owner |
| Auth failure (repo unreachable) | Re-authenticate: `gh auth login`; check VPN; retry launch |
| Corrupt snapshot | Delete snapshot: `rm ~/.code-server/snapshots/<repo-id-hash>.snapshot.json` |
| Policy violation | Check `multi-repo-ux-policy.json`; may need policy exception (Scenario 2) |
| `approval_required=true`, no approval | Approver must approve in Appsmith console (see below) |
| Snapshot size exceeded | Admin: increase `snapshot_retention_limit_mb` or clear old snapshots |

---

## Scenario 2: Policy Exception Request for Shared Workspace Set

### When a policy exception is needed
- A workspace set requires features disabled by active policy (e.g., terminal replay)
- A team set requires more repos than `max_open_repos` allows
- `approval_required=true` but approver is unavailable

### Appsmith approval workflow

1. Developer submits exception request from portal (Appsmith operator console).
2. Request appears in Appsmith "Pending Approvals" page with:
   - Workspace set ID + name
   - Requested policy exception (key + current value + requested value)
   - Business justification
   - Requestor + team
3. Approver reviews and approves or rejects with reason.
4. On approval:
   - `approved_by` and `approved_at` are written to workspace set RBAC block
   - Launch unblocked
   - Audit event `policy.override_attempted` + `policy.loaded` emitted
5. Exception is scoped to the workspace set (not global).

### Emergency: stuck approval (P1 incident)

If an approval is blocking a P0/P1 incident response:

```bash
# 1. Open a break-glass waiver per docs/governance/break-glass-policy.md
# 2. Admin can bypass approval check:
curl -X POST -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason": "P0 incident response", "waiver_id": "<waiver-id>"}' \
  https://ide.kushnir.cloud/api/v1/workspace-sets/$WORKSPACE_SET_ID/launch

# 3. Record break-glass entry in config/waivers/ with approver signature
# 4. File PIR within 24h per break-glass policy
```

---

## Scenario 3: Session Restore Metadata Not Visible in Admin

### Check

```bash
# Confirm session-broker is running and reachable
docker compose ps session-broker
curl -H "Authorization: Bearer $ADMIN_TOKEN" \
  https://ide.kushnir.cloud/api/v1/workspace-sets/$WORKSPACE_SET_ID/session-metadata

# Check if audit events are being emitted
tail -20 artifacts/policy-reports/multi-repo-ux-conformance.jsonl
```

### Resolution

- If session-broker is down: `docker compose restart session-broker`
- If audit log is empty: check `telemetry_level` in `config/policies/multi-repo-ux-policy.json` (must not be `off`)
- If API returns 403: verify caller has admin role (`rbac.editors` or org admin)

---

## Escalation

| Level | Condition | Contact |
|---|---|---|
| L1 | Developer self-serve (portal error message + this runbook) | — |
| L2 | Repeated restore failures (>3 in 24h for same user) | Developer Platform on-call |
| L3 | Data loss or security-related policy exception | Security Operations + Platform lead |
