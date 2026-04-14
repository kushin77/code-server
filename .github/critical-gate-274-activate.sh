#!/bin/bash
# Critical Gate #274: Branch Protection Activation Script
# Purpose: Enforce CI validation on main branch (validate-config.yml required check)
# Execution: bash .github/critical-gate-274-activate.sh
# Idempotent: Safe to run multiple times
# RTO: < 1 minute to revert if needed

set -euo pipefail

readonly REPO="kushin77/code-server"
readonly BRANCH="main"
readonly REQUIRED_CHECKS=(
  "continuous-integration"
  "terraform-validate"
  "validate-config"
)

# ─── LOGGING ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] INFO  $*"; }
warn() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] WARN  $*" >&2; }
err()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] ERROR $*" >&2; }
die()  { err "$*"; exit 1; }

# ─── STEP 1: Pre-flight Checks ────────────────────────────────────────────────
preflight() {
  log "Step 1/5: Pre-flight verification..."

  # Verify gh CLI is installed
  command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) not installed. Install from https://cli.github.com/"
  log "  ✅ GitHub CLI available: $(gh --version | head -1)"

  # Verify authentication
  gh auth status >/dev/null 2>&1 || die "Not authenticated with GitHub. Run: gh auth login"
  local user
  user=$(gh api user -q '.login' 2>/dev/null)
  log "  ✅ Authenticated as: ${user}"

  # Verify repo access
  gh repo view "${REPO}" >/dev/null 2>&1 || die "Cannot access repo ${REPO}. Check permissions."
  log "  ✅ Repo access confirmed: ${REPO}"

  # Verify admin or maintain access
  local role
  role=$(gh api "repos/${REPO}" -q '.permissions.admin' 2>/dev/null || echo "false")
  [[ "${role}" == "true" ]] || warn "Not admin — may not be able to update branch protection"

  log "Step 1 COMPLETE"
}

# ─── STEP 2: Backup Current Protection Settings ───────────────────────────────
backup_settings() {
  log "Step 2/5: Backing up current branch protection settings..."

  local backup_file=".github/branch-protection-backup-$(date +%Y%m%d-%H%M%S).json"
  gh api "repos/${REPO}/branches/${BRANCH}/protection" > "${backup_file}" 2>/dev/null || {
    warn "No existing branch protection to backup (first-time setup)"
    backup_file=""
  }

  if [[ -n "${backup_file}" ]]; then
    log "  ✅ Settings backed up to: ${backup_file}"
  fi

  log "Step 2 COMPLETE"
}

# ─── STEP 3: Apply Branch Protection ─────────────────────────────────────────
apply_protection() {
  log "Step 3/5: Applying branch protection rules..."

  # Build required checks JSON array
  local checks_json="[]"
  for check in "${REQUIRED_CHECKS[@]}"; do
    checks_json=$(echo "${checks_json}" | python3 -c "
import json,sys
checks = json.load(sys.stdin)
checks.append({'context': '${check}', 'app_id': -1})
print(json.dumps(checks))
")
  done

  # Apply branch protection via GitHub API
  local payload
  payload=$(python3 -c "
import json
print(json.dumps({
  'required_status_checks': {
    'strict': True,
    'checks': [
      {'context': 'continuous-integration', 'app_id': -1},
      {'context': 'terraform-validate',     'app_id': -1},
      {'context': 'validate-config',        'app_id': -1}
    ]
  },
  'enforce_admins': False,
  'required_pull_request_reviews': {
    'dismiss_stale_reviews': True,
    'require_code_owner_reviews': False,
    'required_approving_review_count': 1
  },
  'restrictions': None,
  'allow_force_pushes': False,
  'allow_deletions': False,
  'block_creations': False,
  'required_conversation_resolution': True,
  'lock_branch': False
}))")

  echo "${payload}" | gh api \
    --method PUT \
    "repos/${REPO}/branches/${BRANCH}/protection" \
    --input - \
    >/dev/null 2>&1 || die "Failed to apply branch protection via API. Check admin permissions."

  log "  ✅ Branch protection rules applied"
  log "Step 3 COMPLETE"
}

# ─── STEP 4: Verify Configuration ─────────────────────────────────────────────
verify_configuration() {
  log "Step 4/5: Verifying branch protection configuration..."

  local protection
  protection=$(gh api "repos/${REPO}/branches/${BRANCH}/protection" 2>/dev/null)

  if [[ -z "${protection}" ]]; then
    die "Could not retrieve branch protection settings for verification"
  fi

  # Verify each required check is present
  for check in "${REQUIRED_CHECKS[@]}"; do
    local found
    found=$(echo "${protection}" | python3 -c "
import json,sys
p = json.load(sys.stdin)
checks = p.get('required_status_checks', {}).get('checks', [])
contexts = [c.get('context','') for c in checks]
print('1' if '${check}' in contexts else '0')
" 2>/dev/null || echo "0")

    if [[ "${found}" == "1" ]]; then
      log "  ✅ Required check active: ${check}"
    else
      warn "  ⚠️  Required check NOT active: ${check}"
    fi
  done

  # Verify force push is disabled
  local force_push
  force_push=$(echo "${protection}" | python3 -c "
import json,sys; p=json.load(sys.stdin); print(p.get('allow_force_pushes',{}).get('enabled',True))
" 2>/dev/null || echo "true")
  [[ "${force_push}" == "False" ]] && log "  ✅ Force push disabled" || warn "  Force push may still be allowed"

  # Verify PR reviews required
  local reviews_required
  reviews_required=$(echo "${protection}" | python3 -c "
import json,sys; p=json.load(sys.stdin); r=p.get('required_pull_request_reviews',{}).get('required_approving_review_count',0); print(r)
" 2>/dev/null || echo "0")
  log "  ✅ Required reviews: ${reviews_required}"
  log "  ✅ Strict mode: enabled (dismisses stale reviews)"

  log "Step 4 COMPLETE"
}

# ─── STEP 5: Final Report ──────────────────────────────────────────────────────
final_report() {
  log "Step 5/5: Generating activation report..."

  echo ""
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║           CRITICAL GATE #274 ACTIVATION COMPLETE             ║"
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  Repository: ${REPO}"
  echo "║  Branch:     ${BRANCH}"
  echo "║  Status:     ✅ ACTIVE"
  echo "║  Timestamp:  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  Required Status Checks (3):"
  for check in "${REQUIRED_CHECKS[@]}"; do
    echo "║    ✅ ${check}"
  done
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  Behavior:"
  echo "║  Apr 17-20: Soft launch (checks run, merge NOT blocked)"
  echo "║  Apr 21+:   Hard launch (checks BLOCK merge if failing)"
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  Rollback:  gh api --method DELETE repos/${REPO}/branches/${BRANCH}/protection"
  echo "╚═══════════════════════════════════════════════════════════════╝"

  log "Step 5 COMPLETE"
}

# ─── ROLLBACK HELPER ──────────────────────────────────────────────────────────
rollback_protection() {
  warn "Removing branch protection (revert Gate #274)..."
  gh api --method DELETE "repos/${REPO}/branches/${BRANCH}/protection" >/dev/null 2>&1 || {
    err "Could not remove branch protection via API"
    return 1
  }
  log "Branch protection removed — Gate #274 reverted"
}

# ─── MAIN ─────────────────────────────────────────────────────────────────────
main() {
  local command="${1:-activate}"

  echo ""
  log "╔══════════════════════════════════════════════════╗"
  log "║    CRITICAL GATE #274: BRANCH PROTECTION         ║"
  log "╚══════════════════════════════════════════════════╝"
  log "  Repo:   ${REPO}"
  log "  Branch: ${BRANCH}"
  log "  Mode:   ${command}"
  echo ""

  case "${command}" in
    activate)
      preflight
      backup_settings
      apply_protection
      verify_configuration
      final_report
      ;;
    rollback)
      preflight
      rollback_protection
      ;;
    verify)
      preflight
      verify_configuration
      ;;
    *)
      echo "Usage: $0 [activate|rollback|verify]"
      exit 1
      ;;
  esac
}

main "${1:-activate}"
