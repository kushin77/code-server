---
title: Ephemeral Shadow Replay Runbook
description: Execute read-safe shadow traffic replay against an active ephemeral session and interpret evidence bundle output.
owner: Platform Engineering
last_review_date: 2026-04-20
status: active
---

## Purpose

Validate an active ephemeral session with production-like, anonymized read-only traces before merge.

## Preconditions

- Session broker is reachable.
- Target session is in `ready` or `testing` state.
- Caller is authorized to view the session.
- Replay traces include only `GET`, `HEAD`, or `OPTIONS` requests.

## 1. Execute Shadow Replay

```bash
curl -sS -X POST "${SESSION_BROKER_URL}/sessions/${SESSION_ID}/shadow-replay" \
  -H "Content-Type: application/json" \
  -H "x-auth-request-user: ${AUTH_USER}" \
  -H "x-auth-request-email: ${AUTH_EMAIL}" \
  -d '{
    "maxLatencyRegressionMs": 50,
    "traces": [
      {
        "method": "GET",
        "path": "/healthz",
        "baselineStatus": 200,
        "baselineLatencyMs": 20
      },
      {
        "method": "HEAD",
        "path": "/",
        "baselineStatus": 200,
        "baselineLatencyMs": 15
      }
    ]
  }' | jq
```

Expected result:
- HTTP `200` response with `report` and `evidenceBundle.reportPath`.
- `report.statusMismatchCount` and `report.latencyRegressionCount` populated.

## 2. Retrieve Evidence Bundle

```bash
curl -sS "${SESSION_BROKER_URL}/sessions/${SESSION_ID}/evidence" \
  -H "x-auth-request-user: ${AUTH_USER}" \
  -H "x-auth-request-email: ${AUTH_EMAIL}" | jq
```

Expected bundle fields:
- `events` includes `shadow_replay` audit action.
- `shadowReplay.report` includes comparative diff rows.
- `shadowReplay.reportPath` points to the persisted artifact in session storage.

## 3. Interpret Report

- `statusMismatchCount > 0`: behavior regression likely present.
- `latencyRegressionCount > 0`: latency exceeded allowed delta (`maxLatencyRegressionMs`).
- Each `diffs[]` entry shows baseline versus observed status and latency deltas.

## 4. Negative Guardrail Validation

Send a non-read-safe method and ensure rejection:

```bash
curl -sS -X POST "${SESSION_BROKER_URL}/sessions/${SESSION_ID}/shadow-replay" \
  -H "Content-Type: application/json" \
  -H "x-auth-request-user: ${AUTH_USER}" \
  -H "x-auth-request-email: ${AUTH_EMAIL}" \
  -d '{
    "traces": [
      {
        "method": "POST",
        "path": "/api/workspaces",
        "baselineStatus": 200,
        "baselineLatencyMs": 25
      }
    ]
  }' | jq
```

Expected result:
- HTTP `400` or `422` validation/policy error.
- Replay is not executed.

## Operational Notes

- Replay is intentionally non-destructive and blocks write methods.
- Reports persist under the session evidence directory as `shadow-replay-report.json`.
- Use issue comments to attach summarized report findings for auditability.
