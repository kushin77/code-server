#!/usr/bin/env bash
###############################################################################
# Phase 5 Week 1: Light Load Test Wrapper
#
# Delegates to the Python load-test implementation while keeping shell-based
# entry points consistent with the rest of the repository.
###############################################################################

# Governance Compliance: GOV-001/GOV-002
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"
trap 'log_error "Load test failed at line $LINENO"; exit 1' ERR
trap 'log_info "Light load test process finished."' EXIT

PRIMARY_HOST="${PRIMARY_HOST:?PRIMARY_HOST must be set}"
PRIMARY_PORT="${PRIMARY_PORT:-80}"
PYTHON_SCRIPT="${SCRIPT_DIR}/phase5-light-load-test.py"

log_info "Starting light load test against ${PRIMARY_HOST}..."
export PRIMARY_HOST
export PRIMARY_PORT

if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
        log_error "Missing Python implementation: ${PYTHON_SCRIPT}"
        exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
        log_error "python3 is required to run the light load test"
        exit 1
fi

# Use regular execution instead of exec to preserve trap environment
python3 "${PYTHON_SCRIPT}"
exit $?
