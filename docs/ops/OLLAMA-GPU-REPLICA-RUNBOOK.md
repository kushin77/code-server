# Ollama GPU Replica Routing Runbook

Purpose:
- Define the operator workflow for validating GPU routing, failover, and failback behavior.

When to use:
- Any time `config/ollama-integration-contract.yml` or [docs/ai/OLLAMA-ROUTING-POLICY.md](../../docs/ai/OLLAMA-ROUTING-POLICY.md) changes.

Operational steps:
1. Validate the contract locally.
   - `bash scripts/ci/validate-ollama-gpu-routing-failover.sh`
2. Check the primary GPU endpoint.
   - `curl http://192.168.168.42:11434/api/version`
3. Check the fallback CPU endpoint.
   - `curl http://192.168.168.31:11434/api/version`
4. Run the failover drill in a controlled environment.
   - Confirm `.42` health loss promotes `.31`
   - Confirm failback occurs after the configured recovery window
5. Record the evidence bundle.
   - Endpoint checks
   - Failover latency
   - Failback latency
   - Any model load degradation notes

Evidence requirements:
- The primary and fallback hosts must match the committed integration contract.
- The routing strategy must remain `health-primary-fallback`.
- The canary percentages and GPU memory guardrail must remain unchanged unless the contract is version-bumped.

Rollback loop:
- If failover is slower than the contract threshold, revert the routing change and keep the previous active host.
- If GPU pressure exceeds the guardrail, reduce concurrency before changing models.