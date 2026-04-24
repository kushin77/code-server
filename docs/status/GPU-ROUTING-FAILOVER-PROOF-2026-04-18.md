# GPU Routing Failover Proof — 2026-04-18

Purpose:
- Capture proof that the GPU routing and failover contract is validated by a deterministic local checker and CI workflow.

Artifacts:
- [config/ollama-integration-contract.yml](../../config/ollama-integration-contract.yml)
- [docs/ai/OLLAMA-ROUTING-POLICY.md](../../docs/ai/OLLAMA-ROUTING-POLICY.md)
- [docs/ops/OLLAMA-GPU-REPLICA-OPERATIONS.md](../../docs/ops/OLLAMA-GPU-REPLICA-OPERATIONS.md)
- [docs/GPU-ROUTING-FAILOVER-631.md](../../docs/GPU-ROUTING-FAILOVER-631.md)
- [scripts/ci/validate-ollama-gpu-routing-failover.sh](../../scripts/ci/validate-ollama-gpu-routing-failover.sh)
- [.github/workflows/ollama-gpu-routing-failover.yml](../../.github/workflows/ollama-gpu-routing-failover.yml)

Verified commands:
1. Local routing validation
   - `bash scripts/ci/validate-ollama-gpu-routing-failover.sh`
   - Result: passed.

Coverage facts:
- The contract pins the primary GPU host and fallback CPU host.
- The routing policy documents the health-primary-fallback strategy, failover rules, and rollout thresholds.
- The operations doc documents the checks for the active endpoint and the failover drill.
- The issue doc captures the tested failover behavior and performance baseline.

Operational note:
- This proof is file-based and can be regenerated without transient network state once the validator is executed.