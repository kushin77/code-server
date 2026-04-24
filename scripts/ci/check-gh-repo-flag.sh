#!/bin/bash
# @file check-gh-repo-flag.sh
# @module governance/ci
# @description CI guard to enforce --repo flag on all gh issue/pr CLI calls
# @governance GOV-002

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
readonly REPORT_FILE="artifacts/gh-repo-flag-audit.json"
readonly VIOLATIONS_FILE="artifacts/gh-repo-flag-violations.md"

# Commands that require --repo flag
readonly GH_COMMANDS_REQUIRING_REPO=(
    "issue create"
    "issue list"
    "issue view"
    "issue edit"
    "issue close"
    "issue comment"
    "issue unlock"
    "issue lock"
    "pr create"
    "pr list"
    "pr view"
    "pr edit"
    "pr close"
    "pr reopen"
    "pr comment"
    "pr review"
)

# ============================================================================
# Logging
# ============================================================================
log_info() {
    echo "ℹ️  $*" >&2
}

log_error() {
    echo "❌ $*" >&2
}

log_warn() {
    echo "⚠️  $*" >&2
}

# ============================================================================
# Audit Functions
# ============================================================================

audit_sh_files() {
    local violations=0
    local violations_list=()
    
    log_info "Scanning shell scripts for gh CLI calls without --repo flag..."
    
    while IFS= read -r file; do
        while IFS= read -r line_num line_content; do
            # Skip comments and documentation
            [[ "$line_content" =~ ^\s*# ]] && continue
            [[ "$line_content" =~ \`\`\` ]] && continue
            
            # Check for gh issue/pr commands without --repo
            for cmd in "${GH_COMMANDS_REQUIRING_REPO[@]}"; do
                if [[ "$line_content" =~ gh\ ${cmd} ]] && [[ ! "$line_content" =~ --repo ]] && [[ ! "$line_content" =~ github_gh ]]; then
                    violations=$((violations + 1))
                    local violation="${file}:${line_num}: Missing --repo flag"
                    violations_list+=("$violation")
                    log_error "$violation"
                fi
            done
        done < <(grep -n "gh\s\+\(issue\|pr\)" "$file" 2>/dev/null || true)
    done < <(find . -name "*.sh" -type f \
        ! -path "./node_modules/*" \
        ! -path "./.git/*" \
        ! -path "./.venv/*" \
        2>/dev/null)
    
    return $violations
}

audit_yml_files() {
    local violations=0
    local violations_list=()
    
    log_info "Scanning YAML workflows for gh CLI calls without --repo flag..."
    
    while IFS= read -r file; do
        while IFS= read -r line_num line_content; do
            # Skip comments
            [[ "$line_content" =~ ^\s*# ]] && continue
            
            # Check for gh issue/pr commands without --repo
            for cmd in "${GH_COMMANDS_REQUIRING_REPO[@]}"; do
                if [[ "$line_content" =~ gh\ ${cmd} ]] && [[ ! "$line_content" =~ --repo ]]; then
                    violations=$((violations + 1))
                    local violation="${file}:${line_num}: Missing --repo flag"
                    violations_list+=("$violation")
                    log_error "$violation"
                fi
            done
        done < <(grep -n "gh\s\+\(issue\|pr\)" "$file" 2>/dev/null || true)
    done < <(find . -name "*.yml" -o -name "*.yaml" | grep -E '\.github/workflows' 2>/dev/null || true)
    
    return $violations
}

generate_report() {
    local total_violations=$1
    local scanned_files=$2
    
    local status="PASS"
    if [ "$total_violations" -gt 0 ]; then
        status="FAIL"
    fi
    
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$status",
  "total_violations": $total_violations,
  "scanned_files": $scanned_files,
  "policy": "All 'gh issue' and 'gh pr' commands must include --repo flag for explicit repo scope",
  "remediation": {
    "option_1": "Use scripts/ci/gh-wrapper.sh which auto-adds --repo",
    "option_2": "Manually add '--repo kushin77/code-server' to gh command",
    "option_3": "Use scripts/_common/issue-create-unified.sh for issue creation"
  }
}
EOF
    
    if [ "$total_violations" -gt 0 ]; then
        cat > "$VIOLATIONS_FILE" <<EOF
# GitHub CLI --repo Flag Violations

Policy: All \`gh issue\` and \`gh pr\` commands must include \`--repo kushin77/code-server\` flag.

## Violations Found: $total_violations

$(printf '%s\n' "${violations_list[@]}")

## Remediation Steps

1. **Use gh-wrapper**: \`scripts/ci/gh-wrapper.sh\` auto-adds --repo flag
2. **Use unified script**: \`scripts/_common/issue-create-unified.sh\` for safe issue creation
3. **Manual fix**: Add \`--repo kushin77/code-server\` to all \`gh issue\`/\`gh pr\` commands

## Examples

### Before (WRONG)
\`\`\`bash
# gh issue list --state open
# gh issue create --title "Bug" --body "Description"
\`\`\`

### After (CORRECT)
\`\`\`bash
# gh issue list --state open --repo kushin77/code-server
# gh issue create --title "Bug" --body "Description" --repo kushin77/code-server
\`\`\`

Or use the wrapper:
\`\`\`bash
bash scripts/ci/gh-wrapper.sh issue-list --state open
bash scripts/ci/gh-wrapper.sh issue-create "Bug" "Description" "P3"
\`\`\`
EOF
    fi
}

# ============================================================================
# Main
# ============================================================================

log_info "Starting GitHub CLI --repo flag audit..."

total_files=0
total_violations=0

# Audit shell scripts
if audit_sh_files; then
    : # Continue
else
    total_violations=$?
fi

total_files=$(find . -name "*.sh" -type f ! -path "./node_modules/*" ! -path "./.git/*" ! -path "./.venv/*" 2>/dev/null | wc -l)

# Audit YAML workflows
if audit_yml_files; then
    : # Continue
else
    total_violations=$((total_violations + $?))
fi

# Generate report
generate_report "$total_violations" "$total_files"

# Log results
log_info "Audit complete:"
log_info "  Scanned files: $total_files"
log_info "  Violations found: $total_violations"
log_info "  Report: $REPORT_FILE"

if [ "$total_violations" -gt 0 ]; then
    log_warn "Violations file: $VIOLATIONS_FILE"
    log_error "CI guard: FAILED - --repo flag policy violations detected"
    exit 1
else
    log_info "✅ All gh commands properly scoped with --repo flag"
    exit 0
fi
