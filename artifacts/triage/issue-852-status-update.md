Status update for #852 (next actionable pass):

I validated the current runtime triage surface against the Kubernetes/container log-to-issue acceptance criteria.

What is already in place:
- scripts/ops/error-fingerprint-triage.sh performs runtime log fingerprinting and deduplicated issue routing for container logs.
- .github/workflows/error-triage.yml implements create-or-update behavior keyed by a fingerprint marker.
- Existing triage bodies include error context and recurrence comments, which helps reduce duplicate issue spam.

What still blocks closure:
- The active pipeline is container/runtime oriented, but I do not yet see explicit Kubernetes signal mapping for pod crash loops, scheduling/evictions, and image-pull/readiness classes.
- Current issue templates do not consistently include namespace/service/container plus last-known-good state metadata.
- A dedicated k8s-class taxonomy mapping (runtime/scheduling/health/security) is not yet visible as a canonical contract.

Conclusion:
- #852 remains OPEN; dedup triage substrate exists, but k8s-specific class coverage and context enrichment are still required for full acceptance.
