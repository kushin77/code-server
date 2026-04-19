#!/usr/bin/env bash
# @file        scripts/fix-metadata-headers.sh
# @module      governance
# @description Fix missing @file/@module/@description headers in active scripts per MANIFEST.toml
# @owner       platform
# @status      active

set -euo pipefail

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
MANIFEST="${SCRIPTS_DIR}/MANIFEST.toml"
DRY_RUN=false
MODIFIED_COUNT=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            grep '^#' "$0" | grep -E '^\s*#\s' | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# Helper: Count header lines
count_header_lines() {
    local file="$1"
    local count=0
    
    while IFS= read -r line; do
        if [[ $count -eq 0 && "$line" =~ ^\#!/ ]]; then
            count=$((count + 1))
        elif [[ "$line" =~ ^# ]] && [[ $count -gt 0 ]]; then
            count=$((count + 1))
        elif [[ -z "$line" && $count -gt 0 ]]; then
            count=$((count + 1))
            break
        elif [[ -n "$line" && ! "$line" =~ ^# ]] && [[ $count -gt 0 ]]; then
            break
        fi
    done < "$file"
    
    echo "$count"
}

# Helper: Get content after header
get_post_header() {
    local file="$1"
    local header_lines
    header_lines=$(count_header_lines "$file")
    
    if [[ $header_lines -gt 0 ]]; then
        tail -n +"$((header_lines + 1))" "$file"
    else
        cat "$file"
    fi
}

# Helper: Create new header
create_header() {
    local filename="$1"
    local category="$2"
    local purpose="$3"
    
    cat <<EOF
#!/usr/bin/env bash
# @file        scripts/${filename}
# @module      ${category}
# @description ${purpose}
#
EOF
}

# Helper: Check if header is complete
has_complete_header() {
    local file="$1"
    local header
    header=$(head -n 12 "$file")
    
    [[ "$header" =~ @file[[:space:]]+scripts/ ]] && \
    [[ "$header" =~ @module[[:space:]]+[^[:space:]] ]] && \
    [[ "$header" =~ @description[[:space:]]+[^[:space:]] ]]
}

# Helper: Fix a single script
fix_script() {
    local filename="$1"
    local category="$2"
    local purpose="$3"
    local filepath="${SCRIPTS_DIR}/${filename}"
    
    if [[ ! -f "$filepath" ]]; then
        echo -e "${RED}✗${NC} ${filename} (file not found)"
        return 1
    fi
    
    if has_complete_header "$filepath"; then
        echo -e "${GREEN}✓${NC} ${filename} (already valid)"
        return 0
    fi
    
    # Handle TODO purposes
    if [[ "$purpose" == "TODO: add purpose" ]]; then
        purpose="Script for ${filename%.sh}"
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}?${NC} ${filename} (would add/fix headers)"
        return 0
    fi
    
    local new_header
    new_header=$(create_header "$filename" "$category" "$purpose")
    local post_content
    post_content=$(get_post_header "$filepath")
    local temp_file="${filepath}.tmp"
    
    # Write fixed file
    {
        printf '%s\n' "$new_header"
        printf '%s\n' "$post_content"
    } > "$temp_file"
    
    # Preserve executable bit
    if [[ -x "$filepath" ]]; then
        chmod +x "$temp_file"
    fi
    
    mv "$temp_file" "$filepath"
    MODIFIED_COUNT=$((MODIFIED_COUNT + 1))
    echo -e "${GREEN}✓${NC} ${filename} (fixed)"
}

# Main execution
main() {
    echo "Fixing script metadata headers from MANIFEST.toml"
    [[ "$DRY_RUN" == true ]] && echo "(DRY RUN MODE)"
    echo ""
    
    if [[ ! -f "$MANIFEST" ]]; then
        echo -e "${RED}✗ MANIFEST not found: $MANIFEST${NC}"
        exit 1
    fi
    
    # Parse MANIFEST.toml and fix active scripts
    local total=0
    while IFS=$'\t' read -r filename category purpose; do
        total=$((total + 1))
        fix_script "$filename" "$category" "$purpose" || true
    done < <(
        awk -F '"' '
            BEGIN { in_script=0; file=""; status=""; category=""; purpose="" }
            /^\[\[script\]\]/ { in_script=1; file=""; status=""; category=""; purpose=""; next }
            /^\[\[/ && !/^\[\[script\]\]/ { in_script=0; next }
            !in_script { next }
            /^file[[:space:]]*=/ { file=$2; next }
            /^status[[:space:]]*=/ { status=$2; next }
            /^category[[:space:]]*=/ { category=$2; next }
            /^purpose[[:space:]]*=/ {
                purpose=$2;
                if (status=="active" && file!="") {
                    print file "\t" category "\t" purpose;
                }
                next
            }
        ' "${MANIFEST}" | sort -u
    )
    
    # Report results
    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Dry run complete: $total active scripts in MANIFEST${NC}"
        echo "Run without --dry-run to apply fixes"
    else
        echo -e "${GREEN}Fixed $MODIFIED_COUNT of $total scripts${NC}"
        if [[ $MODIFIED_COUNT -gt 0 ]]; then
            echo "Run scripts/ci/check-metadata-headers.sh to verify"
        fi
    fi
    
    return 0
}

main "$@"
