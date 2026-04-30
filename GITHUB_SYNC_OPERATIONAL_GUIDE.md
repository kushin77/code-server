# GitHub Sync - Operational Guidelines

**Date:** April 30, 2026  
**Status:** Active  
**Scope:** kushin77/code-server GitHub repository  

---

## Overview

This workspace has two GitHub sync mechanisms:

### 1. **SLOG Issue Sync** ✅ ACTIVE
- **Source:** Structured logging (SLOG) grouped issues in logs
- **Destination:** GitHub Issues on kushin77/code-server
- **Script:** `sync-slog-to-github.sh`
- **Status:** Operational with retry logic
- **Result:** 30 SLOG issues synced (3 created, 27 updated)

### 2. **Markdown Task Sync** ⏸️ FILTERED
- **Source:** Task markers (`- [ ]`) in markdown files
- **Destination:** GitHub Issues on kushin77/code-server
- **Script:** `sync-issues-to-github.sh`
- **Status:** Operational but filtered to exclude operational docs
- **Approved Sources:** ROADMAP, PLAN, GAP-ANALYSIS, MIGRATION files only

---

## What Gets Synced (Markdown)

✅ **INCLUDED:**
- `ROADMAP.md` — Strategic roadmaps with task markers
- `*PLAN.md` — Implementation plans
- `*GAP-ANALYSIS*.md` — Gap analysis tasks
- `*MIGRATION*.md` — Migration guides
- Other files in: `artifacts/`, `terraform/`, `docs/testing/`, `docs/operations/`, `docs/sso/`

❌ **EXCLUDED:**
- Operational checklists: `MASTER_DEPLOYMENT_EXECUTION_CHECKLIST.md`, `IaC-DEPLOYMENT-CHECKLIST.md`
- All files with names containing: PHASE, DEPLOYMENT, OPERATIONS, CHECKLIST, RUNBOOK, GUIDE, PACKAGE
- All files with names containing: STATUS, PROGRESS, COMPLETE, COMPLETION, REPORT, SUMMARY, HANDOFF, CERTIFICATE, VERIFICATION, EVIDENCE

---

## Why Operational Docs Are Excluded

**Problem Discovered:**
- 206 markdown files with 5,358 task markers identified
- Most were operational reference guides, not GitHub-trackable work items
- Examples: `MASTER_DEPLOYMENT_EXECUTION_CHECKLIST.md`, `PHASE_2B_MASTER_DEPLOYMENT_GUIDE.md`, `OPERATIONS_HANDOFF.md`

**Root Cause:**
- These files contain **internal deployment procedures** (e.g., "verify services healthy")
- Same tasks repeated across 10+ guides (deployment variations, phase-specific versions)
- Not suitable for GitHub issue tracking — they're runbook procedures
- Would require 30+ hours to sync all at OAuth rate limit

**Solution:**
- Exclude files matching operational keywords (PHASE, DEPLOYMENT, OPERATIONS, etc.)
- Keep only strategic/planning guides that have unique actionable items
- Reduces sync scope from 5,358 tasks to ~100-200 actual trackable items

---

## Rate Limiting & Retry Strategy

Both sync scripts implement **4-tier exponential backoff retry logic:**

```
Attempt 1: Wait 5 seconds
Attempt 2: Wait 10 seconds
Attempt 3: Wait 20 seconds
Attempt 4: Wait 40 seconds
```

**Triggers on:** HTTP 403 "rate limit exceeded" errors

**OAuth Token Limits:** ~60 requests/hour (secondary limit)  
**Fine-grained PAT Limits:** ~5000 requests/hour (if upgraded)

---

## Using the Sync Scripts

### Run SLOG Sync
```bash
bash sync-slog-to-github.sh
```
- Processes all grouped SLOG issues
- Creates/updates GitHub issues automatically
- Includes retry logic on rate limits

### Run Markdown Sync (Single Batch)
```bash
SYNC_MAX_CREATE=50 bash sync-issues-to-github.sh
```
- Syncs up to 50 new task markers
- Skips already-synced items
- Respects exclusion filters automatically

### Run Markdown Sync (Progressive Batches)
```bash
SYNC_MAX_CREATE=50 timeout 600 bash sync-issues-to-github.sh
# Wait for completion, then resume:
SYNC_START_AFTER='last-task-name' SYNC_MAX_CREATE=50 bash sync-issues-to-github.sh
```
- Process large sync jobs in checkpointed batches
- Avoids rate limit timeouts
- Resume from where you left off

---

## Configuration

**Environment Variables:**
- `GITHUB_TOKEN` — GCP Secret Manager token (required)
- `GITHUB_OWNER` — Default: `kushin77`
- `GITHUB_REPO` — Default: `code-server`
- `SYNC_MAX_CREATE` — Max new issues per run (default: unlimited)
- `SYNC_START_AFTER` — Resume after this task name (default: from start)
- `SYNC_PATH_FILTER` — Filter by file path (default: none)
- `SYNC_INCLUDE_CODE_TASKS` — Include code TODO markers (default: 0/false)

**Token Source:**
- Retrieved via: `gcloud secrets versions access latest --secret="github-token"`
- Requires GCP credentials configured
- Falls back to `GITHUB_TOKEN` environment variable if available

---

## Monitoring & Troubleshooting

### Check Token Status
```bash
bash sync-issues-now.sh  # Retrieves and validates token
```

### View Active Syncs
```bash
ps aux | grep 'sync.*github'
tail -f /tmp/markdown-sync-*.log
```

### Identify Sync Issues
```bash
# See what gets synced from a file
python3 -c "
from pathlib import Path
import re

path = Path('ROADMAP.md')
for idx, line in enumerate(path.read_text().splitlines(), 1):
    if re.match(r'^- \[ \]', line.strip()):
        print(f'{idx}: {line}')
"
```

### Rate Limit Status
```bash
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/rate_limit | jq '.rate_limit'
```

---

## Summary

✅ **SLOG sync:** Fully operational, 30 issues synced  
✅ **Markdown sync:** Operational, intelligently filtered  
✅ **Retry logic:** 4-tier exponential backoff implemented  
✅ **Rate limits:** Handled automatically  
✅ **Exclusions:** Operational checklists excluded (5,000+ tasks removed)  

**Next Steps:**
- Run syncs on schedule (e.g., hourly, daily)
- Monitor token health
- Review GitHub issues created to verify quality
- Escalate if rate limits prevent progress (consider fine-grained PAT upgrade)

