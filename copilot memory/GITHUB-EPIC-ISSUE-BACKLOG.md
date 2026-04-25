# GitHub Epic and Issue Backlog

## Program Goal
Build and ship a self-cleaning, memory-aware, GitHub-aware copilot profile for code-server that:
- remembers intent, goals, and decisions,
- prevents repeated suggestions,
- detects and resolves contradictions,
- continuously ingests repository and issue state,
- is shareable across users and teams.

## Source Artifacts Mapped
- copilot_self_clean_prompt.txt
- copilot_memory_engine.js
- github_repo_scanner_prompt.txt
- github_scanner_implementation.js
- codeserver_extension_source.ts
- codeserver_copilot_profile.json
- codeserver_profile_readme.txt
- codeserver_distribution_guide.txt
- codeserver_deployment_checklist.txt
- complete_solution_summary.txt
- enterprise-engineering-master-prompt.md

## Label Set (Create Once)
- type:epic
- type:feature
- type:bug
- type:task
- type:security
- type:docs
- area:memory
- area:dedup
- area:github-sync
- area:extension
- area:distribution
- area:observability
- area:governance
- priority:P0
- priority:P1
- priority:P2
- status:blocked

## Milestones
- M1 Foundation
- M2 GitHub Intelligence
- M3 Extension Productization
- M4 Multi-User and Governance
- M5 Launch and Operations

## EPIC 1: Memory Core and Decision System (P0)
Title:
EPIC: Build persistent intent-memory core with decision lock and contradiction tracking

Objective:
Implement production memory primitives (structured goals, active context, locked decisions, contradiction log), with backend support for memory, Redis, and PostgreSQL.

Success Metrics:
- 100% of accepted suggestions become decision locks.
- 100% of responses include active goals and blockers context.
- Zero memory data loss in persistence backends under restart tests.

Child Issues:

1) ISSUE: Implement memory schema and migration plan
- Labels: type:feature, area:memory, priority:P0
- Milestone: M1 Foundation
- Scope:
  - Define canonical schema for session_goals, active_context, contradiction_log, suggestion_history.
  - Version schema with forward compatibility.
- Acceptance Criteria:
  - JSON schema committed and validated in CI.
  - Migration document covers memory -> Redis -> PostgreSQL transitions.
  - Backward compatibility test passes for prior export format.

2) ISSUE: Add Redis backend for shared memory state
- Labels: type:feature, area:memory, priority:P0
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Redis backend stores goals, decisions, contradictions.
  - Restart test confirms persistence.
  - TTL and pruning behavior is configurable.

3) ISSUE: Add PostgreSQL backend with audit-ready tables
- Labels: type:feature, area:memory, priority:P0
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Normalized tables for goals, decisions, suggestions, contradictions.
  - Indexed queries for recent decisions and active goals.
  - Audit timestamps and actor metadata captured.

4) ISSUE: Implement decision lock API and revisit workflow
- Labels: type:feature, area:memory, priority:P0
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Accepted suggestions create immutable decision records.
  - Future conflicting suggestions prompt explicit revisit consent.
  - Decision lock behavior covered by unit tests.

5) ISSUE: Implement contradiction detection and resolution ledger
- Labels: type:feature, area:memory, priority:P1
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Contradictions are detected before response finalization.
  - Resolution choice and timestamp are persisted.
  - Contradiction log is queryable in extension UI.

## EPIC 2: Deduplication Engine and Response Hygiene (P0)
Title:
EPIC: Prevent repeated suggestions with semantic dedup and confidence controls

Objective:
Stop duplicate recommendations, enforce novelty checks, and make duplicate handling explicit to users.

Success Metrics:
- Duplicate suggestion rate per session below 2%.
- 100% of detected duplicates include prior timestamp and recovery options.

Child Issues:

1) ISSUE: Replace mock embeddings with production embedding provider
- Labels: type:feature, area:dedup, priority:P0
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Embedding provider abstraction supports local and hosted providers.
  - Similarity search runs under 100ms for 5k suggestions.
  - Provider selection is configuration-driven.

2) ISSUE: Implement configurable semantic threshold and per-domain tuning
- Labels: type:feature, area:dedup, priority:P1
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Threshold default is 0.85 and is overrideable.
  - Domain-specific threshold overrides supported.
  - Regression tests validate false-positive and false-negative bounds.

3) ISSUE: Add dedup middleware preflight for every response
- Labels: type:feature, area:dedup, priority:P0
- Milestone: M1 Foundation
- Acceptance Criteria:
  - Every response path runs dedup check first.
  - Duplicate path returns expand/pivot/revisit options.
  - Middleware instrumentation reports dedup hit rate.

4) ISSUE: Build dedup quality benchmark suite
- Labels: type:task, area:dedup, priority:P1
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Curated dataset of repeated and near-repeated prompts.
  - Automated scorecard in CI.
  - Weekly quality report generated.

## EPIC 3: GitHub Scanner and Roadmap Ingestion (P0)
Title:
EPIC: Ingest repos, issues, and PRs into actionable copilot memory

Objective:
Continuously scan GitHub repositories and convert state into active/completed/blocked/deferred goals.

Success Metrics:
- 100% of repos scanned on schedule.
- 95% of in-progress issues linked to PR status.
- Blocked/stalled detection precision above 90%.

Child Issues:

1) ISSUE: Implement GraphQL pagination scanner for repos/issues/PRs
- Labels: type:feature, area:github-sync, priority:P0
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Full org/user scan supports pagination and retries.
  - API errors and rate-limit responses are handled with backoff.
  - Scan summary includes processed counts and duration.

2) ISSUE: Build issue and PR classifier (completed/in-progress/blocked/deferred/rejected)
- Labels: type:feature, area:github-sync, priority:P0
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Classification rules documented and test-covered.
  - Stalled definitions are configurable (default 14/30 day windows).
  - Cross-links between issues and PRs persisted.

3) ISSUE: Add technical debt extraction from TODO/FIXME and dependency signals
- Labels: type:feature, area:github-sync, priority:P1
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Debt items captured with severity and repo mapping.
  - Duplicate debt findings consolidated.
  - Export includes debt by repo and global pattern groups.

4) ISSUE: Daily scheduler plus manual refresh command
- Labels: type:feature, area:github-sync, priority:P1
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Default cron schedule configured and overridable.
  - Manual refresh command updates memory immediately.
  - Last scan status visible in UI and logs.

5) ISSUE: Import scanner snapshot into memory goals
- Labels: type:feature, area:memory, area:github-sync, priority:P0
- Milestone: M2 GitHub Intelligence
- Acceptance Criteria:
  - Snapshot merge is idempotent.
  - Existing goals update instead of duplicating.
  - Blockers propagate into active_context.

## EPIC 4: Code-Server Extension Productization (P1)
Title:
EPIC: Deliver production extension UI/commands for memory and GitHub visibility

Objective:
Ship a stable extension with chat panel, memory state, GitHub status, and core command set.

Success Metrics:
- Zero activation crashes across supported code-server versions.
- All commands discoverable and functional.

Child Issues:

1) ISSUE: Finalize extension activation and configuration validation
- Labels: type:feature, area:extension, priority:P1
- Milestone: M3 Extension Productization
- Acceptance Criteria:
  - Clear startup validation for missing tokens/keys.
  - Safe degradation when GitHub token is absent.
  - Configuration schema documented and test-covered.

2) ISSUE: Implement memory state webview with decision and blocker panels
- Labels: type:feature, area:extension, priority:P1
- Milestone: M3 Extension Productization
- Acceptance Criteria:
  - Active goals, recent decisions, contradictions shown.
  - Refresh action updates live data.
  - Empty/error states handled cleanly.

3) ISSUE: Implement GitHub status webview with scan health and stale work
- Labels: type:feature, area:extension, area:github-sync, priority:P1
- Milestone: M3 Extension Productization
- Acceptance Criteria:
  - Repos/issues/PR counts and last scan time shown.
  - Stalled items highlighted.
  - Click-through links to issue or PR references supported.

4) ISSUE: Harden command set (export/import/reset/refresh)
- Labels: type:feature, area:extension, priority:P1
- Milestone: M3 Extension Productization
- Acceptance Criteria:
  - Export/import format versioned.
  - Reset flow requires explicit confirmation.
  - Command telemetry emits success/failure events.

## EPIC 5: Observability, Quality Gates, and Safety (P0)
Title:
EPIC: Add guardrails, metrics, and CI gates for reliable behavior

Objective:
Instrument runtime behavior and enforce quality gates in CI to prevent regressions.

Success Metrics:
- 100% of releases pass lint/test/build/security checks.
- Alerting available for failed scans and memory corruption events.

Child Issues:

1) ISSUE: Add structured logging and correlation IDs
- Labels: type:feature, area:observability, priority:P0
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - All major operations emit structured logs.
  - Correlation ID links chat turn, dedup check, and memory write.
  - Sensitive fields are redacted.

2) ISSUE: Add metrics dashboard for memory and scanner health
- Labels: type:feature, area:observability, priority:P1
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - Metrics include dedup hits, contradiction rate, scan duration, sync failures.
  - Dashboard supports daily and weekly trend views.

3) ISSUE: Build CI quality gates for schema, tests, and security scan
- Labels: type:task, area:governance, priority:P0
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - CI blocks on failed schema validation, unit tests, and dependency audit.
  - Secret scanning enforced for all PRs.
  - Release workflow signs and verifies artifacts.

4) ISSUE: Define incident runbook for scanner or memory outages
- Labels: type:docs, area:governance, priority:P1
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - Triage flow includes rollback and data recovery steps.
  - Owner and SLA defined for P0 and P1 incidents.

## EPIC 6: Distribution, Multi-User Adoption, and Governance (P1)
Title:
EPIC: Package, publish, and operate as a shared profile for other users

Objective:
Deliver marketplace/GitHub/Docker distribution and make shared usage repeatable and safe.

Success Metrics:
- First install to productive use under 10 minutes.
- Team mode with shared backend validated in staging.

Child Issues:

1) ISSUE: Publish extension artifacts and release automation
- Labels: type:task, area:distribution, priority:P1
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Tagged release produces installable artifact.
  - Release notes generated from changelog.
  - Checksums published with artifact.

2) ISSUE: Create team deployment path (Docker plus shared Redis/PostgreSQL)
- Labels: type:feature, area:distribution, priority:P1
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Docker compose path validated end-to-end.
  - Shared backend profile documented.
  - Backup and restore tested.

3) ISSUE: Write operator and user docs (install, config, troubleshooting)
- Labels: type:docs, area:distribution, priority:P1
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Operator guide includes monitoring and incident playbook.
  - User guide includes quick-start and common failures.
  - Docs are linked from release page.

4) ISSUE: Governance policy for memory sharing and data ownership
- Labels: type:task, area:governance, priority:P1
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Policy defines tenancy boundaries and retention.
  - Export/import rights and audit expectations documented.
  - Privacy and compliance review completed.

## EPIC 7: Prompt and Agent Governance (P1)
Title:
EPIC: Standardize system prompts and prevent prompt drift across environments

Objective:
Create one canonical prompt stack and ensure all environments use the same behavior contract.

Success Metrics:
- 100% of runtime prompt configurations map to canonical versions.
- Prompt drift detection catches changes before deployment.

Child Issues:

1) ISSUE: Canonicalize master prompt and split runtime sections
- Labels: type:feature, area:governance, priority:P1
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - Prompt sections modularized (memory, dedup, github, response format).
  - Version header and changelog added.
  - Prompt tests verify required sections present.

2) ISSUE: Add prompt linting and policy checks in CI
- Labels: type:task, area:governance, priority:P1
- Milestone: M4 Multi-User and Governance
- Acceptance Criteria:
  - CI fails if required policy blocks are missing.
  - Prompt format and token budget checks enforced.

3) ISSUE: Add admin command to display active prompt version
- Labels: type:feature, area:extension, area:governance, priority:P2
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Runtime can show active prompt hash and source.
  - Troubleshooting path documented.

## EPIC 8: Backlog Hygiene and Continuous Planning (P2)
Title:
EPIC: Keep roadmap clean, de-duplicated, and execution-ready

Objective:
Prevent backlog decay and duplicate work by adding recurring audit routines.

Success Metrics:
- Duplicate issues reduced to zero.
- 100% of open issues mapped to an epic and milestone.

Child Issues:

1) ISSUE: Weekly backlog triage automation
- Labels: type:task, area:governance, priority:P2
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Weekly job flags stale, duplicate, and unowned issues.
  - Auto-generated triage report is posted.

2) ISSUE: Epic to issue traceability matrix
- Labels: type:task, area:governance, priority:P2
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Every issue links to epic parent.
  - Every epic shows open/closed child counts.

3) ISSUE: Quarterly architecture and debt review cadence
- Labels: type:task, area:governance, priority:P2
- Milestone: M5 Launch and Operations
- Acceptance Criteria:
  - Review template captures debt trends and blocked dependencies.
  - Quarterly decisions feed directly into next milestone.

## Suggested Creation Order (GitHub)
1. Create all labels.
2. Create milestones M1-M5.
3. Create 8 epic issues with type:epic label.
4. Create all child issues and link to parent epic.
5. Assign owners and initial estimates.
6. Start with EPIC 1, 2, and 3 in parallel only where file ownership does not conflict.

## Epic Template (Copy/Paste)
Title:
EPIC: <short objective>

Body:
- Background: <why this epic matters>
- Objective: <desired outcome>
- Scope In: <what is included>
- Scope Out: <what is not included>
- Success Metrics: <quantitative targets>
- Dependencies: <other epics/issues>
- Risks: <top risks>
- Child Issues:
  - #<id> <title>
  - #<id> <title>
- Definition of Done:
  - [ ] Criteria 1
  - [ ] Criteria 2

## Issue Template (Copy/Paste)
Title:
<area>: <action-oriented summary>

Body:
- Problem: <what is broken or missing>
- Goal: <target behavior>
- Scope:
  - In: <items>
  - Out: <items>
- Implementation Notes: <approach>
- Acceptance Criteria:
  - [ ] AC1
  - [ ] AC2
  - [ ] AC3
- Test Plan:
  - [ ] Unit tests
  - [ ] Integration tests
  - [ ] Manual validation
- Dependencies: <issue links>
- Risks: <known risks>
- Rollback Plan: <if release fails>
- Definition of Done:
  - [ ] Code merged
  - [ ] Tests passing
  - [ ] Docs updated
