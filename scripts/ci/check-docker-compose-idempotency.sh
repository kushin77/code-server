#!/bin/bash
# @file scripts/ci/check-docker-compose-idempotency.sh
# @module infrastructure/validation
# @description P3-1531: Validate Docker Compose configuration is idempotent (safe to run multiple times)
# @governance GOV-002: All services must use immutable image digests, no floating tags, pinned versions
# @usage check-docker-compose-idempotency.sh [--compose-file FILE] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common logging functions (P3 #1533: consolidated logging)
source "${REPO_ROOT}/scripts/_common/init.sh"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
REPORT_FILE="${REPO_ROOT}/artifacts/compose-idempotency-report.txt"

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

check_floating_tags() {
	log_info "Checking for floating image tags"

	local violations=0
	local image_line
	while IFS= read -r image_line; do
		local line_number="${image_line%%:*}"
		local line_content="${image_line#*:}"
		local image_ref="${line_content#*image: }"
		image_ref="${image_ref//\"/}"

		case "${image_ref}" in
			*:latest|*:main|*:master|*:dev|*:develop|*:staging)
				log_warn "Floating tag detected on line ${line_number}: ${image_ref}"
				violations=$((violations + 1))
				;;
		esac
	done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)

	return $violations
}

check_immutability() {
	log_info "Checking immutable configuration patterns"

	local issues=0
	local image_line
	while IFS= read -r image_line; do
		local line_number="${image_line%%:*}"
		local line_content="${image_line#*:}"
		local image_ref="${line_content#*image: }"
		image_ref="${image_ref//\"/}"

		if [[ "${image_ref}" != *"@sha256:"* ]]; then
			log_warn "Found image reference without digest pin on line ${line_number}: ${image_ref}"
			issues=$((issues + 1))
		fi
	done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)

	return $issues
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

	local floating_tags_ok=0
	local immutable_ok=0
	local restart_ok=0
	local health_ok=0

	if check_floating_tags; then
		floating_tags_ok=1
	fi
	if check_immutability; then
		immutable_ok=1
	fi
	if check_restart_policies; then
		restart_ok=1
	fi
	if check_health_checks; then
		health_ok=1
	fi

	local overall_status="PASS"
	[[ ${floating_tags_ok} -eq 0 ]] && overall_status="FAIL"
	[[ ${immutable_ok} -eq 0 ]] && overall_status="FAIL"
	[[ ${restart_ok} -eq 0 ]] && overall_status="FAIL"

	mkdir -p "$(dirname "${REPORT_FILE}")"
	cat > "${REPORT_FILE}" <<EOF
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
compose_file=${COMPOSE_FILE}
status=${overall_status}
immutable_image_digests=${floating_tags_ok}
immutable_configuration=${immutable_ok}
restart_policies=${restart_ok}
health_checks=${health_ok}
EOF

	log_info "Report saved to ${REPORT_FILE}"

	[[ ${overall_status} == "PASS" ]]
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
		cat > "${REPORT_FILE}" <<EOF
status=SKIPPED
compose_file=NONE
reason=No compose manifest present in repo
EOF
		log_warn "Compose manifest not present; skipping idempotency validation"
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
 while IFS= read -r image; do
 local line_number="${image%%:*}"
 local line_content="${image#*:}"
 local image_ref="${line_content#*image: }"

 if [[ -z "${image_ref}" ]]; then
 continue
 fi

 if [[ "${image_ref}" != *"@sha256:"* ]]; then
 log_warn "Unpinned image detected on line ${line_number}: ${image_ref}"
 violations=$((violations + 1))
 continue
 fi

 case "${image_ref}" in
 *:latest|*:main|*:master|*:dev|*:develop|*:staging)
 log_warn "Floating tag detected on line ${line_number}: ${image_ref}"
 violations=$((violations + 1))
 ;;
 esac
 done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)
 while IFS= read -r image_line; do
 local line_number="${image_line%%:*}"
 local line_content="${image_line#*:}"
 local image_ref="${line_content#*image: }"
 image_ref="${image_ref//\"/}"

 if [[ "${image_ref}" != *"@sha256:"* ]]; then
 log_warn "Unpinned image detected on line ${line_number}: ${image_ref}"
 violations=$((violations + 1))
 continue
 fi

 if grep -qE '^[[:space:]]*image:[[:space:]]*.*:latest([[:space:]]|$)' "${COMPOSE_FILE}"; then
 log_warn "Found latest tag reference"
 log_warn "Floating tag detected on line ${line_number}: ${image_ref}"
 violations=$((violations + 1))
 ;;
 esac
 done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)
#!/bin/bash
# @file scripts/ci/check-docker-compose-idempotency.sh
# @module infrastructure/validation
# @description P3-1531: Validate Docker Compose configuration is idempotent (safe to run multiple times)
# @governance GOV-002: All services must use immutable image digests, no floating tags, pinned versions
# @usage check-docker-compose-idempotency.sh [--compose-file FILE] [--fix] [--report]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common logging functions (P3 #1533: consolidated logging)
source "${REPO_ROOT}/scripts/_common/init.sh"

COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
REPORT_FILE="${REPO_ROOT}/artifacts/compose-idempotency-report.txt"

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

check_floating_tags() {
	log_info "Checking for floating image tags"

	local violations=0
	local image_line
	while IFS= read -r image_line; do
		local line_number="${image_line%%:*}"
		local line_content="${image_line#*:}"
		local image_ref="${line_content#*image: }"
		image_ref="${image_ref//\"/}"

		case "${image_ref}" in
			*:latest|*:main|*:master|*:dev|*:develop|*:staging)
				log_warn "Floating tag detected on line ${line_number}: ${image_ref}"
				violations=$((violations + 1))
				;;
		esac
	done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)

	return $violations
}

check_immutability() {
	log_info "Checking immutable configuration patterns"

	local issues=0
	local image_line
	while IFS= read -r image_line; do
		local line_number="${image_line%%:*}"
		local line_content="${image_line#*:}"
		local image_ref="${line_content#*image: }"
		image_ref="${image_ref//\"/}"

		if [[ "${image_ref}" != *"@sha256:"* ]]; then
			log_warn "Found image reference without digest pin on line ${line_number}: ${image_ref}"
			issues=$((issues + 1))
		fi
	done < <(grep -nE '^[[:space:]]*image:[[:space:]]*' "${COMPOSE_FILE}" || true)

	return $issues
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

	local floating_tags_ok=0
	local immutable_ok=0
	local restart_ok=0
	local health_ok=0

	if check_floating_tags; then
		floating_tags_ok=1
	fi
	if check_immutability; then
		immutable_ok=1
	fi
	if check_restart_policies; then
		restart_ok=1
	fi
	if check_health_checks; then
		health_ok=1
	fi

	local overall_status="PASS"
	[[ ${floating_tags_ok} -eq 0 ]] && overall_status="FAIL"
	[[ ${immutable_ok} -eq 0 ]] && overall_status="FAIL"
	[[ ${restart_ok} -eq 0 ]] && overall_status="FAIL"

	mkdir -p "$(dirname "${REPORT_FILE}")"
	cat > "${REPORT_FILE}" <<EOF
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
compose_file=${COMPOSE_FILE}
status=${overall_status}
immutable_image_digests=${floating_tags_ok}
immutable_configuration=${immutable_ok}
restart_policies=${restart_ok}
health_checks=${health_ok}
EOF

	log_info "Report saved to ${REPORT_FILE}"

	[[ ${overall_status} == "PASS" ]]
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
		cat > "${REPORT_FILE}" <<EOF
status=SKIPPED
compose_file=NONE
reason=No compose manifest present in repo
EOF
		log_warn "Compose manifest not present; skipping idempotency validation"
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