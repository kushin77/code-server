#!/usr/bin/env bash
# @file        scripts/ci/check-autopilot-setup-drift.sh
# @module      ci/ide
# @description Regression guard for false-positive Autopilot setup prompts.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

readonly REPORT_FILE="${AUTOPILOT_SETUP_REPORT:-/tmp/autopilot-setup-drift-report.json}"

require_command "python3" "python3 is required for report validation"

log_info "Running setup-state reconciler in dry-run mode"
if ! SETUP_RECONCILE_REPORT="$REPORT_FILE" bash "$SCRIPT_DIR/../ops/reconcile-setup-state.sh" --dry-run >/tmp/autopilot-setup-drift.log; then
    log_warn "setup-state reconciler reported capability gaps; evaluating for false-positive drift only"
fi

python3 - "$REPORT_FILE" <<'PY'
import json
import sys

report_path = sys.argv[1]
with open(report_path, encoding="utf-8") as handle:
    report = json.load(handle)

probes = {probe["probe"]: probe for probe in report.get("probes", [])}
missing_reason_codes = [probe["probe"] for probe in report.get("probes", []) if not probe.get("reason_code")]
if missing_reason_codes:
    print("Missing reason_code fields:", ", ".join(sorted(missing_reason_codes)), file=sys.stderr)
    sys.exit(1)

healthy_prereqs = all(
    probes.get(name, {}).get("status") == "ok"
    for name in [
        "git-credential-helper",
        "auth-keepalive",
        "gsm-env-canonical",
        "code-server-auth-doctor",
    ]
    if name in probes
)

setup_flags = probes.get("setup-state-flags", {})
if healthy_prereqs and setup_flags.get("status") == "fail":
    print(
        "Autopilot setup drift detected despite healthy prerequisites: "
        + setup_flags.get("reason_code", "UNKNOWN"),
        file=sys.stderr,
    )
    sys.exit(1)
PY

log_info "Autopilot setup-state regression guard passed"