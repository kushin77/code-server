#!/bin/bash
# @file        scripts/generate-env-docs.sh
# @module      operations
# @description generate env docs — on-prem code-server
# @owner       platform
# @status      active
# ════════════════════════════════════════════════════════════════════════════════════════════
# scripts/generate-env-docs.sh — Auto-generate ENV_REFERENCE.md from schema
# ════════════════════════════════════════════════════════════════════════════════════════════
#
# Purpose: Auto-generate comprehensive markdown documentation from .env.schema.json
# This ensures docs are always in sync with actual schema
# Source of Truth: .env.schema.json
#
# Usage:
#   bash scripts/generate-env-docs.sh > ENV_REFERENCE.md
#   bash scripts/generate-env-docs.sh | tee ENV_REFERENCE.md
# ════════════════════════════════════════════════════════════════════════════════════════════

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SCHEMA_FILE="${REPO_ROOT}/.env.schema.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found. Install via: apt install jq" >&2
  exit 2
fi

# Check if schema exists
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: Schema file not found: $SCHEMA_FILE" >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Generate documentation
# ─────────────────────────────────────────────────────────────────────────────────────────────

echo "# Environment Variables Reference"
echo ""
echo "**Source of Truth**: [\`.env.schema.json\`](.env.schema.json)"
echo "**Last Generated**: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "**Auto-Generated**: Do NOT edit manually. Update .env.schema.json instead."
echo ""

# Extract header info from schema
echo "## Overview"
echo ""
jq -r '.description' "$SCHEMA_FILE"
echo ""
echo "### Loading Order (Bottom Overwrites Top)"
echo ""

# Generate loading order table
echo "| Priority | File | Description |"
echo "|----------|------|-------------|"
jq -r '.loading_order.sequence[] | "| \(.step) | \(.file) | \(.description) |"' "$SCHEMA_FILE"
echo ""

echo "## All Variables"
echo ""

# For each group, generate a section
jq -r '.groups | keys[]' "$SCHEMA_FILE" | while read -r group; do
  echo "### 📌 $(jq -r ".groups[\"$group\"].description" "$SCHEMA_FILE")"
  echo ""

  # Generate table header
  echo "| Variable | Type | Required | Default | Secret | Description |"
  echo "|----------|------|----------|---------|--------|-------------|"

  # Generate table rows for each variable
  jq -r ".groups[\"$group\"].variables | to_entries[] | 
    \"\(.key) | \(.value.type // \"string\") | \(.value.required // false) | \(.value.default // \"-\") | \(.value.secret // false) | \(.value.description)\""  "$SCHEMA_FILE" | while IFS='|' read -r var type req def secret desc; do
    # Clean up spacing
    var=$(echo "$var" | xargs)
    type=$(echo "$type" | xargs)
    req=$(echo "$req" | xargs)
    def=$(echo "$def" | xargs)
    secret=$(echo "$secret" | xargs)
    desc=$(echo "$desc" | xargs)
    
    # Add secret indicator
    if [[ "$secret" == "true" ]]; then
      secret_ind="🔐"
    else
      secret_ind="-"
    fi
    
    echo "| \`$var\` | $type | $req | $def | $secret_ind | $desc |"
  done
  
  echo ""
done

# Validation section
echo "## Validation"
echo ""
echo "### Required Variables"
echo ""
echo "The following variables MUST be set before deployment:"
echo ""
echo "\`\`\`"
jq -r '.validation.required_variables[]' "$SCHEMA_FILE" | while read -r var; do
  echo "- $var"
done
echo "\`\`\`"
echo ""

echo "### Validation Script"
echo ""
echo "Run validation before deployment:"
echo ""
echo "\`\`\`bash"
echo "bash scripts/validate-env.sh"
echo "\`\`\`"
echo ""
echo "**Exit Codes**:"
echo "- \`0\`: Validation passed"
echo "- \`1\`: Missing required variable(s)"
echo "- \`2\`: Invalid variable format"
echo ""

# Secret variables section
echo "## Secret Variables"
echo ""
echo "🔐 These variables contain sensitive data and MUST be kept secure:"
echo ""
echo "| Variable | Vault Path | Rotation |"
echo "|----------|------------|----------|"

jq -r '.secret_variables.variables[] as $var | 
  if (.groups[].variables[$var].vault_path != null) then 
    "| \($var) | \(.groups[].variables[$var].vault_path // \"N/A\") | 90 days |"
  else
    "| \($var) | N/A | 90 days |"
  end' "$SCHEMA_FILE" 2>/dev/null | sort -u || true

echo ""
echo "**Storage**:"
jq -r '"\n- " + .secret_variables.storage' "$SCHEMA_FILE"
echo ""

echo "**Rotation Policy**:"
jq -r '"\n" + .secret_variables.rotation_policy' "$SCHEMA_FILE"
echo ""

# Implementation phases
echo "## Implementation Phases"
echo ""

jq -r '.implementation_phases | to_entries[] | 
  "\n### \(.value.name) (Phase \(.key | gsub(\"phase_\"; \"\")))\n\n**Target**: \(.value.target_date)\n\n**Tasks**:\n" + 
  ((.value.tasks | map("- " + .)) | join("\n"))' "$SCHEMA_FILE"

echo ""
echo "## Examples"
echo ""
echo "### Development Setup"
echo ""
echo "\`\`\`bash"
echo "# Load defaults + dev overrides"
echo "set -a"
echo "source .env.defaults"
echo "source .env.dev"
echo "set +a"
echo ""
echo "# Validate"
echo "bash scripts/validate-env.sh"
echo "\`\`\`"
echo ""

echo "### Production Setup"
echo ""
echo "\`\`\`bash"
echo "# Load defaults + production overrides + Vault secrets"
echo "set -a"
echo "source .env.defaults"
echo "source .env.production"
echo "export GOOGLE_CLIENT_SECRET=\$(vault kv get -field=value secret/oauth2/google/client_secret)"
echo "export POSTGRES_PASSWORD=\$(vault kv get -field=value secret/postgres/password)"
echo "set +a"
echo ""
echo "# Validate"
echo "bash scripts/validate-env.sh --strict"
echo ""
echo "# Deploy"
echo "docker-compose up -d"
echo "\`\`\`"
echo ""

echo "---"
echo ""
echo "**Last Updated**: $(date)"
echo "**Schema Version**: $(jq -r '.version' "$SCHEMA_FILE")"
