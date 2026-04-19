# Ollama Routing Policy

Routing standard:
- Primary endpoint: `http://192.168.168.42:11434`
- Fallback endpoint: `http://192.168.168.31:11434`
- Strategy: health-primary-fallback with automatic failback after recovery

Health policy:
- Liveness: `GET /api/version`
- Readiness: `GET /api/tags`
- Warm-state checks: required models must remain loaded or loadable on the active endpoint
- GPU memory pressure threshold: 85 percent on `.42`

Failover rules:
- Trigger on health failure, timeout beyond policy threshold, or GPU pressure breach.
- Keep user sessions running during endpoint changes.
- Fallback may substitute lower-cost models when capacity protection requires it.

Capacity guardrails:
- Per-model concurrency limits are defined in `config/ollama-integration-contract.yml`.
- Global request-rate protection prevents GPU starvation.
- Overload behavior is queue, then downgrade, then reject.

Rollout:
- Canary migration stages are 10 percent, 50 percent, then 100 percent.
- Roll back when error rate, latency regression, or safety incidents cross thresholds.