# Ollama GPU Replica Operations

Objective:
- Keep GPU-class inference on 192.168.168.42 with seamless failover to 192.168.168.31.

Operational checks:
- Verify `.42` health with `curl http://192.168.168.42:11434/api/version`.
- Verify readiness with `curl http://192.168.168.42:11434/api/tags`.
- If `.42` is unhealthy, confirm startup exported `OLLAMA_FALLBACK_ENDPOINT=http://192.168.168.31:11434`.

Failover drill:
1. Simulate `.42` outage or timeout.
2. Run `scripts/ollama-init.sh status` and confirm it can reach the fallback endpoint.
3. Confirm model pulls continue against `.31` without credential prompts.
4. Restore `.42` and verify automatic failback after the configured recovery window.

Incident notes:
- If GPU memory pressure exceeds the contract threshold, reduce concurrency before changing models.
- If both endpoints fail, keep the workspace in read-only AI mode and surface a platform incident.