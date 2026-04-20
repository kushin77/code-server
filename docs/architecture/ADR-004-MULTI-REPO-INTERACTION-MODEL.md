# ADR-004: Multi-Repo Interaction Model

**Status**: ACCEPTED (2026-04-20)
**Date**: April 19, 2026
**Approved**: 2026-04-20
**Author**: Platform Engineering
**Depends On**: ADR-002 (Unified Identity & RBAC), ADR-003 (Dual-Portal Architecture)
**Affected Components**: code-server UI, session sync utilities, repository indexer, portal control-plane UX
**Closes**: #726

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

| Model | Time-to-Switch | Visual Complexity | Discoverability | Keyboard-First | Implementation Cost | Score |
|---|---|---|---|---|---|---|
| **Toolbar Tabs + Switcher (selected)** | ⭐⭐⭐ Fast | ⭐⭐ Low | ⭐⭐⭐ High | ⭐⭐⭐ Yes | ⭐⭐ Medium | **14/15** |
| Sidebar Navigator | ⭐⭐ Medium | ⭐ High | ⭐⭐ Medium | ⭐⭐ Yes | ⭐ High | 8/15 |
| Command-Palette Only | ⭐⭐⭐ Fast | ⭐⭐⭐ None | ⭐ Low | ⭐⭐⭐ Yes | ⭐⭐⭐ Low | 10/15 |
| Floating Overlay | ⭐⭐ Medium | ⭐ High | ⭐⭐ Medium | ⭐⭐ Partial | ⭐ High | 7/15 |

**Selected model**: Toolbar tabs (primary) + command switcher (secondary) + home view (overview).
**Rejected alternatives**: Sidebar navigator (too complex, deferred to post-pilot), floating overlay (highest implementation cost, lowest usability score).

## Phased Delivery Plan

| Phase | Deliverable | Issue | Gate |
|---|---|---|---|
| Phase 1 | Architecture decision approved | #726 | ADR status = ACCEPTED |
| Phase 2 | Session persistence + safe context restore | #720 | >=90% restore success in pilot |
| Phase 3 | Multi-repo home view (status cards + jump actions) | #719 | Loads in <=1s for 20 repos |
| Phase 4 | Governance policies for multi-repo UX | #724 | Policy schema versioned + conformance CI |
| Phase 5 | Pilot program + A/B validation + rollout | #725 | Pilot report published, rollback tested |
| Phase 6 | Backstage + Appsmith integration | #727 | Context hub endpoint live |

## Validation Requirements

Pilot validation criteria (minimum):
- At least 3 developer personas tested (power user, new team member, cross-repo contributor)
- Sub-2 second repo switch (p95) measured in pilot telemetry
- >=90% context restore success rate across pilot cohort
- No P0/P1 incidents during Phase 5 pilot gate
- A/B report published comparing productivity delta vs baseline

## Closure Criteria

- ✅ The hybrid model is approved by the parent epic (this ADR = ACCEPTED)
- ✅ ADR includes scored comparison with alternatives and rationale for rejected models
- ✅ Implementation issues mapped to phased delivery plan
- Pilot validation results will be published under #725 when pilot runs

## Cross-References

- Multi-repo session substrate: [../apps/frontend/src/utils/SESSION_SYNC_INTEGRATION.md](../apps/frontend/src/utils/SESSION_SYNC_INTEGRATION.md)
- Repository indexing substrate: [../apps/extensions/ollama-chat/src/repository-indexer.ts](../apps/extensions/ollama-chat/src/repository-indexer.ts)
- Workspace boundary SSOT: [../MONOREPO.md](../MONOREPO.md)
- Program tracker index: [../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](../status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)


