#!/usr/bin/env bash
# @file        scripts/audit/audit-github-cli-usage.sh
# @module      audit/github-cli-usage
# @description Audit all `gh` CLI calls in codebase to ensure --repo flag and error handling
#
# Generates:
# - List of all gh CLI calls
# - Compliance report (--repo flag present, error handling present)
# - Remediation recommendations
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly AUDIT_OUTPUT="${1:-.audit-github-cli.json}"
REPO_ROOT="$SCRIPT_DIR"

# ============================================================================
# Audit Functions
# ============================================================================

#
# Find all gh CLI invocations in scripts
#
find_gh_cli_calls() {
  log_info "Scanning for 'gh' CLI calls..."
  
  find "$REPO_ROOT" \
    -type f \
    \( -name "*.sh" -o -name "*.bash" -o -name "*.yml" -o -name "*.yaml" -o -name "*.py" \) \
    ! -path "./.git/*" \
    ! -path "./node_modules/*" \
    ! -path "./dist/*" \
    ! -path "*/.venv/*" \
    -exec grep -l "gh " {} \; 2>/dev/null | sort
}

#
# Extract gh CLI calls with line numbers and context
#
analyze_gh_cli_usage() {
  local file="$1"
  local line_num
  local line_content
  
  while IFS=: read -r line_num line_content; do
    # Skip comments
    [[ "$line_content" =~ ^[[:space:]]*# ]] && continue
    
    # Extract command
    local has_repo_flag=false
    local has_error_handling=false
    
    if [[ "$line_content" =~ --repo ]]; then
      has_repo_flag=true
    fi
    
    # Check if next line has error handling (|| catch, || die, etc.)
    local next_line
    next_line=$(sed -n "$((line_num+1))p" "$file" 2>/dev/null || echo "")
    if [[ "$next_line" =~ (\|\||if) ]]; then
      has_error_handling=true
    fi
    
    # Output record
    python3 - "$file" "$line_num" "$line_content" "$has_repo_flag" "$has_error_handling" <<'PY'
import json
import sys

file_path = sys.argv[1]
line_number = sys.argv[2]
command = sys.argv[3]
has_repo = sys.argv[4].lower() == 'true'
has_error = sys.argv[5].lower() == 'true'

record = {
    'file': file_path,
    'line': line_number,
    'command': command,
    'has_repo_flag': has_repo,
    'has_error_handling': has_error,
    'status': '✓ compliant' if has_repo and has_error else '⚠ needs-fix',
}

print(json.dumps(record, ensure_ascii=False))
PY
  done < <(grep -n "gh " "$file" 2>/dev/null | grep -v "^[[:space:]]*#" || true)
}

#
# Generate comprehensive audit report
#
generate_audit_report() {
  log_info "Generating audit report..."
  
  local total_calls=0
  local compliant_calls=0
  local non_compliant_calls=0
  
  local temp_file
  temp_file=$(mktemp)
  
  while IFS= read -r file; do
    while IFS= read -r record; do
      if [[ -n "$record" ]]; then
        echo "$record" >> "$temp_file"
        
        # Count stats
        ((++total_calls))

        local status
        status=$(python3 - "$record" <<'PY'
import json
import sys

print(json.loads(sys.argv[1]).get('status', ''))
PY
)
        if [[ "$status" == "✓ compliant" ]]; then
          ((++compliant_calls))
        else
          ((++non_compliant_calls))
        fi
      fi
    done < <(analyze_gh_cli_usage "$file")
  done < <(find_gh_cli_calls)
  
  python3 - "$temp_file" "$AUDIT_OUTPUT" "$total_calls" "$compliant_calls" "$non_compliant_calls" <<'PY'
import json
import math
import pathlib
import sys
from datetime import datetime, timezone

records_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
total = int(sys.argv[3])
compliant = int(sys.argv[4])
non_compliant = int(sys.argv[5])

records = []
with records_path.open('r', encoding='utf-8') as handle:
    for raw_line in handle:
        raw_line = raw_line.strip()
        if raw_line:
            records.append(json.loads(raw_line))

compliance_rate = "0%"
if total > 0:
    compliance_rate = f"{math.floor((compliant / total) * 100)}%"

report = {
    "audit_summary": {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "total_gh_calls": total,
        "compliant_calls": compliant,
        "non_compliant_calls": non_compliant,
        "compliance_rate": compliance_rate,
    },
    "records": records,
}

output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
PY
  
  rm -f "$temp_file"
  
  log_info "✓ Audit report generated: $AUDIT_OUTPUT"
  log_info "  Total gh calls: $total_calls"
  log_info "  ✓ Compliant: $compliant_calls"
  log_info "  ⚠ Non-compliant: $non_compliant_calls"
  log_info "  Compliance rate: $((compliant_calls * 100 / total_calls))%"
}

#
# Generate remediation script for non-compliant calls
#
generate_remediation_recommendations() {
  log_info "Generating remediation recommendations..."
  
  local recommendations_file="${AUDIT_OUTPUT%.json}-remediation.md"
  
  cat > "$recommendations_file" <<'EOF'
# GitHub CLI Remediation Recommendations

## Summary
This report identifies all `gh` CLI calls that need remediation for GitHub API stability.

### Compliance Issues

#### Issue 1: Missing --repo Flag
All `gh issue`, `gh pr`, `gh release` calls MUST include `--repo OWNER/REPO`.

**Fix:**
```bash
# Before:
# gh issue create --title "Bug fix" --body "Description"

# After:
# gh issue create --title "Bug fix" --body "Description" --repo kushin77/code-server
```

#### Issue 2: Missing Error Handling
All `gh` CLI calls must check exit code and implement retry logic for transient errors.

**Fix:**
```bash
# Before:
# gh issue list --assignee me

# After:
GH_TOKEN="$(github_get_token)" gh issue list --assignee me --repo kushin77/code-server || {
  log_error "GitHub CLI error: $?"
  return 1
}
```

#### Issue 3: Using Classic PAT Instead of Fine-Grained Token
All GitHub authentication must use fine-grained tokens (not classic PAT).

**Fix:**
```bash
# Before:
export GH_TOKEN="ghp_classic_token..."

# After:
export GH_TOKEN="$(github_get_token)"  # Uses GSM-stored fine-grained token
```

### Automated Migration Path

1. **Replace all direct `gh` calls with wrapper:**
   ```bash
   
   # Use:
   github_gh issue create --title "..." --repo kushin77/code-server
   # instead of:
   # gh issue create --title "..." --repo kushin77/code-server
   ```

2. **Use gsm-backed token retrieval:**
   ```bash
   TOKEN=$(github_get_token)  # Automatically uses GSM
   ```

3. **Wrap in error handling:**
   ```bash
   github_api_call GET "/repos/kushin77/code-server/issues" || return 1
   ```

### High-Priority Files to Fix
(List generated from audit output)

EOF
  
  # Append non-compliant files
  python3 - "$AUDIT_OUTPUT" "$recommendations_file" <<'PY'
import json
import pathlib
import sys

audit_path = pathlib.Path(sys.argv[1])
recommendations_path = pathlib.Path(sys.argv[2])

data = json.loads(audit_path.read_text(encoding='utf-8'))
with recommendations_path.open('a', encoding='utf-8') as handle:
    for record in data.get('records', []):
        if 'needs-fix' in record.get('status', ''):
            handle.write(f"\n- {record.get('file')}:{record.get('line')} - {record.get('command')}")
PY
  
  log_info "✓ Remediation recommendations: $recommendations_file"
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  log_info "Starting GitHub CLI usage audit..."
  log_info "Scanning: $REPO_ROOT"
  
  generate_audit_report
  generate_remediation_recommendations
  
  log_info "✓ Audit complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
