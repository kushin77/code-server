# Multi-Repo UX Policy

**Purpose**: Multi-Repo UX Policy — reference and operational document.

Schema version: `1`

This policy governs the default behavior for the multi-repo navigation experience. It is intentionally versioned so that the client and any future backend enforcement can validate the same contract.

## Policy fields

- `schemaVersion`: contract version for compatibility checks
- `policyVersion`: stable identifier for the policy family
- `tier`: `admin`, `developer`, `reviewer`, `auditor`, or `read-only`
- `label`: user-facing policy label
- `canSwitchWorkspace`: allows repo switching and tabs
- `canUseQuickSwitcher`: allows command-palette switching
- `canRestoreSession`: allows session restore flows
- `canPinWorkspace`: allows pinned workspace management
- `maxRecentWorkspaces`: upper bound for recent workspace history
- `limits.maxRepos`: maximum repo count for the tier
- `limits.persistenceDepth`: maximum restore depth for the tier
- `limits.retentionDays`: local retention window for policy-managed data
- `limits.telemetryLevel`: `off`, `summary`, or `detailed`

## Compliance checks

- Recent workspace history must stay within `maxRecentWorkspaces`
- Client capability flags must not exceed the policy tier
- A serialized policy can be exported and restored without losing the schema version

## Auditability

- The client persists the resolved policy and the latest conformance report in local storage
- The audit record includes the policy id, policy version, schema version, and issue count
- Policy definitions can be serialized and restored for reversibility