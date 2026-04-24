# Template Guide

This directory documents the reusable templates that keep governance, deployment, and infrastructure work consistent.

## GitHub Templates

- `.github/pull_request_template.md` - required PR gate for non-trivial changes.
- `.github/ISSUE_TEMPLATE/bug.yml` - defect and regression reports.
- `.github/ISSUE_TEMPLATE/feature.yml` - feature or enhancement requests.
- `.github/ISSUE_TEMPLATE/task.yml` - implementation tasks and maintenance work.
- `.github/ISSUE_TEMPLATE/epic.yml` - ordered multi-step initiatives.
- `.github/ISSUE_TEMPLATE/infrastructure.yml` - deployment, ops, and infra changes.
- `.github/ISSUE_TEMPLATE/security.yml` - security findings and remediation work.
- `.github/ISSUE_TEMPLATE/governance-waiver.md` - temporary policy exception request.
- `.github/ISSUE_TEMPLATE/governance-remediation.md` - policy violation remediation path.

## Infrastructure Templates

- `docker-compose.service.yml.tpl` - service stanza template for new Compose-managed services.
- `terraform/modules/_template/` - starting point for new Terraform modules.
- `docs/adr/TEMPLATE.md` - Architecture Decision Record template.

## Usage Rules

1. Copy the template instead of inventing a new structure.
2. Replace placeholders with environment variables or explicit inputs.
3. Keep generated output deterministic and idempotent.
4. Add validation or CI coverage when a template becomes reusable in more than one place.

## When To Extend The Library

- A second service or module follows the same pattern.
- A new issue type needs dedicated guidance.
- A recurring manual step should become a template or checklist.

## Related Governance

- Follow `scripts/_template.sh` for new bash scripts.
- Use `scripts/_common/init.sh` for script bootstrap.
- Keep all template content free of hardcoded secrets, domains, and host-specific values.