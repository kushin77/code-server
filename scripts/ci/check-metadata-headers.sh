#!/usr/bin/env bash
# @file        scripts/ci/check-metadata-headers.sh
# @module      governance
# @description Enforce @file/@module/@description metadata on active MANIFEST scripts and cross-check MANIFEST purpose.
# @owner       platform
# @status      active

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/scripts/MANIFEST.toml"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "ERROR: MANIFEST not found: ${MANIFEST}"
  exit 1
fi

normalize() {
  tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9 ]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//'
}

failures=0
total=0
warnings=0

while IFS=$'\t' read -r rel_path purpose; do
  script_path="${REPO_ROOT}/scripts/${rel_path}"
  total=$((total + 1))

  if [[ ! -f "${script_path}" ]]; then
    echo "ERROR: active MANIFEST script missing from disk: scripts/${rel_path}"
    failures=$((failures + 1))
    continue
  fi

  header="$(head -12 "${script_path}")"

  if ! grep -qE '^# @file[[:space:]]+scripts/' <<<"${header}"; then
    echo "ERROR: missing @file header: scripts/${rel_path}"
    failures=$((failures + 1))
  fi

  if ! grep -qE '^# @module[[:space:]]+[^[:space:]].*$' <<<"${header}"; then
    echo "ERROR: missing @module header: scripts/${rel_path}"
    failures=$((failures + 1))
  fi

  if ! grep -qE '^# @description[[:space:]]+[^[:space:]].*$' <<<"${header}"; then
    echo "ERROR: missing @description header: scripts/${rel_path}"
    failures=$((failures + 1))
    continue
  fi

  if [[ -n "${purpose}" && "${purpose}" != "TODO: add purpose" ]]; then
    manifest_norm="$(printf '%s' "${purpose}" | normalize)"
    desc_line="$(grep -E '^# @description' <<<"${header}" | head -1 | sed -E 's/^# @description[[:space:]]+//')"
    desc_norm="$(printf '%s' "${desc_line}" | normalize)"

    if [[ "${desc_norm}" != *"${manifest_norm}"* ]]; then
      echo "ERROR: purpose/header drift: scripts/${rel_path}"
      echo "  MANIFEST purpose: ${purpose}"
      echo "  Header desc:      ${desc_line}"
      failures=$((failures + 1))
    fi
  else
    warnings=$((warnings + 1))
    echo "WARN: TODO purpose in MANIFEST (cross-ref skipped): scripts/${rel_path}"
  fi
done < <(
  awk -F '"' '
    BEGIN { in_script=0; file=""; status=""; purpose="" }
    /^\[\[script\]\]/ { in_script=1; file=""; status=""; purpose=""; next }
    /^\[\[/ && !/^\[\[script\]\]/ { in_script=0; next }
    !in_script { next }
    /^file[[:space:]]*=/ { file=$2; next }
    /^status[[:space:]]*=/ { status=$2; next }
    /^purpose[[:space:]]*=/ {
      purpose=$2;
      if (status=="active" && file!="") {
        print file "\t" purpose;
      }
      next
    }
  ' "${MANIFEST}" | sort -u
)

echo ""
echo "Metadata header audit complete"
echo "Active scripts scanned: ${total}"
echo "Warnings: ${warnings}"

if [[ ${failures} -gt 0 ]]; then
  echo "Failures: ${failures}"
  exit 1
fi

echo "Failures: 0"
echo "PASS: active scripts satisfy GOV-002 metadata header requirements"
