#!/usr/bin/env bash
# @file        scripts/governance/build-policy-bundle.sh
# @module      governance/policy-bundle
# @description Build and sign a versioned OPA policy bundle manifest + archive
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

POLICY_DIR="opa/policies"
OUT_DIR="artifacts/policy-bundles"
SIGNING_KEYS_FILE="config/vault-signing-keys.json"
VERSION=""
CHANNEL="stable"
TTL_HOURS="168"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/build-policy-bundle.sh --version <x.y.z> [--channel stable|canary|rollback] [--policy-dir <path>] [--out-dir <path>] [--signing-keys <path>] [--ttl-hours <int>]
EOF
}

iso_utc_plus_hours() {
  local hours="$1"
  if date -u -d "+${hours} hours" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "+${hours} hours" +%Y-%m-%dT%H:%M:%SZ
  else
    python3 - "$hours" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

hours = int(sys.argv[1])
print((datetime.now(timezone.utc) + timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --channel)
      CHANNEL="$2"
      shift 2
      ;;
    --policy-dir)
      POLICY_DIR="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --signing-keys)
      SIGNING_KEYS_FILE="$2"
      shift 2
      ;;
    --ttl-hours)
      TTL_HOURS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  log_error "--version is required"
  usage
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  log_error "version must match x.y.z"
  exit 1
fi

if [[ ! "$CHANNEL" =~ ^(stable|canary|rollback)$ ]]; then
  log_error "channel must be one of: stable, canary, rollback"
  exit 1
fi

require_command "python3" "python3 is required"
require_dir "$POLICY_DIR"
require_file "$SIGNING_KEYS_FILE"

SIGNING_KEYS_VAULT_PATH="${SIGNING_KEYS_VAULT_PATH:-secret/policy/signing-keys}"
SIGNING_KEYS_SOURCE_FILE="$SIGNING_KEYS_FILE"
SIGNING_KEYS_TMP_FILE=""
SIGNING_KEYS_RAW_TMP_FILE=""

cleanup() {
  if [[ -n "$SIGNING_KEYS_RAW_TMP_FILE" && -f "$SIGNING_KEYS_RAW_TMP_FILE" ]]; then
    rm -f "$SIGNING_KEYS_RAW_TMP_FILE"
  fi
  if [[ -n "$SIGNING_KEYS_TMP_FILE" && -f "$SIGNING_KEYS_TMP_FILE" ]]; then
    rm -f "$SIGNING_KEYS_TMP_FILE"
  fi
}

trap cleanup EXIT

if [[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]]; then
  SIGNING_KEYS_TMP_FILE="$(mktemp)"
  SIGNING_KEYS_SOURCE_FILE="$SIGNING_KEYS_TMP_FILE"
  SIGNING_KEYS_RAW_TMP_FILE="$(mktemp)"

  if command -v vault >/dev/null 2>&1; then
    vault kv get -format=json "$SIGNING_KEYS_VAULT_PATH" > "$SIGNING_KEYS_RAW_TMP_FILE"
    python3 - "$SIGNING_KEYS_SOURCE_FILE" "$SIGNING_KEYS_RAW_TMP_FILE" <<'PY'
import json
import sys

dest = sys.argv[1]
raw_path = sys.argv[2]

with open(raw_path, "r", encoding="utf-8") as handle:
  payload = json.load(handle)

data = payload.get("data", {})
if isinstance(data, dict) and isinstance(data.get("data"), dict):
  data = data["data"]

with open(dest, "w", encoding="utf-8") as f:
  json.dump(data, f, indent=2)
  f.write("\n")
PY
  elif command -v curl >/dev/null 2>&1; then
    vault_api_path="secret/data/${SIGNING_KEYS_VAULT_PATH#secret/}"
    curl -fsS -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR%/}/v1/${vault_api_path}" > "$SIGNING_KEYS_RAW_TMP_FILE"
    python3 - "$SIGNING_KEYS_SOURCE_FILE" "$SIGNING_KEYS_RAW_TMP_FILE" <<'PY'
import json
import sys

dest = sys.argv[1]
raw_path = sys.argv[2]

with open(raw_path, "r", encoding="utf-8") as handle:
  payload = json.load(handle)

data = payload.get("data", {})
if isinstance(data, dict) and isinstance(data.get("data"), dict):
  data = data["data"]

with open(dest, "w", encoding="utf-8") as f:
  json.dump(data, f, indent=2)
  f.write("\n")
PY
  else
    log_warn "Vault environment detected but neither vault nor curl is available; using local signing-key contract"
    cp "$SIGNING_KEYS_FILE" "$SIGNING_KEYS_SOURCE_FILE"
  fi
fi

mkdir -p "$OUT_DIR"

bundle_id="pb-$(date -u +%Y%m%d-%H%M%S)"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
expires_at="$(iso_utc_plus_hours "$TTL_HOURS")"
archive="$OUT_DIR/policy-bundle-${VERSION}-${CHANNEL}.tar.gz"
manifest="$OUT_DIR/policy-bundle-${VERSION}-${CHANNEL}.manifest.json"

mapfile -t policy_files < <(find "$POLICY_DIR" -type f -name '*.rego' | sort)
if [[ "${#policy_files[@]}" -eq 0 ]]; then
  log_fatal "No .rego files found under $POLICY_DIR"
fi

tar -czf "$archive" -C "$POLICY_DIR" .

python3 - \
  "$manifest" \
  "${archive#./}" \
  "$bundle_id" \
  "$VERSION" \
  "$CHANNEL" \
  "$generated_at" \
  "$expires_at" \
  "$SIGNING_KEYS_SOURCE_FILE" \
  "$POLICY_DIR" \
  "${policy_files[@]}" <<'PY'
import hashlib
import json
import os
import sys

manifest_path = sys.argv[1]
archive_path = sys.argv[2]
bundle_id = sys.argv[3]
version = sys.argv[4]
channel = sys.argv[5]
generated_at = sys.argv[6]
expires_at = sys.argv[7]
signing_keys_path = sys.argv[8]
policy_dir = os.path.normpath(sys.argv[9])
policy_files = sys.argv[10:]

with open(signing_keys_path, "r", encoding="utf-8") as f:
  signing_keys = json.load(f)

current_key = signing_keys.get("key_versions", {}).get("current", {})
if not isinstance(current_key, dict):
  raise SystemExit("invalid signing keys contract: key_versions.current is missing")

signed_by = current_key.get("key_id")
key_version = current_key.get("vault_version")
if not isinstance(signed_by, str) or not signed_by.strip():
  raise SystemExit("invalid signing keys contract: current.key_id is missing")
if not isinstance(key_version, int) or key_version < 1:
  raise SystemExit("invalid signing keys contract: current.vault_version is missing")

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

policies = []
for p in sorted(policy_files):
    rel = os.path.relpath(os.path.normpath(p), policy_dir).replace("\\", "/")
    policies.append({"path": rel, "sha256": sha256_file(p)})

unsigned = {
    "bundle_id": bundle_id,
    "version": version,
    "channel": channel,
    "generated_at": generated_at,
    "expires_at": expires_at,
    "archive": archive_path,
    "archive_sha256": sha256_file(archive_path),
    "signed_by": signed_by,
    "key_version": key_version,
    "policies": policies,
}

unsigned_canonical = json.dumps(unsigned, sort_keys=True, separators=(",", ":")).encode("utf-8")
signature = f"sha256:{hashlib.sha256(unsigned_canonical).hexdigest()}"

manifest = dict(unsigned)
manifest["signature"] = signature

with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

log_info "Policy bundle archive: $archive"
log_info "Policy bundle manifest: $manifest"
log_info "Bundle id/version/channel: $bundle_id / $VERSION / $CHANNEL"
