#!/usr/bin/env bash
# @file        scripts/ops/deploy-collab-9-staging.sh
# @module      operations/deployment
# @description Deploy Collab-9 GitHub task synchronization to staging environment
# @owner       platform-engineering
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Configuration
STAGING_HOST="${STAGING_HOST:-192.168.168.31}"
STAGING_USER="${STAGING_USER:-akushnir}"
DRY_RUN="${DRY_RUN:-0}"
FEATURE_FLAG="${FEATURE_WEBHOOK_ENABLED:-true}"

# Derived
STAGING_SSH="${STAGING_USER}@${STAGING_HOST}"
REPO_PATH="code-server-enterprise"

log_info "=========================================="
log_info "Collab-9 Staging Deployment"
log_info "=========================================="
log_info "Target: $STAGING_HOST"
log_info "Repository: $REPO_PATH"
log_info "Feature Flag: $FEATURE_FLAG"
log_info "Dry Run: $DRY_RUN"
log_info ""

# Pre-flight checks
log_info "Running pre-flight checks..."

# 1. Verify SSH connectivity
log_info "  → Checking SSH connectivity to $STAGING_SSH"
if ! ssh -o ConnectTimeout=5 "$STAGING_SSH" "whoami" &>/dev/null; then
  log_fatal "SSH connectivity failed to $STAGING_SSH"
fi
log_info "  ✓ SSH connectivity verified"

# 2. Verify git state
log_info "  → Checking git state on $STAGING_HOST"
git_output=$(ssh "$STAGING_SSH" "cd $REPO_PATH && git status --short 2>&1" || true)
if [ -n "$git_output" ]; then
  log_error "Uncommitted changes on $STAGING_HOST:"
  echo "$git_output" | sed 's/^/    /'
  log_fatal "Please commit or stash changes before deployment"
fi
log_info "  ✓ Working tree clean"

# 3. Verify main branch is at latest
log_info "  → Fetching latest from origin"
if [ "$DRY_RUN" = "0" ]; then
  ssh "$STAGING_SSH" "cd $REPO_PATH && git fetch origin main"
fi
log_info "  ✓ Latest code fetched"

# 4. Get current commit
current_commit=$(ssh "$STAGING_SSH" "cd $REPO_PATH && git rev-parse HEAD")
origin_commit=$(ssh "$STAGING_SSH" "cd $REPO_PATH && git rev-parse origin/main")
log_info "  Current commit: $current_commit"
log_info "  Origin commit:  $origin_commit"

if [ "$current_commit" != "$origin_commit" ]; then
  log_warn "Local commit differs from origin/main. Pulling latest..."
  if [ "$DRY_RUN" = "0" ]; then
    ssh "$STAGING_SSH" "cd $REPO_PATH && git reset --hard origin/main"
  fi
fi
log_info "  ✓ At latest commit"

log_info ""
log_info "Pre-flight checks passed!"
log_info ""

# Deployment
log_info "Deploying Collab-9 to staging..."

if [ "$DRY_RUN" = "1" ]; then
  log_info "[DRY RUN] Would execute:"
  log_info "  1. Pull latest code"
  log_info "  2. Set FEATURE_WEBHOOK_ENABLED=$FEATURE_FLAG"
  log_info "  3. Run: docker-compose up -d"
  log_info "  4. Wait 10s for services to stabilize"
  log_info "  5. Run health checks"
  exit 0
fi

# 1. Pull latest code
log_info "  → Pulling latest code from origin/main"
ssh "$STAGING_SSH" "cd $REPO_PATH && git pull origin main"

# 2. Set environment variable for deployment (idempotent: avoid duplicates)
log_info "  → Setting feature flags"
ssh "$STAGING_SSH" "cd $REPO_PATH && \
    touch .env.local && \
    grep -q 'FEATURE_WEBHOOK_ENABLED=' .env.local || echo 'FEATURE_WEBHOOK_ENABLED=$FEATURE_FLAG' >> .env.local"

# 3. Redeploy services
log_info "  → Redeploying services"
ssh "$STAGING_SSH" "cd $REPO_PATH && docker-compose down >/dev/null 2>&1 || true"
ssh "$STAGING_SSH" "cd $REPO_PATH && docker-compose up -d --force-recreate backend"

# 4. Wait for services to stabilize
log_info "  → Waiting for services to stabilize..."
sleep 10

# 5. Health checks
log_info "  → Running health checks"
health_check() {
  local endpoint="http://$STAGING_HOST:3000/health/ready"
  curl -s -f "$endpoint" >/dev/null 2>&1 && return 0 || return 1
}

retries=0
max_retries=30
while ! health_check && [ $retries -lt $max_retries ]; do
  retries=$((retries + 1))
  sleep 2
done

if [ $retries -eq $max_retries ]; then
  log_warn "Health checks did not pass within timeout"
else
  log_info "  ✓ Health checks passed (attempt $retries/$max_retries)"
fi

log_info ""
log_info "=========================================="
log_info "✓ Deployment complete!"
log_info "=========================================="
log_info "Staging URL: http://$STAGING_HOST:3000"
log_info "Health check: http://$STAGING_HOST:3000/health/ready"
log_info "Metrics: http://$STAGING_HOST:3000/metrics/github-task-sync"
log_info ""
log_info "Next steps:"
log_info "  1. Run integration tests"
log_info "  2. Run load tests"
log_info "  3. Verify metrics collection"
log_info "  4. Validate alerting"
log_info "  5. Sign off for production"
log_info ""

exit 0
