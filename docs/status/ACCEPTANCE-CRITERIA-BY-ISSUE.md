# Acceptance Criteria by Current Open Issue

Date: April 18, 2026
Status: Active

This file lists acceptance criteria for the current open program (#659-#668) and the persistent tracker (#291).

## #659 Program: Production transition (monorepo + code-server co-dev + active-active reliability)

Acceptance Criteria:
- [ ] #660-#668 have clear dependencies and completion evidence
- [ ] Sprint gates executed in order and verified
- [ ] Program summary links all merged implementation PRs
- [ ] No unresolved blocker issues for this program

Closure Condition:
- Close only after #660-#668 are complete and verified

## #660 EPIC: True monorepo and pnpm migration

Acceptance Criteria:
- [ ] Monorepo package graph and workspace boundaries are canonical
- [ ] pnpm workspace lock discipline is enforced in CI
- [ ] Build, test, and lint entrypoints are deterministic
- [ ] Migration rollback and compatibility path are documented

Closure Condition:
- Monorepo migration controls merged with validation coverage

## #661 EPIC: code-server core plus enhancement co-development model

Acceptance Criteria:
- [ ] Co-development model defines ownership boundaries for core and enhancements
- [ ] Build and test flows work for both core and enhancement workstreams
- [ ] Contribution workflow is documented and reproducible
- [ ] Operational handoff model is defined

Closure Condition:
- Co-development model merged with tests and runbook

## #662 EPIC: Active-active autoscale and zero-downtime service continuity (.31/.42)

Acceptance Criteria:
- [ ] Active-active topology and autoscale policy are codified
- [ ] Zero-downtime continuity is tested across .31 and .42
- [ ] Failover and failback drills are repeatable and documented
- [ ] Service continuity telemetry is measurable

Closure Condition:
- Active-active continuity controls merged and validated

## #663 EPIC: Release engineering and operational hardening for production mode

Acceptance Criteria:
- [ ] Release engineering process is codified for production mode
- [ ] Hardening controls are implemented and validated
- [ ] Operational runbooks cover deployment, rollback, and incident response
- [ ] Regression guard exists for release-path failures

Closure Condition:
- Release-hardening controls merged and linked to operational evidence

## #664 Sprint Gate: Monorepo foundation approved

Acceptance Criteria:
- [ ] Monorepo foundation artifacts are approved and merged
- [ ] Workspace/package layout is stable and documented
- [ ] Foundation gate exit criteria are met and evidenced

Closure Condition:
- Foundation gate evidence merged and approved

## #665 Sprint Gate: Monorepo migration execution complete

Acceptance Criteria:
- [ ] Monorepo migration executes successfully in CI and local workflow
- [ ] Migration verification checks pass with no structural regressions
- [ ] Rollback and recovery path is documented

Closure Condition:
- Migration gate evidence merged and signoff posted

## #666 Sprint Gate: code-server co-development pipeline proven

Acceptance Criteria:
- [ ] Co-development pipeline for code-server is implemented
- [ ] Core/enhancement changes run through a unified validated pipeline
- [ ] Failure handling and rollback behavior are verified

Closure Condition:
- Pipeline gate merged with reproducible validation output

## #667 Sprint Gate: Active-active autoscale and failover drills passed

Acceptance Criteria:
- [ ] Active-active autoscale behavior is validated under load
- [ ] Failover and failback drills are executed successfully
- [ ] Continuity KPIs are measured before/after

Closure Condition:
- Active-active gate merged with drill and metrics evidence

## #668 Sprint Gate: Production cutover and SLO sign-off complete

Acceptance Criteria:
- [ ] Production cutover checklist completed
- [ ] SLO sign-off evidence is attached
- [ ] Residual risks and exceptions are documented

Closure Condition:
- Cutover and SLO evidence merged and linked from issue

## #669-#683 Implementation lane

Acceptance Criteria:
- [ ] Each issue has implementation evidence linked from merged PR(s)
- [ ] IaC/automation changes are idempotent and reproducible
- [ ] CI coverage exists for changed behavior (or explicit rationale if not feasible)
- [ ] Rollout and rollback steps are documented per issue
- [ ] Cross-issue dependencies are explicitly referenced in PR body and issue comments

Closure Condition:
- Close each issue only when merged evidence, verification output, and dependency linkage are present

## #291 Persistent tracker: VSCode crash RCA and stability tracking

Acceptance Criteria:
- [ ] Recurring RCA updates posted with incident evidence
- [ ] Trend metrics maintained (frequency, severity, MTTR)
- [ ] Mitigation actions linked to implementation issues

Closure Condition:
- Never close; keep as long-term operational tracker
