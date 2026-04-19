# On-Prem Immutable State Data Plane (.31/.42)

## Purpose
Define the single source of truth for code-server user durability across primary 192.168.168.31 and replica 192.168.168.42, with immutable IaC-mounted paths, retention classes, and deterministic verification evidence.

## State Tiers

### Tier A: Must Survive
- /home/coder/workspace
  - Source of truth mount: bind mount from repository workspace path via docker compose.
  - Business criticality: highest (user repositories and active work).
- /home/coder/.local/share/code-server/User
  - Source of truth mount: code-server-profile volume.
  - Business criticality: highest (settings, keybindings, user profile).
- /home/coder/.local/share/code-server/extensions
  - Source of truth mount: code-server-profile volume.
  - Business criticality: high (extension state and capability parity).

### Tier B: Recoverable Cache/Temp
- /home/coder/.cache
- Language/toolchain build caches within workspace and ephemeral containers.
- Container writable layers for non-mounted paths.

Tier B may be reconstructed. Tier A is protected by replication checks and snapshot/restore tests.

## Canonical Persistence Layout

Current canonical compose mappings in docker-compose.yml:
- code-server-workspace (NFS volume: ${NAS_HOST}:/export/code-server/workspace) -> /home/coder/workspace
- code-server-profile (NFS volume: ${NAS_HOST}:/export/code-server/profile) -> /home/coder/.local/share/code-server
- code-server-profile-backups (NFS volume: ${NAS_HOST}:/export/code-server/profile-backups) -> backup snapshots

This mapping enforces ephemeral container state outside Tier A mounts and is immutable in practice because redeploy and failover scripts read compose state from source-controlled files and do not rely on mutable in-container edits.

Security baseline constraints for this model:
- code-server auth mode is password-based (no `--auth=none` in production baseline).
- `CODE_SERVER_PASSWORD` must be explicitly set; no weak fallback defaults.
- Baseline compose does not mount `/var/run/docker.sock`.

## Retention and Rollback Points
- Periodic profile backup container writes tiered profile archives to code-server-profile-backups volume.
- Retain at least 30 days of profile snapshots.
- Failover evidence and drift reports stored under /tmp/code-server-state-evidence on the operator host.
- Rollback point is any validated snapshot archive with a passing manifest hash check.

## Non-Interactive Redeploy Requirement
- Standard redeploy and failover flows must be non-interactive and idempotent.
- No manual in-container modifications are part of standard operation.
- Any destructive recreate prompt in manual docker operations is out-of-policy for canonical runbooks.

## Evidence Requirements
- Drift report (Tier A signatures, file counts, byte counts):
  - scripts/operations/redeploy/onprem/state-replication-verify.sh --action drift-report
- Tier-A replication sync from primary to replica:
  - scripts/operations/redeploy/onprem/state-replication-verify.sh --action replicate-tier-a
- Snapshot + restore extraction verification:
  - scripts/operations/redeploy/onprem/state-replication-verify.sh --action snapshot-restore-test

Both commands emit JSON evidence to /tmp/code-server-state-evidence by default.

## Operator Commands

From operator workspace:

```bash
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action drift-report
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action replicate-tier-a
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action snapshot-restore-test
```

From host-local run mode:

```bash
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --mode local-on-host --action drift-report
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --mode local-on-host --action replicate-tier-a
bash scripts/operations/redeploy/onprem/state-replication-verify.sh --mode local-on-host --action snapshot-restore-test
```

## Policy Outcome
- Immutable, source-controlled state layout defined.
- Tier A durability criteria explicitly mapped.
- Verification workflow produces repeatable, machine-readable evidence for issue closure and audit.
