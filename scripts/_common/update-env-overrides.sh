#!/bin/bash
# ============================================================================
# Environment Override Helper - Update variables in environment-specific overrides
# Usage: source scripts/_common/update-env-overrides.sh
# Functions:
#   update_env_var <variable_name> <new_value> [environment]
#   get_env_var <variable_name> [environment]
# ============================================================================

set -e

# Error handling for sourced script
trap 'return 1' ERR

# Determine environment (default to private)
OVERRIDE_ENVIRONMENT="${OVERRIDE_ENVIRONMENT:-private}"

# Get base repository root
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)}"

# Path to environment overrides
ENV_OVERRIDE_FILE="${REPO_ROOT}/.env/${OVERRIDE_ENVIRONMENT}/overrides"

# Validate override file exists
if [[ ! -f "$ENV_OVERRIDE_FILE" ]]; then
    echo "ERROR: Override file not found: $ENV_OVERRIDE_FILE" >&2
    return 1
fi

# ============================================================================
# Update a variable in the environment overrides file
# Arguments:
#   $1 - variable name (e.g., DB_PASSWORD)
#   $2 - new value (will be properly quoted)
#   $3 - environment (optional, defaults to OVERRIDE_ENVIRONMENT)
# ============================================================================
update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env="${3:-$OVERRIDE_ENVIRONMENT}"
    
    if [[ -z "$var_name" || -z "$var_value" ]]; then
        echo "ERROR: update_env_var requires variable name and value" >&2
        return 1
    fi
    
    local override_file="${REPO_ROOT}/.env/${env}/overrides"
    
    if [[ ! -f "$override_file" ]]; then
        echo "ERROR: Override file not found: $override_file" >&2
        return 1
    fi
    
    # Escape special characters for sed replacement
    local escaped_value=$(echo "$var_value" | sed 's/[&/\]/\\&/g')
    
    # Check if variable exists; if so update, otherwise add
    if grep -q "^export ${var_name}=" "$override_file"; then
        # Variable exists - update it with proper quoting
        sed -i "s/^export ${var_name}=.*/export ${var_name}='${escaped_value}'/g" "$override_file"
        echo "✓ Updated ${var_name} in .env/${env}/overrides"
    else
        # Variable doesn't exist - add it
        echo "export ${var_name}='${var_value}'" >> "$override_file"
        echo "✓ Added ${var_name} to .env/${env}/overrides"
    fi
}

# ============================================================================
# Get a variable value from environment overrides
# Arguments:
#   $1 - variable name
#   $2 - environment (optional, defaults to OVERRIDE_ENVIRONMENT)
# Returns:
#   Variable value (without quotes)
# ============================================================================
get_env_var() {
    local var_name="$1"
    local env="${2:-$OVERRIDE_ENVIRONMENT}"
    
    if [[ -z "$var_name" ]]; then
        echo "ERROR: get_env_var requires variable name" >&2
        return 1
    fi
    
    local override_file="${REPO_ROOT}/.env/${env}/overrides"
    
    if [[ ! -f "$override_file" ]]; then
        echo "ERROR: Override file not found: $override_file" >&2
        return 1
    fi
    
    # Extract and unquote the value
    grep "^export ${var_name}=" "$override_file" | sed "s/^export ${var_name}='\\(.*\\)'/\\1/" || echo ""
}

# ============================================================================
# Update multiple variables at once (batch update)
# Arguments:
#   Pass variable assignments as arguments: VAR1="value1" VAR2="value2" ...
#   Optional last argument: environment (if starts with @ or called from env var)
# ============================================================================
update_env_vars_batch() {
    local env="${OVERRIDE_ENVIRONMENT}"
    
    # Check if last argument specifies environment
    local last_arg="${!#}"
    if [[ "$last_arg" =~ ^@(private|air-gapped)$ ]]; then
        env="${last_arg#@}"
        set -- "${@:1:$#-1}"  # Remove last argument
    fi
    
    for assignment in "$@"; do
        # Parse VAR=value format
        if [[ "$assignment" =~ ^([A-Z_]+)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            update_env_var "$var_name" "$var_value" "$env"
        fi
    done
}

# ============================================================================
# Reload environment from consolidated structure
# Respects ENVIRONMENT variable for environment-specific loading
# ============================================================================
reload_env_overrides() {
    local env="${1:-${ENVIRONMENT:-private}}"
    
    echo "Reloading environment from consolidated structure (environment: $env)"
    
    # Source common defaults first
    if [[ -f "${REPO_ROOT}/.env/_common/defaults" ]]; then
        source "${REPO_ROOT}/.env/_common/defaults"
    fi
    
    # Then source environment-specific overrides
    if [[ -f "${REPO_ROOT}/.env/${env}/overrides" ]]; then
        source "${REPO_ROOT}/.env/${env}/overrides"
    fi
    
    echo "✓ Environment reloaded"
}

# Export functions for use in other scripts
export -f update_env_var
export -f get_env_var
export -f update_env_vars_batch
export -f reload_env_overrides
