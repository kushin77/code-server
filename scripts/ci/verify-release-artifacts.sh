#!/usr/bin/env bash

################################################################################
# @file verify-release-artifacts.sh
# @module ci/release
# @description Verify release assets and checksum manifest for published releases
# @governance GOV-002: Immutable, version-controlled, idempotent verification
################################################################################

set -euo pipefail

if [[ -z "${GITHUB_EVENT_PATH:-}" ]]; then
  echo "GITHUB_EVENT_PATH is required"
  exit 2
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required"
  exit 2
fi

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

metadata_file="${work_dir}/release-metadata.txt"
python3 - <<'PY' > "${metadata_file}"
import json
import os
import sys

path = os.environ["GITHUB_EVENT_PATH"]
with open(path, "r", encoding="utf-8") as f:
    payload = json.load(f)

release = payload.get("release")
if not release:
    print("ERROR: release payload not found", file=sys.stderr)
    sys.exit(1)

print(f"TAG={release.get('tag_name', '')}")
print(f"ID={release.get('id', '')}")
for asset in release.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name and url:
        print(f"ASSET={name}|{url}")
PY

# shellcheck disable=SC1090
source "${metadata_file}"

echo "Verifying release tag: ${TAG:-unknown}"

assets_dir="${work_dir}/assets"
mkdir -p "${assets_dir}"

checksum_file=""
non_checksum_assets=0

while IFS= read -r line; do
  [[ "${line}" =~ ^ASSET= ]] || continue
  spec="${line#ASSET=}"
  name="${spec%%|*}"
  url="${spec#*|}"

  output_path="${assets_dir}/${name}"
  echo "Downloading asset: ${name}"
  curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/octet-stream" \
    "${url}" -o "${output_path}"

  if [[ "${name,,}" =~ ^(sha256sums(\.txt)?|checksums(\.txt)?)$ ]]; then
    checksum_file="${output_path}"
  else
    non_checksum_assets=$((non_checksum_assets + 1))
  fi
done < "${metadata_file}"

if [[ ${non_checksum_assets} -eq 0 ]]; then
  echo "No release artifacts found (excluding checksum manifest)"
  exit 1
fi

if [[ -z "${checksum_file}" ]]; then
  echo "Checksum manifest missing (expected SHA256SUMS or checksums.txt)"
  exit 1
fi

filtered_checksums="${assets_dir}/checksums.filtered"
: > "${filtered_checksums}"
verified_entries=0

while IFS= read -r raw_line; do
  [[ -z "${raw_line}" ]] && continue

  # Expected line format: <hash> <space><space or *> <filename>
  hash_part="$(printf '%s\n' "${raw_line}" | awk '{print $1}')"
  file_part="$(printf '%s\n' "${raw_line}" | awk '{print $2}')"

  [[ -z "${hash_part}" || -z "${file_part}" ]] && continue
  file_part="${file_part#*}"
  file_name="$(basename "${file_part}")"

  if [[ -f "${assets_dir}/${file_name}" ]]; then
    printf '%s  %s\n' "${hash_part}" "${file_name}" >> "${filtered_checksums}"
    verified_entries=$((verified_entries + 1))
  fi
done < "${checksum_file}"

if [[ ${verified_entries} -eq 0 ]]; then
  echo "Checksum manifest does not reference any downloaded release artifacts"
  exit 1
fi

(
  cd "${assets_dir}"
  sha256sum -c "${filtered_checksums}"
)

echo "Release artifact verification passed (${verified_entries} artifact checksum entries validated)."
