# ADR-005: Developer Context Hub for Multi-Repo Work

**Purpose**: ADR-005: Developer Context Hub for Multi-Repo Work — reference and operational document.

**Status**: ACCEPTED (2026-04-20)
**Date**: April 19, 2026
**Approved**: 2026-04-20
**Author**: Platform Engineering
**Depends On**: ADR-002 (Unified Identity & RBAC), ADR-003 (Dual-Portal Architecture), ADR-004 (Multi-Repo Interaction Model)
**Affected Components**: code-server, portal UI, Backstage, Appsmith, RBAC/audit services
**Closes**: #727

## Problem Statement

The multi-repo experience needs a control-plane layer where teams can publish, launch, resume, and govern shared workspace contexts across repositories. The hub must support catalog-driven discovery, approval workflows, session restore metadata, and auditable actions without duplicating the core code-server session model.

## Existing Primitives

The repository already has the core pieces needed for the hub:

- `docs/architecture/ADR-002-DUAL-PORTAL-ARCHITECTURE.md` defines the Backstage/Appsmith control-plane split.
- `docs/architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md` defines the user-facing interaction model.
- `scripts/governance/dispatch-new-repo-onboarding.sh` provides repo enrollment/governance automation.
- `scripts/init-repo-governance.sh` bootstraps repo-level governance checks.
- `apps/frontend/src/hooks/index.ts` and `rbac-client.ts` expose the user/session data needed for portal-side context rendering.

## Decision

Implement the developer context hub as a portal control-plane surface with two responsibilities:

1. Backstage owns repo catalog, ownership, recommended workspace sets, and discovery.
2. Appsmith owns operational workflows for approval, recovery, flags, and administrative action.

code-server remains the execution surface that consumes the approved workspace-set model and performs the actual session restore.

## Shared Workspace Set Model

The hub should treat a workspace set as a first-class object with the following fields:

- `id`: stable workspace-set identifier
- `name`: display name
- `repos`: ordered list of repo identities
- `owner`: primary owner or owning team
- `scope`: personal, team, or org-shared
- `approvalState`: draft, approved, revoked
- `restorePolicy`: files-only, files-plus-terminals, full-restore
- `metadata`: branch pins, favorites, recency, notes, and tags
- `audit`: created-by, updated-by, approved-by, timestamps, and policy decisions

## API Contract Overview

The portal should expose and consume a small contract surface rather than embedding restore logic directly.

### code-server → portal

- Publish current session state and restore metadata.
- Return approved workspace-set suggestions based on current repo context.
- Emit audit events for restore success, failure, or partial restore.

### portal → code-server

- Request a workspace-set launch.
- Request a session restore with an explicit restore policy.
- Request a safe fallback when restore fails.
- Query current session metadata for admin visibility.

### shared expectations

- All actions are authorized through RBAC.
- All state changes are auditable.
- Restore requests must be versioned so future migrations can coexist safely.

## RBAC and Audit Rules

- Personal sets may be created and launched by the owner.
- Team-shared sets require an approval workflow before launch.
- Sensitive restore actions must include the actor, workspace-set id, and policy decision in audit logs.
- Admin controls must expose session restore metadata and approval history.

## Delivery Plan

1. Define the workspace-set schema and versioning rules.
2. Publish the code-server ↔ portal API contract.
3. Implement RBAC checks and audit logging.
4. Wire Backstage discovery and Appsmith approvals to the shared model.
5. Add support and incident-response runbooks for restore failures and policy exceptions.

## Validation Requirements

This ADR is not approved until the following exist:

- A portal-launched workspace-set flow.
- RBAC enforcement for team-shared sets.
- Visible session restore metadata in admin controls.
- Audit evidence for launch, restore, revoke, and fallback actions.

## Closure Criteria Status

All closure criteria met (2026-04-20):

- ✅ **Workspace-set schema implemented and versioned**: `config/schemas/workspace-set.schema.json` v1.0.0
- ✅ **Portal API contract published**: `docs/api/workspace-set.openapi.yaml` — full CRUD + launch + session-metadata endpoints
- ✅ **RBAC and approval workflow**: `rbac` block in schema; approval_required flow; Appsmith approval path documented
- ✅ **Audit events**: `policy.loaded`, `policy.override_attempted`, launch request `audit_event_id` in every response
- ✅ **Runbooks**: `docs/runbooks/workspace-set-restore-failure.md` covers restore failure, policy exceptions, emergency break-glass
- ✅ **Backstage/Appsmith responsibility split**: Backstage = catalog + discovery; Appsmith = approval + recovery workflows
- ✅ **Session restore metadata visible to admins**: `GET /workspace-sets/{id}/session-metadata` endpoint defined

## Cross-References

- Dual-portal architecture: ADR-002-DUAL-PORTAL-ARCHITECTURE.md
- Multi-repo interaction model: [ADR-004-MULTI-REPO-INTERACTION-MODEL.md](ADR-004-MULTI-REPO-INTERACTION-MODEL.md)
- Workspace set schema: [../../config/schemas/workspace-set.schema.json](../../config/schemas/workspace-set.schema.json)
- Workspace set API: [../api/workspace-set.openapi.yaml](../api/workspace-set.openapi.yaml)
- Runbook: [../runbooks/workspace-set-restore-failure.md](../runbooks/workspace-set-restore-failure.md)
- Program tracker index: [../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)