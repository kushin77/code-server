# Session FinOps Guardrails

This runbook defines the operational policy for ephemeral session quotas, runtime limits, inactivity timeouts, and usage visibility.

## Policy Defaults

- Maximum active sessions per user: 1
- Maximum active sessions per team/domain: 3
- Maximum runtime per session: 8 hours
- Maximum inactivity before teardown: 2 hours
- Usage telemetry window: 24 hours

## Broker Controls

- Launch requests are denied with HTTP 429 when user or team quotas are exceeded.
- Launch requests are denied with HTTP 422 when the requested TTL exceeds the runtime policy.
- The broker automatically reaps stale sessions that exceed runtime or inactivity limits.
- Usage summaries are available from `GET /usage/summary?windowHours=24`.
- Prometheus scrapes broker telemetry from `GET /metrics` for quota pressure, reaper health, and usage trends.

## Usage Review

- Review `teams` output from the usage summary endpoint for active session counts, failed sessions, and estimated CPU hours.
- Investigate spikes in failed sessions or rapid growth in estimated CPU hours before raising quota limits.
- Use the `Session FinOps Guardrails` Grafana dashboard for current quota utilization, launch denials, reaper staleness, and team usage trends.

## Recommended Alert Thresholds

- Warning: any team at 80% of the active-session quota for 10 minutes.
- Critical: any quota-denied launch burst above 5 events in 10 minutes.
- Warning: stale-session reaper failure or no reaper activity for 30 minutes.
- Critical: sessions exceeding runtime policy for more than 5 minutes.
- The Prometheus alert rules mirror these thresholds and page on sustained pressure or stalled cleanup.

## Tuning Guidance

- Raise per-user quota only after verifying the user is not leaving stale sessions open.
- Raise per-team quota only after checking estimated CPU hours and the team’s recent change cadence.
- Keep inactivity shorter than runtime so abandoned sessions are reclaimed before hard TTL expiry.
- Use the telemetry endpoint to compare active sessions versus total runtime before changing defaults.