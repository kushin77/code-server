# AI Model Promotion Gates (#630)

This file is kept as a compatibility bridge for CI policy checks and for direct references from governance automation.

Canonical navigation index: [docs/structure/README.md](structure/README.md)

## Canary Evidence Format

Every model promotion decision must include the following artifacts:

- `evaluation_report.json`
- `canary_results.json`
- `promotion_decision.md`

The canary evidence package must show measured quality, safety, and latency behavior across the canary window before default-stage promotion.

## Postmortem Loop

If a canary fails promotion thresholds, open an incident/postmortem entry and attach failure evidence plus rollback confirmation.

Postmortem updates must include:

- trigger condition
- rollback execution status
- remediation owner and follow-up issue

## CI Enforcement

This contract is validated by:

- `scripts/ci/validate-ollama-model-promotion-gates.sh`

CI blocks when required evidence format or section markers are missing from this policy file.
