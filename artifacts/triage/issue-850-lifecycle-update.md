## Status Update: Dedup/routing lifecycle advanced (reopen on recurrence now implemented)

Implemented additional lifecycle behavior in `.github/workflows/error-triage.yml` to improve board hygiene and canonical issue continuity:

- Fingerprint matching now checks all issue states (`open` + `closed`) for existing canonical triage issues.
- On recurrence against a closed fingerprinted issue:
  - The issue is automatically reopened.
  - A recurrence comment is appended with current severity/source/context metadata.
- Existing open issue behavior remains create-or-update (no duplicate issue spam for same fingerprint).

Related progress in this pass:
- Cloudflare source-aware routing added (query coverage, severity mapping, source labels, correlation ID extraction, remediation hints).
- Kubernetes/container source-aware routing added (signal taxonomy + namespace/service/pod/container + last-known-good context).

What this resolves for #850:
- Event fingerprinting and canonical issue linking: reinforced.
- Duplicate suppression for repeated incidents: reinforced.
- Reopen lifecycle on recurrence: now implemented.

Remaining blocker before closure:
- Auto-close behavior still needs an active policy execution step tied to sustained no-recurrence/remediation state (config has `auto_close_days`, but workflow-level close automation is not yet wired in this same path).

Keeping #850 open only for that remaining auto-close lifecycle execution gap.