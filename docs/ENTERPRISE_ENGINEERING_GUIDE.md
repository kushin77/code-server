# Enterprise Engineering System — Implementation Guide

This document provides a **quick-start reference** for the enterprise FAANG-level engineering standards implemented in this repository.

All of the components described here work together to enforce elite-tier code quality, security, and operational excellence.

---

## Quick Navigation

| Component | Purpose | Location |
|-----------|---------|----------|
| **CONTRIBUTING.md** | Engineering constitution | [CONTRIBUTING.md](../../CONTRIBUTING.md) |
| **PR Template** | Enforced PR structure | [.github/pull_request_template.md](.github/pull_request_template.md) |
| **CODEOWNERS** | Code review enforcement | [.github/CODEOWNERS](.github/CODEOWNERS) |
| **Branch Protection** | Automated gates | [.github/BRANCH_PROTECTION.md](.github/BRANCH_PROTECTION.md) |
| **ADR System** | Architectural decisions | [docs/adr/](adr/) |
| **SLOs** | Reliability targets | [docs/slos/](slos/) |

---

## Workflow for Developers

### 1. Before Starting

```bash
# Update local branch
git checkout main
git pull origin main

# Create feature branch (naming: feature/xxx, bugfix/xxx, refactor/xxx)
git checkout -b feature/my-awesome-feature
```

### 2. Development

```bash
# Make changes, commit frequently
git add .
git commit -m "Clear, concise commit message"

# Run local checks BEFORE pushing
pre-commit run --all-files    # Lint, format
./scripts/validate.sh          # Custom validations
pytest tests/ -v --cov=.       # Unit tests
```

### 3. Push & Open PR

```bash
# Push to GitHub
git push origin feature/my-awesome-feature

# Open PR (GitHub will auto-detect and show PR template)
# Fill in ALL sections of template (no skipping)
```

### 4. CI/CD Runs Automatically

Pipeline executes:
1. **Lint** — Code style (must pass)
2. **Unit tests** — Coverage gate 80% (must pass)
3. **SAST** — Security scan (must pass)
4. **Dependency scan** — CVE detection (must pass)
5. **Secrets scan** — No hardcoded credentials (must pass)
6. **IaC policy** — OPA/Conftest (if .tf files)
7. **Build artifact** — Create signed, versioned image

### 5. Code Review

Two reviewers required:
1. **Code owner** (@kushin77 for critical paths)
2. **Peer engineer** (any qualified reviewer)

### 6. Merge & Deploy

Once approved and all checks pass:
- **Merge strategy**: Rebase and merge (linear history)
- **Auto-deployment**: CD pipeline runs
- **Monitoring**: Watch error rate, latency, health checks

---

## FAQ

### Q: Can I skip the PR template?
**A**: No. Sections exist for a reason. Fill them in. If a section doesn't apply, explain why.

### Q: Do I need tests for this change?
**A**: If it changes behavior, yes. If it's documentation-only, no.

### Q: What if I want to bypass branch protection?
**A**: Document the exception in GitHub, get approval from principal engineer. Expect to explain in next team meeting.

---

## Final Truth

**Code quality is not a suggestion — it's a requirement.**

Elite engineering = **enforcement + culture + automation**.

No exceptions. No compromises. No "we'll clean it up later."