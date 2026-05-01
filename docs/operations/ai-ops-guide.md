# AI Operations Guide

**Phase**: 13 - AI-Powered Operations  
**Audience**: On-call engineers, SREs, and incident commanders  
**Scope**: Alert deduplication, runbook guidance, and scaling recommendations

This guide explains the deterministic AI-ops advisor that sits on top of the shared
alert receiver. It is intentionally heuristic-based so it can run without external
ML dependencies while still reducing noise and speeding up response.

## What It Does

### Alert Deduplication
- Groups alerts by `alertname`, `component`, and `severity`.
- Keeps one representative alert per fingerprint.
- Reports how many duplicates were suppressed.

### Runbook Guidance
- Uses the alert annotation runbook when present.
- Falls back to component-based runbooks when annotations are missing.
- Returns a structured execution plan if a caller wants to auto-run a playbook.

### Scaling Recommendations
- Flags load, latency, CPU, and memory alerts as scaling candidates.
- Recommends immediate scale-up for critical alerts.
- Recommends review-based scale-up for warning alerts.

## How To Use It

1. Send the Alertmanager webhook to the shared alert receiver.
2. Inspect the `ai` block in the response.
3. Review the deduplication result first to understand alert noise.
4. Use the runbook recommendation to jump straight to the likely fix.
5. Use the scaling recommendation to decide whether to expand capacity.

## Response Shape

The alert receiver returns an `ai` object with three sections:

- `deduplication`: unique alerts, duplicate count, and fingerprints
- `runbooks`: suggested runbooks with confidence
- `scaling`: scaling recommendations with confidence and reasons

## Operational Notes

- The advisor is deterministic, so operators should treat it as guidance, not an autonomous change system.
- The runbook executor plan is side-effect free by design.
- Existing alert routing to Slack and PagerDuty still runs alongside the AI guidance.