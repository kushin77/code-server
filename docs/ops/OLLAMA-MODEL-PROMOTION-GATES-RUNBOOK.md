# Ollama Model Promotion Gates Runbook

Purpose:
- Define the operator workflow for promoting a new Ollama default model through candidate, canary, and production.

When to use:
- Any time `config/ollama-model-promotion-gates.yml` or `OLLAMA_DEFAULT_MODEL` changes.

Operational steps:
1. Update the model candidate and confirm the new revision is compatible with the release train.
2. Regenerate or review the evidence bundle:
   - `evaluation_report.json`
   - `canary_results.json`
   - `promotion_decision.md`
3. Run the local gate validator:
   - `bash scripts/ci/validate-ollama-model-promotion-gates.sh`
4. Publish the canary rollout notes and capture the approval record.
5. Promote only after human approval, artifact review, and rollback readiness are confirmed.

Evidence requirements:
- The evaluation report must record the model version, dataset, accuracy, safety score, latency, and reviewer.
- The canary results must record rollout percentage, duration, error rate, latency regression, and incident count.
- The decision note must record the final approval or rejection and the rollback rationale.

Rollback loop:
- If any threshold is exceeded, revert the default model immediately.
- Record the failed evidence bundle and the incident summary.
- Re-run the validator before any further promotion attempt.