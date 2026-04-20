#!/usr/bin/env bash
# @file        scripts/validate-env.sh
# @module      testing
# @description validate env - on-prem code-server
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# scripts/validate-env.sh - Environment Variable Validation
# ════════════════════════════════════════════════════════════════════════════════════════════
#
# Purpose: Validate that all required environment variables are set and in correct format
# Source of Truth: .env.schema.json
# Trigger: Called before docker-compose up (prevent container startup if validation fails)
# Exit Codes: 0=success, 1=missing variables, 2=invalid format
#
# Usage:
#   bash scripts/validate-env.sh
#   bash scripts/validate-env.sh --strict  (also validate optional vars)
#   bash scripts/validate-env.sh --verbose (show all variables)
# ════════════════════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEMA_FILE="${REPO_ROOT}/.env.schema.json"
VERBOSE=false
STRICT=false
ALLOW_PLACEHOLDERS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --allow-placeholders)
      ALLOW_PLACEHOLDERS=true
      shift
      ;;
    *)
      log_fatal "Unknown option: $1"
      ;;
  esac
done

require_command jq
require_file "$SCHEMA_FILE"

passed=0
failed=0
skipped=0

emit_error() {
  if ! log_error "$*"; then
    :
  fi
}

load_env_file() {
  local env_file="$1"

  if [[ -f "$env_file" ]]; then
    set +u
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    set -u
    log_info "Loaded env file: $(basename "$env_file")"
  else
    log_warn "Missing env file: $(basename "$env_file")"
  fi
}

schema_var_rows() {
  jq -r '
    .groups[].variables
    | to_entries[]
    | [
        .key,
        ((.value.required // false) | tostring),
        (.value.type // ""),
        (.value.format // ""),
        (.value.validation // ""),
        ((.value.enum // []) | join("|")),
        ((.value.secret // false) | tostring)
      ]
    | @tsv
  ' "$SCHEMA_FILE"
}

is_placeholder_value() {
  local value="$1"

  [[ "$value" == "YOUR-"* ]] || [[ "$value" == *"HERE"* ]] || [[ "$value" == "changeme" ]]
}

validate_format() {
  local var_name="$1"
  local value="$2"
  local var_type="$3"
  local var_format="$4"
  local validation_rule="$5"
  local enum_values="$6"

  case "$var_type" in
    integer)
      if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        emit_error "$var_name: expected integer, got '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
    boolean)
      if ! [[ "$value" =~ ^(true|false)$ ]]; then
        emit_error "$var_name: expected boolean true/false, got '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
  esac

  if [[ -n "$enum_values" ]]; then
    local allowed=false
    local enum_value
    IFS='|' read -r -a enum_list <<< "$enum_values"
    for enum_value in "${enum_list[@]}"; do
      if [[ "$value" == "$enum_value" ]]; then
        allowed=true
        break
      fi
    done

    if [[ "$allowed" != "true" ]]; then
      emit_error "$var_name: invalid value '$value' (expected one of: $enum_values)"
      ((failed+=1))
      return 1
    fi
  fi

  case "$var_format" in
    ipv4)
      if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        emit_error "$var_name: invalid IPv4 format '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
    domain)
      if [[ "$value" != "localhost" ]] && ! [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        emit_error "$var_name: invalid domain format '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
    url)
      if ! [[ "$value" =~ ^https?://[^[:space:]]+$ ]]; then
        emit_error "$var_name: invalid URL format '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
    hex)
      if ! [[ "$value" =~ ^[a-fA-F0-9]+$ ]]; then
        emit_error "$var_name: expected hex characters only, got '$value'"
        ((failed+=1))
        return 1
      fi
      ;;
  esac

  if [[ -n "$validation_rule" ]]; then
    if [[ "$validation_rule" =~ ^length==([0-9]+)$ ]]; then
      local expected_length="${BASH_REMATCH[1]}"
      if [[ ${#value} -ne $expected_length ]]; then
        emit_error "$var_name: expected length $expected_length, got ${#value}"
        ((failed+=1))
        return 1
      fi
    fi
  fi

  return 0
}

validate_env() {
  log_info "Validating environment variables against .env.schema.json"

  load_env_file "$REPO_ROOT/.env.defaults"

  local deployment_env="${DEPLOYMENT_ENV:-dev}"
  load_env_file "$REPO_ROOT/.env.${deployment_env}"
  load_env_file "$HOME/.code-server/.env"

  export DEPLOYMENT_ENV="${DEPLOYMENT_ENV:-$deployment_env}"
  log_info "Effective deployment environment: $DEPLOYMENT_ENV"

  local var_name required var_type var_format validation_rule enum_values secret
  while IFS=$'\t' read -r var_name required var_type var_format validation_rule enum_values secret; do
    local value="${!var_name:-}"

    if [[ -z "$value" ]]; then
      if [[ "$required" == "true" ]]; then
        emit_error "$var_name: missing required variable"
        ((failed+=1))
      elif [[ "$STRICT" == "true" ]]; then
        log_warn "$var_name: not set"
        ((skipped+=1))
      else
        ((skipped+=1))
      fi
      continue
    fi

    if is_placeholder_value "$value"; then
      if [[ "$ALLOW_PLACEHOLDERS" == "true" ]]; then
        log_warn "$var_name: placeholder value accepted for preflight gating"
        if [[ "$VERBOSE" == "true" ]]; then
          log_info "$var_name: placeholder (${#value} chars)"
        fi
        ((passed+=1))
        continue
      fi

      emit_error "$var_name: placeholder value detected"
      ((failed+=1))
      continue
    fi

    if ! validate_format "$var_name" "$value" "$var_type" "$var_format" "$validation_rule" "$enum_values"; then
      continue
    fi

    if [[ "$secret" == "true" ]]; then
      log_warn "$var_name: secret value is present in the runtime environment"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
      log_info "$var_name: set (${#value} chars)"
    fi

    ((passed+=1))
  done < <(schema_var_rows)

  echo ""
  log_info "Validation summary"
  log_info "Passed:  $passed"
  log_info "Failed:  $failed"
  log_info "Skipped: $skipped"

  if [[ $failed -gt 0 ]]; then
    emit_error "Validation failed"
    exit 1
  fi

  log_info "Validation passed"
}

validate_env
