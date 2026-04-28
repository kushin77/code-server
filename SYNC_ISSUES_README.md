# Sync Issues to GitHub

This workspace has two GitHub issue sync paths:

1. Task sync: backlog and task markers to GitHub issues.
2. SLOG sync: grouped warning/error/critical/issue log signals to GitHub issues.

## Task Sync

Two methods to sync local task markers to GitHub Issues.

## Method 1: Using GCP Secret Manager (Recommended)

This automatically retrieves your GitHub token from GCP Secret Manager:

```bash
bash sync-issues-now.sh
```

What it does:
1. Tries `github-token`, then `github-fine-grained-token` from GCP Secret Manager.
2. Scans approved markdown checkboxes and TODO headings.
3. Creates GitHub issues with a `task-sync-source: path:line` marker in the body.
4. Skips tasks that already exist by searching for that source marker.
5. Stops immediately if GitHub starts returning rate-limit errors.

**Prerequisites:**
- ✓ GCP SDK installed
- ✓ Authenticated to GCP: `gcloud auth login --update-adc`
- ✓ GCP project configured: `gcloud config set project purebliss-ghl`
- ✓ Secret accessible: `gcloud secrets list`

## Method 2: Using Manual Token

If you prefer to provide the token manually:

```bash
export GITHUB_TOKEN="your-github-token-here"
bash sync-issues-to-github.sh
```

## Batch Controls

Use environment variables to continue safely after a partial run:

```bash
SYNC_MAX_CREATE=25 bash sync-issues-now.sh
SYNC_PATH_FILTER=ROADMAP.md SYNC_MAX_CREATE=10 bash sync-issues-now.sh
SYNC_START_AFTER='task-sync-source: ROADMAP.md:42' SYNC_MAX_CREATE=25 bash sync-issues-now.sh
```

- `SYNC_MAX_CREATE`: maximum number of new GitHub issues to create in one run.
- `SYNC_PATH_FILTER`: only consider tasks whose source path matches the provided substring.
- `SYNC_START_AFTER`: resume after the first task whose source path, title, or marker matches the provided substring.

## Expected Output

```
Discovered 1633 local tasks
SKIP  [ROADMAP.md] Provision managed K8s cluster (EKS/GKE/AKS - blocked on infrastructure)
CREATE #1957 [ROADMAP.md] Implement global load balancing via Cloudflare/Caddy orchestration
STOP  Reached SYNC_MAX_CREATE=25; ending batch
Summary: created=25 skipped=18 failed=0
```

## Troubleshooting

**"GITHUB_TOKEN not set"**
- Run: `bash sync-issues-now.sh` (uses GCP automatically)
- OR: `export GITHUB_TOKEN=<token> && bash sync-issues-to-github.sh`

**"Failed to retrieve token from GSM"**
- Check GCP authentication: `gcloud auth print-access-token`
- Check project: `gcloud config get-value project`
- Verify secret exists: `gcloud secrets list | grep github`

**"API rate limit exceeded"**
- Wait for the GitHub rate-limit window to reset.
- Retry with a smaller batch: `SYNC_MAX_CREATE=10 bash sync-issues-now.sh`
- Resume from a known point: `SYNC_START_AFTER='task-sync-source: ROADMAP.md:42' bash sync-issues-now.sh`

**"Command 'gcloud' not found"**
- Install GCP SDK: https://cloud.google.com/sdk/docs/install
- OR use Method 2 with manual token

## What Gets Synced

- Markdown tasks: unchecked checkboxes and TODO headings.
- Code tasks: `TODO`, `FIXME`, and `HACK` markers only when `SYNC_INCLUDE_CODE_TASKS=1` is set.
- Duplicate detection: source-marker search using `task-sync-source: path:line`.

## Grouped SLOG Sync

Use this to sync repeated runtime warnings, errors, critical events, and issue-style log entries into one GitHub issue per normalized signature.

### Recommended

```bash
bash sync-slog-now.sh
```

What it does:
1. Uses `GITHUB_TOKEN` from the environment if present.
2. Otherwise tries `github-token`, then `github-fine-grained-token` from GCP Secret Manager.
3. Otherwise falls back to the git credential helper.
4. Scans runtime log files plus markdown incident logs.
5. Groups repeated events by normalized severity plus message signature.
6. Updates an existing GitHub issue when the same signature already exists.
7. Creates a new issue only when that signature has not been triaged yet.

### Manual Token

```bash
export GITHUB_TOKEN="your-github-token-here"
bash sync-slog-to-github.sh
```

### Defaults

```bash
bash sync-slog-now.sh
```

- Runtime sources: `logs/*.log`, `logs/**/*.log`, root `*.log`, `artifacts/**/*.log`
- Markdown incident logs: enabled by default
- Default severities: `warning,error,critical,issue`
- Duplicate detection: `slog-sync-signature: <hash>` marker in the issue body
- Routing: grouped issues are classified into families such as `drift`, `deployment`, `health-checks`, `database`, `docker`, `caddy`, or `runtime-logs`

### Common Overrides

```bash
SLOG_DRY_RUN=1 bash sync-slog-to-github.sh
SLOG_SEVERITIES=error,critical,issue bash sync-slog-now.sh
SLOG_INCLUDE_MARKDOWN_LOGS=0 bash sync-slog-now.sh
SLOG_PATH_FILTER=logs/ bash sync-slog-now.sh
SLOG_MAX_CREATE=5 bash sync-slog-now.sh
```

- `SLOG_DRY_RUN`: print grouped candidates without creating or updating issues.
- `SLOG_SEVERITIES`: override the default severity set.
- `SLOG_INCLUDE_MARKDOWN_LOGS`: set to `0` to exclude markdown incident logs.
- `SLOG_PATH_FILTER`: only consider sources whose path contains the provided substring.
- `SLOG_MAX_CREATE`: cap only new issue creation; existing grouped issues are still updated.

### Expected Output

```text
Discovered 8 grouped slog issue candidate(s).
Updated existing slog issue #2043: [slog][warning] Caddy not available, skipping Caddy drift check
Updated existing slog issue #2048: [slog][warning] Docker daemon not available — skipping Docker Compose drift check
SLOG sync complete. created=0 updated=8 grouped=8
```

## Skipped Paths

These paths are excluded automatically:
- `.git`
- `node_modules`
- `.backups`
- `.bootstrap-state`
- `docs/archive`

## After Sync

1. Check GitHub Issues: https://github.com/kushin77/code-server/issues
2. Review the created issues and note the last source marker processed.
3. Resume with `SYNC_START_AFTER` and a small `SYNC_MAX_CREATE` value if more tasks remain.
4. Reference issues in commits: "Fixes #123"

## Next Steps

1. Run: `SYNC_MAX_CREATE=10 bash sync-issues-now.sh`
2. Increase the batch size only if GitHub rate limits allow it.
3. Use `SYNC_PATH_FILTER` to work file-by-file when needed.
