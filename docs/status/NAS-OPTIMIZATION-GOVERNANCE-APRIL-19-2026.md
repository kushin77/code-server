# NAS Optimization and Data-Path Governance - April 19, 2026

Status: Complete
Scope: NAS utilization patterns, hot/warm/cold data-path guidance, and operational optimization opportunities for the current on-prem stack.

## Purpose

This is the canonical SSOT artifact for issue #845. It documents the current NAS baseline, the data-path policy, and the optimization opportunities that reduce unnecessary coupling to shared storage.

## Evidence Reviewed

- [../ops/NAS-ARCHITECTURE.md](../ops/NAS-ARCHITECTURE.md)
- [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- [ARCHITECTURE-STRESS-REVIEW-APRIL-19-2026.md](ARCHITECTURE-STRESS-REVIEW-APRIL-19-2026.md)
- [../status/ELITE-INFRASTRUCTURE-SUMMARY.md](ELITE-INFRASTRUCTURE-SUMMARY.md)

## Current Baseline

The current platform baseline is a shared NAS-backed persistence model:

- NAS host: `192.168.168.56`
- Export: `/export`
- Mount point: `/mnt/nas`
- Protocol: `nfs4`

Current shared-storage uses:

- Workspace/profile persistence for the code-server stack
- Shared model and backup storage for AI-enabled services
- Operational backup and recovery paths

Current risk profile:

- Shared storage is central to persistence and recovery.
- NAS coupling can add latency to interactive workflows if hot paths are placed on the shared mount.
- Conflicting NAS references increase operator confusion if not routed through the SSOT.

## Data-Path Policy

Use the following rule set for where data should live:

| Data Class | Location | Rationale |
| --- | --- | --- |
| Hot interactive workspace data | Local ephemeral or service-local disk | Minimizes latency for editor and session state. |
| Warm application state | Local persistent service volume or controlled shared mount | Keeps runtime recovery reasonable without overloading NAS. |
| Cold backups and archives | NAS-backed backup path | Best fit for durable retention and restore workflows. |
| Shared model assets and large reusable blobs | NAS or dedicated object/backup storage | Avoids repeated downloads and centralizes large immutable assets. |

Policy rules:

1. Do not place latency-sensitive editor or restore paths on the NAS if a local or service-local path can satisfy the requirement.
2. Do place backups, archives, and shared durable assets on the NAS when they benefit from centralized retention.
3. Keep the NAS contract aligned with [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md) and the ops index.
4. Treat hardcoded NAS host/export values outside the SSOT as drift.

## Optimization Opportunities

1. Keep the editor and transient session working set local where practical.
2. Reserve the NAS for backup, recovery, and large shared assets rather than per-keystroke or per-request traffic.
3. Separate cold backup traffic from interactive workspace traffic to reduce contention.
4. Avoid unnecessary cross-host NAS churn during normal development flows.
5. Use the NAS contract consistently in documentation, scripts, and IaC so operators do not have to reconcile multiple versions of the topology.

## Operational Checks

- Confirm both hosts mount the NAS contract successfully.
- Confirm workspace, profile, backup, and shared asset paths are writable where expected.
- Confirm failover and recovery documentation still match the current mount/export contract.
- Confirm no new critical workflow depends on NAS when a local or ephemeral path is sufficient.

## Closure Criteria

- NAS topology is documented in one canonical place.
- Data-path policy distinguishes hot, warm, and cold usage.
- Optimization opportunities are documented and tied to the current topology.
- Operators can use the SSOT docs to decide what belongs on NAS versus local storage.

## Cross-References

- NAS architecture: [../NAS-ARCHITECTURE.md](../NAS-ARCHITECTURE.md)
- Config SSOT: [../governance/CONFIG-SSOT.md](../governance/CONFIG-SSOT.md)
- Operations index: [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
- Issue tracker SSOT: [ISSUE-TRACKER-APRIL-19-2026.md](ISSUE-TRACKER-APRIL-19-2026.md)
