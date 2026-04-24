# E2E Service Account Provisioning Proof — 2026-04-18

Purpose:
- Capture local proof that workspace provisioning uses the canonical GSM-backed auth path for the dedicated E2E service-account flow.

Context:
- The dedicated E2E service-account profile already exists in [config/e2e-service-account-profile.yml](../../config/e2e-service-account-profile.yml).
- The workspace provisioning path is responsible for fetching workspace credentials and exporting them into the session environment.

Verified commands:
1. Syntax and idempotence
   - `bash -n scripts/workspace-provision`
   - `WORKSPACE_PROVISION_SKIP=1 bash scripts/workspace-provision`

2. GSM-backed credential bootstrap
   - `env -u GITHUB_TOKEN -u GH_TOKEN bash scripts/workspace-provision`

Observed result:
- `workspace-provision` detected the current workspace user.
- `GITHUB_TOKEN` was provisioned from GSM using the canonical `gcp-eiq/github-token` path.
- GCP Application Default Credentials were available in the session.
- Provisioning completed successfully without requiring a pre-exported token.

Evidence summary:
- Workspace credential sourcing is GSM-first and ephemeral.
- The script does not require a persistent token file or a one-off manual export.
- The path is idempotent: skip mode remains a no-op, and normal mode only sets missing credentials.

Operational note:
- This is local provisioning proof, not a full production E2E run. Production validation still requires the browser/login flow and release-gate evidence.