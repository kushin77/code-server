# Instructions, Intent, and Memory SSOT

Purpose: canonical index for active instruction sources, policy-intent documents, and memory guidance.

## Scope

- Active instruction sources used by Copilot and repository automation
- Policy and intent documents that define how the repository should behave
- Memory guidance for session notes and repo-scoped working notes
- Ownership, review cadence, and change control for governance text

## Canonical Precedence

When guidance conflicts, apply the following order from highest to lowest priority:

1. `.github/copilot-instructions.md`
2. `.github/copilot-instructions-ENHANCED-APRIL-19-2026.md` once effective for the repo
3. `.github/GOVERNANCE.md`
4. `.github/ISSUE-WORKFLOW-POLICY.md`
5. `.github/ISSUE_MANAGEMENT.md`
6. `docs/governance/README.md` and the docs it indexes
7. `docs/status/CONTRIBUTING.md` for memory and workflow policy
8. `/memories/session/` and `/memories/repo/` as ephemeral working notes only

## Active Instruction Sources

| Source | Purpose | Status |
|---|---|---|
| `.github/copilot-instructions.md` | Baseline repository instructions and enforcement rules | Active |
| `.github/copilot-instructions-ENHANCED-APRIL-19-2026.md` | Expanded governance overlay with stronger enforcement language | Staged / effective 2026-04-22 |
| `.github/GOVERNANCE.md` | GitHub-side governance framework and repo standards | Active |
| `.github/ISSUE-WORKFLOW-POLICY.md` | Branch, commit, PR, and issue linkage workflow | Active |
| `.github/ISSUE_MANAGEMENT.md` | Issue management conventions and automation rules | Active |

## Policy and Intent Documents

| Document | Purpose | Status |
|---|---|---|
| [README.md](README.md) | Governance policy SSOT entry point | Active |
| [POLICY.md](POLICY.md) | Canonical policy text | Active |
| [POLICY-INDEX.md](POLICY-INDEX.md) | Machine-readable policy registry and ownership map | Active |
| [CONFIG-SSOT.md](CONFIG-SSOT.md) | Configuration ownership and precedence map | Active |
| [GLOBAL-DEDUP-GOVERNANCE.md](GLOBAL-DEDUP-GOVERNANCE.md) | Deduplication and overlap rules | Active |
| [WAIVERS.md](WAIVERS.md) | Approved waiver inventory | Active |
| [WAIVER-REQUEST.md](WAIVER-REQUEST.md) | Temporary exception request format | Active |
| [CHANGELOG.md](CHANGELOG.md) | Governance history and revision record | Active |
| [production-readiness-training.md](production-readiness-training.md) | Instructional intent for readiness review | Active |
| [elite-best-practices/instructions/](elite-best-practices/instructions/) | Focused instruction slices for specific governance or operational work | Active |

## Memory Guidance

Memory files are working notes, not source of truth.

| Scope | Purpose | Retention | Rule |
|---|---|---|---|
| `/memories/session/` | In-progress session notes and handoff state | 48 hours | Delete after the session ends or after the work is captured elsewhere |
| `/memories/repo/` | Repo facts that are not yet durable in GitHub | 30 days | Delete once the fact is captured in a GitHub issue or canonical doc |
| GitHub issue | Durable work state and accepted decisions | Permanent | Wins over memory whenever both exist |

## Change Control

1. Any new instruction or intent doc must be created through a GitHub issue and linked PR.
2. Any conflicting instruction or policy text must be reconciled in the canonical document first, then mirrored here.
3. Memory notes may capture working context, but durable facts must be promoted to GitHub issues or canonical docs.
4. Changes to active instruction sources require a review note in the related issue and a new review date.

## Ownership and Review Cadence

- Primary owner: Platform Engineering
- Security review: Security Engineering for secret, access, or policy changes
- Review cadence: monthly for active instruction sources, weekly while an issue is in progress, and immediately after any rule conflict is discovered

## Workflow Rules

- If a repo fact appears in both memory and GitHub, GitHub wins.
- If a policy statement appears in both an instruction file and a governance doc, update both or reduce the duplication to a pointer.
- If a change introduces contradictory guidance, create or update the tracking issue before merging.

## Cross-References

- [../status/CONTRIBUTING.md](../status/CONTRIBUTING.md)
- [../status/README.md](../status/README.md)
- [README.md](README.md)
- [../ops/OPERATIONS-INDEX.md](../ops/OPERATIONS-INDEX.md)
