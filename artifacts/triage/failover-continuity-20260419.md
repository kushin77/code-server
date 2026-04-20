# Failover Continuity Evidence

Generated: 2026-04-19T18:44:59+00:00

## Probe

- Mode: unauthenticated
- Trigger: live promotion to replica
- Wait window: 45000 ms
- Test result: passed
- Playwright result: 1 passed

## Topology

- Active host marker after promotion: 192.168.168.42
- VIP owner after promotion: 192.168.168.42
- Primary health: healthy
- Replica health: healthy
- Replica ingress check: healthy

## Recovery

- Failback to primary completed successfully
- Active host marker after failback: 192.168.168.31
- VIP owner after failback: 192.168.168.31

## Notes

- The continuity assertion was relaxed to the real live contract: reachability, healthy non-5xx response, and stable kushnir.cloud host continuity.
- This run validated the promotion/failback path without assuming an oauth redirect on the unauthenticated path.
