#!/bin/bash
################################################################################
# scripts/pre-commit/check-hardcoded-ips.sh
# Prevents commits with hardcoded production IPs
################################################################################

set -euo pipefail

# Production IPs we want to prevent
FORBIDDEN_IPS=(
    "192\.168\.168\.31"      # PRIMARY_HOST_IP
    "192\.168\.168\.42"      # REPLICA_HOST_IP  
    "192\.168\.168\.40"      # VIRTUAL_IP
    "192\.168\.168\.56"      # STORAGE_IP
    "192\.168\.168\.32"      # REGION2
    "192\.168\.168\.33"      # REGION3
    "192\.168\.168\.34"      # REGION4
    "192\.168\.168\.35"      # REGION5
)

# Documentation ranges and examples that are OK
ALLOWED_PATTERNS=(
    "192\.0\.2\."            # RFC 5737 documentation
    "203\.0\.113\."          # RFC 5737 documentation
    "198\.51\.100\."         # RFC 5737 documentation
    "10\.0\.0\."             # Private
    "172\.16\."              # Private
    "example\.com"           # DNS
    "localhost"              # Local
    "127\.0\.0\.1"           # Loopback
    "0\.0\.0\.0"             # Any
    "\\\${"                  # Template variables
    "\\\$("                  # Shell substitution
    "secrets\."              # GitHub secrets
)

# Files/paths that are excluded from checks
EXCLUDED_PATHS=(
    "docs/"
    "README"
    "example"
    ".pre-commit-hooks.yaml"
    "CONTRIBUTING.md"
    "archived/"
    "deprecated/"
    "\.github/workflows/"    # Workflows now use ${{ secrets. }}
)

die() {
    echo "❌ ERROR: $1" >&2
    exit 1
}

warn() {
    echo "⚠️  WARNING: $1" >&2
}

is_allowed() {
    local content="$1"
    
    # Check for allowed patterns
    for pattern in "${ALLOWED_PATTERNS[@]}"; do
        if grep -qE "$pattern" <<< "$content"; then
            return 0  # Allowed
        fi
    done
    
    return 1  # Not allowed
}

should_check_file() {
    local file="$1"
    
    # Skip binary files
    if file "$file" | grep -q binary; then
        return 1  # Skip
    fi
    
    # Skip excluded paths
    for excluded in "${EXCLUDED_PATHS[@]}"; do
        if [[ "$file" =~ $excluded ]]; then
            return 1  # Skip
        fi
    done
    
    return 0  # Check it
}

check_file() {
    local file="$1"
    local line_num=0
    local errors=0
    
    if ! should_check_file "$file"; then
        return 0
    fi
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Skip comments and empty lines
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Check for forbidden IPs
        for ip in "${FORBIDDEN_IPS[@]}"; do
            if grep -qE "$ip" <<< "$line"; then
                # Check if it's in an allowed context
                if ! is_allowed "$line"; then
                    echo "❌ $file:$line_num — Hardcoded production IP detected"
                    echo "   $line"
                    echo "   Use: \${PRIMARY_HOST_IP}, \${REPLICA_HOST_IP}, etc. from scripts/_common/ip-config.sh"
                    echo "   Or: \${{ secrets.PRIMARY_HOST_IP }} for GitHub Actions"
                    ((errors++))
                fi
            fi
        done
    done < "$file"
    
    return $errors
}

main() {
    local total_errors=0
    
    # Get staged files
    files=$(git diff --cached --name-only --diff-filter=ACMRTUXB)
    
    if [[ -z "$files" ]]; then
        return 0  # No files to check
    fi
    
    echo "🔍 Checking for hardcoded IPs..."
    
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            if ! check_file "$file"; then
                ((total_errors += $?))
            fi
        fi
    done <<< "$files"
    
    if (( total_errors > 0 )); then
        echo ""
        die "$total_errors hardcoded IP violations found. Commit blocked."
    fi
    
    echo "✅ No hardcoded IPs detected"
    return 0
}

main "$@"
