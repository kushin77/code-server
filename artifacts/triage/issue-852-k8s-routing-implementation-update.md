## Status Update: Kubernetes/container log-to-issue routing implemented

Implemented workload-aware Kubernetes/container routing in the shared triage engine:

- Added Kubernetes-focused Loki query channel in `.github/workflows/error-triage.yml`:
  - Targets `kubelet|kubernetes|containerd|docker|cadvisor` streams.
  - Matches crash-loop, scheduling, readiness/liveness, image-pull, and runtime-policy signals.
- Added Kubernetes signal taxonomy classification:
  - `runtime`, `scheduling`, `health`, `image-pull`, `runtime-policy` (plus `unclassified` fallback).
- Added k8s context extraction into issue templates:
  - Namespace, service, pod, container, and last-known-good image/tag context fields are emitted in issue body/update comments.
- Added source-aware labels:
  - `source:kubernetes` plus `k8s:<signal-class>` when classified.
- Preserved/create-or-update dedup behavior:
  - Existing fingerprint marker routing (`error-triage-fingerprint`) remains the duplicate suppression mechanism.
- Added config support in `config/error-triage-config.yml`:
  - Kubernetes query under Loki sources.
  - Kubernetes issue template label profile (`source:kubernetes`, `infrastructure`, `{severity}`).

Acceptance mapping:
- Workload classification: implemented with explicit k8s signal classes.
- Issue templating with namespace/service/container context: implemented.
- Duplicate suppression: existing fingerprint marker dedup remains active.
- Runtime/scheduling/health/crash signal coverage: implemented via query + classifier.

Remaining to close with full evidence:
- Capture and link at least one live Kubernetes-triggered issue instance from a real triage run (explicit runtime evidence).

Keeping this issue open only for runtime evidence capture.