#!/usr/bin/env bash
# @file        scripts/ops/team-signoff-packet.sh
# @module      operations/validation
# @description Generate the production team sign-off packet for the Apr 27-29 readiness gate
# @status      Executable immediately without external dependencies
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

OUTPUT_FILE="artifacts/triage/team-signoff-packet-$(date +%Y%m%d).md"
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"

mkdir -p "$OUTPUT_DIR"

log_info "Generating team sign-off packet at $OUTPUT_FILE"

required_evidence=(
  "docs/PRODUCTION-DEPLOYMENT-RUNBOOK.md|Production deployment runbook"
  "docs/PERFORMANCE-LOAD-TESTING-GUIDE.md|Performance load testing guide"
  "artifacts/triage/deployment-readiness-report-20260423.md|Deployment readiness report"
  "artifacts/staging/staging-validation-dry-run.md|Staging validation dry run"
  "artifacts/staging/staging-deployment-report.md|Staging deployment report"
  "artifacts/performance-tests/PERFORMANCE-TEST-ANALYSIS-APR22-2026.md|Performance test analysis"
  "artifacts/security/security-audit-report-apr22.md|Security audit report"
)

all_present=true

{
  echo "# Team Sign-Off Packet - $(date '+%B %d, %Y')"
  echo
  echo "**Status**: Ready to Collect"
  echo "**Blocking Issue**: #1464 Team Sign-Offs - Production Readiness Approval"
  echo "**Prepared For**: Apr 27-29 sign-off window"
  echo
  echo "## Evidence Anchors"
  echo
  echo "| Evidence | Status |"
  echo "| --- | --- |"

  for entry in "${required_evidence[@]}"; do
    path="${entry%%|*}"
    label="${entry#*|}"

    if [[ -f "$path" ]]; then
      echo "| $label | Available |"
    else
      echo "| $label | Missing |"
      all_present=false
    fi
  done

  echo
  echo "## Sign-Off Targets"
  echo
  echo "### Infrastructure Team"
  echo "- [ ] Confirm SSH, host, DNS, backup, and NAS readiness"
  echo "- [ ] Validate primary and failover hosts"
  echo "- [ ] Confirm monitoring and rollback procedures"
  echo "- [ ] Sign-off text: \"Approved for production deployment\""
  echo
  echo "### Operations Team"
  echo "- [ ] Review runbook and performance guide"
  echo "- [ ] Confirm staging validation and monitoring readiness"
  echo "- [ ] Validate incident response and rollback coverage"
  echo "- [ ] Sign-off text: \"Operations approved for deployment\""
  echo
  echo "### Security Team"
  echo "- [ ] Review dependency audit and secret handling"
  echo "- [ ] Confirm no critical or high unmitigated vulnerabilities"
  echo "- [ ] Validate GSM and environment variable handling"
  echo "- [ ] Sign-off text: \"Security approved for deployment\""
  echo
  echo "### Product Team"
  echo "- [ ] Confirm feature and documentation readiness"
  echo "- [ ] Validate no blocking P0/P1 issues remain"
  echo "- [ ] Confirm user-facing behavior is stable"
  echo "- [ ] Sign-off text: \"Product ready for production\""
  echo
  echo "### QA Team"
  echo "- [ ] Confirm test pass rate and critical path coverage"
  echo "- [ ] Validate regression and integration coverage"
  echo "- [ ] Confirm performance tests remain within target"
  echo "- [ ] Sign-off text: \"QA approved for deployment\""
  echo
  echo "### Release Manager"
  echo "- [ ] Collect all team approvals"
  echo "- [ ] Confirm no open blocking issues remain"
  echo "- [ ] Approve GO/NO-GO decision path"
  echo "- [ ] Sign-off text: \"Approved for production deployment\""
  echo
  echo "## Next Action"
  echo
  echo "Use this packet during the Apr 27-29 sign-off window to record written approvals, then attach the collected approvals to #1464 and reference the final GO/NO-GO gate in #1467."
} > "$OUTPUT_FILE"

if [[ "$all_present" == true ]]; then
  log_info "Team sign-off packet generated successfully"
else
  log_error "One or more evidence anchors are missing"
  exit 1
fi
