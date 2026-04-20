# Shared Libraries Catalog

This document is the canonical catalog for reusable shell helpers and internal service modules.
It is the index of record for ownership, purpose, canonical usage, and deprecation status.

## Scope

- Shared shell helpers under `scripts/_common/`
- Reusable runtime services under `src/services/`
- Canonical usage docs and migration targets
- Deprecated helpers that must not gain new consumers

## Shell Helper Catalog

All shared bash utilities live under `scripts/_common/`. Do not duplicate them in new scripts.

| Library | Owner | Purpose | Inputs / Outputs | Canonical Usage | Status |
|---|---|---|---|---|---|
| `scripts/_common/init.sh` | Platform Engineering | Canonical bootstrap entrypoint for Bash scripts | Inputs: script environment. Outputs: strict mode, loaded helpers. | Source it once at the top of each active script. | Active |
| `scripts/_common/config.sh` | Platform Engineering | Environment constants and config loading | Inputs: env vars, `.env`-style sources. Outputs: exported config constants. | Use for deploy host, NAS, repo, and port constants. | Active |
| `scripts/_common/logging.sh` | Platform Engineering | Structured logging and command tracing | Inputs: log messages and command strings. Outputs: consistent log lines. | Use `log_info`, `log_warn`, `log_error`, `log_fatal`, `log_debug`. | Active |
| `scripts/_common/utils.sh` | Platform Engineering | General-purpose shell utilities | Inputs: commands, files, vars, retries. Outputs: guard checks and helpers. | Use for `retry`, `require_command`, `require_file`, `add_cleanup`, and related helpers. | Active |
| `scripts/_common/error-handler.sh` | Platform Engineering | Assertion and failure reporting | Inputs: exit status, assertions, context stack. Outputs: structured failure handling. | Use for contract-style assertions and readable failure traces. | Active |
| `scripts/_common/docker.sh` | Platform Engineering | Docker and container operations | Inputs: container/service names and commands. Outputs: status, health, and lifecycle actions. | Use for container operations instead of inline docker plumbing. | Active |
| `scripts/_common/ssh.sh` | Platform Engineering | SSH and remote execution wrappers | Inputs: remote commands and target host context. Outputs: remote command execution. | Use for SSH-based deploy and validation workflows. | Active |

## Canonical Shell Usage Notes

- Start scripts with `scripts/_common/init.sh` and do not source individual helpers one by one.
- Use environment variables and config loading instead of hardcoded deploy host, NAS, or domain literals.
- Keep output through the logging helpers so evidence captures remain consistent across CI and issue comments.
- Treat `scripts/_common/README.md` as the usage guide and this file as the ownership/catalog view.

## Operational Library Catalog (`scripts/lib/`)

These reusable operational helpers are shared across CI, governance, and deployment flows.

| Library | Owner | Purpose | Inputs / Outputs | Canonical Usage | Status |
|---|---|---|---|---|---|
| `scripts/lib/automation-policy-gate.sh` | Platform Engineering | Enforce repo/action allowlists with break-glass audit trails | Inputs: target repo, action category, policy file. Outputs: allow/block decision and audit log lines. | Source in automation scripts before mutating actions and call `policy_gate_require`. | Active |
| `scripts/lib/global-quality-gate.sh` | Platform Engineering | Run multi-phase quality checks for env, docker, validation tooling, CI config, and git health | Inputs: repository working tree and toolchain availability. Outputs: pass/fail summary and per-phase check status. | Execute from CI or operator validation paths as the global quality gate entrypoint. | Active |
| `scripts/lib/inventory-loader.sh` | Platform Engineering | Load production topology from inventory YAML and expose query helpers | Inputs: `environments/production/hosts.yml`. Outputs: exported host/domain variables and lookup functions. | Source in scripts that need host/IP/FQDN values instead of hardcoding topology values. | Active |
| `scripts/lib/merge-settings.js` | Platform Engineering | Merge enterprise and user code-server settings while preserving locked policy keys | Inputs: enterprise settings, user settings. Outputs: merged settings JSON with enforced locked keys. | Invoke from IDE policy/bootstrap workflows to produce effective settings payloads. | Active |
| `scripts/lib/policy-bundle.sh` | Platform Engineering | Fetch/cache policy bundle and enforce fail-safe revocation checks | Inputs: policy portal URL, user context, cache TTL. Outputs: cached bundle, revocation decision, exit-on-revoked behavior. | Source in session/bootstrap flows and call `policy_bundle_load` + `policy_bundle_assert_not_revoked`. | Active |

## Service Module Catalog

The services below are reusable internal modules. Each module has a canonical usage surface and a preferred documentation trail.

| Module | Owner | Purpose | Inputs / Outputs | Canonical Usage | Status |
|---|---|---|---|---|---|
| `src/services/policy-bundle-verifier/` | Security Engineering | Verify signed policy bundles and compatibility | Inputs: signed bundle, verification options. Outputs: verification result and cached bundle metadata. | Use wherever bundle integrity and expiry must be enforced. | Active |
| `src/services/opa-policy-service/` | Security Engineering | Bundle discovery, rollout lifecycle, and decision logging | Inputs: bundle catalog, decision requests, promotion events. Outputs: policy decisions and audit events. | Use as the policy distribution and decision surface. | Active |
| `src/services/revocation-broker/` | Security Engineering | Strict revocation enforcement with propagation SLOs | Inputs: revocation checks, revoke operations, drill requests. Outputs: revocation results and audit events. | Use for deny-by-default revocation decisions and propagation tracking. | Active |
| `src/services/session-bootstrap-enforcer/` | Platform Engineering | Mandatory assertion validation for session bootstrap | Inputs: portal assertions, policy bundles, policy decisions. Outputs: bootstrap result and audit trail. | Use when a session must be validated before runtime creation. | Active |
| `src/services/correlation-audit-fabric/` | Platform Engineering | Correlation-ID audit fabric for decision traceability | Inputs: actions, audit events, correlation context. Outputs: trace records and query results. | Use for end-to-end decision traceability across portal and runtime. | Active |
| `src/services/tenant-profile-manager/` | Platform Engineering | Tenant-aware profile merging and immutable overlays | Inputs: profile sources, merge options, migration rules. Outputs: merged profile and drift results. | Use when profile hierarchy or policy overlays need canonical merging. | Active |
| `src/services/shared-workspace-acl/` | Platform Engineering | Shared workspace ACL broker with lease support | Inputs: ACL grants, queries, mount operations, revocations. Outputs: ACL checks and audit events. | Use for controlled workspace sharing and access enforcement. | Active |
| `src/services/ephemeral-workspace-lifecycle/` | Platform Engineering | Ephemeral workspace TTL and cleanup management | Inputs: workspace lifecycle context and activity state. Outputs: lifecycle operations and cleanup events. | Use for ephemeral workspace creation, idle cleanup, and termination. | Active |
| `src/services/replication/` | Platform Engineering | Multi-region replication primitives with vector clocks, sync protocol, and conflict resolution | Inputs: replication operations, region topology, sync envelopes. Outputs: converged replicated state and replication metrics/events. | Use for cross-region state replication and deterministic conflict handling paths. | Active |
| `src/services/routing/` | Platform Engineering | Geographic routing, load-balancing, and circuit-breaker failover management | Inputs: region health, latency/load signals, failover policy config. Outputs: routing decisions, failover events, circuit state metrics. | Use as the routing/failover decision layer for multi-region traffic steering. | Active |
| `src/services/testing/` | Platform Engineering | Resilience validation engines for chaos, performance, and load campaigns | Inputs: experiment definitions, workload profiles, validation thresholds. Outputs: test metrics, findings, and resilience verdicts. | Use for controlled fault injection and performance/resilience certification flows. | Active |
| `apps/session-broker/src/index.ts` | Platform Engineering | Per-session container isolation broker | Inputs: auth headers, session requests, Docker socket, database connection. Outputs: per-session containers and session records. | Use only with explicit runtime controls; baseline compose keeps socket access in local-only override. | Active; local-dev override for socket access |

## Internal Documentation Index

| Document | Purpose | Canonical Link |
|---|---|---|
| `docs/SHARED-LIBRARIES.md` | This catalog and usage index | [docs/SHARED-LIBRARIES.md](SHARED-LIBRARIES.md) |
| `scripts/_common/README.md` | Detailed shell helper usage guide | [scripts/_common/README.md](../scripts/_common/README.md) |
| `docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md` | Governance mirror of shared-lib rules | [docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md](governance/elite-best-practices/shared/SHARED-LIBRARIES.md) |
| `docs/status/REPO-FUNCTIONALITY-REVIEW.md` | Repository functionality-to-issue map | [docs/status/REPO-FUNCTIONALITY-REVIEW.md](status/REPO-FUNCTIONALITY-REVIEW.md) |
| `docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md` | Open tracker index | [docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md) |

## Deprecation / Migration Targets

| Deprecated surface | Replacement | Migration note |
|---|---|---|
| `scripts/common-functions.sh` | `scripts/_common/init.sh` | Retired to archived marker stub. New and existing scripts must source `scripts/_common/init.sh`. |
| `scripts/logging.sh` | `scripts/_common/init.sh` | Retired to archived marker stub. Logging must come from `scripts/_common/logging.sh` via init bootstrap. |
| Inline script helpers and logging | `scripts/_common/logging.sh` + `scripts/_common/utils.sh` | New scripts must use the canonical helper stack. |
| `scripts/lib/nas.sh` | `scripts/nas-mount-31.sh` and `scripts/nas-workspace-health.sh` | There is no active `scripts/lib/nas.sh` in this repo. |

## Adoption Rules

1. Before writing a new helper or module, search the catalog and the canonical docs first.
2. If a reusable function or module already exists, import or reuse it instead of duplicating behavior.
3. If a truly new reusable surface is required, add it here in the same change that introduces it.
4. Mark any stale helper, shadow copy, or compatibility shim as deprecated and name the migration target.

## Maintenance Rule

Keep this catalog current as shared code evolves. New reusable logic is not considered tracked until it appears here or in the linked module index.

## Cross-References

- [scripts/_common/README.md](../scripts/_common/README.md)
- [docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md](governance/elite-best-practices/shared/SHARED-LIBRARIES.md)
- [docs/status/REPO-FUNCTIONALITY-REVIEW.md](status/REPO-FUNCTIONALITY-REVIEW.md)
- [docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)