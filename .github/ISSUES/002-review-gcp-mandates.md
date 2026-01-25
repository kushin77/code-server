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
