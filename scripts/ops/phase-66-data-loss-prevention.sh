#!/usr/bin/env bash
# =============================================================================
# Phase 66 — Data Loss Prevention & Exfiltration Detection Engine
# Ops script: demo | summary | report | persist
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENGINE_MODULE="apps.security_ai.data_loss_prevention_engine"

# ---------------------------------------------------------------------------
# Logging helpers (always write to stderr to keep stdout clean for JSON)
# ---------------------------------------------------------------------------
log_info()  { echo "[INFO]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ---------------------------------------------------------------------------
# Traps
# ---------------------------------------------------------------------------
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..." >&2; rm -f /tmp/p66*.tmp 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
run_python() {
    cd "${REPO_ROOT}" && python3 - "$@"
}

# ---------------------------------------------------------------------------
# Mode: demo
# ---------------------------------------------------------------------------
cmd_demo() {
    log_info "=== PHASE 66 — Data Loss Prevention Demo ==="
    run_python <<'PYEOF'
import sys
sys.path.insert(0, ".")
from apps.security_ai.data_loss_prevention_engine import (
    DataLossPreventionEngine,
    DataClassification, ChannelType, PolicyAction,
    make_asset, make_event, make_policy,
    ViolationStatus,
)

engine = DataLossPreventionEngine()

# Register policy
policy = make_policy(
    name="Confidential-Data-Protection",
    classifications=[DataClassification.CONFIDENTIAL, DataClassification.RESTRICTED, DataClassification.TOP_SECRET],
    blocked_channels=[ChannelType.USB, ChannelType.FTP, ChannelType.CLOUD_SYNC],
    monitored_channels=[ChannelType.EMAIL, ChannelType.HTTP_UPLOAD],
)
engine.register_policy(policy)

# Register assets
asset_conf = make_asset(DataClassification.CONFIDENTIAL, owner="alice")
asset_top  = make_asset(DataClassification.TOP_SECRET,   owner="bob")
engine.register_asset(asset_conf)
engine.register_asset(asset_top)

# Analyze transfers
ev1 = make_event("alice", asset_conf, ChannelType.USB, "usb-drive-123")
ev2 = make_event("bob",   asset_top,  ChannelType.FTP, "ftp.external.com")
ev3 = make_event("carol", asset_conf, ChannelType.EMAIL, "carol@partner.com")

for ev in [ev1, ev2, ev3]:
    v = engine.analyze_transfer(ev)
    status = v.severity.value if v else "ALLOWED"
    print(f"  Transfer by {ev.actor!r} via {ev.channel.value}: {status}")

rpt = engine.generate_report()
print(f"\nDLP Report: {rpt.total_violations} violation(s), score={rpt.score:.1f}/25")
print(f"Blocked: {rpt.blocked_transfers}  Monitored: {rpt.monitored_transfers}")
PYEOF
    log_info "Demo complete."
}

# ---------------------------------------------------------------------------
# Mode: summary
# ---------------------------------------------------------------------------
cmd_summary() {
    run_python <<'PYEOF'
import sys, json
sys.path.insert(0, ".")
from apps.security_ai.data_loss_prevention_engine import (
    DataLossPreventionEngine, DataClassification, ChannelType,
    make_asset, make_event, make_policy,
)

engine = DataLossPreventionEngine()
policy = make_policy()
engine.register_policy(policy)
asset = make_asset(DataClassification.RESTRICTED)
engine.register_asset(asset)
ev = make_event("charlie", asset, ChannelType.USB)
engine.analyze_transfer(ev)

print(json.dumps(engine.summary(), indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: report
# ---------------------------------------------------------------------------
cmd_report() {
    run_python <<'PYEOF'
import sys, json
sys.path.insert(0, ".")
from apps.security_ai.data_loss_prevention_engine import (
    DataLossPreventionEngine, DataClassification, ChannelType,
    make_asset, make_event, make_policy,
)

engine = DataLossPreventionEngine()
policy = make_policy()
engine.register_policy(policy)

for cls in [DataClassification.CONFIDENTIAL, DataClassification.RESTRICTED, DataClassification.TOP_SECRET]:
    a = make_asset(cls)
    engine.register_asset(a)
    ev = make_event("attacker", a, ChannelType.USB)
    engine.analyze_transfer(ev)

rpt = engine.generate_report()
print(json.dumps(rpt.to_dict(), indent=2))
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: persist
# ---------------------------------------------------------------------------
cmd_persist() {
    local out_path="/tmp/phase66_dlp_state.json"
    run_python <<PYEOF
import sys, json
sys.path.insert(0, ".")
from apps.security_ai.data_loss_prevention_engine import (
    DataLossPreventionEngine, DataClassification, ChannelType,
    make_asset, make_event, make_policy,
)

engine = DataLossPreventionEngine()
policy = make_policy()
engine.register_policy(policy)
asset = make_asset()
engine.register_asset(asset)
ev = make_event("dave", asset, ChannelType.USB)
engine.analyze_transfer(ev)

path = engine.persist_state("${out_path}")
print(json.dumps({"persisted": True, "path": path}))
PYEOF
    log_info "State persisted to ${out_path}"
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
MODE="${1:-demo}"
case "${MODE}" in
    demo)    cmd_demo    ;;
    summary) cmd_summary ;;
    report)  cmd_report  ;;
    persist) cmd_persist ;;
    *)
        log_error "Unknown mode: ${MODE}. Use: demo | summary | report | persist"
        exit 1
        ;;
esac
