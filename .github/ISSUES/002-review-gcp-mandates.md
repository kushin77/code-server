---
title: "Review GCP mandates and policies"
labels: [onboarding, compliance]
assignees: []
---

# Review GCP mandates

- **Status:** in-progress
- **Description:** Scan `GCP-landing-zone` for mandates, policies, OPA rules, Terraform controls and extract actionable developer requirements (CMEK, VPC-SC, pre-commit hooks, CI gates).

Checklist:

- [ ] Identify mandatory policies (FedRAMP/NIST/OPA)
- [ ] Extract required CI checks and pre-commit configuration
- [ ] Document developer obligations (auth, secrets, remote state)

Findings (summary):

- Mandatory controls: FedRAMP Moderate / NIST controls enforced via OPA policies.
- Remote Terraform state must be in GCS with CMEK and locking; do not keep local state.
- Pre-commit and CI gates required (format, tflint/terraform validate where applicable).
- Security scans: Snyk and static scans integrated in CI; evidence collection automated.
- Secrets: use Secret Manager / GitHub Secrets; repository must not contain secrets.
- Runtime constraints: VPC Service Controls and workload identity may affect local integration tests.

Next steps:

- Update onboarding docs with commands to authenticate (`gcloud auth application-default login`).
- Add CI workflows and pre-commit rules to repo (in progress).
- Document where to find detailed policy docs: `GCP-landing-zone/README.md` and `docs/policies`.
