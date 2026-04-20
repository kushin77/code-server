#!/usr/bin/env bash
# @file        scripts/ci/check-docs-duplicates.sh
# @module      ci/documentation-standards
# @description Detect duplicate or near-duplicate documentation files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS_DIR="${SCRIPT_DIR}/docs"
REPORT_FILE="${SCRIPT_DIR}/artifacts/triage/docs-duplicates-report.log"

mkdir -p "$(dirname "$REPORT_FILE")"

POTENTIAL_DUPLICATES=0

check_for_duplicates() {
    echo "Checking for duplicate documentation..."
    echo ""
    
    # Create hash map of file contents
    declare -A content_hashes
    declare -A file_by_hash
    
    while IFS= read -r doc_file; do
        # Skip STANDARDS.md and other special files
        if [[ "$(basename "$doc_file")" == "STANDARDS.md" ]] || \
           [[ "$(basename "$doc_file")" == "README.md" ]] || \
           [[ "$(basename "$doc_file")" == *"TEMPLATE"* ]]; then
            continue
        fi
        
        # Calculate hash of file content (skip frontmatter)
        local hash=$(sed -n '/^---$/,/^---$/!p' "$doc_file" 2>/dev/null | sha256sum | cut -d' ' -f1)
        
        # Check if we've seen this content before
        if [ -n "${file_by_hash[$hash]:-}" ]; then
            local original="${file_by_hash[$hash]}"
            echo "[WARN] Potential duplicate content detected:"
            echo "       File 1: $original"
            echo "       File 2: $doc_file"
            echo "       Hash: $hash"
            echo ""
            ((POTENTIAL_DUPLICATES++))
        else
            file_by_hash[$hash]="$doc_file"
        fi
    done < <(find "${DOCS_DIR}" -name "*.md" -type f)
}

check_for_orphaned_archives() {
    echo "Checking for orphaned archive pointers..."
    echo ""
    
    # Find archive pointers without targets
    while IFS= read -r archive_file; do
        # Check if it's just a pointer (content mentions "Deprecated" or "See")
        if grep -q "^\[>" "$archive_file" 2>/dev/null; then
            # Extract the link target
            local target=$(grep -oP '(?<=\]\().*?(?=\))' "$archive_file" | head -1)
            
            if [ -n "$target" ]; then
                # Resolve target path
                local archive_dir=$(dirname "$archive_file")
                local resolved_target="${archive_dir}/${target}"
                
                # Check if target exists
                if [ ! -f "$resolved_target" ]; then
                    echo "[ERROR] Orphaned archive pointer (target missing):"
                    echo "       Pointer: $archive_file"
                    echo "       Target: $target (not found)"
                    echo ""
                    ((POTENTIAL_DUPLICATES++))
                fi
            fi
        fi
    done < <(find "${DOCS_DIR}/archives" -name "*.md" -type f 2>/dev/null || true)
}

main() {
    check_for_duplicates
    check_for_orphaned_archives
    
    echo "=========================================="
    echo "Duplicate Detection Results"
    echo "=========================================="
    echo "Potential duplicates found: $POTENTIAL_DUPLICATES"
    echo ""
    
    {
        echo "Duplicate Detection Report"
        echo "=========================="
        echo "Potential duplicates: $POTENTIAL_DUPLICATES"
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo ""
        echo "Action: Review findings and consolidate where appropriate"
    } | tee -a "$REPORT_FILE"
    
    if [ "$POTENTIAL_DUPLICATES" -gt 0 ]; then
        echo "⚠️  WARN: Found $POTENTIAL_DUPLICATES potential duplicate(s) - review recommended"
        exit 0  # Don't fail, just warn
    else
        echo "✅ PASSED: No duplicate documentation detected"
        exit 0
    fi
}

main "$@"
