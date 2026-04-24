# NAS Architecture

Purpose: canonical NAS topology and mount contract for the on-prem code-server stack.

## Contract

- NAS host: `192.168.168.56`
- Export path: `/export`
- Mount point: `/mnt/nas`
- Protocol: `nfs4`

## Topology

The primary host `192.168.168.31` and replica host `192.168.168.42` both mount the same NAS export.
Persistent workspace and service data are stored under the shared mount so failover can preserve user sessions and runtime state.

## Canonical Mount Layout

- `/mnt/nas/code-server/workspace` - shared workspace content
- `/mnt/nas/code-server/profile` - user profile state
- `/mnt/nas/code-server/profile-backups` - periodic profile snapshots
- `/mnt/nas/ollama` - model storage for AI-enabled deployments
- `/mnt/nas/postgres-backups` - database backup snapshots

## Operational Rules

1. Treat this file as the source of truth for NAS host, export, mount, and protocol values.
2. Update the config SSOT and any scripts that consume NAS values together with this document.
3. Validate mounts on both hosts before production deploys or failover drills.
4. Keep legacy NAS path references out of new docs unless they are explicitly marked historical.

## Validation

- Confirm both hosts mount `/mnt/nas` successfully.
- Confirm the workspace, profile, Ollama, and backup subpaths are writable.
- Confirm failover does not change the NAS contract or remount target.

## Related Docs

- [ops/README.md](ops/README.md)
- [ops/OPERATIONS-INDEX.md](ops/OPERATIONS-INDEX.md)
- [governance/CONFIG-SSOT.md](governance/CONFIG-SSOT.md)
