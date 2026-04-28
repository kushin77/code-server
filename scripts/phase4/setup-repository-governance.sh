#!/usr/bin/env bash
###############################################################################
# Phase 4: Repository Governance - FAANG Standards Implementation
#
# @file scripts/phase4/setup-repository-governance.sh
# @module phase4/governance
# @description Implement FAANG-level repository governance
# @governance GOV-003: Repository must meet FAANG code review standards
# @usage ./setup-repository-governance.sh
###############################################################################

set -euo pipefail

trap 'log_error "Governance setup failed at line $LINENO"; exit 1' ERR
trap 'log_info "Governance setup session ending..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

log_info() { echo "[INFO]    | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_success() { echo "[SUCCESS] | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }
log_error() { echo "[ERROR]   | $(date +%Y-%m-%d\ %H:%M:%S) | $*"; }

# ============================================================================
# GIT CONFIGURATION
# ============================================================================

setup_git_config() {
    log_info "Setting up git configuration..."
    
    # Git commit template
    cat > /tmp/.git-commit-template << 'EOF'
# <type>: <subject> (imperative, lowercase, < 50 chars)

# <body> (wrapped at 72 chars)

# <footer> (issue references, breaking changes)
# Type can be:
#   feat     (new feature)
#   fix      (bug fix)
#   refactor (code change that neither fixes nor adds feature)
#   test     (add or update tests)
#   docs     (changes to documentation)
#   style    (formatting, missing semicolons, etc)
#   chore    (dependencies, build tools, etc)
EOF
    
    log_success "✓ Git commit template created"
}

# ============================================================================
# BRANCHING STRATEGY
# ============================================================================

create_branching_strategy() {
    log_info "Documenting branching strategy..."
    
    cat > /tmp/BRANCHING_STRATEGY.md << 'EOF'
# Elite Enterprise Branching Strategy

## Git Flow Model

### Production Branches
- **main**: Production-ready code, deployable at any time
- **develop**: Integration branch for next release

### Supporting Branches
- **feature/<name>**: Feature development
- **bugfix/<name>**: Bug fixes
- **hotfix/<name>**: Emergency production fixes
- **release/<version>**: Release preparation

## Branch Protection Rules

### main
- Require pull request reviews: 2 approvals
- Require status checks to pass
- Include administrators: No
- Allow force pushes: No
- Allow deletions: No

### develop
- Require pull request reviews: 1 approval
- Require status checks to pass
- Include administrators: No
- Allow force pushes: No
- Allow deletions: No

## Workflow

### Feature Development
1. Create branch from develop
   ```
   git checkout -b feature/my-feature develop
   ```

2. Commit changes with conventional messages
   ```
   git commit -m "feat: Add new feature"
   ```

3. Push and create pull request
   ```
   git push origin feature/my-feature
   ```

4. After review approval, merge to develop
   ```
   git merge --no-ff feature/my-feature
   ```

### Release Process
1. Create release branch from develop
   ```
   git checkout -b release/1.0.0 develop
   ```

2. Update version numbers
3. Create release commit
4. Merge to main with tag
5. Merge back to develop

### Hotfix Process
1. Create hotfix from main
   ```
   git checkout -b hotfix/1.0.1 main
   ```

2. Fix issue
3. Merge to main and tag
4. Merge back to develop

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Example
```
feat(auth): Add OAuth2 integration

Implement OAuth2 provider integration with support for
Google and GitHub providers. Add PKCE flow for mobile
clients.

Closes #2345
BREAKING CHANGE: OAuth1 support removed
```

## Pull Request Requirements

1. **Title**: Clear, descriptive, follows conventional commits
2. **Description**: Explains what and why (not how)
3. **Reviewers**: At least 1 for develop, 2 for main
4. **Tests**: All must pass
5. **Documentation**: Updated if needed
6. **Commits**: Should be squashed (one commit per feature)

## Merge Strategy

- Use "squash and merge" for feature branches
- Use "create a merge commit" for release/hotfix branches
- Delete branch after merge

EOF
    
    log_success "✓ Branching strategy documented"
}

# ============================================================================
# CODE REVIEW PROCESS
# ============================================================================

create_code_review_process() {
    log_info "Creating code review process..."
    
    cat > /tmp/CODE_REVIEW_PROCESS.md << 'EOF'
# Code Review Process - FAANG Standards

## Code Review Checklist

### Functionality
- [ ] Code implements the stated requirements
- [ ] Logic is correct and handles edge cases
- [ ] No regression or breaking changes
- [ ] Tests cover the changes
- [ ] Documentation is updated

### Code Quality
- [ ] Follows project code standards
- [ ] No code duplication
- [ ] Functions are small and focused
- [ ] Variable names are clear
- [ ] Comments explain why, not what

### Performance
- [ ] No obvious performance regressions
- [ ] Algorithms are efficient
- [ ] Database queries are optimized
- [ ] Memory usage is reasonable

### Security
- [ ] No hardcoded secrets
- [ ] Input validation is present
- [ ] SQL injection is prevented
- [ ] CSRF protection if needed
- [ ] XSS prevention if applicable

### Testing
- [ ] Unit tests added/updated
- [ ] Integration tests if needed
- [ ] Edge cases covered
- [ ] Tests are readable and maintainable

### Documentation
- [ ] Code comments are clear
- [ ] Architecture decisions documented
- [ ] README updated if needed
- [ ] API documentation updated

## Review Process

1. **Author Preparation**
   - Run all tests locally
   - Check code formatting
   - Write clear commit messages
   - Provide context in PR description

2. **Request Review**
   - Request review from appropriate reviewers
   - Link to relevant issues
   - Describe testing performed

3. **Reviewer Examination**
   - Read PR description
   - Review code changes
   - Check tests
   - Run tests locally if complex
   - Leave comments on specific lines

4. **Author Responds**
   - Address feedback
   - Push additional commits
   - Reply to reviewer comments
   - Request re-review if major changes

5. **Approval and Merge**
   - Minimum required approvals received
   - All feedback addressed
   - All checks passing
   - Author merges when ready

## Review Standards

### Approval Requirements
- develop: 1 approval from core team
- main: 2 approvals (one must be tech lead)
- hotfix: 2 approvals + urgent review

### Timing
- Standard review: 24 hours
- Hotfix review: 2 hours
- Documentation: 6 hours

### Comment Etiquette
- Be respectful and constructive
- Explain reasoning
- Use questions for learning opportunities
- Praise good practices

### Conflict Resolution
- Discussion in PR comments
- Escalate to tech lead if stuck
- Default to FAANG best practices

EOF
    
    log_success "✓ Code review process documented"
}

# ============================================================================
# CI/CD PIPELINE
# ============================================================================

create_cicd_pipeline() {
    log_info "Creating CI/CD pipeline documentation..."
    
    cat > /tmp/CICD_PIPELINE.md << 'EOF'
# CI/CD Pipeline - Automated Testing & Deployment

## Pipeline Stages

### 1. Code Quality Checks
- ShellCheck: Verify shell script syntax
- Markdown lint: Check documentation
- YAML validation: Config files
- JSON validation: JSON files
- Secret scanning: Prevent secret commits

### 2. Automated Testing
- Unit tests: Fast feedback
- Integration tests: Component interaction
- Load tests: Performance verification
- Chaos tests: Failure scenarios
- Security tests: Vulnerability scanning

### 3. Build & Package
- Build artifacts
- Package containers
- Generate documentation
- Create releases

### 4. Deployment Stages

#### Staging
- Deploy to staging environment
- Smoke tests
- Performance baseline
- Security scanning

#### Production
- Manual approval required
- Blue-green deployment
- Health checks
- Rollback capability

## GitHub Actions Configuration

### On Pull Request
- Run all tests
- Code quality checks
- Security scans
- Generate test reports

### On Merge to Develop
- Run full test suite
- Build Docker images
- Push to staging registry
- Deploy to staging

### On Release Tag
- Run full test suite
- Build production images
- Generate release notes
- Deploy to production

## Success Criteria

| Check | Requirement | Action |
|-------|-------------|--------|
| Tests | 100% pass | Fail PR |
| Coverage | >80% | Warn |
| Linting | No errors | Fail PR |
| Security | No critical | Fail PR |
| Performance | <10% regression | Warn |

## Rollback Strategy

### Automatic Rollback Triggers
- Error rate >1%
- Response time >5s (P95)
- Service availability <99%
- Database connection errors

### Manual Rollback
- Tech lead initiated
- Revert to previous release
- Post-incident analysis

EOF
    
    log_success "✓ CI/CD pipeline documented"
}

# ============================================================================
# ISSUE MANAGEMENT
# ============================================================================

create_issue_management() {
    log_info "Creating issue management system..."
    
    cat > /tmp/ISSUE_MANAGEMENT.md << 'EOF'
# Issue Management & Tracking

## Issue Labels

### Priority
- P0: Critical (production down)
- P1: High (major feature broken)
- P2: Medium (feature incomplete)
- P3: Low (minor issues)

### Category
- bug: Bug fix
- feature: New feature
- enhancement: Improvement
- documentation: Doc updates
- test: Testing
- performance: Performance improvement
- security: Security issue
- chore: Maintenance

### Status
- backlog: Not started
- ready: Ready for development
- in-progress: Currently being worked on
- review: In code review
- done: Completed

## Issue Lifecycle

### Creation
- Title: Clear and descriptive
- Description: Steps to reproduce, expected behavior
- Labels: Appropriate labels
- Assignee: If immediately known
- Milestone: Release target

### Development
- Assign to developer
- Link to feature branch
- Link to pull request
- Mark in-progress

### Review
- PR review required
- Code review comments
- Testing verification

### Completion
- PR merged
- Tests passing
- Documentation updated
- Marked done
- Changelog entry

## Release Planning

### Milestones
- Version number (e.g., 1.2.3)
- Release date
- Feature list
- Known issues

### Release Notes
- Summary of changes
- Breaking changes
- Migration guide
- Contributors

EOF
    
    log_success "✓ Issue management documented"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║ PHASE 4: REPOSITORY GOVERNANCE - FAANG STANDARDS           ║"
    log_info "║ Professional repository management                        ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    setup_git_config
    create_branching_strategy
    create_code_review_process
    create_cicd_pipeline
    create_issue_management
    
    echo ""
    log_success "╔════════════════════════════════════════════════════════════╗"
    log_success "║ PHASE 4 GOVERNANCE SETUP COMPLETE                        ║"
    log_success "║ Deliverables:                                            ║"
    log_success "║ - Branching strategy: /tmp/BRANCHING_STRATEGY.md         ║"
    log_success "║ - Code review process: /tmp/CODE_REVIEW_PROCESS.md       ║"
    log_success "║ - CI/CD pipeline: /tmp/CICD_PIPELINE.md                  ║"
    log_success "║ - Issue management: /tmp/ISSUE_MANAGEMENT.md             ║"
    log_success "╚════════════════════════════════════════════════════════════╝"
}

main "$@"
