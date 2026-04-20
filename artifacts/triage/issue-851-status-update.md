Status update for #851 (implementation completed):

I implemented and validated a Cloudflare-specific log-to-issue routing pipeline with source-aware severity mapping, sustained-failure thresholds, and fingerprint-based deduplication.

What was added:
- scripts/ops/cloudflare-log-triage.sh
  - Ingests Cloudflare events from JSONL/JSON payloads.
  - Classifies signals into edge/auth/TLS/WAF/rate-limit/tunnel classes.
  - Applies severity mapping (P1 for critical auth/TLS/tunnel/edge classes; sustained-threshold routing for non-critical classes).
  - Computes deterministic fingerprints and performs create-or-update issue lifecycle.
  - Includes source context, occurrence window, timestamps, correlation IDs, and remediation hints in issue content.
- .github/workflows/cloudflare-log-triage.yml
  - Scheduled every 15 minutes and manually runnable.
  - Reads Cloudflare event payload from secret `CLOUDFLARE_LOG_EVENTS_B64`.
  - Routes signals via scripts/ops/cloudflare-log-triage.sh with issue-write permissions.
- scripts/README.md
  - Added script catalog entry for cloudflare-log-triage.sh.

Validation evidence:
- bash -n scripts/ops/cloudflare-log-triage.sh (syntax check passed)
- Dry-run with representative sample events produced actionable deduped fingerprints:
  - P1 TLS signal (count=1)
  - P2 WAF signal (count=3, sustained threshold)
  - P1 Tunnel signal (count=1)
  - P1 Auth signal (count=1)

Conclusion:
- #851 is ready to close: Cloudflare-specific classification, dedup suppression, and issue routing are now wired end-to-end.