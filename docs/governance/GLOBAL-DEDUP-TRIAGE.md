# Global Dedup Triage

Version: 1.0  
Date: 2026-04-17  
Owner: Platform Engineering

## Objective

Identify overlap clusters across the repository and define executable removal order toward strict single-source-of-truth governance.

## Triage Summary

1. Critical overlap cluster: compose variants and runtime drift risk.
2. Critical overlap cluster: Caddyfile variants and callback/auth behavior drift.
3. High overlap cluster: Terraform root mirror and terraform/ mirror.
4. High overlap cluster: duplicated/near-duplicated docs and naming collisions.
5. Medium overlap cluster: overlapping governance scripts/workflows with advisory-only behavior.

## Cluster Details

### 1) Compose Overlap

Risk:

1. Multiple compose variants can diverge from runtime behavior and reintroduce auth regressions.

Current state:

1. Canonical runtime: docker-compose.yml.
2. Overlap-prone legacy variants are now blocked by CI guard for routine edits.

Removal actions:

1. Freeze legacy compose variants (already enforced in guard).
2. Migrate any remaining consumers to docker-compose.yml.
3. Archive legacy compose variants after migration validation.

### 2) Caddyfile Overlap

Risk:

1. Callback routing and auth proxy behavior can drift between Caddyfile variants.

Current state:

1. Canonical runtime: Caddyfile.
2. Legacy variants blocked by CI guard for routine edits.

Removal actions:

1. Keep runtime changes only in Caddyfile.
2. Archive legacy Caddyfile variants after final dependency check.

### 3) Terraform Mirror Overlap

Risk:

1. Parallel edits across main.tf and terraform/main.tf can create silent drift.

Current state:

1. Guard enforces mirror parity when either mirror file is changed.

Removal actions:

1. Stop introducing new root-level terraform mirrors.
2. Transition consumers to terraform/main.tf as canonical.
3. Decommission root mirror once callers are migrated.

### 4) Documentation Overlap

Risk:

1. Near-duplicate docs with normalized-name collisions create contradictory guidance.

Current state:

1. Guard blocks newly-added docs with normalized-name collisions.

Removal actions:

1. Consolidate duplicate docs into canonical runbooks/ADR paths.
2. Replace superseded docs with stubs that link to canonical source, then archive.

### 5) Governance Control Overlap

Risk:

1. Advisory-only checks allow overlap to persist.

Current state:

1. New blocking workflow: .github/workflows/global-dedup-guard.yml.
2. Enforcement script: scripts/ci/enforce-global-dedup.sh.

Removal actions:

1. Make dedup guard a required status check on main.
2. Route all waivers through governance waiver issue template.
3. Add monthly overlap-burndown metric to governance report.

## Execution Order

1. Enforce freeze (done).
2. Migrate active callers to canonical paths (next).
3. Archive deprecated overlap files.
4. Tighten branch protection to require dedup guard.
5. Track monthly overlap burndown until zero active overlap.

## Exit Criteria

1. No active non-canonical compose or Caddyfile variants changed in 30 days.
2. No parity drift in Terraform mirror checks.
3. No new doc name collisions.
4. All overlap waivers closed or expired.
5. Branch protection includes required dedup guard check.
