# Contributing Guidelines

## Development Workflow
1. **Pull Latest Changes:** Always start by pulling from `main`.
2. **Feature Branching:** Create a descriptive branch (e.g., `feat/opa-policy-update`).
3. **Local Testing:**
   - Run OPA tests: `wsl bash scripts/ops/test-opa-policies.sh`
   - Run build steps relevant to your app.
4. **Commits:** Use [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat:`, `fix:`, `docs:`, `chore:`).
5. **Code Style:** Ensure Python code follows PEP 8 and TypeScript follows local ESLint rules.

## Production Readiness Requirements
All PRs must pass the following "Quality Gate" before being merged to `main`:
- [ ] No lint errors.
- [ ] All unit and E2E tests passing.
- [ ] Documentation updated (if applicable).
- [ ] PR linked to a GitHub Issue.
- [ ] `production-readiness-check.sh` returns PASSED.

## Reporting Issues
Please use the GitHub Issue tracker. Tag issues with appropriate priority:
- **P0:** Critical / Blocker
- **P1:** High Priority
- **P2:** Medium Priority
- **P3:** Low Priority / Technical Debt
