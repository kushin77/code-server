# Service Account Inventory

This document records the canonical service accounts and automation identities used by the platform. It is the SSOT for ownership, scope, and rotation expectations.

## Inventory

| Identity | Type | Owner | Purpose | Secrets / IAM Scope | Rotation | Status | Source |
|---|---|---|---|---|---|---|---|
| `github-actions@kushin77-ops.iam.gserviceaccount.com` | GCP service account | Platform Engineering | GitHub Actions authentication and GSM access for deployment automation | IAM bindings for secret access and CI workflows | Quarterly review or when permissions change | Active | [docs/QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md](../QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md) |
| `code-server@kushnir-cloud.iam.gserviceaccount.com` | GCP service account | Platform Engineering | Production service identity referenced by deployment documentation | Least-privilege project IAM | Quarterly review | Documented | [docs/archives/root-markdowns/INFRASTRUCTURE-REMEDIATION-COMPLETE-APRIL-21-2026.md](../archives/root-markdowns/INFRASTRUCTURE-REMEDIATION-COMPLETE-APRIL-21-2026.md) |
| `code-server-ops@gcp-eiq.iam.gserviceaccount.com` | GCP service account | Platform Engineering | Ops automation and infrastructure management | Least-privilege project IAM | Quarterly review | Documented | [docs/archives/root-markdowns/INFRASTRUCTURE-REMEDIATION-FINAL-GUIDE.md](../archives/root-markdowns/INFRASTRUCTURE-REMEDIATION-FINAL-GUIDE.md) |
| `qa-user-creator@gcp-eiq.iam.gserviceaccount.com` | GCP service account | Platform Engineering | Legacy QA user creation flow | Admin Directory API scope | Retire after migration | Legacy | [docs/archives/root-markdowns/QA-USER-CREATION-RUNBOOK.md](../archives/root-markdowns/QA-USER-CREATION-RUNBOOK.md) |
| `qa@kushnir.cloud` | Workspace identity | QA / Automation | Dedicated QA login for E2E and portal validation | GSM secrets: `qa-user-email`, `qa-user-password` | Quarterly password rotation | Active | [docs/QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md](../QA-CREDENTIALS-IAC-IMMUTABLE-IDEMPOTENT.md) |
| `e2e-service@kushnir.cloud` | Workspace identity | QA / Automation | Dedicated E2E service-account profile | `config/e2e-service-account-profile.yml` | Quarterly review | Active | [docs/status/E2E-SERVICE-ACCOUNT-PROOF-2026-04-18.md](../status/E2E-SERVICE-ACCOUNT-PROOF-2026-04-18.md) |

## Governance Rules

1. Every service identity must have an owner and purpose.
2. Every IAM binding must be least privilege and reproducible.
3. Every secret or key used by automation must be stored in GSM or another approved secret store.
4. Every change to this inventory must be reflected in the relevant deployment or bootstrap automation.

## Validation Commands

```bash
gcloud iam service-accounts list --project kushin77-ops
gcloud secrets versions list qa-user-email --project kushin77-ops
gcloud secrets versions list qa-user-password --project kushin77-ops
```

## Notes

- This inventory should be updated when service accounts are created, rotated, or retired.
- Legacy identities must remain documented until they are fully removed from automation.