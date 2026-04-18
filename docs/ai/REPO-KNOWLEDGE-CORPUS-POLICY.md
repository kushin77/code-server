# Repo Knowledge Corpus Policy

This policy defines what repository content may be indexed for repo-aware AI retrieval.

In scope:
- `docs/**`
- `.github/**`
- `scripts/**`
- `config/**`
- top-level operational READMEs and runbooks

Excluded content:
- `.env*`
- private keys, certificates, raw tokens, and secret material
- generated dependency trees such as `node_modules/**`
- `.git/**`

Scrubbing rules:
- Block ingestion of any content matching secret markers such as `BEGIN PRIVATE KEY`, `ghp_`, or `GITHUB_TOKEN`.
- Redact secret values before indexing whenever a structured source cannot be fully excluded.

Freshness and deduplication:
- Daily incremental sync plus on-demand refresh for critical policy docs.
- Freshness score considers commit recency, linked issue state, and path priority.
- Near-identical chunks are deduplicated before indexing.

Metadata per chunk:
- source path
- commit SHA
- linked issue number when available
- index timestamp
- confidence tag
- freshness tag

Retrieval guardrails:
- Operational claims require citations.
- If retrieved context is insufficient, the AI response must explicitly say so instead of guessing.

Quality metrics:
- grounded answer rate
- citation coverage
- stale citation rate
- hallucination incidents