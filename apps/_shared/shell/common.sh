#!/bin/bash
# ==============================================================================
# SHARED SHELL UTILITIES
# ==============================================================================
# Consolidated shell functions used across scripts.
# This replaces scattered implementations across scripts/ops/*.sh
#
# Usage: source apps/_shared/shell/common.sh
# ==============================================================================

set -euo pipefail

# Source guards
[[ "${_SHARED_SHELL_COMMON_SOURCED:-0}" == "1" ]] && return 0
readonly _SHARED_SHELL_COMMON_SOURCED=1

# ==============================================================================
# RETRY LOGIC (used for resilient deployments)
# ==============================================================================

retry() {
  local max_attempts=5
  local delay=2
  local attempt=1
  
  # Parse options
  while [[ $# -gt 0 ]]; do
    case $1 in
      -a|--attempts) max_attempts="$2"; shift 2 ;;
      -d|--delay) delay="$2"; shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  
  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    
    if [[ $attempt -lt $max_attempts ]]; then
      echo "Attempt $attempt failed. Retrying in ${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))  # Exponential backoff
    fi
    
    attempt+=1
  done
  
  echo "Command failed after $max_attempts attempts" >&2
  return 1
}

# ==============================================================================
# FILE OPERATIONS
# ==============================================================================

ensure_file() {
  local file="$1"
  local content="${2:-}"
  
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
    if [[ -n "$content" ]]; then
      echo "$content" > "$file"
    else
      touch "$file"
    fi
  fi
}

ensure_dir() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
  fi
}

# ==============================================================================
# STRING OPERATIONS
# ==============================================================================

trim() {
  local var="$1"
  var="${var#"${var%%[![:space:]]*}"}"  # Remove leading whitespace
  var="${var%"${var##*[![:space:]]}"}"  # Remove trailing whitespace
  echo "$var"
}

contains() {
  local string="$1"
  local substring="$2"
  [[ "$string" == *"$substring"* ]]
}

startswith() {
  local string="$1"
  local prefix="$2"
  [[ "$string" == "$prefix"* ]]
}

endswith() {
  local string="$1"
  local suffix="$2"
  [[ "$string" == *"$suffix" ]]
}

# ==============================================================================
# VALIDATION
# ==============================================================================

assert_not_empty() {
  local var_value="$1"
  local var_name="${2:-value}"
  
  if [[ -z "$var_value" ]]; then
    echo "ERROR: $var_name is empty" >&2
    return 1
  fi
}

assert_file_exists() {
  local file="$1"
  
  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file" >&2
    return 1
  fi
}

assert_dir_exists() {
  local dir="$1"
  
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: Directory not found: $dir" >&2
    return 1
  fi
}

assert_command_exists() {
  local cmd="$1"
  
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Command not found: $cmd" >&2
    return 1
  fi
}

# ==============================================================================
# EXPORTS
# ==============================================================================

export -f retry ensure_file ensure_dir trim contains startswith endswith
export -f assert_not_empty assert_file_exists assert_dir_exists assert_command_exists
