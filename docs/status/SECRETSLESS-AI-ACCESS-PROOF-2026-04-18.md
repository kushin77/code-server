# Secretsless AI Access Proof — 2026-04-18

Purpose:
- Capture proof that the secretsless AI access contract, entitlement mapping, and quota policy are validated by a deterministic local checker and CI workflow.

Artifacts:
- [config/code-server/ai/ai-access-profiles.yml](../../config/code-server/ai/ai-access-profiles.yml)
- [config/code-server/ai/model-entitlements.yml](../../config/code-server/ai/model-entitlements.yml)
- [config/code-server/ai/quota-policy.yml](../../config/code-server/ai/quota-policy.yml)
- [scripts/ai-runtime-env](../../scripts/ai-runtime-env)
- [docs/ai/SECRETSLESS-AI-ACCESS.md](../../docs/ai/SECRETSLESS-AI-ACCESS.md)
- [docs/SECRETLESS-AI-ACCESS-632.md](../../docs/SECRETLESS-AI-ACCESS-632.md)
- [scripts/ci/validate-secretsless-ai-access.sh](../../scripts/ci/validate-secretsless-ai-access.sh)
- [.github/workflows/secretsless-ai-access.yml](../../.github/workflows/secretsless-ai-access.yml)

Verified commands:
1. Local access validation
   - `bash scripts/ci/validate-secretsless-ai-access.sh`
   - Result: passed.

Coverage facts:
- The access profiles remain deny-by-default and expose only startup-injected profiles.
- The entitlement map is portal-owned and requires actor, reason, and expiry for overrides.
- The quota policy is deny-by-default and uses explicit throttle and denied messages.
- The runtime env script exports the effective contract without storing local secrets.

Operational note:
- This proof is file-based and can be regenerated without transient network state once the validator is executed.