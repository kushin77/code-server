#!/usr/bin/env bash
# @file        scripts/governance/calculate-governance-score.sh
# @module      governance/metrics
# @description Calculate governance debt counts and composite governance score from canonical repo checks
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${REPO_ROOT}/scripts/MANIFEST.toml"
FORMAT="env"

usage() {
  cat <<'EOF'
Usage: calculate-governance-score.sh [--format env|markdown|prometheus]

Outputs governance score inputs derived from canonical repo checks:
- jscpd violations
- missing metadata headers in active MANIFEST scripts
- hardcoded IP files in active top-level scripts
- active compatibility shims with fallback implementations
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${MANIFEST}" ]]; then
  echo "scripts/MANIFEST.toml not found: ${MANIFEST}" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

count_jscpd_violations() {
  local report_dir="${TMP_DIR}/jscpd"
  local report_file="${report_dir}/jscpd-report.json"

  mkdir -p "${report_dir}"

  if ! command -v jscpd >/dev/null 2>&1; then
    echo 0
    return 0
  fi

  (
    cd "${REPO_ROOT}"
    jscpd \
      --min-lines 5 \
      --min-tokens 30 \
      --threshold 0.9 \
      --exclude-pattern '**/archived/**' \
      --exclude-pattern '**/.git/**' \
      --exclude-pattern '**/node_modules/**' \
      --reporter json \
      --output "${report_dir}" \
      . >/dev/null 2>&1 || true
  )

  if [[ ! -f "${report_file}" ]]; then
    echo 0
    return 0
  fi

  jq -r '
    if (.duplicates? | type) == "array" then
      (.duplicates | length)
    elif (.clones? | type) == "array" then
      (.clones | length)
    elif .statistics.total.duplicates? then
      .statistics.total.duplicates
    elif .statistics.total.clones? then
      .statistics.total.clones
    else
      0
    end
  ' "${report_file}" 2>/dev/null || echo 0
}

count_missing_headers() {
  local failures=0
  local rel_path
  local purpose
  local script_path
  local header

  while IFS=$'\t' read -r rel_path purpose; do
    script_path="${REPO_ROOT}/scripts/${rel_path}"

    if [[ ! -f "${script_path}" ]]; then
      failures=$((failures + 1))
      continue
    fi

    header="$(head -12 "${script_path}")"
    if ! grep -qE '^# @file[[:space:]]+scripts/' <<<"${header}" \
      || ! grep -qE '^# @module[[:space:]]+[^[:space:]].*$' <<<"${header}" \
      || ! grep -qE '^# @description[[:space:]]+[^[:space:]].*$' <<<"${header}"; then
      failures=$((failures + 1))
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

  echo "${failures}"
}

count_hardcoded_ip_files() {
  local count=0

  count=$(find "${REPO_ROOT}/scripts" -maxdepth 1 -type f -name '*.sh' -print0 \
    | xargs -0 grep -lE '192\.168\.168\.(30|31|42)\b' 2>/dev/null || true)
  count=$(printf '%s\n' "${count}" | sed '/^$/d' | wc -l | tr -d ' ')

  echo "${count:-0}"
}

count_active_shims_with_fallback() {
  local count=0
  local file

  while IFS= read -r -d '' file; do
    if grep -q 'compatibility shim' "${file}" && grep -q 'Fallback: original implementation' "${file}"; then
      count=$((count + 1))
    fi
  done < <(find "${REPO_ROOT}/scripts" -maxdepth 1 -type f -name '*.sh' -print0)

  echo "${count}"
}

JSCPD_VIOLATIONS="$(count_jscpd_violations)"
MISSING_HEADERS="$(count_missing_headers)"
HARDCODED_IPS="$(count_hardcoded_ip_files)"
ACTIVE_SHIMS_WITH_FALLBACK="$(count_active_shims_with_fallback)"

RAW_SCORE=$((100 \
  - (JSCPD_VIOLATIONS * 5) \
  - (MISSING_HEADERS * 2) \
  - (HARDCODED_IPS * 10) \
  - (ACTIVE_SHIMS_WITH_FALLBACK * 8)))

if (( RAW_SCORE < 0 )); then
  GOVERNANCE_SCORE=0
elif (( RAW_SCORE > 100 )); then
  GOVERNANCE_SCORE=100
else
  GOVERNANCE_SCORE="${RAW_SCORE}"
fi

case "${FORMAT}" in
  env)
    cat <<EOF
GOVERNANCE_SCORE=${GOVERNANCE_SCORE}
JSCPD_VIOLATIONS=${JSCPD_VIOLATIONS}
MISSING_HEADERS=${MISSING_HEADERS}
HARDCODED_IPS=${HARDCODED_IPS}
ACTIVE_SHIMS_WITH_FALLBACK=${ACTIVE_SHIMS_WITH_FALLBACK}
EOF
    ;;
  markdown)
    cat <<EOF
## Governance Score

| Signal | Count | Penalty |
|---|---:|---:|
| jscpd violations | ${JSCPD_VIOLATIONS} | $((JSCPD_VIOLATIONS * 5)) |
| missing headers | ${MISSING_HEADERS} | $((MISSING_HEADERS * 2)) |
| hardcoded IP files | ${HARDCODED_IPS} | $((HARDCODED_IPS * 10)) |
| active fallback shims | ${ACTIVE_SHIMS_WITH_FALLBACK} | $((ACTIVE_SHIMS_WITH_FALLBACK * 8)) |

**Governance Score:** ${GOVERNANCE_SCORE}/100

Formula:

    score = max(0, 100
  - (jscpd_violations * 5)
  - (missing_headers * 2)
  - (hardcoded_ips * 10)
  - (active_shims_with_fallback * 8))
EOF
    ;;
  prometheus)
    cat <<EOF
# HELP governance_score Composite governance score for the current repository snapshot.
# TYPE governance_score gauge
governance_score ${GOVERNANCE_SCORE}
# HELP governance_score_jscpd_violations jscpd duplicate clusters contributing to governance score penalty.
# TYPE governance_score_jscpd_violations gauge
governance_score_jscpd_violations ${JSCPD_VIOLATIONS}
# HELP governance_score_missing_headers Active MANIFEST scripts missing required metadata headers.
# TYPE governance_score_missing_headers gauge
governance_score_missing_headers ${MISSING_HEADERS}
# HELP governance_score_hardcoded_ips Active top-level scripts containing hardcoded IP addresses.
# TYPE governance_score_hardcoded_ips gauge
governance_score_hardcoded_ips ${HARDCODED_IPS}
# HELP governance_score_active_shims_with_fallback Active compatibility shims retaining fallback implementations.
# TYPE governance_score_active_shims_with_fallback gauge
governance_score_active_shims_with_fallback ${ACTIVE_SHIMS_WITH_FALLBACK}
EOF
    ;;
  *)
    echo "Unsupported format: ${FORMAT}" >&2
    exit 1
    ;;
esac