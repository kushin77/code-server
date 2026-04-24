# Ollama Model Promotion Gates Proof — 2026-04-18

Purpose:
- Capture proof that the Ollama model promotion gates contract, policy, and evidence format are validated by a deterministic local checker and CI workflow.

Artifacts:
- [config/ollama-model-promotion-gates.yml](../../config/ollama-model-promotion-gates.yml)
- [scripts/ci/validate-ollama-model-promotion-gates.sh](../../scripts/ci/validate-ollama-model-promotion-gates.sh)
- [.github/workflows/ollama-model-promotion-gates.yml](../../.github/workflows/ollama-model-promotion-gates.yml)
- [docs/AI-MODEL-PROMOTION-GATES-630.md](../../docs/AI-MODEL-PROMOTION-GATES-630.md)
- [docs/ops/OLLAMA-MODEL-PROMOTION-GATES-RUNBOOK.md](../../docs/ops/OLLAMA-MODEL-PROMOTION-GATES-RUNBOOK.md)

Verified commands:
1. Local gate validation
   - `bash scripts/ci/validate-ollama-model-promotion-gates.sh`
   - Result: passed.

Coverage facts:
- The gate contract defines candidate, canary, and default stages.
- The contract requires accuracy, safety, latency, and token cost scorecards.
- The policy documents canary evidence, postmortem handling, and CI enforcement.
- The workflow enforces the same contract on changes to the gate config and policy docs.

Operational note:
- This proof is file-based and can be regenerated without external network state once the validator is executed.