# Observability Operations Checklist

Use this checklist during onboarding or before an on-call handoff.

## Readiness

- [ ] I can describe the metrics, SLO, and tracing paths in the platform.
- [ ] I can point to the shared modules in `apps/shared/`.
- [ ] I can explain how control-plane is instrumented.
- [ ] I can identify the Prometheus job for at least one service.
- [ ] I can find the corresponding Grafana dashboard.

## Hands-On Verification

- [ ] I can query `/metrics` on a live service.
- [ ] I can explain what `request_total`, `errors_total`, and latency metrics mean.
- [ ] I can interpret an SLO alert and determine whether it is availability, error-rate, or latency related.
- [ ] I can trace a request using `X-Trace-Id` or `traceparent`.
- [ ] I can identify the next escalation step if I cannot restore service.

## Incident Drill

- [ ] I can follow the control-plane availability drill.
- [ ] I can follow the high-error-rate drill.
- [ ] I can validate whether a tracing gap is caused by configuration or deployment.
- [ ] I can document the remediation and update the incident log.

## Handoff

- [ ] I have reviewed the observability guide and tracing guide.
- [ ] I know where the runbooks live.
- [ ] I know how to check alert routing.
- [ ] I know who to escalate to for Level 2 and Level 3.
- [ ] I am comfortable handling a routine alert without supervision.