# Ollama Integration Contract Runbook

Objective:
- Validate the cross-repo Ollama integration contract before promotion or rollout.

Scope:
- Applies to [config/ollama-integration-contract.yml](../../config/ollama-integration-contract.yml).
- Covers the version pin, compatibility matrix, release handshake, and rollback guidance.

Workflow:
1. Validate the contract locally.
   - `bash scripts/ci/validate-ollama-integration-contract.sh`

2. Review the compatibility matrix.
   - Confirm the default model is `codellama:7b`.
   - Confirm `llama3` is GPU-only and `mistral` works on both primary and fallback endpoints.

3. Confirm the release handshake.
   - Require a PR, a version bump, contract validation, matrix verification, and production approval.

4. Verify the routing and fallback contract.
   - Primary: `192.168.168.42:11434`
   - Fallback: `192.168.168.31:11434`

5. Follow rollback policy.
   - Use `git revert` to roll back contract changes.
   - Keep the contract version pinned until the full verification matrix has passed.

Artifact policy:
- Keep contract evidence in docs or issue comments; do not keep transient validation data unless it is needed as proof.

Validation criteria:
- The validator passes locally.
- The workflow passes on contract changes.
- The release handshake block remains explicit in the committed contract.