#!/usr/bin/env bash
# @file        scripts/ci/validate-policy-domain-registry.sh
# @module      ci/governance
# @description Validate governance policy domain registry and canonical source mappings
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_FILE="${1:-$ROOT_DIR/config/governance-policy-domains.json}"
POLICY_INDEX_FILE="${2:-$ROOT_DIR/docs/governance/POLICY-INDEX.md}"
REPORT_FILE="${3:-$ROOT_DIR/policy-domain-registry-report.json}"

require_file "$REGISTRY_FILE"
require_file "$POLICY_INDEX_FILE"
require_command "python3" "python3 is required"

python3 - "$ROOT_DIR" "$REGISTRY_FILE" "$POLICY_INDEX_FILE" "$REPORT_FILE" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone

root_dir, registry_file, policy_index_file, report_file = sys.argv[1:5]

with open(registry_file, "r", encoding="utf-8") as f:
    data = json.load(f)

with open(policy_index_file, "r", encoding="utf-8") as f:
    policy_index_text = f.read()

errors = []
warnings = []

domains = data.get("domains")
if not isinstance(domains, list) or len(domains) == 0:
    errors.append("domains must be a non-empty array")
    domains = []

required_ids = {"security", "quality", "ci", "infra"}
seen_ids = set()

for i, d in enumerate(domains):
    ctx = f"domains[{i}]"
    if not isinstance(d, dict):
        errors.append(f"{ctx} must be an object")
        continue

    for key in ["id", "name", "canonical_source", "primary_owner", "secondary_owner"]:
        val = d.get(key)
        if not isinstance(val, str) or not val.strip():
            errors.append(f"{ctx}.{key} must be a non-empty string")

    domain_id = d.get("id", "")
    if isinstance(domain_id, str):
        if domain_id in seen_ids:
            errors.append(f"duplicate domain id: {domain_id}")
        seen_ids.add(domain_id)

    src = d.get("canonical_source", "")
    if isinstance(src, str) and src:
        src_abs = os.path.normpath(os.path.join(root_dir, src))
        if not os.path.exists(src_abs):
            errors.append(f"canonical_source path does not exist: {src}")
        if src not in policy_index_text:
            warnings.append(f"canonical_source not referenced in POLICY-INDEX: {src}")

missing_required = sorted(required_ids - seen_ids)
for mid in missing_required:
    errors.append(f"missing required domain id: {mid}")

report = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "registry": registry_file,
    "policy_index": policy_index_file,
    "summary": {
        "domain_count": len(domains),
        "error_count": len(errors),
        "warning_count": len(warnings),
    },
    "errors": errors,
    "warnings": warnings,
}

with open(report_file, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
    f.write("\n")

print(f"Policy domain registry report: {report_file}")
print(f"Errors: {len(errors)}")
print(f"Warnings: {len(warnings)}")

if errors:
    sys.exit(1)

PY
