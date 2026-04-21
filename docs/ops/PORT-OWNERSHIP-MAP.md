# Port Ownership Map

**Purpose**: Port Ownership Map — reference and operational document.

This document records the reserved host-port policy for the on-prem Docker stacks used by the primary host (`192.168.168.31`) and the replica host (`192.168.168.42`). It exists to prevent repeat bind collisions during restart and redeploy operations.

## Reserved Host Ports

| Host role | Service / stack | Reserved host ports | Notes |
| --- | --- | --- | --- |
| Primary edge | `caddy` | `80`, `443`, `2019` | Primary public ingress and admin port. |
| Primary auth gate | `oauth2-proxy` | `4180` (loopback) | Internal-only loopback binding for IDE auth. |
| Portal auth gate | `oauth2-proxy-portal` | `4181` (internal) | Portal-only auth proxy. |
| Replica edge | `caddy-replica` | `18080` / alternate edge binding | Replica edge must not bind host `80` or `443`. |
| Application stack | `appsmith` | no public host ports | Appsmith remains behind the proxy layer. |

## Collision Rules

- On the primary host, anything other than `caddy` binding host ports `80`, `443`, or `2019` is treated as a blocking collision.
- On the replica host, any binding to host ports `80`, `443`, or `2019` is treated as a blocking collision.
- Restart and redeploy operations must stop before any host-side restart if a reserved port is already claimed.

## Enforcement Path

- Preflight guard: [scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh](../../scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh)
- Dual-host restart and log harvest: [scripts/operations/redeploy/onprem/dual-host-restart-harvest.sh](../../scripts/operations/redeploy/onprem/dual-host-restart-harvest.sh)
- Runbook: [docs/runbooks/dual-host-restart-harvest.md](../runbooks/dual-host-restart-harvest.md)

## Related Issues

- #905 secondary host port-conflict remediation
- #892 dual-host restart and log-harvest workflow