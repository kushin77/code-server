#!/usr/bin/env bash
# @file        scripts/dev/add-metadata-headers.sh
# @module      dev-tooling
# @description Bulk migration tool: adds @file/@module/@description headers to scripts missing them.
#              Idempotent — skips files that already have a @file header.
#              Supports --dry-run mode for preview without modification.
# @owner       platform
# @status      active
# @depends     scripts/_common/init.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
DRY_RUN=false
VERBOSE=false
TARGET_DIR="${SCRIPTS_DIR}"
ACTIVE_ONLY=false

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Adds @file/@module/@description metadata headers to bash scripts missing them.

OPTIONS:
  --dry-run         Preview changes without modifying files
  --verbose         Print all files including already-compliant ones
  --active-only     Only process scripts marked status="active" in scripts/MANIFEST.toml
  --dir PATH        Target directory (default: scripts/)
  --help            Show this help

EXAMPLES:
  $0 --dry-run                   # Preview what would be changed
  $0                             # Apply headers to all non-compliant scripts
  $0 --dir scripts/ci            # Only process scripts/ci/ subdirectory
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true ;;
    --verbose)   VERBOSE=true ;;
    --active-only) ACTIVE_ONLY=true ;;
    --dir)       TARGET_DIR="$2"; shift ;;
    --help|-h)   usage; exit 0 ;;
    *)           echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# Derive @module from path/name heuristics
derive_module() {
  local file="$1"
  local name
  name="$(basename "$file" .sh)"

  case "$name" in
    bootstrap*|provision*)              echo "bootstrap" ;;
    deploy*|rollback*)                  echo "deployment" ;;
    backup*|restore*)                   echo "data-management" ;;
    audit*|logging*)                    echo "audit-logging" ;;
    configure-oidc*|configure-oauth*)   echo "iam" ;;
    configure-rbac*|configure-authz*)   echo "iam" ;;
    configure-workload*)                echo "iam" ;;
    automated-certificate*)             echo "tls" ;;
    automated-deployment*)              echo "deployment" ;;
    automated-env*)                     echo "configuration" ;;
    automated-iac*)                     echo "iac-validation" ;;
    automated-oauth*)                   echo "iam" ;;
    cleanup*)                           echo "maintenance" ;;
    common*|init*)                      echo "common" ;;
    phase-7*|phase-8*)                  echo "ha-deployment" ;;
    security*|scan*)                    echo "security" ;;
    test*|validate*)                    echo "testing" ;;
    vscode*|crash*)                     echo "vscode-stability" ;;
    vpn*|endpoint*)                     echo "networking" ;;
    token*|jwt*)                        echo "auth" ;;
    grafana*|prometheus*|alert*)        echo "observability" ;;
    apply-governance*)                  echo "governance" ;;
    git*)                               echo "git-tooling" ;;
    *)                                  echo "operations" ;;
  esac
}

# Derive @description from filename heuristics
derive_description() {
  local file="$1"
  local name
  name="$(basename "$file" .sh)"
  # Convert kebab-case to sentence
  echo "${name//-/ }" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}' | sed 's/$/ - on-prem code-server enterprise/'
}

# Add header to a single file
add_header() {
  local file="$1"
  local rel_path
  rel_path="${file#${REPO_ROOT}/}"
  local module
  module="$(derive_module "$file")"
  local description
  description="$(derive_description "$file")"

  # Read first line to check for shebang
  local first_line
  first_line="$(head -1 "$file")"
  local header_after_shebang=""

  if [[ "$first_line" == "#!"* ]]; then
    header_after_shebang="${first_line}"$'\n'"# @file        ${rel_path}"$'\n'"# @module      ${module}"$'\n'"# @description ${description}"$'\n'"# @owner       platform"$'\n'"# @status      active"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Would add header to: ${rel_path}"
      echo "          @module: ${module}"
      echo "          @description: ${description}"
    else
      # Get file content after shebang line
      local rest_content
      rest_content="$(tail -n +2 "$file")"
      printf '%s\n%s\n' "${header_after_shebang}" "${rest_content}" > "${file}.tmp"
      mv "${file}.tmp" "${file}"
      echo "  ✅ Added header: ${rel_path}"
    fi
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Would prepend header to: ${rel_path} (no shebang)"
    else
      local content
      content="$(cat "$file")"
      printf '# @file        %s\n# @module      %s\n# @description %s\n# @owner       platform\n# @status      active\n%s\n' \
        "${rel_path}" "${module}" "${description}" "${content}" > "${file}.tmp"
      mv "${file}.tmp" "${file}"
      echo "  ✅ Added header (no shebang): ${rel_path}"
    fi
  fi
}

# Main processing
total=0
skipped=0
added=0

if [[ "${ACTIVE_ONLY}" == "true" ]]; then
  echo "🔍 Scanning active MANIFEST scripts for missing @file headers..."
else
  echo "🔍 Scanning ${TARGET_DIR} for scripts missing @file headers..."
fi
[[ "$DRY_RUN" == "true" ]] && echo "   Mode: DRY RUN — no files will be modified"
echo ""

if [[ "${ACTIVE_ONLY}" == "true" ]]; then
  while IFS=$'\t' read -r rel status; do
    [[ "${status}" == "active" ]] || continue
    file="${REPO_ROOT}/scripts/${rel}"

    total=$((total + 1))

    if [[ ! -f "${file}" ]]; then
      echo "  ⚠️  Missing file from MANIFEST: scripts/${rel}"
      continue
    fi

    if head -5 "$file" | grep -qE "@file"; then
      skipped=$((skipped + 1))
      [[ "$VERBOSE" == "true" ]] && echo "  ⏭️  Already has header: scripts/${rel}"
      continue
    fi

    add_header "$file"
    added=$((added + 1))
  done < <(
    awk -F '"' '
      BEGIN { in_script=0; file=""; status="" }
      /^\[\[script\]\]/ { in_script=1; file=""; status=""; next }
      /^\[\[/ && !/^\[\[script\]\]/ { in_script=0; next }
      !in_script { next }
      /^file[[:space:]]*=/ { file=$2; next }
      /^status[[:space:]]*=/ {
        status=$2;
        if (file!="") print file "\t" status;
      }
    ' "${REPO_ROOT}/scripts/MANIFEST.toml" | sort -u
  )
else
  while IFS= read -r -d '' file; do
    # Skip _common and _archive directories
    [[ "$file" == *"/_common/"* || "$file" == *"/_archive/"* ]] && continue

    total=$((total + 1))

    if head -5 "$file" | grep -qE "@file"; then
      skipped=$((skipped + 1))
      [[ "$VERBOSE" == "true" ]] && echo "  ⏭️  Already has header: ${file#${REPO_ROOT}/}"
      continue
    fi

    add_header "$file"
    added=$((added + 1))
  done < <(find "${TARGET_DIR}" -name "*.sh" -type f -print0 | sort -z)
fi

echo ""
echo "────────────────────────────────────────────────────"
echo "  Total scripts scanned:  ${total}"
echo "  Already compliant:      ${skipped}"
echo "  Headers added:          ${added}"
[[ "$DRY_RUN" == "true" ]] && echo "  (DRY RUN — no changes made)"
echo "────────────────────────────────────────────────────"
