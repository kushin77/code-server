#!/usr/bin/env bash
# @file        scripts/ops/run-resilience-campaign.sh
# @module      ops/governance
# @description Orchestrate resilience campaign audits, smoke tests, and failover validation
# @owner       akushnir
# @status      production
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"
source "$SCRIPT_DIR/../_common/issue-create-unified.sh"

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

log_stage "Running resilience campaign profile: $CAMPAIGN_PROFILE"

log_stage "Collecting baseline surface measurements"
REQUEST_COUNT="$BASELINE_REQUEST_COUNT" \
THROTTLE_LIMIT="$BASELINE_THROTTLE_LIMIT" \
OUTPUT_DIR="$OUTPUT_DIR" \
REPORT_BASENAME="${CAMPAIGN_BASENAME}-baseline" \
bash "$SCRIPT_DIR/collect-live-surface-baseline.sh"

require_file "$baseline_json"
require_file "$baseline_md"

log_stage "Collecting soak-lite surface measurements"
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
    log_stage "Running k6 loadtest profile: $K6_SCALE_PROFILE"
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
    log_stage "Running authenticated smoke check"
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
    log_stage "Running Puppeteer parity check"
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
        log_stage "Running failover continuity check"
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

python3 "$SCRIPT_DIR/generate-resilience-summary.py" \
    --baseline-json "$baseline_json" \
    --soak-json "$soak_json" \
    --summary-json "$summary_json" \
    --summary-md "$summary_md" \
    --auth-status "$auth_status" \
    --auth-exit-code "$auth_exit_code" \
    --auth-reason "$auth_reason" \
    --loadtest-status "$loadtest_status" \
    --loadtest-exit-code "$loadtest_exit_code" \
    --loadtest-reason "$loadtest_reason" \
    --failover-status "$failover_status" \
    --failover-exit-code "$failover_exit_code" \
    --failover-reason "$failover_reason" \
    --puppeteer-status "$puppeteer_status" \
    --puppeteer-exit-code "$puppeteer_exit_code" \
    --puppeteer-reason "$puppeteer_reason" \
    --portal-base-url "$PORTAL_BASE_URL" \
    --ide-base-url "$IDE_BASE_URL" \
    --scale-profile "$K6_SCALE_PROFILE"

if [[ "$AUTO_FILE_DEFECTS" == "1" && ( "$auth_status" == "failed" || "$loadtest_status" == "failed" || "$failover_status" == "failed" || "$puppeteer_status" == "failed" ) ]]; then
    defect_title="P1: Resilience campaign failure (${CAMPAIGN_BASENAME})"
    defect_body=$(cat <<EOF
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
)

    copilot_create_issue \
        --title "$defect_title" \
        --body "$defect_body" \
        --priority P1 \
        --type bug \
        --repo "$DEFECT_REPO" \
        --check-duplicates
fi

log_info "Resilience campaign collected in $OUTPUT_DIR"
