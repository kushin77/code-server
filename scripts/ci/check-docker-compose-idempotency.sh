#!/bin/bash
# @file scripts/ci/check-docker-compose-idempotency.sh
# @module infrastructure/validation
# @description P3-1531: Validate Docker Compose configuration is idempotent (safe to run multiple times)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @usage check-docker-compose-idempotency.sh [--compose-file FILE] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly COMPOSE_FILE="${COMPOSE_FILE:-${REPO_ROOT}/docker-compose.yml}"
readonly REPORT_FILE="${REPORT_FILE:-${REPO_ROOT}/artifacts/compose-idempotency-report.txt}"

# Load network configuration SSOT
source "${REPO_ROOT}/scripts/_common/_epic-1536-network-config.env" || {
    echo "Warning: Network configuration SSOT not found, using defaults"
}

# Source common logging functions (P3 #1533: consolidated logging)
source "${REPO_ROOT}/scripts/_common/init.sh"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--compose-file)
			COMPOSE_FILE="${2:-}"
			shift 2
			;;
		--report|--fix)
			shift
			;;
		*)
			if [[ "$1" != --* ]]; then
				COMPOSE_FILE="$1"
			fi
			shift
			;;
	esac
done

check_image_pins() {
	log_info "Checking for floating image tags"

	local violations=0
	local image_line
	while IFS= read -r image_line; do
		local line_number="${image_line%%:*}"
		local image_ref="${image_line#*: image: }"
		image_ref="${image_ref//\"/}"

		if [[ -z "${image_ref}" ]]; then
			continue
		fi

		if [[ "${image_ref}" != *"@sha256:"* ]]; then
			log_warn "Unpinned image detected on line ${line_number}: ${image_ref}"
			violations=$((violations + 1))
			continue
		fi

		case "${image_ref}" in
			*:latest@sha256:*|*:main@sha256:*|*:master@sha256:*|*:dev@sha256:*|*:develop@sha256:*|*:staging@sha256:*)
				log_warn "Floating tag detected on line ${line_number}: ${image_ref}"
				violations=$((violations + 1))
				;;
		esac
	done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)

	return "${violations}"
}

check_restart_policies() {
	log_info "Checking restart policies for automatic recovery"
	if grep -q 'restart:[[:space:]]*unless-stopped' "${COMPOSE_FILE}"; then
		return 0
	fi

	log_warn "No restart policy found"
	return 1
}

check_health_checks() {
	log_info "Checking for health checks"
	if grep -q 'healthcheck:' "${COMPOSE_FILE}"; then
		return 0
	fi

	log_warn "No health checks found"
	return 1
}

generate_report() {
	log_info "Generating idempotency report"

	local image_pins_ok=0
	local restart_ok=0
	local health_ok=0

	if check_image_pins; then
		image_pins_ok=1
	fi
	if check_restart_policies; then
		restart_ok=1
	fi
	if check_health_checks; then
		health_ok=1
	fi

	local overall_status="PASS"
	if [[ ${image_pins_ok} -eq 0 ]] || [[ ${restart_ok} -eq 0 ]] || [[ ${health_ok} -eq 0 ]]; then
		overall_status="FAIL"
	fi

	mkdir -p "$(dirname "${REPORT_FILE}")"
	{
		echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		echo "compose_file=${COMPOSE_FILE}"
		echo "status=${overall_status}"
		echo "immutable_image_digests=${image_pins_ok}"
		echo "restart_policies=${restart_ok}"
		echo "health_checks=${health_ok}"
	} > "${REPORT_FILE}"

	log_info "Report saved to ${REPORT_FILE}"

	[[ "${overall_status}" == "PASS" ]]
}

main() {
	if [[ ! -f "${COMPOSE_FILE}" ]]; then
		for candidate in \
			"${REPO_ROOT}/docker-compose.service.yml.tpl" \
			"${REPO_ROOT}/docker-compose.env-test.yml" \
			"${REPO_ROOT}/docker-compose.yaml"; do
			if [[ -f "${candidate}" ]]; then
				COMPOSE_FILE="${candidate}"
				break
			fi
		done
	fi

	if [[ ! -f "${COMPOSE_FILE}" ]]; then
		mkdir -p "$(dirname "${REPORT_FILE}")"
		{
			echo "status=SKIPPED"
			echo "compose_file=NONE"
			echo "reason=No compose manifest present in repo"
		} > "${REPORT_FILE}"
		log_warning "Compose manifest not present; skipping idempotency validation"
		return 0
	fi

	log_info "Checking Docker Compose idempotency: ${COMPOSE_FILE}"

	if ! generate_report; then
		log_error "Compose idempotency validation failed"
		return 1
	fi

	log_info "Idempotency check complete"
}

main "$@"