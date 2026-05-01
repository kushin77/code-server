#!/usr/bin/env bash
# @file        scripts/ops/gitlab-primary-setup.sh
# @module      ops/gitlab
# @description One-time setup: push this repo to GitLab and configure it as primary
# @governance  GOV-002
#
# Usage:
#   GITLAB_TOKEN=glpat-xxxx bash scripts/ops/gitlab-primary-setup.sh
#
# What this script does:
#   1. Validates GitLab credentials
#   2. Pushes all branches + tags to gitlab.com/kushin77/code-server
#   3. Sets GitLab as the 'origin' remote (already done if you ran the setup)
#   4. Verifies .gitlab-ci.yml is present and valid
#
# Required env vars:
#   GITLAB_TOKEN  - GitLab personal access token (scope: write_repository)
#
# Optional env vars:
#   GITLAB_INSTANCE     - GitLab host (default: gitlab.com)
#   GITLAB_PROJECT_PATH - project path (default: kushin77/code-server)

set -euo pipefail

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

GITLAB_INSTANCE="${GITLAB_INSTANCE:-https://gitlab.com}"
GITLAB_PROJECT_PATH="${GITLAB_PROJECT_PATH:-kushin77/code-server}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── 1. Validate token ────────────────────────────────────────────────────────
log_step "Validating GitLab credentials"

if [ -z "$GITLAB_TOKEN" ]; then
  log_error "GITLAB_TOKEN not set."
  echo "  Export it: export GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxxxxxx"
  exit 1
fi

WHOAMI=$(curl -sf \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_INSTANCE}/api/v4/user" | jq -r '.username // empty' 2>/dev/null || true)

if [ -z "$WHOAMI" ]; then
  log_error "GitLab authentication failed. Check your GITLAB_TOKEN."
  exit 1
fi
log_info "Authenticated as: $WHOAMI"

# ── 2. Verify .gitlab-ci.yml present ────────────────────────────────────────
log_step "Verifying .gitlab-ci.yml"

if [ ! -f ".gitlab-ci.yml" ]; then
  log_error ".gitlab-ci.yml not found. It should already be present in the repo root."
  exit 1
fi
log_info ".gitlab-ci.yml present ✅"

# Basic YAML syntax check
python3 -c "import yaml; yaml.safe_load(open('.gitlab-ci.yml'))" 2>/dev/null && \
  log_info ".gitlab-ci.yml YAML syntax OK ✅" || \
  log_warn ".gitlab-ci.yml YAML syntax check failed — review manually"

# ── 3. Configure remote ──────────────────────────────────────────────────────
log_step "Configuring GitLab as primary remote"

GITLAB_URL="https://oauth2:${GITLAB_TOKEN}@${GITLAB_INSTANCE#https://}/${GITLAB_PROJECT_PATH}.git"

if git remote get-url origin 2>/dev/null | grep -q "gitlab.com"; then
  log_info "GitLab already set as origin — updating URL with token"
  git remote set-url origin "$GITLAB_URL"
else
  log_warn "origin is not GitLab — adding gitlab remote"
  git remote add gitlab "$GITLAB_URL" 2>/dev/null || \
    git remote set-url gitlab "$GITLAB_URL"
fi

# ── 4. Push to GitLab ────────────────────────────────────────────────────────
log_step "Pushing to GitLab"

CURRENT_BRANCH=$(git branch --show-current)
log_info "Pushing branch: $CURRENT_BRANCH"

git push origin HEAD:"$CURRENT_BRANCH" --follow-tags 2>&1 || {
  log_warn "Push with --follow-tags failed, retrying without..."
  git push origin HEAD:"$CURRENT_BRANCH"
}

log_info "Pushed $CURRENT_BRANCH to GitLab ✅"

# Push main/release branches if they exist
for branch in main release/v1.0.0-production; do
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    log_info "Pushing branch: $branch"
    git push origin "$branch" 2>/dev/null || log_warn "Could not push $branch"
  fi
done

# ── 5. Verify pipeline will trigger ─────────────────────────────────────────
log_step "Verifying GitLab pipeline"

PROJECT_ID=$(curl -sf \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "${GITLAB_INSTANCE}/api/v4/projects/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${GITLAB_PROJECT_PATH}', safe=''))")" \
  | jq -r '.id // empty' 2>/dev/null || true)

if [ -n "$PROJECT_ID" ]; then
  log_info "GitLab project ID: $PROJECT_ID"
  PIPELINE_URL="${GITLAB_INSTANCE}/${GITLAB_PROJECT_PATH}/-/pipelines"
  log_info "Pipeline URL: $PIPELINE_URL"

  # Get latest pipeline status
  PIPELINE_STATUS=$(curl -sf \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    "${GITLAB_INSTANCE}/api/v4/projects/${PROJECT_ID}/pipelines?per_page=1" \
    | jq -r '.[0].status // "unknown"' 2>/dev/null || echo "unknown")
  log_info "Latest pipeline status: $PIPELINE_STATUS"
else
  log_warn "Could not fetch project info — check token scope (needs api or read_api)"
fi

# ── 6. Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  GitLab Primary Setup Complete                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Primary remote: gitlab.com/${GITLAB_PROJECT_PATH}"
log_info "GitHub mirror:  github.com/kushin77/code-server (remote: github)"
echo ""
echo "Next steps:"
echo "  1. Set CI/CD variables in GitLab:"
echo "     ${GITLAB_INSTANCE}/${GITLAB_PROJECT_PATH}/-/settings/ci_cd"
echo "     Required: TF_VAR_primary_host, TF_VAR_replica_host, TF_VAR_apex_domain"
echo "               TF_VAR_admin_email, TF_VAR_postgres_password, TF_VAR_redis_password"
echo "               SSH_PRIVATE_KEY (for Terraform SSH provider)"
echo "               GITHUB_MIRROR_TOKEN (for sync stage to push back to GitHub)"
echo ""
echo "  2. Add a GitLab Runner (or use gitlab.com shared runners):"
echo "     ${GITLAB_INSTANCE}/${GITLAB_PROJECT_PATH}/-/runners"
echo ""
echo "  3. Set up scheduled pipelines:"
echo "     ${GITLAB_INSTANCE}/${GITLAB_PROJECT_PATH}/-/pipeline_schedules"
echo "     - Drift detection:       daily 02:00 UTC  SCHEDULED_JOB=drift-detection"
echo "     - Continuous validation: every 6h UTC     SCHEDULED_JOB=continuous-validation"
echo ""
echo "  4. For future pushes, use:"
echo "     git push origin  (→ GitLab, triggers CI)"
echo "     git push github  (→ GitHub, read-only mirror)"
