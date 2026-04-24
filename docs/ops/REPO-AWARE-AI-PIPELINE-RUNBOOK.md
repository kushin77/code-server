# Repo-Aware AI Pipeline Runbook

Purpose:
- Define the operator workflow for validating the repo-aware AI pipeline contract and evidence bundle.

When to use:
- Any time `config/code-server/ai/repo-rag-pipeline.yml`, [docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md](../../docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md), or repo-aware AI retrieval behavior changes.

Operational steps:
1. Review the corpus policy to confirm only allowed paths are indexed.
2. Confirm the evaluation contract includes the required gold sets and metrics.
3. Validate the pipeline locally:
   - `bash scripts/ci/validate-repo-aware-ai-pipeline.sh`
4. Capture any issue or PR evidence with the evaluation set size, freshness target, and access-control statement.
5. If a claim lacks citations or the context is insufficient, record it as unknown instead of guessing.

Evidence requirements:
- The evaluation set must be explicitly described as the 50-query common-workflow set.
- The freshness target must be documented as less than 5 minutes stale.
- The access-control claim must mention workspace trust and file-permission enforcement.
- The metrics list must include grounded answer rate, citation coverage, stale citation rate, and hallucination incidents.

Rollback loop:
- If corpus scope expands unexpectedly, revert the config and re-run the validator.
- If retrieval starts making uncited claims, halt the rollout and require a doc update before resuming.