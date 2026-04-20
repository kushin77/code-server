# ADR-004: Multi-Repo Interaction Model

**Status**: DRAFT (awaiting pilot validation and persona testing)
**Date**: April 19, 2026
**Author**: Platform Engineering
**Depends On**: ADR-002 (Unified Identity & RBAC), ADR-003 (Dual-Portal Architecture)
**Affected Components**: code-server UI, session sync utilities, repository indexer, portal control-plane UX

## Problem Statement

The current multi-repo workflow requires too many manual steps to move between repositories, restore context, and understand the current workspace state. The interaction model must optimize for speed, discoverability, safety, and maintainability without turning the UI into a cluttered navigation surface.

## Existing Primitives

The repository already has usable building blocks for a multi-repo experience:

- `apps/frontend/src/utils/SESSION_SYNC_INTEGRATION.md` describes cross-tab session sync, leader election, and restore coordination.
- `apps/extensions/ollama-chat/src/repository-indexer.ts` provides repository indexing and context retrieval primitives.
- `docs/MONOREPO.md` defines the workspace-boundary and dependency SSOT.
- `docs/status/MONOREPO-ENFORCEMENT-APRIL-19-2026.md` records the enforcement roadmap for workspace boundaries and naming.

## Decision

Adopt a hybrid interaction model:

1. Toolbar workspace tabs as the primary surface for quick repo switching.
2. Command palette / hotkey repo switcher as the keyboard-first secondary path.
3. Multi-repo home view as the overview and jump-action surface.

Defer a sidebar repo navigator unless pilot validation shows a measurable need.

## Rationale

### Toolbar tabs should be primary

- Fastest visible path for common repo switching.
- Lowest discoverability risk for new users.
- Works naturally with pinned/recent repositories.
- Maps cleanly to the existing tab/session primitives.

### Command switcher should remain secondary

- Best for keyboard-first users and power workflows.
- Complementary to tabs rather than a replacement.
- Already aligned with repository indexing and search primitives.

### Home view should be the overview surface

- Gives users a status-oriented landing page for active repos.
- Supports jump actions, favorites, and team-shared sets.
- Avoids overloading the top toolbar with too much state.

### Sidebar navigator should stay deferred

- Adds more visual complexity than the current evidence justifies.
- Risks duplicating the home view and toolbar affordances.
- Should only be introduced if pilot data shows tabs plus switcher are insufficient.

## Comparative Scorecard

| Model | Time-to-switch | Discoverability | Complexity | Maintenance | Decision |
| --- | --- | --- | --- | --- | --- |
| Toolbar tabs | Best | Strong | Moderate | Moderate | Primary |
| Command-only switcher | Strong | Moderate | Low | Low | Secondary |
| Home view | Moderate | Strong | Moderate | Moderate | Supporting surface |
| Sidebar navigator | Moderate | Strong | High | High | Deferred |

## Phased Delivery Plan

1. Ship command palette / hotkey repo switcher with safe context restore.
2. Add toolbar workspace tabs with pin/recent support.
3. Add the multi-repo home view for overview and jump actions.
4. Run pilot validation with at least three personas.
5. Revisit sidebar only if pilot metrics show a measurable gap.

## Validation Requirements

This ADR is not approved until the pilot evidence exists for at least three personas and the selected model is tied to the measured task-completion and context-switch metrics.

## Closure Criteria

- The hybrid model is approved by the parent epic.
- Pilot validation confirms the interaction model meets the switching and recovery targets.
- Implementation issues map to the phased delivery plan.

## Cross-References

- Multi-repo session substrate: [../apps/frontend/src/utils/SESSION_SYNC_INTEGRATION.md](../apps/frontend/src/utils/SESSION_SYNC_INTEGRATION.md)
- Repository indexing substrate: [../apps/extensions/ollama-chat/src/repository-indexer.ts](../apps/extensions/ollama-chat/src/repository-indexer.ts)
- Workspace boundary SSOT: [../MONOREPO.md](../MONOREPO.md)
- Program tracker index: [../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)
