# OPA Policy Service Migration Guide (#708)

## Purpose

This guide defines the first production-safe migration slice for #708:

- Versioned and signed policy bundles.
- Explicit distribution catalog for channel-based rollout.
- Persisted and queryable decision log export.
- Controlled rollback with auditable approvals.

## Artifacts

- Bundle schema: `config/policy-bundles/bundle-schema.json`
- Distribution catalog: `config/policy-bundles/bundle-catalog.json`
- Bundle build: `scripts/governance/build-policy-bundle.sh`
- Bundle verify: `scripts/governance/verify-policy-bundle.sh`
- Decision log export: `scripts/governance/export-policy-decision-log.sh`
- CI gate: `.github/workflows/policy-bundle-governance.yml`

## Build and verify workflow

```bash
bash scripts/governance/build-policy-bundle.sh --version 1.0.0 --channel canary
bash scripts/governance/verify-policy-bundle.sh --manifest artifacts/policy-bundles/policy-bundle-1.0.0-canary.manifest.json
```

The manifest includes:

- `bundle_id`
- `version`
- `channel`
- `generated_at` and `expires_at`
- Per-policy SHA256 values
- Archive SHA256
- Deterministic signature (`sha256:<digest>`)

## Distribution contract

`bundle-catalog.json` is the discovery contract for policy consumers. Channels represent rollout states:

- `canary`: pre-promotion validation
- `stable`: default production policy
- `rollback`: pinned known-good fallback

Promotion rule:

1. Build and verify canary bundle.
2. Run conformance against representative repositories.
3. Update `stable` pointer only after conformance + approval.

## Decision log export contract

```bash
bash scripts/governance/export-policy-decision-log.sh \
  --input /var/log/policy-runtime.log \
  --out-jsonl artifacts/policy-logs/decision-log.jsonl \
  --out-summary artifacts/policy-logs/summary.json
```

Output includes normalized records:

- `timestamp`
- `decision` (`allow` or `deny`)
- `policy_domain`
- `actor`
- `source`

`summary.json` provides totals and allow/deny counts for downstream dashboards and audit controls.

## Rollback safety

Rollback channel verification requires explicit acknowledgement:

```bash
bash scripts/governance/verify-policy-bundle.sh \
  --manifest artifacts/policy-bundles/policy-bundle-1.0.0-rollback.manifest.json \
  --allow-rollback
```

This ensures version downgrades cannot happen silently.

## Expected next implementation slices

- Replace digest-based signature with asymmetric signing (KMS-backed).
- Publish bundles to immutable object storage with retention policy.
- Stream decision logs to long-term audit store.
- Add automated canary-to-stable promotion based on conformance SLOs.
