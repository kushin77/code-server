# Ollama Integration Contract Proof — 2026-04-18

Purpose:
- Capture proof that the Ollama integration contract and release handshake are validated by a deterministic local checker and CI workflow.

Artifacts:
- [config/ollama-integration-contract.yml](../../config/ollama-integration-contract.yml)
- [scripts/ci/validate-ollama-integration-contract.sh](../../scripts/ci/validate-ollama-integration-contract.sh)
- [.github/workflows/ollama-contract-coverage.yml](../../.github/workflows/ollama-contract-coverage.yml)
- [docs/ops/OLLAMA-INTEGRATION-CONTRACT-RUNBOOK.md](../../docs/ops/OLLAMA-INTEGRATION-CONTRACT-RUNBOOK.md)

Verified commands:
1. Local contract validation
   - `bash scripts/ci/validate-ollama-integration-contract.sh`
   - Result: passed.

Coverage facts:
- The contract declares both GPU and fallback endpoints.
- The compatibility matrix includes the default and optional model tiers.
- The release handshake is explicit and requires version bump, validation, matrix verification, PR, and production approval.
- Routing, canary, capacity, and secretsless auth rules are present in the committed contract.

Operational note:
- This proof is immutable and file-based; no transient network state is required to validate the contract structure.