#!/usr/bin/env python3
"""Add Purpose/Summary metadata to docs missing it."""
import re
import sys
from pathlib import Path

REPO = Path("/mnt/c/code-server-enterprise")

# Files that need Purpose metadata added
FAILING_DOCS = [
    "docs/monitoring/ALERT-CONFIGURATION-PRODUCTION.md",
    "docs/ops/ephemeral-shadow-replay-runbook.md",
    "docs/runbooks/RBAC-ENFORCEMENT-RUNBOOK.md",
    "docs/runbooks/backup-recovery.md",
    "docs/runbooks/caddy-down.md",
    "docs/runbooks/certificate-renewal.md",
    "docs/runbooks/cloudflare-trace-correlation.md",
    "docs/runbooks/code-server-down.md",
    "docs/runbooks/container-restart-investigation.md",
    "docs/runbooks/disk-full.md",
    "docs/runbooks/disk-space-cleanup.md",
    "docs/runbooks/dual-host-restart-harvest.md",
    "docs/runbooks/error-rate-high.md",
    "docs/runbooks/full-redeploy-certification.md",
    "docs/runbooks/high-latency.md",
    "docs/runbooks/oauth-login-failure-recovery.md",
    "docs/runbooks/ollama-performance-investigation.md",
    "docs/runbooks/postgresql-down.md",
    "docs/runbooks/postgresql-replication-lag.md",
    "docs/runbooks/qa-coverage-phase-2.md",
    "docs/runbooks/vpn-gated-e2e-testing.md",
    "docs/runbooks/workspace-set-restore-failure.md",
    "docs/security/THREAT-MODEL-2026-04-19.md",
    "docs/security/cloudflare-access-warp-zero-trust.md",
    "docs/security/cloudflare-edge-security-control-matrix.md",
    "docs/security/session-provenance-contract.md",
    "docs/session-bootstrap-enforcement-756.md",
    "docs/session-broker/SESSION-PROVENANCE-CONTRACT.md",
    "docs/shared-workspace-acl-754.md",
    "docs/slos/code-server.md",
]

PURPOSE_RE = re.compile(r"^(?:\*\*Purpose\*\*|Purpose:|## Scope|## Summary)", re.MULTILINE)
H1_RE = re.compile(r"^# ", re.MULTILINE)


def first_non_empty_line(text):
    for line in text.splitlines():
        if line.strip():
            return line
    return ""


def add_purpose_to_doc(path_str):
    p = REPO / path_str
    if not p.exists():
        print(f"SKIP (not found): {path_str}")
        return

    text = p.read_text(encoding="utf-8")
    first_25 = "\n".join(l for l in text.splitlines()[:25] if l.strip())

    if PURPOSE_RE.search(first_25):
        print(f"SKIP (already has purpose): {path_str}")
        return

    # Find title from H1 or first line
    h1_match = H1_RE.search(text)
    if h1_match:
        title_line = text[h1_match.start():].splitlines()[0]
        title = title_line.lstrip("# ").strip()
    else:
        title = p.stem.replace("-", " ").title()

    # Build a one-line summary from the title
    summary_text = f"\n**Purpose**: {title} runbook — operational procedure for {p.stem.replace('-', ' ')} response.\n"

    # If there's an H1 title at the very start, insert after that line
    if h1_match and h1_match.start() < 200:
        insert_pos = h1_match.start() + len(text[h1_match.start():].splitlines()[0]) + 1
        new_text = text[:insert_pos] + summary_text + text[insert_pos:]
    else:
        # No H1 title or it's too far in; prepend H1 + summary
        new_text = f"# {title}\n{summary_text}\n" + text

    p.write_text(new_text, encoding="utf-8")
    print(f"FIXED: {path_str}")


for doc in FAILING_DOCS:
    try:
        add_purpose_to_doc(doc)
    except Exception as e:
        print(f"ERROR {doc}: {e}", file=sys.stderr)

print("Done.")
