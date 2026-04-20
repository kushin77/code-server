Status update for #852 (evidence captured, ready to close):

Live runtime evidence has been captured and linked via triage issue #947:

- Evidence issue: #947 ([AUTO-TRIAGE] P1 Kubernetes runtime failure on session-broker sample)
- Includes fingerprint marker: `error-triage-fingerprint:852-sample-runtime-crashloop`
- Includes Kubernetes taxonomy context:
  - Event class: runtime
  - Namespace: code-server
  - Service: session-broker
  - Pod: session-broker-7d94f57f5d-r2q6f
  - Container: session-broker
  - Correlation ID: k8s-rt-20260419-01
  - Last-known-good image context

Acceptance mapping:
- Runtime/scheduling/health/crash class coverage: implemented in workflow and config.
- Namespace/service/pod/container context enrichment: present in emitted issue body/comments.
- Duplicate suppression and canonical issue linkage: present via fingerprint marker path.
- Explicit runtime evidence from routed Kubernetes signal: captured in #947.

Conclusion:
- #852 is now ready to close.