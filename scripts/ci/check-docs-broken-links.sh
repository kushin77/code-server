#!/usr/bin/env bash
# @file        scripts/ci/check-docs-broken-links.sh
# @module      ci/documentation-standards
# @description Check for broken internal links and invalid references in documentation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCS_DIR="${SCRIPT_DIR}/docs"
REPO_ROOT="${SCRIPT_DIR}"
REPORT_FILE="${SCRIPT_DIR}/artifacts/triage/docs-broken-links.log"

mkdir -p "$(dirname "$REPORT_FILE")"

BROKEN_LINKS=0
CHECKED_LINKS=0

check_internal_link() {
    local doc_file="$1"
    local link_text="$2"
    local target_path="$3"
    local line_num="$4"
    
    # Skip external URLs
    if [[ "$target_path" =~ ^https?:// ]] || [[ "$target_path" =~ ^mailto: ]]; then
        return 0
    fi
    
    # Skip anchor-only links
    if [[ "$target_path" =~ ^# ]]; then
        return 0
    fi
    
    ((CHECKED_LINKS+=1))
    
    # Resolve relative path
    local doc_dir=$(dirname "$doc_file")
    local resolved_path="${doc_dir}/${target_path}"
    
    # Remove anchors for file existence check
    local file_only="${resolved_path%#*}"
    
    # Normalize path
    file_only=$(cd "$(dirname "$file_only")" 2>/dev/null && pwd -P)/$(basename "$file_only") 2>/dev/null || echo ""
    
    if [ -z "$file_only" ] || [ ! -f "$file_only" ]; then
        echo "[ERROR] Broken link in $doc_file:$line_num"
        echo "        Link: [$link_text]($target_path)"
        echo "        Resolved to: $file_only (not found)"
        echo ""
        ((BROKEN_LINKS+=1))
        return 1
    fi
    
    return 0
}

check_doc_links() {
    local doc_file="$1"
    local line_num=0
    
    while IFS= read -r line; do
        ((line_num+=1))
        
        # Find markdown links: [text](path)
        while [[ "$line" =~ \[([^\]]+)\]\(([^\)]+)\) ]]; do
            local link_text="${BASH_REMATCH[1]}"
            local target_path="${BASH_REMATCH[2]}"
            local matched="${BASH_REMATCH[0]}"
            
            check_internal_link "$doc_file" "$link_text" "$target_path" "$line_num" || true
            
            # Remove this match and continue searching for more on same line
            line="${line#*"$matched"}"
        done
    done < "$doc_file"
}

main() {
    echo "Scanning documentation for broken links..."
    echo ""
    
    # Find all markdown files
    while IFS= read -r doc_file; do
        check_doc_links "$doc_file"
    done < <(find "${DOCS_DIR}" -name "*.md" -type f)
    
    # Summary
    echo "=========================================="
    echo "Link Validation Results"
    echo "=========================================="
    echo "Total links checked: $CHECKED_LINKS"
    echo "Broken links found: $BROKEN_LINKS"
    echo ""
    
    tee -a "$REPORT_FILE" <<EOF
Link Validation Report
=======================
Total links: $CHECKED_LINKS
Broken: $BROKEN_LINKS
Scanned at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    if [ "$BROKEN_LINKS" -gt 0 ]; then
        echo "❌ FAILED: $BROKEN_LINKS broken link(s) found"
        exit 1
    else
        echo "✅ PASSED: No broken links detected"
        exit 0
    fi
}

main "$@"
