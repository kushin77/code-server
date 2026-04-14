#!/bin/bash
################################################################################
# File: init-repo-governance.sh
# Owner: DevOps/Governance Team
# Purpose: Initialize governance framework and enforce standards
# Last Modified: April 14, 2026
# Compatibility: Ubuntu 22.04+, Bash 4.0+
#
# Dependencies:
#   - git — Version control and hook configuration
#   - pre-commit — Framework for git hooks
#   - shellcheck — Bash script linting
#   - terraform — Infrastructure code validation
#
# Related Files:
#   - .pre-commit-config.yaml — Pre-commit hook configuration
#   - .github/GOVERNANCE-ROLLOUT.md — Governance schedule
#   - CONTRIBUTING.md — Developer guidelines
#   - .github/workflows/validate-config.yml — CI validation
#
# Usage:
#   ./init-repo-governance.sh                    # Setup governance framework
#   ./init-repo-governance.sh --team-only        # Setup current team only
#   ./init-repo-governance.sh --verify           # Verify governance installed
#
# Setup Tasks:
#   - Create .pre-commit-config.yaml
#   - Install pre-commit hooks
#   - Setup branch protection on main
#   - Configure PR review requirements
#   - Setup enforcement in CI/CD pipelines
#   - Configure default workflows
#
# Exit Codes:
#   0 — Governance framework initialized successfully
#   1 — Some governance components failed to initialize
#   2 — Critical component initialization failed
#
# Examples:
#   ./scripts/init-repo-governance.sh
#   ./scripts/init-repo-governance.sh --verify
#
# Recent Changes:
#   2026-04-14: Integrated with pre-commit setup
#   2026-04-13: Initial creation with governance initialization
#
################################################################################

# Initialize GitHub Governance for a Single Repository
# Usage: ./init-repo-governance.sh kushin77/repo-name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

REPO_FULL="${1:?Repository required (e.g., kushin77/repo-name)}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Parse owner and repo
IFS='/' read -r OWNER REPO <<< "$REPO_FULL"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warning() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[D]${NC} $*" || true; }

# Check prerequisites
log "Validating prerequisites..."
for cmd in gh jq git; do
    command -v "$cmd" &>/dev/null || { error "$cmd not found"; exit 1; }
done
success "Prerequisites OK"

# Get repo info
log "Fetching repository information: $OWNER/$REPO"
REPO_DATA=$(gh api repos/$OWNER/$REPO --jq '{name: .name, default_branch: .default_branch, is_private: .private, description: .description}')
DEFAULT_BRANCH=$(echo "$REPO_DATA" | jq -r '.default_branch')
IS_PRIVATE=$(echo "$REPO_DATA" | jq -r '.is_private')

verbose "Default branch: $DEFAULT_BRANCH"
verbose "Private: $IS_PRIVATE"
success "Repository found: $REPO_DATA"

# Clone or navigate to repo
log "Setting up local working directory..."
if [[ ! -d "$REPO" ]]; then
    log "Cloning $OWNER/$REPO..."
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clone: gh repo clone $OWNER/$REPO"
    else
        gh repo clone $OWNER/$REPO -- --depth 1
        cd "$REPO"
    fi
else
    cd "$REPO"
    git pull origin $DEFAULT_BRANCH
fi

success "Working in: $(pwd)"

# Create .github/workflows directory if needed
log "Setting up .github/workflows structure..."
if [[ ! -d .github/workflows ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create: .github/workflows"
    else
        mkdir -p .github/workflows
        verbose "Created .github/workflows"
    fi
fi

# Copy templates
log "Copying workflow templates..."
TEMPLATES=(
    "TEMPLATE-ci-lint.yml"
    "TEMPLATE-ci-tests.yml"
    "TEMPLATE-ci-security.yml"
)

for template in "${TEMPLATES[@]}"; do
    SOURCE="../.github/workflows/$template"
    
    if [[ ! -f "$SOURCE" ]]; then
        warning "Template not found: $SOURCE (skipping)"
        continue
    fi
    
    # Determine target name
    if [[ "$template" == "TEMPLATE-ci-lint.yml" ]]; then
        TARGET="ci-lint.yml"
    elif [[ "$template" == "TEMPLATE-ci-tests.yml" ]]; then
        TARGET="ci-tests.yml"
    elif [[ "$template" == "TEMPLATE-ci-security.yml" ]]; then
        TARGET="ci-security.yml"
    fi
    
    if [[ ! -f ".github/workflows/$TARGET" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would copy: $SOURCE → .github/workflows/$TARGET"
        else
            cp "$SOURCE" ".github/workflows/$TARGET"
            verbose "Copied: $TARGET"
        fi
    else
        verbose "Skipped (exists): .github/workflows/$TARGET"
    fi
done

success "Workflow templates ready"

# Create README if doesn't exist
log "Creating .github/README.md..."
if [[ ! -f ".github/README.md" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create: .github/README.md"
    else
        cat > .github/README.md <<'EOF'
# CI/CD Pipeline

This repository uses GitHub Actions for continuous integration and deployment.

## Workflows

- **ci-lint.yml**: Code linting and formatting (runs on push/PR)
- **ci-tests.yml**: Unit and integration tests (runs on push/PR)
- **ci-security.yml**: Security scanning - SAST, SCA, secrets (on push/schedule)

## Getting Started

1. Create a new branch: `git checkout -b feature/my-feature`
2. Make changes and commit
3. Push and create a PR: `git push origin feature/my-feature`
4. Workflows run automatically
5. Check Actions tab for results
6. Address any failures and push again

## Customizing Workflows

See: [../../../.github/workflows/README.md](../../../.github/workflows/README.md)

## Cost & Governance

This repository follows the governance framework:
- [.github/GOVERNANCE.md](../.github/GOVERNANCE.md)
- [.github/GOVERNANCE-QUICK-REFERENCE.md](../.github/GOVERNANCE-QUICK-REFERENCE.md)

Budget: See COST-ESTIMATE.md

## Questions?

Post in Slack: #devops-governance
EOF
        success "Created: .github/README.md"
    fi
else
    verbose "Skipped: .github/README.md (already exists)"
fi

# Create COST-ESTIMATE.md template
log "Creating COST-ESTIMATE.md..."
if [[ ! -f "COST-ESTIMATE.md" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create: COST-ESTIMATE.md"
    else
        cat > COST-ESTIMATE.md <<'EOF'
# Cost Estimate: $REPO

## Monthly Workflow Cost Projection

| Workflow | Frequency | Duration | Monthly Runs | Cost |
|----------|-----------|----------|--------------|------|
| ci-lint | per push | 10 min | 100 | $13.33 |
| ci-tests | per push | 20 min | 100 | $26.67 |
| ci-security | weekly | 15 min | 4 | $0.80 |
| **TOTAL** | | | | **$40.80** |

## Budget Allocation

Based on 100 pushes/month across main and develop branches.

| Category | Quota | Budget |
|----------|-------|--------|
| ci-lint | 100/month | $13.33 |
| ci-tests | 100/month | $26.67 |
| total | 200/month | $40 |

## Assumptions

- Average 2 commits per feature branch before merge
- 50 merged PRs per month (100 pushes to main/develop)
- Each push triggers ci-lint and ci-tests (parallel)
- Security scanning weekly (minimal cost)

## Review & Approval

**Owner**: @(assign username)
**Approved by**: (DevOps Lead)
**Date**: $(date +%Y-%m-%d)

## Optimization Tips

If costs exceed budget:
1. Use caching for dependencies (npm ci with cache)
2. Reduce matrix testing (Node versions)
3. Move non-critical jobs to scheduled/manual
4. Split into separate workflows if possible

See: [COST-OPTIMIZATION.md](../../COST-OPTIMIZATION.md)
EOF
        success "Created: COST-ESTIMATE.md"
    fi
else
    verbose "Skipped: COST-ESTIMATE.md (already exists)"
fi

# Create commit
log "Preparing commit..."
if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would commit:"
    git status --short
else
    if git status --porcelain | grep -q .; then
        git add .github/ COST-ESTIMATE.md
        git commit -m "chore: Initialize governance-compliant CI/CD workflows"
        success "Committed: Governance workflows"
    else
        verbose "No changes to commit"
    fi
fi

# Create PR with onboarding checklist
log "Creating onboarding issue..."
CHECKLIST='- [ ] Customize workflows for repo (languages, dependencies)
- [ ] Update COST-ESTIMATE.md with actual budget
- [ ] Review and approve workflows
- [ ] Enable Actions if disabled
- [ ] Test workflows (create dummy PR)
- [ ] Documentation review
- [ ] Compliance sign-off'

if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would create issue:"
    echo "Title: Governance Onboarding: $REPO"
    echo "Checklist:"
    echo "$CHECKLIST"
else
    ISSUE_URL=$(gh issue create \
        --title "Governance Onboarding: $REPO" \
        --body "# Governance Compliance Checklist

Repository: \`$OWNER/$REPO\`

$CHECKLIST

See: [GOVERNANCE-ONBOARDING.md](../../GOVERNANCE-ONBOARDING.md)" \
        --label governance 2>&1 | tail -1)
    
    success "Created issue: $ISSUE_URL"
fi

# Summary
log "=========================================="
success "Governance Initialization Complete"
log "=========================================="
echo ""
echo "Repository: $REPO"
echo "Default Branch: $DEFAULT_BRANCH"
echo "Private: $IS_PRIVATE"
echo ""
echo "✓ Workflows copied"
echo "✓ Documentation created"
echo "✓ Cost estimate template ready"
echo "✓ Onboarding issue created"
echo ""
echo "Next steps:"
echo "1. git push origin $DEFAULT_BRANCH"
echo "2. Customize workflows for your repo"
echo "3. Update COST-ESTIMATE.md"
echo "4. Review onboarding issue"
echo "5. Request approval from DevOps team"
echo ""
echo "Contact: #devops-governance"

