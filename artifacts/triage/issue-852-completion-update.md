## Status update for #852 (implementation completed)

Implemented and validated a dedicated Kubernetes/container log-to-issue routing pipeline with explicit k8s taxonomy, workload context, and deduplicated issue lifecycle.

What was added:
- `scripts/ops/kubernetes-log-triage.sh`
  - Ingests Kubernetes events from JSONL/JSON payloads (or `KUBERNETES_LOG_EVENTS_B64`).
  - Classifies signals into: `runtime`, `scheduling`, `health`, `image-pull`, `runtime-policy`.
  - Applies severity mapping (`P1` for critical classes; threshold-based routing for non-critical).
  - Computes deterministic fingerprints and performs create-or-update issue lifecycle.
  - Emits namespace/service/pod/container/last-known-image context in issue bodies.
- `.github/workflows/kubernetes-log-triage.yml`
  - Scheduled every 15 minutes and manually runnable.
  - Routes payload-backed Kubernetes events via the new triage script.
  - Supports dry-run mode.
- `scripts/README.md`
  - Added script catalog entry for `kubernetes-log-triage.sh`.

Validation evidence:
- `bash -n scripts/ops/kubernetes-log-triage.sh` passed.
- Dry-run with representative Kubernetes sample events produced actionable deduped fingerprints:
  - `P1 runtime` (CrashLoopBackOff-style signal)
  - `P1 scheduling` (FailedScheduling-style signal)
  - `P2 health` routed on sustained threshold (3 occurrences)

Conclusion:
- #852 is ready to close: explicit Kubernetes signal taxonomy, workload-aware templates, and duplicate-suppressed issue routing are now wired end-to-end.