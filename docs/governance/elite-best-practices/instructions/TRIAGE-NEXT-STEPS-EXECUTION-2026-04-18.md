# Triage Next Steps Execution (2026-04-18)

Purpose: convert current governance and redeploy work into issue-driven, measurable execution with on-prem focus.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-19

## Current State

- Elite best-practices folder structure consolidated to single canonical tree: `docs/governance/elite-best-practices/` (12 subfolders, no stubs, no duplicates).
- Former `docs/elite-best-practices/` stub tree retired (git rm'd, redirected here).
- Replica failover host path is live on `.42` for code-server + oauth2-proxy, with ingress validation on `:18080`.
- New deterministic failover entrypoint implemented:
   - `scripts/operations/redeploy/onprem/failover-orchestrate.sh`
- In-workspace operator tasks added for preflight, redeploy, status, promote, failback.
- Secure baseline hardening completed in compose/template (13/13 CI guard checks passing):
   - required `CODE_SERVER_PASSWORD` (no weak fallback)
   - no TLS bypass env in baseline compose
   - no baseline docker socket mount (optional override file only)
   - profile backups emit `sha256` checksum sidecars
   - NFS-backed volumes for NAS .56 (workspace, profile, ollama, postgres-backup)
   - legacy compose stubs retired (`scripts/docker-compose.yml`, `docker/docker-compose.yml`)
- Compose hardening CI guard: `scripts/ci/check-compose-hardening-guard.sh` (13/13)
- NAS `.56` shared storage wired (commit `4e1882b4`):
   - workspace, profile, profile-backups, ollama-data, postgres-backup → NFS `/export/*`
   - DB engines remain `driver: local` (NFS locking incompatible)
- Keepalived VRRP module wired in Terraform (commit `e2e7d149`):
   - VIP: `192.168.168.30`
   - Primary: `.31` (MASTER, priority 150), Replica: `.42` (BACKUP, priority 100)
   - `advert_int=1`, `fall=2` → ~2s failover SLA
   - Activation and orchestration path completed under #715 (closed)
- Authenticated failover continuity execution path is now present:
   - `.github/workflows/e2e-authenticated-failover-continuity.yml`
   - `scripts/ci/prepare-playwright-storage-state.sh`
   - `docs/ops/AUTHENTICATED-FAILOVER-CONTINUITY-733.md`
- Previously open failover/runtime gate issues are now closed with evidence:
   - #692, #695, #710, #711, #712, #713, #714, #733, #750, #751
- Auth conformance reporting now supports minimal environments without `jq`:
   - `scripts/ci/test-auth-conformance.sh` (JSON quoting fallback)
- Latest validated operational run (2026-04-18, explicit SSH key path):
   - preflight passed (`--mode ssh --ssh-key ~/.ssh/id_rsa_onprem --fix-stale-logs`)
   - redeploy passed (`--mode ssh --ssh-key ~/.ssh/id_rsa_onprem --fix-stale-logs`)
   - failover status baseline evidence: `/tmp/code-server-failover-evidence/failover-20260418T210450Z.json`
   - promote evidence (active marker `.31` -> `.42`): `/tmp/code-server-failover-evidence/failover-20260418T210458Z.json`
   - failback evidence (active marker `.42` -> `.31`): `/tmp/code-server-failover-evidence/failover-20260418T210513Z.json`
   - final result: primary HEALTHY, replica HEALTHY, replica ingress healthy
- Core domain-managed client enhancement stream is now consolidated under:
   - #751 EPIC (runtime transformation)
   - #752-#760 child implementation issues
- Redeploy preflight hardening completed and validated on production host:
   - commit `2ac5232f`: NAS export subpath gate (fail-fast before compose)
   - commit `05cf1cf0`: dual-domain drift check alignment (`ide` + apex-aware)
- Extension-governance conformance stream progressed under #760:
   - commit `0f620e71`: auth conformance suite Category 5 added (`scripts/ci/lint-role-profiles.sh` integration)
   - local stability evidence: 3/3 passing runs (`/tmp/auth-conformance-report*.json`, 10/10 pass each)
   - CI regression root cause from run `24617562996` isolated (jq fallback misread explicit `false` as missing)
   - commit `c2bbb35f`: key-presence parsing fix in `scripts/ci/lint-role-profiles.sh`
   - CI verification: Security run `24617607483` reports `Auth/Policy Conformance Suite` completed/success
- Failover/load-balancing hardening follow-up landed and was re-validated (2026-04-19 UTC):
   - commit `f22cd841`: persistent Caddy `/data` + `/config` volumes for stable TLS/runtime state
   - commit `34f1f984`: failover orchestration enforces VIP-owner convergence during promote/failback
   - evidence snapshots:
      - `/tmp/code-server-failover-evidence/failover-20260419T005433Z.json` (baseline status)
      - `/tmp/code-server-failover-evidence/failover-20260419T005458Z.json` (promote: marker + VIP owner converge to `.42`)
      - `/tmp/code-server-failover-evidence/failover-20260419T005516Z.json` (failback: marker + VIP owner converge to `.31`)
   - ingress/auth probe reliability validated: 10/10 successful VIP checks
- Overlap cleanup completed for superseded issues:
   - #738 -> superseded by #759
   - #739 -> superseded by #756
   - #741 -> superseded by #757
   - #749 -> superseded by #758

## Immediate Priority Focus (P0/P1 Only)

Run this queue before any P2/P3 work.

1. **P0 critical gate**: #702 (fail-closed governance pipeline).
2. **P1 policy authority foundations**: #700 -> #701 -> #704.
3. **P1 runtime enforcement path**: #703 -> #705 -> #708.
4. **P1 control-plane enablement**: #706 -> #707 -> #742.
5. **P1 portal delivery children**: #743 -> #744 -> #745 -> #746 -> #747 -> #748.
6. **P1 extension-governance closure path**: #735 (close epic with #760 and #759 evidence retained).

Priority debug rule:
- Any failing CI/conformance result tied to #702, #701, #703, #705, #708, or #735 preempts lower-priority implementation work until green.

## Issue-Mapped Next Steps (Open Backlog)

### Stream A: Governance Foundations (dedupe first)
1. **#700 (EPIC)**: Enterprise global governance control plane (single policy authority).
2. **#704 (EPIC)**: Canonical policy SSOT and deduplication of governance sources.
3. **#701 (EPIC)**: Org-wide GitHub governance enforcement (rulesets + branch protections).
4. **#702 (EPIC)**: Fail-closed governance pipeline (P0 controls block merge).

### Stream B: Runtime Governance
5. **#703 (EPIC)**: Enterprise IDE policy runtime.
6. **#705 (EPIC)**: Centralized waiver governance.
7. **#708 (EPIC)**: OPA policy service evolution.

### Stream C: Control Plane Productization
8. **#706 (EPIC)**: Governance admin center (Backstage + Appsmith).
9. **#707 (EPIC)**: Repository onboarding and continuous compliance.
10. **#742 (EPIC)**: Open-source control-plane adoption stream.

### Stream D: Portal Control-Plane Delivery (execute under the Stream C parent epic)
11. **#743**: Windows-DC to portal capability mapping and ownership matrix.
12. **#744**: Backstage as primary portal control-plane UX.
13. **#745**: Appsmith operator revoke + break-glass console.
14. **#746**: Identity authority standardization (Keycloak/Auth + group claims).
15. **#747**: OPA centralized policy decision point integration.
16. **#748**: Vault adoption for policy-signing keys and secret lifecycle.

### Stream E: Extension Governance and Conformance
17. **#735 (EPIC)**: Portal-only extension governance for thin-client IDE.

### Stream F: Multi-Repo UX (execute after governance contracts stabilize)
19. **#717 (EPIC)**: Multi-repo developer navigation experience.
20. **#718**: Instant repo switcher.
21. **#719**: Multi-repo home view.
22. **#720**: Session persistence and safe restore.
23. **#721**: Workspace tabs in toolbar.
24. **#722**: Cross-repo isolation and permission model.
25. **#723**: Sub-2s repo switch SLO and resource guardrails.
26. **#724**: Enterprise policy defaults/limits/compliance for multi-repo UX.
27. **#725**: Pilot rollout and feature-flag validation.
28. **#726**: Architecture decision for best multi-repo interaction model.
29. **#727**: Developer context hub integration.

## Execution Order (Overlap-Reduced)

1. **Single authority first**: execute #700 and #704 before any new governance feature work.
2. **Enforcement second**: land #701 then #702 so merge gates and branch rules enforce SSOT.
3. **Runtime policy third**: execute #703 with #705 and #708 in that order.
4. **Control-plane apps fourth**: execute #706 and #707, then implement #742 through #743-#748 in order.
5. **Extension governance fifth**: execute #735 closure with #759 and #760 evidence.
6. **UX last**: execute #717 through #727 only after Stream A-E contracts are stable.

### Debug/Triage Rule Set

- Keep one active epic stream in progress at a time unless a dependency requires parallel work.
- Each stream must name one canonical config source and one canonical runbook.
- No duplicate helper scripts: reuse `scripts/_common/` and existing operation wrappers.
- Evidence format is uniform across streams: issue comment includes commit, command, pass/fail, artifact path.

### PowerShell-Safe Remote Docker Inspect

When running inspect commands from Windows PowerShell, avoid heavily escaped Go templates that commonly fail with parsing errors.

- Safe label dump:
   - `ssh akushnir@192.168.168.31 "docker inspect appsmith --format '{{json .Config.Labels}}'"`
- Service health/name check:
   - `ssh akushnir@192.168.168.31 "docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | egrep -i 'appsmith|portal|oauth2|caddy'"`

Use these as the canonical diagnostics before deeper redeploy/failover investigation.

## State Durability Commands

Run Tier-A drift and snapshot-restore verification:

- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action drift-report`
- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action replicate-tier-a`
- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action snapshot-restore-test`

Run compose hardening baseline guard:

- `bash scripts/ci/check-compose-hardening-guard.sh`

Run overlap/staleness backlog guard:

- `bash scripts/ci/validate-triage-open-backlog.sh`

## Bootstrap Reference

- See `docs/governance/elite-best-practices/instructions/DEPLOY-IDENTITY-BOOTSTRAP.md` for deterministic identity setup and `local-on-host` fallback.

## Anti-Duplication Guardrails

- Do not add new helper functions if equivalents exist under `scripts/_common/`.
- Keep all operational guidance under `docs/governance/elite-best-practices/`.
- Avoid introducing duplicate workflow logic when templates can be reused.

## Done Definition

- Stream A done when #700/#704/#701/#702 are implemented with no policy-source duplication.
- Stream B done when #703/#705/#708 enforce fail-closed decisions with auditable exceptions.
- Stream C done when #706/#707/#742 use Stream A-B contracts without redefining schema/policy paths.
- Stream D done when #743/#744/#745/#746/#747/#748 are integrated without introducing a second policy authority.
- Stream E done when #735 closes with #759 hardening and #760 conformance evidence retained.
- Stream F done when #717 through #727 ship without introducing alternate state stores or policy models.
- No new loose root files are introduced in active branches.
