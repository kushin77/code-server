#!/usr/bin/env bash
################################################################################
# @file scripts/ops/phase-37-response-automation.sh
# @description Phase 37 — Security Response Automation Orchestrator
#
# Modes:
#   --mode status    Print automation score and workflow summary
#   --mode trigger   Trigger a response workflow for a given incident
#   --mode demo      Synthetic demo: critical + high + medium triggers
#   --mode replay    Re-execute failed workflow steps
#
# Usage:
#   bash scripts/ops/phase-37-response-automation.sh --mode status
#   bash scripts/ops/phase-37-response-automation.sh --mode demo --dry-run
#   DRY_RUN=true bash scripts/ops/phase-37-response-automation.sh --mode trigger \
#     --severity critical --container code-server-app-1 --source phase36
#
# @since 2026-05-01
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

trap 'log_error "Phase 37 script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Phase 37 response automation script exiting"' EXIT

MODE="${MODE:-status}"
DRY_RUN="${DRY_RUN:-true}"
SEVERITY="${SEVERITY:-high}"
CONTAINER="${CONTAINER:-code-server-primary-1}"
SOURCE="${SOURCE:-phase36}"
DESCRIPTION="${DESCRIPTION:-Automated security trigger}"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="$2";        shift 2 ;;
    --dry-run)     DRY_RUN=true;     shift   ;;
    --no-dry-run)  DRY_RUN=false;    shift   ;;
    --severity)    SEVERITY="$2";    shift 2 ;;
    --container)   CONTAINER="$2";   shift 2 ;;
    --source)      SOURCE="$2";      shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: $0 [--mode status|trigger|demo|replay] [options]"
      echo ""
      echo "Modes:"
      echo "  status   — show automation score and summary (default)"
      echo "  trigger  — trigger response for an incident"
      echo "  demo     — synthetic multi-severity demo"
      echo "  replay   — re-attempt failed workflow steps"
      echo ""
      echo "Options for 'trigger':"
      echo "  --severity   critical|high|medium|low  (default: high)"
      echo "  --container  target container ID"
      echo "  --source     phase32|phase35|phase36|manual"
      echo "  --description  incident description"
      exit 0
      ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

mkdir -p "${REPO_ROOT}/artifacts/phase37"
_p37_log() { log_info "[phase-37] $*"; }

# ---------------------------------------------------------------------------
# Mode: status
# ---------------------------------------------------------------------------
run_status() {
  _p37_log "Phase 37 — automation status"
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, '.')
from apps.security_ai.response_automation import summary, automation_score

s = summary()
print(f"Phase 37 Automation Score: {s['automation_score']}/20")
print(f"Total workflows triggered: {s['total_workflows']}")
print(f"Total step executions:     {s['total_step_executions']}")
by_type = s.get('executions_by_type', {})
if by_type:
    print("Executions by type:")
    for rt, count in sorted(by_type.items()):
        print(f"  {rt}: {count}")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: trigger
# ---------------------------------------------------------------------------
run_trigger() {
  _p37_log "Phase 37 — trigger response (severity=${SEVERITY} container=${CONTAINER} dry_run=${DRY_RUN})"

  python3 - <<PYEOF
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, SeverityThreshold, get_executions
)

source_map = {
    'phase32': TriggerSource.PHASE32,
    'phase35': TriggerSource.PHASE35,
    'phase36': TriggerSource.PHASE36,
    'manual':  TriggerSource.MANUAL,
}

trigger = ResponseTrigger(
    trigger_id=str(uuid.uuid4()),
    source=source_map.get('${SOURCE}', TriggerSource.MANUAL),
    severity='${SEVERITY}',
    container_id='${CONTAINER}',
    description='${DESCRIPTION}',
)

wf = trigger_response(trigger, dry_run=${DRY_RUN}, severity_threshold=SeverityThreshold.ANY)
if wf is None:
    print("Trigger below severity threshold — no workflow created")
else:
    print(f"Workflow triggered: {wf.workflow_id}")
    print(f"Steps: {len(wf.steps)}")
    execs = get_executions(wf.workflow_id)
    for e in execs:
        status = e.get('status', '?')
        rt = e.get('response_type', '?')
        result = e.get('result', '')
        print(f"  [{status.upper()}] {rt}: {result[:80]}")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: demo
# ---------------------------------------------------------------------------
run_demo() {
  _p37_log "Phase 37 demo — multi-severity response automation"

  python3 - <<'PYEOF'
import sys, uuid
sys.path.insert(0, '.')
from apps.security_ai.response_automation import (
    trigger_response, ResponseTrigger, TriggerSource, SeverityThreshold, summary
)

print("=== Phase 37 Response Automation Demo ===")
print()

scenarios = [
    {
        "source": TriggerSource.PHASE36,
        "severity": "critical",
        "container_id": "code-server-primary-1",
        "description": "suspicious process detected + secret exposed in env",
    },
    {
        "source": TriggerSource.PHASE32,
        "severity": "high",
        "container_id": "code-server-replica-1",
        "description": "multiple failed auth attempts — possible brute force",
    },
    {
        "source": TriggerSource.PHASE35,
        "severity": "critical",
        "container_id": "code-server-primary-1",
        "description": "forensic trace confirmed memory exfiltration pathway",
    },
    {
        "source": TriggerSource.MANUAL,
        "severity": "medium",
        "container_id": "code-server-worker-1",
        "description": "config drift detected in monitoring agent",
    },
]

for i, sc in enumerate(scenarios, 1):
    print(f"Scenario {i}: [{sc['severity'].upper()}] {sc['source'].value}")
    t = ResponseTrigger(
        trigger_id=str(uuid.uuid4()),
        source=sc["source"],
        severity=sc["severity"],
        container_id=sc["container_id"],
        description=sc["description"],
    )
    wf = trigger_response(t, dry_run=True, severity_threshold=SeverityThreshold.ANY)
    if wf:
        print(f"  Workflow {wf.workflow_id[:8]}...: {len(wf.steps)} steps")
        for step in wf.steps:
            print(f"    → {step.response_type.value}")
    else:
        print("  Skipped (below threshold)")
    print()

s = summary()
print(f"Final state:")
print(f"  Total workflows: {s['total_workflows']}")
print(f"  Total executions: {s['total_step_executions']}")
print(f"  Automation score: {s['automation_score']}/20")
PYEOF
}

# ---------------------------------------------------------------------------
# Mode: replay
# ---------------------------------------------------------------------------
run_replay() {
  _p37_log "Phase 37 — replay failed executions (dry_run=${DRY_RUN})"

  python3 - <<'PYEOF'
import sys
sys.path.insert(0, '.')
from apps.security_ai.response_automation import get_executions, ExecutionStatus

execs = get_executions()
failed = [e for e in execs if e.get("status") == "failed"]
if not failed:
    print("No failed executions to replay.")
else:
    print(f"Found {len(failed)} failed execution(s) — replay not yet implemented (would retry each)")
    for e in failed:
        print(f"  [{e['workflow_id'][:8]}...] {e['response_type']}: {e.get('result', '')[:60]}")
PYEOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${MODE}" in
  status)  run_status  ;;
  trigger) run_trigger ;;
  demo)    run_demo    ;;
  replay)  run_replay  ;;
  *)
    log_error "Unknown mode '${MODE}'. Use: status, trigger, demo, replay"
    exit 1
    ;;
esac
