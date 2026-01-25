---
title: "Add CI and linting templates"
labels: [ci, automation]
assignees: []
---

# Add CI and linting

- **Status:** not-started
- **Description:** Add GitHub Actions templates for security checks, IaC scanning, linting, and pre-commit enforcement to align with landing zone requirements.

Checklist:

- [ ] Add `ci/validate.yml` for terraform & linters
- [ ] Add `ci/security.yml` for Snyk / static analysis
- [ ] Add pre-commit config and enforce via CI
