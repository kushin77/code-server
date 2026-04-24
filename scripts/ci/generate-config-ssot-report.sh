#!/usr/bin/env bash
# @file        scripts/ci/generate-config-ssot-report.sh
# @module      ci/config-validation
# @description Generate a configuration SSOT report from canonical ownership mappings.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

CONFIG_SSOT_DOC="$REPO_ROOT/docs/governance/CONFIG-SSOT.md"
REPORT_DIR="$REPO_ROOT/artifacts/config-ssot"
REPORT_JSON="$REPORT_DIR/config-ssot-report.json"
REPORT_MD="$REPORT_DIR/config-ssot-report.md"

mkdir -p "$REPORT_DIR"

python3 - "$CONFIG_SSOT_DOC" "$REPORT_JSON" "$REPORT_MD" <<'PY'
import json
import sys
from pathlib import Path

doc_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])
md_path = Path(sys.argv[3])

if not doc_path.exists():
    raise SystemExit(f"Missing SSOT document: {doc_path}")

lines = doc_path.read_text(encoding="utf-8").splitlines()
rows = []
inside = False
for line in lines:
    if line.startswith("| Config class |"):
        inside = True
        continue
    if inside and not line.startswith("|"):
        break
    if inside:
        if line.startswith("|---"):
            continue
        parts = [part.strip() for part in line.strip("|").split("|")]
        if len(parts) == 3 and parts[0] != "Config class":
            rows.append({
                "config_class": parts[0],
                "canonical_owner": parts[1],
                "consuming_surfaces": parts[2],
            })

report = {
    "source": str(doc_path.relative_to(doc_path.parents[2])),
    "count": len(rows),
    "entries": rows,
}

json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

md_lines = [
    "# Configuration SSOT Report",
    "",
    f"Source: `{report['source']}`",
    f"Count: {report['count']}",
    "",
    "| Config class | Canonical owner | Consuming surfaces |",
    "|---|---|---|",
]
for row in rows:
    md_lines.append(f"| {row['config_class']} | {row['canonical_owner']} | {row['consuming_surfaces']} |")

md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")
PY

log_success "Configuration SSOT report generated"
log_info "JSON: $REPORT_JSON"
log_info "Markdown: $REPORT_MD"