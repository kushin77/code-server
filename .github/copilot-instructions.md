# Copilot Instructions — code-server-enterprise

> Policy version: 1.0 | Enforced by: `apps/copilot-engine`

This file governs how GitHub Copilot and the `@code-server/copilot-engine`
autonomous agent behave across all domains in this repository.

---

## Domains

| Domain   | Scope |
|----------|-------|
| `code`   | CI/CD, FlowCI, GitPeak, Git governance, TypeScript/Python services |
| `infra`  | Terraform, Kubernetes, Docker Compose, Caddy, NAS, TLS |
| `sales`  | GTM playbooks, LinkedIn/Google Ads, email nurture, Chrome extensions |
| `product`| AnimForge, EXPOSED.ai, real estate intelligence, AI video production |

---

## Memory Rules (enforced at runtime by `apps/copilot-engine`)

### Rule 1 — No Silent Repetition
Before any suggestion, the engine checks semantic similarity against all prior
suggestions in the session (threshold: 0.85). If a duplicate is detected:
- The engine **stops** and surfaces the prior suggestion with its timestamp.
- It asks: _"I mentioned this at [time]. Expand on it or take a different angle?"_

### Rule 2 — Conflict Surfacing
If a proposed answer conflicts with a locked decision:
- Surface the conflict: _"Earlier we decided [X]. This contradicts that because [Y]. Proceed?"_
- Log to `contradiction_log` with resolution timestamp.

### Rule 3 — Decision Lock-In
When a user accepts a suggestion:
- Call `memory.lockDecision(goalId, decision)` to persist it.
- All future suggestions must align with locked decisions or explicitly ask to revisit.

### Rule 4 — Explicit Domain Switching
When the domain changes mid-session:
- Log a warning: _"Switching from [old] to [new]. Goals in [old] are still open."_
- Update `active_context.current_domain`.

### Rule 5 — Assumption Declaration
At the start of every response, list all assumptions being made.
If an assumption is later proven wrong, update `active_context.assumptions` and
adjust subsequent responses accordingly.

---

## Response Format (every response)

```
**Memory State**: Active goals: [list] | Domain: [domain] | Blockers: [list]

[Your answer here]

**Dedup Check**: Is this new? [Yes/No — if No, reference prior timestamp]

**Next Step**: [Concrete next action]
```

---

## Anti-Patterns — never do these

- Suggest the same thing twice without flagging it first
- Offer contradictory advice without surfacing the conflict
- Forget prior locked decisions
- Switch domains without an explicit transition warning
- Make assumptions without declaring them upfront

---

## Git Workflow Mandate (branch sprawl prevention)

After every completed task or issue, follow this sequence without skipping steps.

Canonical mirror policy: [repo/copilot/rules/instructions/branch-lifecycle-mandate.instructions.md](../repo/copilot/rules/instructions/branch-lifecycle-mandate.instructions.md)

### Mandatory completion flow

1. Verify task completion and run relevant checks/tests.
2. Commit immediately with a clear task/issue-scoped message.
3. Push the commit to remote.
4. Merge to `main` (or update/open PR and complete merge as the only active integration path).
5. Redeploy from `main` after merge.
6. Clean up both local and remote working branches used for the task.

### Branch lifecycle rules

- One active branch per task/issue; no stacked or long-lived feature branches.
- Start branch cleanup immediately after merge and redeploy confirmation.
- Do not start the next task until the previous task branch is deleted locally and remotely.
- If cleanup cannot be completed, explicitly report blocker and owner in status output.

### Required completion status output

Every completion response must include:
- Commit SHA
- Remote push confirmation
- Main merge confirmation
- Redeploy confirmation
- Local branch cleanup confirmation
- Remote branch cleanup confirmation

### Forbidden behaviors

- Leaving merged branches undeleted (local or remote)
- Accumulating multiple active branches for parallel unfinished work without explicit approval
- Deferring commit/push/merge/redeploy/cleanup to a later session

### Deterministic enforcement

- Session completion evidence hook: `.github/hooks/completion-evidence-enforcer.json`
- Hook validator script: `scripts/hooks/enforce-completion-evidence.py`
- Remote merged-branch cleanup CI gate: `scripts/ci/check-merged-branch-cleanup.sh`
- GitHub Actions enforcement job: `.github/workflows/governance-checks.yml` (`branch-hygiene`)
- Local git pre-push gate for main: `.githooks/pre-push` via `scripts/hooks/pre-push-branch-hygiene.sh`
- Local hook installer: `scripts/hooks/install-local-git-hooks.sh` (`pnpm hooks:install`)

---

## Architecture (`apps/copilot-engine`)

```
src/
  memory.js        – Layer 1: structured intent map, goal tracking, decisions
  deduplication.js – Layer 2: cosine similarity, mock/real embeddings, contradiction heuristic
  engine.js        – Layer 3: rolling conversation, Claude Sonnet 4 integration
  index.js         – Public re-exports
  demo.js          – Smoke test (requires ANTHROPIC_API_KEY)
```

### Swapping the embedding provider

```js
import { setEmbeddingProvider } from "@code-server/copilot-engine/deduplication";

// Example: Ollama nomic-embed-text
setEmbeddingProvider(async (text) => {
  const res = await fetch("http://localhost:11434/api/embeddings", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: "nomic-embed-text", prompt: text }),
  });
  const json = await res.json();
  return json.embedding;
});
```

### Production persistence

| Layer | Dev (default) | Production |
|-------|---------------|------------|
| Intent map | In-process `Map` | Redis `HSET` / PostgreSQL `jsonb` |
| Vector store | In-process `Map` | Qdrant (`apps/memory-engine`) / Pinecone |
| Conversation | In-process array | Redis sorted set (TTL 2 h) |

Wire to the existing `apps/memory-engine` (Qdrant-backed) for vector storage and
to the existing `apps/prompt-gateway` for system prompt injection.

---

## Deployment checklist

- [ ] Set `ANTHROPIC_API_KEY` in environment / secrets manager
- [ ] Add `apps/copilot-engine` to Docker Compose / Helm chart if running as a service
- [ ] Replace `mockEmbedding` with a real provider (`setEmbeddingProvider`)
- [ ] Wire vector store to `apps/memory-engine` (Qdrant)
- [ ] Wire conversation persistence to Redis
- [ ] Run `pnpm --filter @code-server/copilot-engine demo` to smoke-test

---

## Validation scenarios

| Test | Input | Expected |
|------|-------|----------|
| Dedup | Same question twice | Second call returns `type: "duplicate_flag"` |
| Conflict | Ask for A then B (contradictory) | Engine surfaces conflict before answering |
| Decision lock | Make decision → ask to revisit | Engine asks for explicit permission |
| Domain flip | Switch code → sales | Engine logs domain switch warning |
| Assumption | State assumption → contradict it | Engine corrects and updates assumptions |
