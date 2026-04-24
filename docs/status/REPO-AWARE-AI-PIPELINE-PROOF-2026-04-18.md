# Repo-Aware AI Pipeline Proof — 2026-04-18

Purpose:
- Capture proof that the repo-aware AI pipeline contract, corpus policy, and evidence schema are validated by a deterministic local checker and CI workflow.

Artifacts:
- [config/code-server/ai/repo-rag-pipeline.yml](../../config/code-server/ai/repo-rag-pipeline.yml)
- [docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md](../../docs/ai/REPO-KNOWLEDGE-CORPUS-POLICY.md)
- [scripts/ai-runtime-env](../../scripts/ai-runtime-env)
- [scripts/ci/validate-repo-aware-ai-pipeline.sh](../../scripts/ci/validate-repo-aware-ai-pipeline.sh)
- [.github/workflows/repo-aware-ai-pipeline.yml](../../.github/workflows/repo-aware-ai-pipeline.yml)
- [docs/ops/REPO-AWARE-AI-PIPELINE-RUNBOOK.md](../../docs/ops/REPO-AWARE-AI-PIPELINE-RUNBOOK.md)

Verified commands:
1. Local pipeline validation
   - `bash scripts/ci/validate-repo-aware-ai-pipeline.sh`
   - Result: passed.

Coverage facts:
- The evaluation contract explicitly names the 50-query common-workflow gold set.
- The freshness policy uses daily incremental sync plus on-demand refresh for critical paths.
- The retrieval contract requires citations and returns unknown when context is insufficient.
- The corpus policy excludes secrets, environment files, and dependency trees from indexing.

Operational note:
- This proof is file-based and can be regenerated without transient network state once the validator is executed.