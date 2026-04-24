#!/usr/bin/env bash
# @file        scripts/governance/verify-policy-bundle.sh
# @module      governance/policy-bundle
# @description Verify policy bundle manifest signature and rollback safety against catalog
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

MANIFEST=""
CATALOG="config/policy-bundles/bundle-catalog.json"
SCHEMA="config/policy-bundles/bundle-schema.json"
SIGNING_KEYS="config/vault-signing-keys.json"
POLICY_DIR="opa/policies"
ALLOW_ROLLBACK="false"

usage() {
  cat <<'EOF'
Usage:
  scripts/governance/verify-policy-bundle.sh --manifest <path> [--catalog <path>] [--schema <path>] [--signing-keys <path>] [--policy-dir <path>] [--allow-rollback]
EOF
}

normalize_path() {
  local p="$1"
  echo "${p#./}"
}

version_lt() {
  local a="$1"
  local b="$2"
  local first
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)"
  [[ "$first" == "$a" && "$a" != "$b" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="$2"
      shift 2
      ;;
    --catalog)
      CATALOG="$2"
      shift 2
      ;;
    --schema)
      SCHEMA="$2"
      shift 2
      ;;
    --signing-keys)
      SIGNING_KEYS="$2"
      shift 2
      ;;
    --policy-dir)
      POLICY_DIR="$2"
      shift 2
      ;;
    --allow-rollback)
      ALLOW_ROLLBACK="true"
      shift
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

if [[ -z "$MANIFEST" ]]; then
  log_error "--manifest is required"
  usage
  exit 1
fi

require_command "python3" "python3 is required"
require_file "$MANIFEST"
require_file "$CATALOG"
require_file "$SCHEMA"
require_file "$SIGNING_KEYS"
require_dir "$POLICY_DIR"

SIGNING_KEYS_VAULT_PATH="${SIGNING_KEYS_VAULT_PATH:-secret/policy/signing-keys}"
SIGNING_KEYS_SOURCE_FILE="$SIGNING_KEYS"
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
    cp "$SIGNING_KEYS" "$SIGNING_KEYS_SOURCE_FILE"
  fi
fi

mapfile -t verify_values < <(python3 - "$MANIFEST" "$CATALOG" "$SCHEMA" "$SIGNING_KEYS_SOURCE_FILE" "$POLICY_DIR" <<'PY'
import datetime
import hashlib
import json
import os
import re
import sys

manifest_path = sys.argv[1]
catalog_path = sys.argv[2]
schema_path = sys.argv[3]
signing_keys_path = sys.argv[4]
policy_dir = os.path.normpath(sys.argv[5])

with open(manifest_path, "r", encoding="utf-8") as f:
  manifest = json.load(f)

with open(catalog_path, "r", encoding="utf-8") as f:
  catalog = json.load(f)

with open(schema_path, "r", encoding="utf-8") as f:
  schema = json.load(f)

with open(signing_keys_path, "r", encoding="utf-8") as f:
  signing_keys = json.load(f)

def fatal(msg: str) -> None:
  print(msg, file=sys.stderr)
  sys.exit(1)

warnings = []

def sha256_file(path: str) -> str:
  h = hashlib.sha256()
  with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
      h.update(chunk)
  return h.hexdigest()

def normalize_path(path: str) -> str:
  return path[2:] if path.startswith("./") else path

required = schema.get("required", [])
for key in required:
  if key not in manifest:
    fatal(f"Manifest failed required schema checks: missing key '{key}'")

props = schema.get("properties", {})
bundle_id_pattern = props.get("bundle_id", {}).get("pattern", r"^pb-[0-9]{8}-[0-9]{6}$")
version_pattern = props.get("version", {}).get("pattern", r"^[0-9]+\.[0-9]+\.[0-9]+$")
channel_enum = props.get("channel", {}).get("enum", ["canary", "stable", "rollback"])
signature_pattern = props.get("signature", {}).get("pattern", r"^sha256:[a-f0-9]{64}$")
policy_sha_pattern = props.get("policies", {}).get("items", {}).get("properties", {}).get("sha256", {}).get("pattern", r"^[a-f0-9]{64}$")

key_versions = signing_keys.get("key_versions", {})
current_key = key_versions.get("current", {})
previous_key = key_versions.get("previous", {})
verification_rules = signing_keys.get("verification_rules", {})

if not isinstance(current_key, dict):
  fatal("Signing keys contract invalid: missing current key metadata")
if not isinstance(previous_key, dict):
  fatal("Signing keys contract invalid: missing previous key metadata")

current_key_id = current_key.get("key_id")
previous_key_id = previous_key.get("key_id")
current_key_version = current_key.get("vault_version")
previous_key_version = previous_key.get("vault_version")

accept_current = verification_rules.get("accept_current", True)
accept_previous = verification_rules.get("accept_previous_valid_versions", True)
reject_unknown_key_ids = verification_rules.get("reject_unknown_key_ids", True)
key_version_mismatch_action = verification_rules.get("key_version_mismatch_action", "warn")

if not isinstance(manifest.get("bundle_id"), str) or not re.match(bundle_id_pattern, manifest["bundle_id"]):
  fatal("Manifest failed required schema checks: invalid bundle_id")
if not isinstance(manifest.get("version"), str) or not re.match(version_pattern, manifest["version"]):
  fatal("Manifest failed required schema checks: invalid version")
if manifest.get("channel") not in channel_enum:
  fatal("Manifest failed required schema checks: invalid channel")
if not isinstance(manifest.get("archive"), str) or not manifest["archive"]:
  fatal("Manifest failed required schema checks: invalid archive")
if not isinstance(manifest.get("archive_sha256"), str) or not re.match(r"^[a-f0-9]{64}$", manifest["archive_sha256"]):
  fatal("Manifest failed required schema checks: invalid archive_sha256")
if not isinstance(manifest.get("signature"), str) or not re.match(signature_pattern, manifest["signature"]):
  fatal("Manifest failed required schema checks: invalid signature")
if not isinstance(manifest.get("policies"), list) or not manifest["policies"]:
  fatal("Manifest failed required schema checks: policies must be a non-empty array")

manifest_signed_by = manifest.get("signed_by")
manifest_key_version = manifest.get("key_version")

if manifest_signed_by is None:
  warnings.append("Manifest missing signed_by; inferring current signing key from contract")
  manifest_signed_by = current_key_id
if manifest_key_version is None:
  warnings.append("Manifest missing key_version; inferring current signing key version from contract")
  manifest_key_version = current_key_version

if not isinstance(manifest_signed_by, str) or not manifest_signed_by.strip():
  fatal("Manifest failed required schema checks: invalid signed_by")
if not isinstance(manifest_key_version, int) or manifest_key_version < 1:
  fatal("Manifest failed required schema checks: invalid key_version")

accepted_key_ids = []
if accept_current and isinstance(current_key_id, str) and current_key_id.strip():
  accepted_key_ids.append(current_key_id)
if accept_previous and isinstance(previous_key_id, str) and previous_key_id.strip():
  accepted_key_ids.append(previous_key_id)

if manifest_signed_by not in accepted_key_ids:
  if reject_unknown_key_ids:
    fatal(f"Manifest signed_by '{manifest_signed_by}' is not accepted by the signing contract")
  warnings.append(f"Manifest signed_by '{manifest_signed_by}' is not in the accepted key set")

expected_key_version = None
if manifest_signed_by == current_key_id:
  expected_key_version = current_key_version
elif manifest_signed_by == previous_key_id:
  expected_key_version = previous_key_version

if expected_key_version is not None and manifest_key_version != expected_key_version:
  mismatch = (
    f"Manifest key_version {manifest_key_version} does not match expected vault version {expected_key_version} "
    f"for signing key {manifest_signed_by}"
  )
  if key_version_mismatch_action == "deny":
    fatal(mismatch)
  warnings.append(mismatch)

for p in manifest["policies"]:
  if not isinstance(p, dict):
    fatal("Manifest failed required schema checks: policy entry must be object")
  if not isinstance(p.get("path"), str) or not p["path"]:
    fatal("Manifest failed required schema checks: policy path is invalid")
  if not isinstance(p.get("sha256"), str) or not re.match(policy_sha_pattern, p["sha256"]):
    fatal("Manifest failed required schema checks: policy sha256 is invalid")

unsigned = dict(manifest)
signature = unsigned.pop("signature", "")
if signature.startswith("sha256:"):
  actual = "sha256:" + hashlib.sha256(
    json.dumps(unsigned, sort_keys=True, separators=(",", ":")).encode("utf-8")
  ).hexdigest()
  if signature != actual:
    fatal(f"Bundle signature mismatch: expected={signature} actual={actual}")
elif signature.startswith("RS256:"):
  fatal("RS256 signatures are declared by schema but not supported by this verifier yet")
else:
  fatal("Unsupported signature algorithm in bundle manifest")

try:
  expires = datetime.datetime.strptime(manifest["expires_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
except ValueError:
  fatal("Manifest failed required schema checks: invalid expires_at")
if expires <= datetime.datetime.now(datetime.timezone.utc):
  fatal("Bundle manifest is expired and cannot be used")

archive_path = normalize_path(manifest["archive"])
if not os.path.isfile(archive_path):
  fatal(f"Bundle archive file not found: {archive_path}")
archive_actual = sha256_file(archive_path)
if archive_actual != manifest["archive_sha256"]:
  fatal(f"Bundle archive digest mismatch: expected={manifest['archive_sha256']} actual={archive_actual}")

for p in manifest["policies"]:
  policy_file = os.path.join(policy_dir, p["path"])
  if not os.path.isfile(policy_file):
    fatal(f"Policy file not found: {policy_file}")
  actual_policy_sha = sha256_file(policy_file)
  if actual_policy_sha != p["sha256"]:
    fatal(f"Policy file digest mismatch: {policy_file}")

channel = manifest.get("channel", "")
version = manifest.get("version", "")
stable_version = catalog.get("channels", {}).get("stable", {}).get("version", "0.0.0")
catalog_manifest = catalog.get("channels", {}).get(channel, {}).get("bundle_manifest", "")
if catalog_manifest and normalize_path(catalog_manifest) != normalize_path(manifest_path):
  fatal(f"Catalog channel pointer mismatch for '{channel}': catalog={catalog_manifest} manifest={manifest_path}")

print(channel)
print(version)
print(stable_version)
for warning in warnings:
  print(f"WARN: {warning}", file=sys.stderr)
PY
)

channel="${verify_values[0]:-}"
version="${verify_values[1]:-}"
stable_version="${verify_values[2]:-0.0.0}"

if [[ "$channel" == "rollback" && "$ALLOW_ROLLBACK" != "true" ]]; then
  log_fatal "Rollback channel requires --allow-rollback"
fi

if [[ "$ALLOW_ROLLBACK" != "true" ]]; then
  if version_lt "$version" "$stable_version"; then
    log_fatal "Version downgrade detected: $version vs $stable_version. Use --allow-rollback with audit approval."
  fi
fi

log_info "Bundle verification passed: version=$version channel=$channel"
