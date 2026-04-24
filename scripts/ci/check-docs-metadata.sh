#!/usr/bin/env bash
# @file        scripts/ci/check-docs-metadata.sh
# @module      ci/documentation-standards
# @description Validate that all docs have required frontmatter metadata

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"
DOCS_DIR="${REPO_ROOT}/docs"
REPORT_FILE="${REPO_ROOT}/artifacts/triage/docs-metadata-validation.log"

mkdir -p "$(dirname "$REPORT_FILE")"

# Counters
TOTAL_DOCS=0
DOCS_WITH_ERRORS=0
METADATA_ERRORS=0

# Check if yq is available for YAML parsing
if ! command -v yq &> /dev/null; then
    echo "[WARN] yq not found. Skipping detailed YAML validation."
    echo "       Install: pip install yq"
fi

validate_doc() {
    local doc_path="$1"
    local doc_relative="${doc_path#${DOCS_DIR}/}"
    local has_error=0
    
    ((TOTAL_DOCS+=1))
    
    # Check if file starts with ---
    if ! head -n 1 "$doc_path" | grep -q '^---$'; then
        echo "[ERROR] Missing frontmatter block in: $doc_relative"
        ((METADATA_ERRORS+=1))
        ((has_error=1))
        ((DOCS_WITH_ERRORS+=1))
        return
    fi
    
    # Extract frontmatter section (between first --- and second ---)
    local frontmatter_end
    frontmatter_end=$(awk '/^---$/{ count++; if(count==2) print NR; exit }' "$doc_path" 2>/dev/null || true)
    frontmatter_end="${frontmatter_end:-0}"
    
    if [ "$frontmatter_end" -eq 0 ]; then
        echo "[ERROR] No closing --- in frontmatter: $doc_relative"
        ((METADATA_ERRORS+=1))
        ((has_error=1))
        return
    fi
    
    local frontmatter; frontmatter=$(sed -n '2,'$((frontmatter_end-1))'p' "$doc_path")
    
    # Check required fields using grep (fallback if yq unavailable)
    local required_fields=("title" "description" "owner" "last_review_date" "status")
    for field in "${required_fields[@]}"; do
        if ! echo "$frontmatter" | grep -q "^${field}:"; then
            echo "[ERROR] Missing required field '$field' in: $doc_relative"
            ((METADATA_ERRORS+=1))
            ((has_error=1))
        fi
    done
    
    # Validate status field
    if echo "$frontmatter" | grep -q "^status:"; then
        local status; status=$(echo "$frontmatter" | grep "^status:" | head -1 | sed 's/^status:[[:space:]]*//')
        if ! echo "$status" | grep -qE '^(active|draft|archived)'; then
            echo "[ERROR] Invalid status '$status' (must be: active|draft|archived) in: $doc_relative"
            ((METADATA_ERRORS+=1))
            ((has_error=1))
        fi
    fi
    
    # Validate date format
    if echo "$frontmatter" | grep -q "^last_review_date:"; then
        local date; date=$(echo "$frontmatter" | grep "^last_review_date:" | head -1 | sed 's/^last_review_date:[[:space:]]*//;s/#.*//')
        if ! echo "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
            echo "[ERROR] Invalid date format '$date' (use YYYY-MM-DD) in: $doc_relative"
            ((METADATA_ERRORS+=1))
            ((has_error=1))
        else
            # Check if > 90 days old
            local doc_date_epoch; doc_date_epoch=$(date -d "$date" +%s 2>/dev/null || echo "0")
            local now_epoch; now_epoch=$(date +%s)
            local age_days=$(( (now_epoch - doc_date_epoch) / 86400 ))
            
            if [ "$age_days" -gt 90 ]; then
                echo "[WARN] Document review date is ${age_days} days old (>90 days): $doc_relative"
            fi
        fi
    fi
    
    if [ "$has_error" -eq 1 ]; then
        ((DOCS_WITH_ERRORS+=1))
    fi
}

main() {
    echo "Validating documentation metadata..."
    echo ""
    
    # Find all markdown files in docs/
    while IFS= read -r doc_path; do
        # Skip templates and archives for now
        if [[ "$doc_path" == *"TEMPLATE"* ]] || [[ "$doc_path" == *"/archives/"* ]]; then
            continue
        fi
        
        validate_doc "$doc_path"
    done < <(find "${DOCS_DIR}" -name "*.md" -type f)
    
    # Summary
    echo ""
    echo "=========================================="
    echo "Documentation Metadata Validation Results"
    echo "=========================================="
    echo "Total docs scanned: $TOTAL_DOCS"
    echo "Docs with errors: $DOCS_WITH_ERRORS"
    echo "Total metadata errors: $METADATA_ERRORS"
    echo ""
    
    # Save report
    {
        echo "Validation Summary"
        echo "===================="
        echo "Total docs: $TOTAL_DOCS"
        echo "Errors: $DOCS_WITH_ERRORS"
        echo "Details above"
    } >> "$REPORT_FILE"
    
    if [ "$DOCS_WITH_ERRORS" -gt 0 ]; then
        echo "❌ FAILED: Metadata validation errors found"
        exit 1
    else
        echo "✅ PASSED: All docs have valid metadata"
        exit 0
    fi
}

main "$@"
