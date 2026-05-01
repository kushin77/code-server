# GitLab Integration Strategy

**Version**: 1.0  
**Date**: April 25, 2026  
**Status**: ACTIVE  

---

## Strategy Overview

This document outlines how kushin77/code-server integrates with GitLab for:
1. **Source Control Mirror** — Read-only copy of GitHub repository
2. **Issue Synchronization** — Bi-directional issue tracking
3. **Governance Compliance** — Unified project governance across platforms

---

## Architecture

### Deployment Model: GitHub-Centric with GitLab Mirror

```
GitHub (Source of Truth)
  ├─ Issues: Authoritative
  ├─ PRs: Authoritative  
  └─ Code: Primary

GitLab (Secondary Mirror)
  ├─ Issues: Synced from GitHub (read-only)
  ├─ PRs: Manual linking only
  └─ Code: Cloned repository
```

### Why GitLab?

1. **Enterprise Compatibility** — GitLab supports self-hosted deployments
2. **CI/CD Flexibility** — Works with on-prem runners
3. **Alternative VCS** — Reduces GitHub single-point-of-failure
4. **Compliance** — Support for regulated industries (HIPAA, PCI-DSS)
5. **Cost** — Self-hosted GitLab has no per-seat charges

---

## Issue Synchronization

### One-Way Sync: GitHub → GitLab

**Direction**: GitHub is authoritative source  
**Frequency**: Every 1 hour via scheduled workflow  
**Conflicts**: GitHub always wins (overwrites GitLab)

#### Sync Rules

| GitHub State | GitLab Action | Notes |
|--------------|---------------|-------|
| Open issue | Create/update issue | Title, description, labels |
| Issue with PR link | Add comment with PR URL | Link to GitHub PR |
| Closed issue | Mark as "wontfix" + archive | Closes loop |
| Deleted issue | Delete in GitLab | Rare event |
| Label: P0 | Add label: emergency | Severity mapping |
| Label: P1 | Add label: urgent | Severity mapping |
| Label: blocked | Add comment: "BLOCKED" | Notification |

#### Sync Metadata

```json
{
  "github": {
    "url": "https://github.com/kushin77/code-server/issues/1234",
    "number": 1234,
    "created_at": "2026-04-25T03:00:00Z",
    "updated_at": "2026-04-25T03:30:00Z",
    "sync_token": "github_issue_1234_abc123"
  }
}
```

---

## GitLab Configuration

### Project Setup

```
GitLab Instance: https://gitlab.com (or self-hosted)
Project: kushin77/code-server (private mirror)
Visibility: Internal (team only)
CI/CD: Disabled (mirror only)
Merge Requests: Disabled (read-only)
```

### Environment Variables

```bash
# CI/CD secrets (GitHub Actions)
GITLAB_INSTANCE=https://gitlab.com
GITLAB_TOKEN=glpat-xxxxx (GitLab personal access token)
GITLAB_PROJECT_ID=12345678
GITLAB_PROJECT_PATH=kushin77/code-server

# Sync configuration
SYNC_ENABLED=true
SYNC_FREQUENCY_MINUTES=60
SYNC_BATCH_SIZE=100
SYNC_RETRY_COUNT=3
```

---

## Sync Process (IaC & Idempotent)

### Step 1: Fetch All GitHub Issues

```bash
gh issue list --limit 10000 --repo kushin77/code-server \
  --json number,title,body,state,labels,createdAt,updatedAt \
  > /tmp/github_issues.json
```

### Step 2: Check Existing GitLab Issues

```bash
curl -s https://gitlab.com/api/v4/projects/$GITLAB_PROJECT_ID/issues?per_page=200 \
  --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  > /tmp/gitlab_issues.json
```

### Step 3: Diff & Sync

- For each GitHub issue:
  - If not in GitLab: Create
  - If in GitLab + different: Update  
  - If closed in GitHub: Mark as "wontfix" in GitLab
  - If state matches: Skip (idempotent)

### Step 4: Audit & Verify

- Count synced issues
- Verify no data loss
- Log sync results

---

## Backup & Recovery

### Automated Backups

```bash
# Daily backup of GitLab issues to S3
gitlab-backup.sh --project=$GITLAB_PROJECT_ID --target=s3://backups/gitlab/

# Weekly backup to local NAS
gitlab-backup.sh --project=$GITLAB_PROJECT_ID --target=/nas/backups/gitlab/
```

### Recovery Procedure

```bash
# 1. Restore from backup
gitlab-restore.sh --backup=s3://backups/gitlab/backup-2026-04-25.tar.gz

# 2. Verify data integrity  
gitlab-verify.sh --project=$GITLAB_PROJECT_ID

# 3. Re-sync with GitHub
gitlab-sync.sh --force-full
```

---

## Governance & Compliance

### Data Privacy

- ✅ GitLab instance secured with 2FA + SSH keys only
- ✅ Issue data encrypted at rest (if self-hosted)
- ✅ API tokens rotated quarterly
- ✅ Access logs retained for 1 year

### Audit Trail

Every sync operation logged:
```json
{
  "timestamp": "2026-04-25T03:00:00Z",
  "action": "sync_complete",
  "github_issues": 42,
  "gitlab_issues_created": 5,
  "gitlab_issues_updated": 3,
  "sync_duration_seconds": 23,
  "status": "success",
  "actor": "github-actions[bot]"
}
```

### Disaster Recovery

- **RTO** (Recovery Time Objective): 1 hour
- **RPO** (Recovery Point Objective): 1 hour (sync frequency)
- **Backup Retention**: 90 days
- **Failover**: Manual (GitLab → GitHub reference)

---

## Monitoring & Alerts

### Health Checks

```bash
# Every 30 minutes
gitlab-health.sh --check-api --check-sync-lag --check-storage

# Alerts if:
# - API response > 10s
# - Sync lag > 90 minutes  
# - Storage < 1GB free
```

### Metrics Tracked

| Metric | Alert Threshold | Action |
|--------|-----------------|--------|
| Sync latency | > 90 min | Warn + Retry |
| Failed syncs | > 3 consecutive | Page on-call |
| Data mismatch | > 0 | Investigate immediately |
| API errors | > 10% | Rate limit check |

---

## Troubleshooting

### Common Issues

**Issue: "authentication required"**
```bash
# Verify token
curl -s https://gitlab.com/api/v4/user --header "PRIVATE-TOKEN: $GITLAB_TOKEN"

# Rotate token if expired
gitlab-token-rotate.sh
```

**Issue: "sync lag > 90 minutes"**
```bash
# Force immediate sync
gitlab-sync.sh --force

# Check API status
gitlab-health.sh --verbose
```

**Issue: "data mismatch in GitLab"**
```bash
# Full re-sync (deletes all, re-creates)
gitlab-sync.sh --full-reset

# Verify integrity
gitlab-verify.sh --detailed
```

---

## Future Enhancements

1. **Bi-directional Sync** — Allow GitLab edits (GitHub still authoritative)
2. **PR Mirroring** — Sync pull requests to GitLab merge requests
3. **Release Automation** — Auto-create GitLab releases from GitHub tags
4. **GitLab Projects** — Automated project board sync
5. **Webhook Integration** — Real-time sync instead of hourly polling

---

## Related Documentation

- `scripts/integration/gitlab-sync.sh` — Sync automation script
- `.github/workflows/gitlab-sync.yml` — CI/CD workflow
- `docs/operations/DEPLOYMENT-RUNBOOK.md` — Deployment procedures
- `docs/security/SECURITY-GUIDE.md` — Security & access control

