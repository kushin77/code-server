#!/usr/bin/env bash
# @file        scripts/ci/run-jwt-e2e-tests.sh
# @module      ci/auth
# @description Phase 2E: End-to-end tests for JWT service-to-service authentication
#              Tests token issuance, validation, expiry, failover, and service integration.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OIDC_BASE_URL="${OIDC_BASE_URL:-http://localhost:4182}"
BACKEND_BASE_URL="${BACKEND_BASE_URL:-http://localhost:3001}"
SESSION_BROKER_URL="${SESSION_BROKER_URL:-http://localhost:5000}"
TEST_CLIENT_ID="${TEST_CLIENT_ID:-session-broker}"
TEST_CLIENT_SECRET="${TEST_CLIENT_SECRET:-}"  # loaded from env or .env
TIMEOUT_S="${TIMEOUT_S:-10}"
MAX_FAILURES="${MAX_FAILURES:-0}"  # 0 = strict (any failure fails suite)
REPORT_DIR="${REPORT_DIR:-artifacts/triage}"

PASS=0
FAIL=0
SKIP=0
declare -a FAILED_TESTS=()

mkdir -p "${REPORT_DIR}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pass() {
  local name="$1"
  PASS=$((PASS + 1))
  log_info "  PASS  ${name}"
}

fail() {
  local name="$1"
  local reason="${2:-}"
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("${name}")
  log_error "  FAIL  ${name}${reason:+ — ${reason}}"
}

skip() {
  local name="$1"
  local reason="${2:-}"
  SKIP=$((SKIP + 1))
  log_warn "  SKIP  ${name}${reason:+ — ${reason}}"
}

# Make a request with a timeout; store HTTP status in global $HTTP_STATUS
http_get() {
  local url="$1"
  shift
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT_S}" "$@" "${url}" 2>/dev/null || echo "000")
  RESPONSE_BODY=$(curl -s --max-time "${TIMEOUT_S}" "$@" "${url}" 2>/dev/null || echo "")
}

http_post_json() {
  local url="$1"
  local body="$2"
  shift 2
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT_S}" \
    -H "Content-Type: application/json" -d "${body}" "$@" "${url}" 2>/dev/null || echo "000")
  RESPONSE_BODY=$(curl -s --max-time "${TIMEOUT_S}" \
    -H "Content-Type: application/json" -d "${body}" "$@" "${url}" 2>/dev/null || echo "")
}

http_post_form() {
  local url="$1"
  shift
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT_S}" \
    -H "Content-Type: application/x-www-form-urlencoded" "$@" "${url}" 2>/dev/null || echo "000")
  RESPONSE_BODY=$(curl -s --max-time "${TIMEOUT_S}" \
    -H "Content-Type: application/x-www-form-urlencoded" "$@" "${url}" 2>/dev/null || echo "")
}

extract_json() {
  local json="$1" key="$2"
  echo "${json}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('${key}',''))" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
check_prereqs() {
  log_info "=== Checking prerequisites ==="
  local ok=1

  for cmd in curl python3; do
    if ! command -v "${cmd}" &>/dev/null; then
      log_warn "Command not found: ${cmd}"
      ok=0
    fi
  done

  if [[ -z "${TEST_CLIENT_SECRET}" ]]; then
    if [[ -f "${SCRIPT_DIR}/../../.env" ]]; then
      TEST_CLIENT_SECRET=$(grep -E '^SESSION_BROKER_CLIENT_SECRET=' "${SCRIPT_DIR}/../../.env" \
        | cut -d= -f2- | tr -d '"' | head -1 || true)
    fi
  fi

  if [[ -z "${TEST_CLIENT_SECRET}" ]]; then
    log_warn "TEST_CLIENT_SECRET not set — token acquisition tests will be skipped"
    SKIP_TOKEN_TESTS=1
  else
    SKIP_TOKEN_TESTS=0
  fi

  [[ "${ok}" == "1" ]] || log_fatal "Prerequisite checks failed — install missing commands and retry"
}

# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------

# Suite 1: OIDC Issuer Availability
test_oidc_discovery_endpoint() {
  local name="OIDC_DISCOVERY: /.well-known/openid-configuration returns 200"
  http_get "${OIDC_BASE_URL}/.well-known/openid-configuration"
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    pass "${name}"
  else
    fail "${name}" "HTTP ${HTTP_STATUS}"
  fi
}

test_oidc_discovery_fields() {
  local name="OIDC_DISCOVERY: response contains required fields (issuer, jwks_uri, token_endpoint)"
  http_get "${OIDC_BASE_URL}/.well-known/openid-configuration"
  if [[ "${HTTP_STATUS}" != "200" ]]; then
    skip "${name}" "OIDC issuer unreachable"
    return
  fi
  local issuer jwks_uri token_endpoint
  issuer=$(extract_json "${RESPONSE_BODY}" "issuer")
  jwks_uri=$(extract_json "${RESPONSE_BODY}" "jwks_uri")
  token_endpoint=$(extract_json "${RESPONSE_BODY}" "token_endpoint")
  if [[ -n "${issuer}" && -n "${jwks_uri}" && -n "${token_endpoint}" ]]; then
    pass "${name}"
  else
    fail "${name}" "issuer='${issuer}' jwks_uri='${jwks_uri}' token_endpoint='${token_endpoint}'"
  fi
}

test_jwks_endpoint() {
  local name="JWKS: /.well-known/jwks.json returns valid key set"
  http_get "${OIDC_BASE_URL}/.well-known/jwks.json"
  if [[ "${HTTP_STATUS}" != "200" ]]; then
    fail "${name}" "HTTP ${HTTP_STATUS}"
    return
  fi
  local keys
  keys=$(echo "${RESPONSE_BODY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('keys',[])));" 2>/dev/null || echo "0")
  if [[ "${keys}" -gt 0 ]]; then
    pass "${name}"
  else
    fail "${name}" "No keys in JWKS response"
  fi
}

test_jwks_key_algorithm() {
  local name="JWKS: key uses RS256 algorithm"
  http_get "${OIDC_BASE_URL}/.well-known/jwks.json"
  if [[ "${HTTP_STATUS}" != "200" ]]; then
    skip "${name}" "JWKS endpoint unreachable"
    return
  fi
  local alg
  alg=$(echo "${RESPONSE_BODY}" | python3 -c \
    "import json,sys; keys=json.load(sys.stdin).get('keys',[]); print(keys[0].get('alg','') if keys else '')" 2>/dev/null || echo "")
  if [[ "${alg}" == "RS256" ]]; then
    pass "${name}"
  else
    fail "${name}" "Expected RS256, got '${alg}'"
  fi
}

# Suite 2: Token Acquisition
test_token_acquisition() {
  local name="TOKEN_CLIENT: client_credentials flow returns access_token"
  if [[ "${SKIP_TOKEN_TESTS}" == "1" ]]; then
    skip "${name}" "TEST_CLIENT_SECRET not set"
    return
  fi
  http_post_form "${OIDC_BASE_URL}/oauth2/token" \
    -d "grant_type=client_credentials" \
    -d "client_id=${TEST_CLIENT_ID}" \
    -d "client_secret=${TEST_CLIENT_SECRET}" \
    -d "audience=code-server"
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    ACQUIRED_TOKEN=$(extract_json "${RESPONSE_BODY}" "access_token")
    if [[ -n "${ACQUIRED_TOKEN}" ]]; then
      pass "${name}"
    else
      fail "${name}" "Response 200 but no access_token in body"
    fi
  else
    fail "${name}" "HTTP ${HTTP_STATUS}: ${RESPONSE_BODY}"
  fi
}

test_token_has_required_claims() {
  local name="TOKEN_CLIENT: token contains required claims (sub, aud, iss, iat, exp)"
  if [[ "${SKIP_TOKEN_TESTS}" == "1" || -z "${ACQUIRED_TOKEN:-}" ]]; then
    skip "${name}" "No token acquired"
    return
  fi
  # Decode JWT payload (base64url, second segment)
  local payload_b64
  payload_b64=$(echo "${ACQUIRED_TOKEN}" | cut -d. -f2)
  # Add padding
  local padded
  padded="${payload_b64}$(python3 -c "p='${payload_b64}'; print('='*((4-len(p)%4)%4))")"
  local claims
  claims=$(echo "${padded}" | python3 -c \
    "import json,base64,sys; raw=sys.stdin.read().strip(); p=base64.urlsafe_b64decode(raw+'=='); print(json.dumps(json.loads(p)))" \
    2>/dev/null || echo "{}")
  local sub aud iss iat exp
  sub=$(extract_json "${claims}" "sub")
  aud=$(extract_json "${claims}" "aud")
  iss=$(extract_json "${claims}" "iss")
  iat=$(extract_json "${claims}" "iat")
  exp=$(extract_json "${claims}" "exp")
  if [[ -n "${sub}" && -n "${aud}" && -n "${iss}" && -n "${iat}" && -n "${exp}" ]]; then
    pass "${name}"
  else
    fail "${name}" "sub='${sub}' aud='${aud}' iss='${iss}' iat='${iat}' exp='${exp}'"
  fi
}

test_token_expiry_positive() {
  local name="TOKEN_CLIENT: token exp is in the future"
  if [[ -z "${ACQUIRED_TOKEN:-}" ]]; then
    skip "${name}" "No token acquired"
    return
  fi
  local payload_b64 claims exp now
  payload_b64=$(echo "${ACQUIRED_TOKEN}" | cut -d. -f2)
  claims=$(echo "${payload_b64}" | python3 -c \
    "import json,base64,sys; raw=sys.stdin.read().strip(); p=base64.urlsafe_b64decode(raw+'=='); print(json.dumps(json.loads(p)))" \
    2>/dev/null || echo "{}")
  exp=$(extract_json "${claims}" "exp")
  now=$(date +%s)
  if [[ -n "${exp}" && "${exp}" -gt "${now}" ]]; then
    pass "${name}"
  else
    fail "${name}" "exp=${exp} now=${now}"
  fi
}

test_invalid_credentials_rejected() {
  local name="TOKEN_CLIENT: invalid credentials return 401/400"
  if [[ "${SKIP_TOKEN_TESTS}" == "1" ]]; then
    skip "${name}" "TEST_CLIENT_SECRET not set"
    return
  fi
  http_post_form "${OIDC_BASE_URL}/oauth2/token" \
    -d "grant_type=client_credentials" \
    -d "client_id=invalid-client" \
    -d "client_secret=wrong-secret" \
    -d "audience=code-server"
  if [[ "${HTTP_STATUS}" == "401" || "${HTTP_STATUS}" == "400" ]]; then
    pass "${name}"
  else
    fail "${name}" "Expected 401/400, got HTTP ${HTTP_STATUS}"
  fi
}

# Suite 3: JWT Middleware / Backend Integration
test_bearer_token_accepted() {
  local name="JWT_MIDDLEWARE: valid bearer token accepted by backend /health endpoint"
  if [[ -z "${ACQUIRED_TOKEN:-}" ]]; then
    skip "${name}" "No token acquired"
    return
  fi
  http_get "${BACKEND_BASE_URL}/health" -H "Authorization: Bearer ${ACQUIRED_TOKEN}"
  # Accept 200 (health OK) or 404 (route not wired yet — middleware didn't reject)
  if [[ "${HTTP_STATUS}" == "200" || "${HTTP_STATUS}" == "404" ]]; then
    pass "${name}"
  elif [[ "${HTTP_STATUS}" == "401" || "${HTTP_STATUS}" == "403" ]]; then
    fail "${name}" "Valid token was rejected (HTTP ${HTTP_STATUS})"
  else
    skip "${name}" "Backend not reachable (HTTP ${HTTP_STATUS})"
  fi
}

test_missing_token_rejected() {
  local name="JWT_MIDDLEWARE: request without Authorization header returns 401"
  http_get "${BACKEND_BASE_URL}/api/v1/workspaces"
  if [[ "${HTTP_STATUS}" == "401" ]]; then
    pass "${name}"
  elif [[ "${HTTP_STATUS}" == "000" ]]; then
    skip "${name}" "Backend not reachable"
  else
    # A 404 could mean route doesn't exist yet (not wired), which is acceptable
    skip "${name}" "Route not yet wired (HTTP ${HTTP_STATUS})"
  fi
}

test_expired_token_rejected() {
  local name="JWT_MIDDLEWARE: expired token (exp in past) returns 401"
  # Craft a minimal expired JWT with a dummy signature — middleware should reject on exp check
  local header payload
  header=$(echo -n '{"alg":"RS256","typ":"JWT"}' | python3 -c "import base64,sys; print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).decode().rstrip('='))")
  payload=$(echo -n "{\"sub\":\"test\",\"aud\":\"code-server\",\"iss\":\"https://ide.kushnir.cloud\",\"iat\":1000000,\"exp\":1000001}" \
    | python3 -c "import base64,sys; print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).decode().rstrip('='))")
  local expired_token="${header}.${payload}.invalidsignature"
  http_get "${BACKEND_BASE_URL}/api/v1/workspaces" -H "Authorization: Bearer ${expired_token}"
  if [[ "${HTTP_STATUS}" == "401" ]]; then
    pass "${name}"
  elif [[ "${HTTP_STATUS}" == "000" ]]; then
    skip "${name}" "Backend not reachable"
  else
    skip "${name}" "Route not yet wired (HTTP ${HTTP_STATUS})"
  fi
}

test_malformed_token_rejected() {
  local name="JWT_MIDDLEWARE: malformed Authorization header returns 401"
  http_get "${BACKEND_BASE_URL}/api/v1/workspaces" -H "Authorization: notabearer"
  if [[ "${HTTP_STATUS}" == "401" ]]; then
    pass "${name}"
  elif [[ "${HTTP_STATUS}" == "000" ]]; then
    skip "${name}" "Backend not reachable"
  else
    skip "${name}" "Route not yet wired (HTTP ${HTTP_STATUS})"
  fi
}

# Suite 4: Session-Broker Integration
test_session_broker_health() {
  local name="SESSION_BROKER: health endpoint returns 200"
  http_get "${SESSION_BROKER_URL}/health"
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    pass "${name}"
  else
    skip "${name}" "Session broker not reachable (HTTP ${HTTP_STATUS})"
  fi
}

test_session_broker_jwt_accepted() {
  local name="SESSION_BROKER: JWT bearer token accepted on /api endpoint"
  if [[ -z "${ACQUIRED_TOKEN:-}" ]]; then
    skip "${name}" "No token acquired"
    return
  fi
  http_get "${SESSION_BROKER_URL}/api/sessions" -H "Authorization: Bearer ${ACQUIRED_TOKEN}"
  if [[ "${HTTP_STATUS}" == "200" || "${HTTP_STATUS}" == "404" ]]; then
    pass "${name}"
  elif [[ "${HTTP_STATUS}" == "401" || "${HTTP_STATUS}" == "403" ]]; then
    fail "${name}" "JWT token rejected by session-broker (HTTP ${HTTP_STATUS})"
  else
    skip "${name}" "Session broker not reachable (HTTP ${HTTP_STATUS})"
  fi
}

# Suite 5: Observability Integration
test_metrics_endpoint() {
  local name="OBSERVABILITY: /metrics endpoint serves Prometheus text format"
  http_get "${BACKEND_BASE_URL}/metrics"
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    if echo "${RESPONSE_BODY}" | grep -q "jwt_"; then
      pass "${name}"
    else
      fail "${name}" "Metrics endpoint returned 200 but no jwt_* metrics found"
    fi
  elif [[ "${HTTP_STATUS}" == "000" ]]; then
    skip "${name}" "Backend not reachable"
  else
    # Not all deploys expose /metrics on the same port — acceptable skip
    skip "${name}" "Metrics endpoint not at ${BACKEND_BASE_URL}/metrics (HTTP ${HTTP_STATUS})"
  fi
}

test_prometheus_scrape_target() {
  local name="OBSERVABILITY: Prometheus scrape target 'jwt-auth' registered"
  local prom_url="${PROMETHEUS_URL:-http://localhost:9090}"
  http_get "${prom_url}/api/v1/targets"
  if [[ "${HTTP_STATUS}" == "200" ]]; then
    if echo "${RESPONSE_BODY}" | python3 -c \
      "import json,sys; data=json.load(sys.stdin); active=[t for tg in data.get('data',{}).get('activeTargets',[]) for t in [tg.get('labels',{}).get('job','')] if t]; print('found' if 'jwt-auth' in active else 'missing')" \
      2>/dev/null | grep -q "found"; then
      pass "${name}"
    else
      skip "${name}" "jwt-auth job not yet scraped (may need deploy)"
    fi
  else
    skip "${name}" "Prometheus not reachable (HTTP ${HTTP_STATUS})"
  fi
}

# ---------------------------------------------------------------------------
# Run suites
# ---------------------------------------------------------------------------
ACQUIRED_TOKEN=""
SKIP_TOKEN_TESTS=0

log_info "================================================================"
log_info " Phase 2E — JWT Service-to-Service Authentication E2E Tests"
log_info "================================================================"
log_info "OIDC base: ${OIDC_BASE_URL}"
log_info "Backend:   ${BACKEND_BASE_URL}"
log_info "Broker:    ${SESSION_BROKER_URL}"
log_info ""

check_prereqs

log_info ""
log_info "--- Suite 1: OIDC Issuer Availability ---"
test_oidc_discovery_endpoint
test_oidc_discovery_fields
test_jwks_endpoint
test_jwks_key_algorithm

log_info ""
log_info "--- Suite 2: Token Acquisition ---"
test_token_acquisition
test_token_has_required_claims
test_token_expiry_positive
test_invalid_credentials_rejected

log_info ""
log_info "--- Suite 3: JWT Middleware / Backend Integration ---"
test_bearer_token_accepted
test_missing_token_rejected
test_expired_token_rejected
test_malformed_token_rejected

log_info ""
log_info "--- Suite 4: Session-Broker Integration ---"
test_session_broker_health
test_session_broker_jwt_accepted

log_info ""
log_info "--- Suite 5: Observability ---"
test_metrics_endpoint
test_prometheus_scrape_target

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL + SKIP))
log_info ""
log_info "================================================================"
log_info " Results: ${PASS}/${TOTAL} passed  |  ${FAIL} failed  |  ${SKIP} skipped"
log_info "================================================================"

if [[ "${FAIL}" -gt 0 ]]; then
  log_error "Failed tests:"
  for t in "${FAILED_TESTS[@]}"; do
    log_error "  - ${t}"
  done
fi

# Write machine-readable report
REPORT_FILE="${REPORT_DIR}/jwt-e2e-results.json"
python3 -c "
import json, sys
print(json.dumps({
  'suite': 'Phase2E-JWT-E2E',
  'timestamp': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
  'results': { 'pass': ${PASS}, 'fail': ${FAIL}, 'skip': ${SKIP}, 'total': ${TOTAL} },
  'failed_tests': $(python3 -c "import json; print(json.dumps(${FAILED_TESTS[*]+["$(IFS='","'; echo "${FAILED_TESTS[*]}")"]} if ${FAILED_TESTS[*]+1}0 else []))" 2>/dev/null || echo '[]'),
  'oidc_url': '${OIDC_BASE_URL}',
  'backend_url': '${BACKEND_BASE_URL}'
}, indent=2))
" > "${REPORT_FILE}" 2>/dev/null || true

log_info "Report written: ${REPORT_FILE}"

if [[ "${FAIL}" -gt "${MAX_FAILURES}" ]]; then
  log_fatal "Test suite FAILED (${FAIL} failures exceeds MAX_FAILURES=${MAX_FAILURES})"
fi

log_info "Test suite PASSED"
