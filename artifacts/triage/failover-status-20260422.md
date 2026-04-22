# Failover Status Evidence

Generated: 2026-04-22T17:45:25Z

## Status Report

- Active host marker: 192.168.168.31
- VIP owner: none
- Primary health: HEALTHY
- Replica health: HEALTHY
- Replica ingress check: healthy

Updated: 2026-04-22T17:49:47Z

## Updated Status

- caddy-replica is running on the replica host.
- The replica ingress probe at http://127.0.0.1:18080/oauth2/start?rd=/ returns the expected OAuth redirect response.

## Notes

- The failover status report was run from the primary host using `operator-run-mode.sh --action status --mode local-on-host`.
- The replica ingress check is now healthy after restoring the temporary `caddy-replica` listener on port 18080.
- The primary and replica hosts themselves are healthy at the container level.
