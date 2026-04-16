# GitHub Issue Closure Procedure - Phase 1

**Purpose**: Close 7 duplicate GitHub issues that have been consolidated into 3 canonical issues.

**Status**: READY TO EXECUTE (requires admin rights)

---

## Issues to Close

### Portal & Service Catalog Duplicates (→ #385)
- #386 - Service Discovery Portal v1
- #389 - Portal RBAC Configuration
- #391 - Service Catalog UI
- #392 - Portal Database Schema

### Telemetry & Observability Duplicates (→ #377)
- #395 - Observability Phase 2: Advanced Tracing
- #396 - Observability Phase 3: ML-Powered Anomaly Detection
- #397 - Observability Phase 4: Predictive Alerting

### Why These Are Duplicates

Phase 1 consolidation identified that multiple issues covered overlapping scope:

1. **Portal Issues (#386, #389, #391, #392)**: All addressed by single canonical issue #385
   - Service discovery, RBAC, catalog, database - all implemented together

2. **Telemetry Issues (#395, #396, #397)**: Deferred to later phases
   - Phase 2-4 features not in Phase 1 scope
   - Consolidated into epic #377 for future planning

---

## How to Close Issues

### Option 1: Automated Script (Recommended)

**Linux/macOS**:
```bash
bash scripts/close-duplicate-issues.sh
```

**Windows**:
```batch
scripts\close-duplicate-issues.bat
```

**Requirements**:
- GitHub CLI installed: https://cli.github.com
- Authenticated: `gh auth login`
- Admin rights to kushin77/code-server

### Option 2: GitHub Web UI (Manual)

1. Go to https://github.com/kushin77/code-server/issues
2. For each issue (#386, #389, #391, #392, #395, #396, #397):
   - Click on the issue
   - Click "Close as..."
   - Select "Duplicate"
   - Link to canonical issue (#385 or #377)
   - Confirm closure

### Option 3: GitHub CLI Commands (One-by-One)

```bash
# Install GitHub CLI if needed
# https://cli.github.com

# Authenticate
gh auth login

# Close portal duplicates
gh issue close 386 --repo kushin77/code-server --reason duplicate
gh issue close 389 --repo kushin77/code-server --reason duplicate
gh issue close 391 --repo kushin77/code-server --reason duplicate
gh issue close 392 --repo kushin77/code-server --reason duplicate

# Close telemetry duplicates
gh issue close 395 --repo kushin77/code-server --reason duplicate
gh issue close 396 --repo kushin77/code-server --reason duplicate
gh issue close 397 --repo kushin77/code-server --reason duplicate
```

---

## Verification

After closing, verify:

```bash
# Check that issues are closed
gh issue list --repo kushin77/code-server --state closed | grep -E "386|389|391|392|395|396|397"

# Confirm canonical issues are still open
gh issue view 385 --repo kushin77/code-server  # Portal
gh issue view 377 --repo kushin77/code-server  # Telemetry
gh issue view 382 --repo kushin77/code-server  # IAM
```

---

## What Was Already Done (No Action Needed)

✅ Consolidation comments posted to all 10 issues (#386, #389, #391, #392, #395, #396, #397, #385, #377, #382)
✅ Consolidation rationale documented
✅ Phase 1 implementation completed and committed
✅ Deployment procedures documented

**Still Needed**:
- Close the 7 duplicate issues (this procedure)
- User to execute closure with admin rights

---

## Timeline

**Phase 1 Delivery**: April 15-16, 2026 ✅ (Complete)
**Issue Closure**: April 16-17, 2026 (Awaiting admin execution)
**Deployment**: Immediate or May 1-31, 2026 (Ready to go)

---

## Questions?

Refer to GitHub issue consolidation comments for rationale:
- #385 (Portal) - consolidates #386, #389, #391, #392
- #377 (Telemetry) - consolidates #395, #396, #397
- #382 (IAM) - no duplicates

All comments include implementation status and links to Phase 1 code.
