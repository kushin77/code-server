# P0 Governance Enforcement SLA and Ownership Matrix

Date: 2026-04-18
Issue: #702

## Purpose
Define accountability and response targets for fail-closed governance controls in CI.

## Enforcement Scope
P0 checks are blocking by default and include:
- Shell script quality (shellcheck)
- Terraform fmt and validate
- YAML linting
- Duplication detection (jscpd)
- Secret detection (gitleaks and trufflehog verified findings)

P1 and P2 checks remain advisory unless promoted by policy decision.

## Waiver Policy
Temporary bypass of P0 behavior is allowed only when both are present:
- GOVERNANCE_P0_WAIVER_ISSUE
- GOVERNANCE_P0_WAIVER_TOKEN

If one exists without the other, pipeline execution fails.

## SLA Targets
- Detection latency: under 5 minutes from workflow start to first failed P0 signal
- Triage acknowledgement: under 30 minutes during business hours
- Mitigation decision: under 4 hours for production-impacting P0 failures
- Waiver decision: under 2 hours if bypass is requested
- Closure evidence posted: under 1 business day after fix merge

## Owner Matrix
| Area | Primary Owner | Secondary Owner | Escalation Trigger |
|---|---|---|---|
| Governance workflow integrity | Platform Engineering | DevOps | Guardrail regression or fail-open pattern detected |
| Secret scanning enforcement | Security Engineering | Platform Engineering | Verified secret or scanner bypass detected |
| Terraform and YAML policy gates | Infrastructure Engineering | Platform Engineering | Repeated P0 validation failures across 2+ runs |
| Waiver approvals and expiry | Security Engineering | Repository Owners | Waiver exceeds approved expiry or lacks issue linkage |
| Audit and evidence publication | Repository Owners | Platform Engineering | Missing incident notes or acceptance evidence |

## Operational Metrics
Track and publish weekly:
- Count of P0 failures
- Count of bypassed P0 checks
- Count of invalid waiver attempts
- Mean time to acknowledge
- Mean time to mitigation

Target values:
- Bypassed P0 checks without waiver: 0
- Invalid waiver attempts accepted: 0

## Review Cadence
- Weekly review in governance sync
- Monthly policy calibration across P0/P1/P2 boundaries
- Immediate review after any incident involving P0 bypass or silent pass-through
