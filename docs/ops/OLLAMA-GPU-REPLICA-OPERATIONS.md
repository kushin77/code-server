# Ollama GPU Replica Operations

**Purpose**: Ollama GPU Replica Operations — reference and operational document.

Objective:
- Keep GPU-class inference on `replica.prod.internal` with seamless failover to `primary.prod.internal`.

Operational checks:
- Verify `replica.prod.internal` health with `curl http://replica.prod.internal:11434/api/version`.
- Verify readiness with `curl http://replica.prod.internal:11434/api/tags`.
- If `replica.prod.internal` is unhealthy, confirm startup exported `OLLAMA_FALLBACK_ENDPOINT=http://primary.prod.internal:11434`.

Failover drill:
1. Simulate `replica.prod.internal` outage or timeout.
2. Run `scripts/ollama-init.sh status` and confirm it can reach the fallback endpoint.
3. Confirm model pulls continue against `primary.prod.internal` without credential prompts.
4. Restore `replica.prod.internal` and verify automatic failback after the configured recovery window.

Incident notes:
- If GPU memory pressure exceeds the contract threshold, reduce concurrency before changing models.
- If both endpoints fail, keep the workspace in read-only AI mode and surface a platform incident.