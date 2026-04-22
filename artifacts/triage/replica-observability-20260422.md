# Replica Observability Evidence

Generated: 2026-04-22T17:52:36Z

## Current State

- Failover status: healthy
- Active host marker: 192.168.168.31
- Primary health: HEALTHY
- Replica health: HEALTHY
- Replica ingress check: healthy
- caddy-replica: running
- redis-exporter: healthy
- promtail: healthy

## Remediation Notes

- Replica promtail was stabilized by removing file-based scrape targets and leaving an empty scrape set.
- Redis exporter was recreated with the live replica Redis target and is now healthy.
- Replica ingress on port 18080 is active and returns the expected OAuth redirect response.
