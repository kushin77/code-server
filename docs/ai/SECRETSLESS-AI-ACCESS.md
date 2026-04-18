# Secretsless AI Access

This repository standardizes AI access for code-server as a startup-injected workspace policy, not a user-managed token workflow.

Policy:
- The admin portal is the source of truth for AI entitlement and quota tier.
- code-server injects the active AI profile at startup.
- The primary AI endpoint is 192.168.168.42 and the automatic fallback is 192.168.168.31.
- No user-entered API key or token is required in the IDE.
- Model access is deny-by-default unless the workspace policy maps the user to a profile.

Runtime contract:
- Access profiles live in `config/code-server/ai/ai-access-profiles.yml`.
- Model entitlements live in `config/code-server/ai/model-entitlements.yml`.
- Quota tiers live in `config/code-server/ai/quota-policy.yml`.
- code-server startup reads these contracts through `scripts/ai-runtime-env` and exports the effective environment.

Safeguards:
- If the GPU-backed replica is unavailable, startup injects the fallback endpoint without prompting the user for credentials.
- Quota exceed behavior throttles with a clear message instead of silently failing.
- Audit trails for grants, revokes, and overrides remain portal-owned.

Persistence rule:
- AI access state must not be written into user settings, workspace files, or checked-in secrets.