# Observability Operations Training Guide

**Phase**: 11 - Documentation & Training  
**Audience**: On-call engineers, SREs, DevOps, and service owners  
**Scope**: Prometheus, Grafana, Alertmanager, shared monitoring, SLOs, and tracing

This guide turns the Phase 9 and Phase 10 observability work into an operator-ready
training package. Use it for onboarding, refresher training, and incident drills.

## What Operators Should Know

### 1. Metrics Path
- Services expose `/metrics` via the shared monitoring module.
- Prometheus scrapes service jobs from `config/prometheus.yml` and the mirrored config tree.
- Control-plane is the reference implementation for request, error, and latency metrics.

### 2. SLO Path
- SLO targets live in `apps/shared/slo.py`.
- Availability, error rate, and p99 latency are the standard indicators.
- Alert rules in `monitoring/alerts/alert-rules.yml` and `config/monitoring/alerts/prometheus-rules.yml` fire when thresholds are violated.

### 3. Tracing Path
- Shared tracing lives in `apps/shared/tracing.py`.
- OpenTelemetry is optional; the fallback still propagates a stable `X-Trace-Id` header.
- Control-plane demonstrates the integration pattern and request correlation flow.

## Training Modules

### Module 1: Read the Dashboard
1. Open Grafana and load the observability dashboard.
2. Confirm the service availability panel is green.
3. Check error-rate and latency panels for recent spikes.
4. Review traces when a request path looks slow or inconsistent.

### Module 2: Validate Scraping
1. Confirm the service exposes `/metrics`.
2. Check Prometheus targets for the service job.
3. Ensure the job name matches the configured scrape target.
4. Verify new metrics appear after a sample request.

### Module 3: Respond to Alerts
1. Read the alert title and labels first.
2. Determine whether the alert is service-down, SLO-breach, or tracing-related.
3. Pull the matching runbook.
4. Reproduce the symptom in the smallest possible scope.
5. Record the fix and any follow-up action.

### Module 4: Trace a Request
1. Identify the request ID or `X-Trace-Id` header.
2. Follow the request in logs.
3. Inspect the corresponding trace in the tracing backend if available.
4. Compare the trace timing with Prometheus latency metrics.

## Drill Scenarios

### Scenario A: Control Plane Availability Drop
- Symptom: `ControlPlaneAvailabilitySLOViolation` alert fires.
- Validate `/health` and `/metrics` on the control-plane service.
- Check Prometheus target status.
- Confirm whether the issue is a real outage or a scrape failure.

### Scenario B: High Error Rate
- Symptom: `ControlPlaneErrorRateSLOViolation` alert fires.
- Review recent errors in logs.
- Check whether the failures correlate with a recent deployment.
- Confirm whether the affected code path is covered by a retry or fallback.

### Scenario C: Tracing Gaps
- Symptom: Requests appear in logs but traces are missing or incomplete.
- Check `OTEL_ENABLED` and `OTEL_EXPORTER_OTLP_ENDPOINT`.
- Verify the `X-Trace-Id` header is present in responses.
- Confirm the service imported and called the shared tracing helpers.

## Escalation Path

- **Level 1**: On-call engineer restores service or collects evidence.
- **Level 2**: Ops lead reviews a repeated failure or ambiguous alert.
- **Level 3**: Engineering lead is involved when code changes or architecture changes are required.

## Sign-Off Criteria

Before an engineer is cleared to operate the observability stack independently, they must:

- Explain the metrics path from app to Prometheus.
- Explain the SLO targets and the alert thresholds.
- Explain how tracing is propagated across requests.
- Demonstrate one alert investigation end-to-end.
- Demonstrate one trace follow-up from logs to dashboard.
