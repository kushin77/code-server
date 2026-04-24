# Shared E2E Fixtures

Use this directory for deterministic browser-test helpers that must remain stable across runs.

Standards:
- Keep fixtures pure and side-effect free.
- Prefer explicit locale, timezone, viewport, and header defaults.
- Do not read secrets from disk here; use the workspace provisioning path instead.
