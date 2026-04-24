# Multi-Repo Rollout Plan - April 19, 2026

Status: Active
Scope: Pilot program, feature flags, A/B validation, and rollback criteria for multi-repo navigation.

## Purpose

This is the canonical rollout artifact for issue #725. It defines the staged delivery plan, the pilot evidence required before broader enablement, and the rollback criteria needed to keep the release safe.

## Rollout Principles

- Ship the smallest safe slice first.
- Make every capability independently flaggable.
- Capture a baseline before rollout and compare against it.
- Keep rollback deterministic and fast.

## Rollout Phases

1. Baseline capture.
2. Internal pilot with feature flags disabled by default.
3. Limited cohort enablement with telemetry and guardrails.
4. A/B comparison against the current workflow.
5. Gradual expansion only if metrics stay within target.

## Feature-Flag Matrix

| Capability | Flag | Default | Notes |
| --- | --- | --- | --- |
| Toolbar tabs | `multiRepoTabs` | Off | Primary switch surface. |
| Command switcher | `multiRepoQuickSwitch` | Off | Keyboard-first path. |
| Home view | `multiRepoHomeView` | Off | Overview and jump actions. |
| Session restore | `multiRepoRestore` | Off | Must be explicitly piloted. |
| Shared sets | `multiRepoSharedSets` | Off | Requires approval and RBAC. |

## Pilot Evidence Requirements

- Capture a pre-rollout productivity baseline.
- Define the pilot cohort and rollback owner.
- Track productivity delta and stability metrics.
- Record incident rate and any restore failures.
- Publish a readiness score before expanding cohort size.

## Rollback Criteria

- Switch latency exceeds the agreed threshold.
- Restore failure rate exceeds tolerance.
- Safety or audit violations appear in pilot telemetry.
- Users report unacceptable context-loss or workflow friction.

## Validation Outputs

- Pilot dashboard with productivity, incident, and recovery metrics.
- A/B report comparing the new path to the current workflow.
- Tested kill-switch and rollback playbook.

## Closure Criteria

- Feature flags exist for each capability and cohort.
- A baseline is captured before exposure.
- A/B reporting covers productivity and stability.
- The rollback matrix is documented and tested.

## Cross-References

- Multi-repo interaction model: [../architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md](../architecture/ADR-004-MULTI-REPO-INTERACTION-MODEL.md)
- Multi-repo policy spec: [MULTI-REPO-POLICY-SPEC-APRIL-19-2026.md](MULTI-REPO-POLICY-SPEC-APRIL-19-2026.md)
- Program tracker index: [PROGRAM-TRACKER-INDEX-APRIL-19-2026.md](PROGRAM-TRACKER-INDEX-APRIL-19-2026.md)
