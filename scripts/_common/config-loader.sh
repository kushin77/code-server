#!/usr/bin/env bash
################################################################################
# scripts/_common/config-loader.sh
# Unified configuration loading with override hierarchy and validation
# 
# Loads config in this order (later overrides earlier):
# 1. config/_base-config.env (defaults)
# 2. config/_base-config.env.$DEPLOY_ENV (environment-specific)
# 3. .env (local secrets/overrides)
# 4. Command-line arguments (future enhancement)
#
# Usage:
#   source scripts/_common/init.sh  # Auto-sources this
#   config::load  # Load defaults
#   config::get POSTGRES_MEMORY_LIMIT  # Get a value
#   config::set MY_VAR "value"  # Set a value
################################################################################

set -euo pipefail

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# ─ Global config state ─
declare -gA _CONFIG_VALUES
declare -g _CONFIG_LOADED=false

################################################################################
# config::load — Load configuration from environment files
# Usage: config::load [env_name]
################################################################################
config::load() {
    local env_name="${1:-${DEPLOY_ENV:-production}}"
    
    if [[ "$_CONFIG_LOADED" == "true" ]]; then
        return 0
    fi

    # Load base config
    if [[ -f "$PROJECT_ROOT/config/_base-config.env" ]]; then
        set -a
        source "$PROJECT_ROOT/config/_base-config.env"
        set +a
        _config::_store_values
    else
        echo "WARNING: Base config not found: $PROJECT_ROOT/config/_base-config.env" >&2
    fi

    # Load environment-specific overrides
    local env_file="$PROJECT_ROOT/config/_base-config.env.$env_name"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
        _config::_store_values
    fi

    # Load local .env (secrets, personal overrides)
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
        _config::_store_values
    fi

    _CONFIG_LOADED=true
}

################################################################################
# config::get — Retrieve a configuration value
# Usage: config::get VAR_NAME [default_value]
# Returns: Value, or default if not found
################################################################################
config::get() {
    local var_name="$1"
    local default="${2:-}"

    if [[ "${_CONFIG_VALUES[$var_name]:-}" != "" ]]; then
        echo "${_CONFIG_VALUES[$var_name]}"
    elif [[ -v "$var_name" ]]; then
        # Fallback: check environment
        echo "${!var_name}"
    elif [[ -n "$default" ]]; then
        echo "$default"
    else
        echo "ERROR: Config value not found: $var_name" >&2
        return 1
    fi
}

################################################################################
# config::set — Set a configuration value in memory
# Usage: config::set VAR_NAME value
################################################################################
config::set() {
    local var_name="$1"
    local value="$2"
    _CONFIG_VALUES["$var_name"]="$value"
    export "$var_name"="$value"
}

################################################################################
# config::validate — Validate required config values
# Usage: config::validate "VAR1" "VAR2" "VAR3"
# Returns: 0 if all present, 1 if any missing
################################################################################
config::validate() {
    local missing=()
    
    for var_name in "$@"; do
        if [[ -z "${_CONFIG_VALUES[$var_name]:-}" && -z "${!var_name:-}" ]]; then
            missing+=("$var_name")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required config values:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return 1
    fi
}

################################################################################
# config::audit — Print all loaded config (for debugging)
# Usage: config::audit [pattern]  # pattern is optional grep filter
################################################################################
config::audit() {
    local pattern="${1:-.*}"
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║ Configuration Audit                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    for key in $(printf '%s\n' "${!_CONFIG_VALUES[@]}" | sort); do
        if [[ "$key" =~ $pattern ]]; then
            local value="${_CONFIG_VALUES[$key]}"
            # Mask sensitive values
            if [[ "$key" =~ PASSWORD|SECRET|TOKEN|KEY ]]; then
                value="***REDACTED***"
            fi
            printf '  %-45s = %s\n' "$key" "$value"
        fi
    done
    echo ""
}

################################################################################
# Internal: Store all current environment variables in associative array
################################################################################
_config::_store_values() {
    # This is a simplified version. In production, parse the sourced file directly
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        _CONFIG_VALUES["$key"]="$value"
    done < <(compgen -e | while read var; do echo "$var=${!var}"; done 2>/dev/null || true)
}

# Auto-load on source
config::load
