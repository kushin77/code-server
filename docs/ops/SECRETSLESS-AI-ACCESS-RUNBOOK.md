# Secretsless AI Access Runbook

Purpose:
- Define the operator workflow for validating secretsless AI access, entitlement mapping, and quota enforcement.

When to use:
- Any time [config/code-server/ai/ai-access-profiles.yml](../../config/code-server/ai/ai-access-profiles.yml), [config/code-server/ai/model-entitlements.yml](../../config/code-server/ai/model-entitlements.yml), [config/code-server/ai/quota-policy.yml](../../config/code-server/ai/quota-policy.yml), or [scripts/ai-runtime-env](../../scripts/ai-runtime-env) changes.

Operational steps:
1. Validate the access contracts locally.
   - `bash scripts/ci/validate-secretsless-ai-access.sh`
2. Confirm the workspace profile is injected at startup.
   - The active profile should be exported by `scripts/ai-runtime-env`.
3. Confirm the primary and fallback endpoints are present in the runtime env.
4. Verify quota enforcement returns the friendly throttle message instead of failing silently.
5. Confirm no API key or token is written to workspace files or user settings.

Evidence requirements:
- The admin portal remains the source of truth for entitlement and quota tier.
- The entitlement map must remain deny-by-default.
- The quota policy must remain deny-by-default and throttle with a clear message.

Rollback loop:
- If secrets appear in local state, stop and remove them before continuing.
- If the runtime env diverges from the committed contract, revert the env change and rerun the validator.