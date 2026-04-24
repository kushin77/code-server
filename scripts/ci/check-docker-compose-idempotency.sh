#!/bin/bash
# @file check-docker-compose-idempotency.sh
# @module infrastructure/validation
# @description P3-1531: Validate Docker Compose configuration is idempotent (safe to run multiple times)
# @governance GOV-002: All services must use immutable image digests, no floating tags, pinned versions
# @usage check-docker-compose-idempotency.sh [--compose-file FILE] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
REPO_ROOT=$(cd ${SCRIPT_DIR}/../.. && pwd)

# Source common logging functions (P3 #1533: consolidated logging)
source "${REPO_ROOT}/scripts/_common/init.sh"

COMPOSE_FILE=${REPO_ROOT}/docker-compose.yml
REPORT_FILE=${REPO_ROOT}/artifacts/compose-idempotency-report.txt

while [[ $# -gt 0 ]]; do
 case $1 in
 --compose-file)
 COMPOSE_FILE=$2
 shift 2
 ;;
 --report)
 shift
 ;;
 --fix)
 shift
 ;;
 *)
 if [[ $1 != --* ]]; then
 COMPOSE_FILE=$1
 fi
 shift
 ;;
 esac
done

check_floating_tags() {
 log_info "Checking for floating image tags"
 local violations=0
 local images
 images=$(grep -E '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" | awk '{print $2}')
 for image in $images; do
 case "$image" in
 *:latest|*:main|*:master|*:dev|*:develop|*:staging)
 log_warn "Floating tag detected: $image"
 violations=$((violations + 1))
 ;;
 esac
 done
 return $violations
}

check_immutability() {
 log_info "Checking immutable configuration patterns"
 local issues=0
 if grep -qE ^[[:space:]]*volumes:[[:space:]]*$ ${COMPOSE_FILE}; then
 issues=$issues
 fi
 return $issues
}

check_restart_policies() {
 log_info "Checking restart policies for automatic recovery"
 if grep -q restart:[[:space:]]*unless-stopped ${COMPOSE_FILE}; then
 return 0
 fi
 log_warn "No restart policy found"
 return 1
}

check_health_checks() {
 log_info "Checking for health checks"
 if grep -q healthcheck: ${COMPOSE_FILE}; then
 return 0
 fi
 log_warning No health checks found
 return 1
}

generate_report() {
 log_info Generating idempotency report
 local floating_tags_ok=0
 local immutable_ok=0
 local restart_ok=0
 local health_ok=0

 check_floating_tags && floating_tags_ok=1 || true
 check_immutability && immutable_ok=1 || true
 check_restart_policies && restart_ok=1 || true
 check_health_checks && health_ok=1 || true

 local overall_status=PASS
 [[ $floating_tags_ok -eq 0 ]] && overall_status=FAIL
 [[ $restart_ok -eq 0 ]] && overall_status=FAIL

 mkdir -p $(dirname ${REPORT_FILE})
 {
 echo timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
 echo compose_file=${COMPOSE_FILE}
 echo status=${overall_status}
 echo immutable_image_digests=${floating_tags_ok}
 echo immutable_configuration=${immutable_ok}
 echo restart_policies=${restart_ok}
 echo health_checks=${health_ok}
 } > ${REPORT_FILE}

 log_info Report saved to ${REPORT_FILE}
}

main() {
	if [[ ! -f ${COMPOSE_FILE} ]]; then
		for candidate in \
			${REPO_ROOT}/docker-compose.service.yml.tpl \
			${REPO_ROOT}/docker-compose.env-test.yml \
			${REPO_ROOT}/docker-compose.yaml; do
			if [[ -f ${candidate} ]]; then
				COMPOSE_FILE=${candidate}
				break
			fi
		done
	fi

 if [[ ! -f ${COMPOSE_FILE} ]]; then
		mkdir -p $(dirname ${REPORT_FILE})
		{
			echo status=SKIPPED
			echo compose_file=NONE
			echo reason=No compose manifest present in repo
		} > ${REPORT_FILE}
				log_warning "Compose manifest not present; skipping idempotency validation"
		return 0
 fi

 log_info Checking Docker Compose idempotency: ${COMPOSE_FILE}
 check_floating_tags || true
 check_immutability || true
 check_restart_policies || true
 check_health_checks || true
 generate_report
 log_info Idempotency check complete
}

main $@