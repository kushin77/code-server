#!/usr/bin/env bash
# @file        scripts/ops/run-resilience-campaign.sh
# @module      ops/monitoring
# @description Run the active resilience campaign baseline, soak-lite, and authenticated smoke checks.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

OUTPUT_DIR="${OUTPUT_DIR:-artifacts/triage}"
CAMPAIGN_BASENAME="${CAMPAIGN_BASENAME:-resilience-campaign}"
PORTAL_BASE_URL="${PORTAL_BASE_URL:-https://kushnir.cloud}"
IDE_BASE_URL="${IDE_BASE_URL:-https://ide.kushnir.cloud}"
CAMPAIGN_PROFILE="${CAMPAIGN_PROFILE:-baseline}"

baseline_request_count_set=false
baseline_throttle_limit_set=false
soak_request_count_set=false
soak_throttle_limit_set=false
k6_scale_profile_set=false
playwright_workers_set=false

if [[ -n "${BASELINE_REQUEST_COUNT+x}" ]]; then
    baseline_request_count_set=true
fi
if [[ -n "${BASELINE_THROTTLE_LIMIT+x}" ]]; then
    baseline_throttle_limit_set=true
fi
if [[ -n "${SOAK_REQUEST_COUNT+x}" ]]; then
    soak_request_count_set=true
fi
if [[ -n "${SOAK_THROTTLE_LIMIT+x}" ]]; then
    soak_throttle_limit_set=true
fi
if [[ -n "${K6_SCALE_PROFILE+x}" ]]; then
    k6_scale_profile_set=true
fi
if [[ -n "${PLAYWRIGHT_WORKERS+x}" ]]; then
    playwright_workers_set=true
fi

BASELINE_REQUEST_COUNT="${BASELINE_REQUEST_COUNT:-5}"
BASELINE_THROTTLE_LIMIT="${BASELINE_THROTTLE_LIMIT:-5}"
SOAK_REQUEST_COUNT="${SOAK_REQUEST_COUNT:-15}"
SOAK_THROTTLE_LIMIT="${SOAK_THROTTLE_LIMIT:-5}"
K6_SCALE_PROFILE="${K6_SCALE_PROFILE:-baseline}"
PLAYWRIGHT_WORKERS="${PLAYWRIGHT_WORKERS:-1}"
RUN_K6_LOADTEST="${RUN_K6_LOADTEST:-1}"

case "$CAMPAIGN_PROFILE" in
    baseline)
        ;;
    100x)
        if [[ "$baseline_request_count_set" == "false" ]]; then
            BASELINE_REQUEST_COUNT="50"
        fi
        if [[ "$baseline_throttle_limit_set" == "false" ]]; then
            BASELINE_THROTTLE_LIMIT="10"
        fi
        if [[ "$soak_request_count_set" == "false" ]]; then
            SOAK_REQUEST_COUNT="100"
        fi
        if [[ "$soak_throttle_limit_set" == "false" ]]; then
            SOAK_THROTTLE_LIMIT="20"
        fi
        if [[ "$k6_scale_profile_set" == "false" ]]; then
            K6_SCALE_PROFILE="100x"
        fi
        if [[ "$playwright_workers_set" == "false" ]]; then
            PLAYWRIGHT_WORKERS="4"
        fi
        ;;
    *)
        log_fatal "Unknown CAMPAIGN_PROFILE: $CAMPAIGN_PROFILE (expected baseline or 100x)"
        ;;
esac

RUN_AUTHENTICATED_SMOKE="${RUN_AUTHENTICATED_SMOKE:-1}"
RUN_PUPPETEER_PARITY="${RUN_PUPPETEER_PARITY:-1}"
AUTH_SMOKE_REQUIRE_QA_STORAGE_STATE="${AUTH_SMOKE_REQUIRE_QA_STORAGE_STATE:-0}"
AUTH_SMOKE_REQUIRE_VPN="${AUTH_SMOKE_REQUIRE_VPN:-1}"
AUTH_SMOKE_REQUIRE_SINGLE_LOGIN="${AUTH_SMOKE_REQUIRE_SINGLE_LOGIN:-1}"
RUN_FAILOVER_CONTINUITY="${RUN_FAILOVER_CONTINUITY:-1}"
FAILOVER_CONTINUITY_MODE="${FAILOVER_CONTINUITY_MODE:-unauth}"
FAILOVER_WAIT_MS="${FAILOVER_WAIT_MS:-45000}"
FAILOVER_TRIGGER_CMD="${FAILOVER_TRIGGER_CMD:-}"
PLAYWRIGHT_STORAGE_STATE="${PLAYWRIGHT_STORAGE_STATE:-}"
AUTO_FILE_DEFECTS="${AUTO_FILE_DEFECTS:-0}"
DEFECT_REPO="${DEFECT_REPO:-kushin77/code-server}"
DEFECT_LABELS_CSV="${DEFECT_LABELS_CSV:-testing,quality,P1}"

require_command python3
if [[ "$RUN_K6_LOADTEST" == "1" ]]; then
    require_command k6
fi
mkdir -p "$OUTPUT_DIR"

baseline_json="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-baseline.json"
baseline_md="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-baseline.md"
soak_json="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-soak-lite.json"
soak_md="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-soak-lite.md"
auth_log="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-authenticated-smoke.log"
summary_json="$OUTPUT_DIR/${CAMPAIGN_BASENAME}.json"
summary_md="$OUTPUT_DIR/${CAMPAIGN_BASENAME}.md"
loadtest_log="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-k6.log"
loadtest_json="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-k6.json"

log_info "Running resilience campaign profile: $CAMPAIGN_PROFILE"

log_info "Collecting baseline surface measurements"
REQUEST_COUNT="$BASELINE_REQUEST_COUNT" \
THROTTLE_LIMIT="$BASELINE_THROTTLE_LIMIT" \
OUTPUT_DIR="$OUTPUT_DIR" \
REPORT_BASENAME="${CAMPAIGN_BASENAME}-baseline" \
bash "$SCRIPT_DIR/collect-live-surface-baseline.sh"

require_file "$baseline_json"
require_file "$baseline_md"

log_info "Collecting soak-lite surface measurements"
REQUEST_COUNT="$SOAK_REQUEST_COUNT" \
THROTTLE_LIMIT="$SOAK_THROTTLE_LIMIT" \
OUTPUT_DIR="$OUTPUT_DIR" \
REPORT_BASENAME="${CAMPAIGN_BASENAME}-soak-lite" \
bash "$SCRIPT_DIR/collect-live-surface-baseline.sh"

require_file "$soak_json"
require_file "$soak_md"

loadtest_status="skipped"
loadtest_exit_code=0
loadtest_reason="not requested"

if [[ "$RUN_K6_LOADTEST" == "1" ]]; then
    log_info "Running k6 loadtest profile: $K6_SCALE_PROFILE"
    set +e
    trap - ERR
    env \
        BASE_URL="$IDE_BASE_URL" \
        SCALE_PROFILE="$K6_SCALE_PROFILE" \
        k6 run --quiet --summary-export "$loadtest_json" "$SCRIPT_DIR/../loadtest/k6-baseline.js" \
        >"$loadtest_log" 2>&1
    loadtest_exit_code=$?
    set -e

    if [[ "$loadtest_exit_code" -eq 0 ]]; then
        loadtest_status="passed"
        loadtest_reason=""
        log_info "k6 loadtest passed"
    else
        loadtest_status="failed"
        loadtest_reason="exit code $loadtest_exit_code"
        log_warn "k6 loadtest failed with exit code $loadtest_exit_code"
    fi
else
    log_info "k6 loadtest skipped by configuration"
fi

auth_status="skipped"
auth_exit_code=0
auth_reason="not requested"
failover_status="skipped"
failover_exit_code=0
failover_reason="not requested"
puppeteer_status="skipped"
puppeteer_exit_code=0
puppeteer_reason="not requested"
defect_issue_url=""

if [[ "$RUN_AUTHENTICATED_SMOKE" == "1" ]]; then
    log_info "Running authenticated smoke check"
    set +e
    trap - ERR
    env \
        REQUIRE_QA_STORAGE_STATE="$AUTH_SMOKE_REQUIRE_QA_STORAGE_STATE" \
        REQUIRE_VPN="$AUTH_SMOKE_REQUIRE_VPN" \
        REQUIRE_SINGLE_LOGIN="$AUTH_SMOKE_REQUIRE_SINGLE_LOGIN" \
        PLAYWRIGHT_WORKERS="$PLAYWRIGHT_WORKERS" \
        PORTAL_BASE_URL="$PORTAL_BASE_URL" \
        IDE_BASE_URL="$IDE_BASE_URL" \
        bash "$SCRIPT_DIR/../ci/run-kushnir-cloud-appsmith-login-e2e.sh" \
        >"$auth_log" 2>&1
    auth_exit_code=$?
    set -e

    if [[ "$auth_exit_code" -eq 0 ]]; then
        auth_status="passed"
        auth_reason=""
        log_info "Authenticated smoke check passed"
    else
        auth_status="failed"
        auth_reason="exit code $auth_exit_code"
        log_warn "Authenticated smoke check failed with exit code $auth_exit_code"
    fi
else
  log_info "Authenticated smoke check skipped by configuration"
fi

if [[ "$RUN_PUPPETEER_PARITY" == "1" ]]; then
    log_info "Running Puppeteer parity check"
    set +e
    trap - ERR
    env \
        PORTAL_BASE_URL="$PORTAL_BASE_URL" \
        IDE_BASE_URL="$IDE_BASE_URL" \
        E2E_DIR="tests/e2e" \
        bash "$SCRIPT_DIR/../ci/run-kushnir-cloud-appsmith-login-puppeteer.sh" \
        >"$OUTPUT_DIR/${CAMPAIGN_BASENAME}-puppeteer-parity.log" 2>&1
    puppeteer_exit_code=$?
    set -e

    if [[ "$puppeteer_exit_code" -eq 0 ]]; then
        puppeteer_status="passed"
        puppeteer_reason=""
        log_info "Puppeteer parity check passed"
    else
        puppeteer_status="failed"
        puppeteer_reason="exit code $puppeteer_exit_code"
        log_warn "Puppeteer parity check failed with exit code $puppeteer_exit_code"
    fi
else
    log_info "Puppeteer parity check skipped by configuration"
fi

if [[ "$RUN_FAILOVER_CONTINUITY" == "1" ]]; then
    if [[ "$FAILOVER_CONTINUITY_MODE" == "auth" && -z "$PLAYWRIGHT_STORAGE_STATE" ]]; then
        failover_reason="PLAYWRIGHT_STORAGE_STATE not set"
        log_warn "Failover continuity check skipped: $failover_reason"
    else
        log_info "Running failover continuity check"
        set +e
        trap - ERR
        env \
            CONTINUITY_MODE="$FAILOVER_CONTINUITY_MODE" \
            TEST_BASE_URL="$IDE_BASE_URL" \
            PLAYWRIGHT_WORKERS="$PLAYWRIGHT_WORKERS" \
            PLAYWRIGHT_STORAGE_STATE="$PLAYWRIGHT_STORAGE_STATE" \
            FAILOVER_WAIT_MS="$FAILOVER_WAIT_MS" \
            FAILOVER_TRIGGER_CMD="$FAILOVER_TRIGGER_CMD" \
            bash "$SCRIPT_DIR/../ci/run-playwright-failover-continuity.sh" \
            >"$OUTPUT_DIR/${CAMPAIGN_BASENAME}-failover-continuity.log" 2>&1
        failover_exit_code=$?
        set -e

        if [[ "$failover_exit_code" -eq 0 ]]; then
            failover_status="passed"
            failover_reason=""
            log_info "Failover continuity check passed"
        else
            failover_status="failed"
            failover_reason="exit code $failover_exit_code"
            log_warn "Failover continuity check failed with exit code $failover_exit_code"
        fi
    fi
else
    log_info "Failover continuity check skipped by configuration"
fi

python3 - "$baseline_json" "$soak_json" "$summary_json" "$summary_md" "$auth_status" "$auth_exit_code" "$auth_reason" "$loadtest_status" "$loadtest_exit_code" "$loadtest_reason" "$failover_status" "$failover_exit_code" "$failover_reason" "$puppeteer_status" "$puppeteer_exit_code" "$puppeteer_reason" "$PORTAL_BASE_URL" "$IDE_BASE_URL" "$K6_SCALE_PROFILE" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

baseline_json = Path(sys.argv[1])
soak_json = Path(sys.argv[2])
summary_json = Path(sys.argv[3])
summary_md = Path(sys.argv[4])
auth_status = sys.argv[5]
auth_exit_code = int(sys.argv[6])
auth_reason = sys.argv[7]
loadtest_status = sys.argv[8]
loadtest_exit_code = int(sys.argv[9])
loadtest_reason = sys.argv[10]
failover_status = sys.argv[11]
failover_exit_code = int(sys.argv[12])
failover_reason = sys.argv[13]
puppeteer_status = sys.argv[14]
puppeteer_exit_code = int(sys.argv[15])
puppeteer_reason = sys.argv[16]
portal_base_url = sys.argv[17]
ide_base_url = sys.argv[18]
scale_profile = sys.argv[19]

with baseline_json.open(encoding='utf-8') as handle:
    baseline = json.load(handle)

with soak_json.open(encoding='utf-8') as handle:
    soak = json.load(handle)

generated_at = datetime.now(timezone.utc).isoformat(timespec='seconds')

summary = {
    'generated_at': generated_at,
    'portal_base_url': portal_base_url,
    'ide_base_url': ide_base_url,
    'baseline': baseline,
    'soak_lite': soak,
    'authenticated_smoke': {
        'status': auth_status,
        'exit_code': auth_exit_code,
        'reason': auth_reason,
        'log_file': str(summary_json.parent / f"{summary_json.stem}-authenticated-smoke.log"),
    },
    'loadtest': {
        'status': loadtest_status,
        'exit_code': loadtest_exit_code,
        'reason': loadtest_reason,
        'log_file': str(summary_json.parent / f"{summary_json.stem}-k6.log"),
        'summary_file': str(summary_json.parent / f"{summary_json.stem}-k6.json"),
        'scale_profile': scale_profile,
    },
    'failover_continuity': {
        'status': failover_status,
        'exit_code': failover_exit_code,
        'reason': failover_reason,
        'log_file': str(summary_json.parent / f"{summary_json.stem}-failover-continuity.log"),
    },
    'puppeteer_parity': {
        'status': puppeteer_status,
        'exit_code': puppeteer_exit_code,
        'reason': puppeteer_reason,
        'log_file': str(summary_json.parent / f"{summary_json.stem}-puppeteer-parity.log"),
    },
    'campaign_status': 'degraded' if auth_status == 'failed' or loadtest_status == 'failed' or failover_status == 'failed' or puppeteer_status == 'failed' else 'in-progress',
}

summary_json.write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')

lines = [
    '# Resilience Campaign Summary',
    '',
    f'Generated: {generated_at}',
    f'Campaign profile: {scale_profile}',
    f'Portal base URL: {portal_base_url}',
    f'IDE base URL: {ide_base_url}',
    '',
    '## Baseline',
    '',
]

for report in baseline['reports']:
    lines.append(
        f"- {report['name']}: {report['status_counts']} avg={report['average_seconds']}s min={report['min_seconds']}s max={report['max_seconds']}s"
    )

lines += [
    '',
    '## Soak-Lite',
    '',
]

for report in soak['reports']:
    lines.append(
        f"- {report['name']}: {report['status_counts']} avg={report['average_seconds']}s min={report['min_seconds']}s max={report['max_seconds']}s"
    )

lines += [
    '',
    '## Authenticated Smoke',
    '',
    f'- status: {auth_status}',
    f'- exit code: {auth_exit_code}',
    f'- reason: {auth_reason or "n/a"}',
    '',
    '## Loadtest',
    '',
    f'- status: {loadtest_status}',
    f'- exit code: {loadtest_exit_code}',
    f'- reason: {loadtest_reason or "n/a"}',
    f'- scale profile: {scale_profile}',
    '',
    '## Failover Continuity',
    '',
    f'- status: {failover_status}',
    f'- exit code: {failover_exit_code}',
    f'- reason: {failover_reason or "n/a"}',
    '',
    '## Puppeteer Parity',
    '',
    f'- status: {puppeteer_status}',
    f'- exit code: {puppeteer_exit_code}',
    f'- reason: {puppeteer_reason or "n/a"}',
    '',
    '## Notes',
    '',
    '- This runner collects a repeatable surface baseline and a slightly heavier soak sample.',
    '- It also provides an authenticated smoke path when the required environment is available.',
    '- It includes a Puppeteer parity probe for critical login and root-path checks.',
    '- It includes a profile-driven k6 loadtest for baseline and 100x campaign modes.',
    '- Chaos/fault injection remains a separate follow-up step for the broader resilience campaign.',
]

summary_md.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

if [[ "$AUTO_FILE_DEFECTS" == "1" && ( "$auth_status" == "failed" || "$loadtest_status" == "failed" || "$failover_status" == "failed" || "$puppeteer_status" == "failed" ) ]]; then
    if command -v gh >/dev/null 2>&1; then
        defect_body_file="$OUTPUT_DIR/${CAMPAIGN_BASENAME}-defect.md"
        defect_title="P1: Resilience campaign failure (${CAMPAIGN_BASENAME})"

        cat > "$defect_body_file" <<EOF
Automated resilience campaign detected at least one failing phase.

Campaign: $CAMPAIGN_BASENAME
Profile: $CAMPAIGN_PROFILE
Generated summary: $summary_json

Statuses:
- authenticated_smoke: $auth_status (exit $auth_exit_code)
- loadtest: $loadtest_status (exit $loadtest_exit_code)
- failover_continuity: $failover_status (exit $failover_exit_code)
- puppeteer_parity: $puppeteer_status (exit $puppeteer_exit_code)

Reproduction:
1. Run: 
   \
   CAMPAIGN_PROFILE=$CAMPAIGN_PROFILE OUTPUT_DIR=$OUTPUT_DIR bash scripts/ops/run-resilience-campaign.sh
2. Inspect logs under: $OUTPUT_DIR

Artifact links (local paths):
- $summary_json
- $summary_md
- $auth_log
- $loadtest_log
- $OUTPUT_DIR/${CAMPAIGN_BASENAME}-failover-continuity.log
- $OUTPUT_DIR/${CAMPAIGN_BASENAME}-puppeteer-parity.log
EOF

        IFS=',' read -r -a defect_labels <<< "$DEFECT_LABELS_CSV"
        gh_args=(issue create --repo "$DEFECT_REPO" --title "$defect_title" --body-file "$defect_body_file")
        for label in "${defect_labels[@]}"; do
            trimmed_label="$(printf '%s' "$label" | xargs)"
            if [[ -n "$trimmed_label" ]]; then
                gh_args+=(--label "$trimmed_label")
            fi
        done

        set +e
        trap - ERR
        defect_issue_url="$(gh "${gh_args[@]}" 2>/dev/null)"
        gh_exit=$?
        set -e
        if [[ "$gh_exit" -ne 0 ]]; then
            log_warn "Automatic defect filing failed for $DEFECT_REPO"
        else
            log_warn "Filed campaign defect: $defect_issue_url"
        fi
    else
        log_warn "AUTO_FILE_DEFECTS requested but gh is not available"
    fi
fi

if [[ -n "$defect_issue_url" ]]; then
    python3 - "$summary_json" "$defect_issue_url" <<'PY'
import json
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
issue_url = sys.argv[2]
data = json.loads(summary_path.read_text(encoding='utf-8'))
data['defect_issue_url'] = issue_url
summary_path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
PY
fi

log_info "Resilience campaign collected in $OUTPUT_DIR"
