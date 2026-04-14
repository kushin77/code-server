# GitHub Actions Workflow Templates

This directory contains governance-compliant workflow templates for kushin77/* repositories.

## Using the Templates

Copy and customize templates for your repository:

```bash
# Copy template
cp TEMPLATE-ci-lint.yml ci-lint.yml

# Customize
# 1. Update job names if needed
# 2. Adjust timeouts for your repo
# 3. Update repository-specific paths
# 4. Commit and enable in Actions tab
```

## Available Templates

### 1. TEMPLATE-ci-lint.yml
**Purpose**: Linting and code formatting

**Triggers**:
- Push to main/develop (only if src/ or package.json changed)
- Pull request to main

**Jobs**:
- `lint`: ESLint, Prettier, or similar (10 min)
- `spell-check`: Typo detection (5 min)

**Cost**: ~$13/month (100 runs)

**Customize**:
```yaml
- run: npm run lint  # Change to your lint command
- run: npm run format:check  # Change to your linter
```

---

### 2. TEMPLATE-ci-tests.yml
**Purpose**: Unit and integration testing

**Triggers**:
- Push to main/develop (only if src/tests changed)
- Pull request to main

**Jobs**:
- `unit-tests`: Matrix across Node 18 & 20 (20 min)
- `integration-tests`: With database/cache services (25 min)
- `test-summary`: Aggregates results (5 min)

**Cost**: ~$26/month (100 runs across 2 Node versions)

**Customize**:
```yaml
strategy:
  matrix:
    node-version: [18.x, 20.x]  # Adjust as needed

services:
  postgres:
    image: postgres:15  # Customize as needed
  redis:
    image: redis:7
```

---

### 3. TEMPLATE-ci-security.yml
**Purpose**: Security scanning (SAST, SCA, secrets, containers)

**Triggers**:
- Push to main/develop
- Pull requests
- Weekly schedule (Sunday 2 AM)

**Jobs**:
- `dependency-check`: npm audit + Snyk (15 min)
- `sast-scan`: SemGrep (15 min)
- `container-scan`: Trivy filesystem (10 min)
- `secret-scan`: TruffleHog (10 min)

**Cost**: ~$13/month (varies by schedule)

**Customize**:
```yaml
- name: Audit dependencies
  run: npm audit --audit-level=moderate  # Adjust severity

- uses: snyk/actions/node@master
  secrets.SNYK_TOKEN  # Requires Snyk account
```

---

### 4. TEMPLATE-ci-build.yml
**Purpose**: Build and push Docker images (or other artifacts)

**Triggers**:
- Push to main with code changes
- After successful tests (workflow_run)

**Jobs**:
- `build`: Docker build + push to GHCR (30 min)
- `scan-image`: Trivy image scan (15 min)

**Cost**: ~$40/month (container storage + build compute)

**Customize**:
```yaml
REGISTRY: ghcr.io  # Change to your registry
IMAGE_NAME: your-org/your-image

with:
  context: .  # Docker build context
```

---

## Governance Requirements (Built-in)

✅ All templates include:

```yaml
env:
  COST_CATEGORY: "ci-lint"  # Category for quota tracking

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # Cancel stale runs

timeout-minutes: 10          # Job-level timeout

- name: Cleanup
  if: always()
  run: docker system prune -af  # Resource cleanup
```

## Repository Compliance

To be governance-compliant, your repository must have:

```
.github/
├─ workflows/
│  ├─ lint.yml         (based on TEMPLATE-ci-lint.yml)
│  ├─ test.yml         (based on TEMPLATE-ci-tests.yml)
│  ├─ security.yml     (based on TEMPLATE-ci-security.yml)
│  └─ build.yml        (optional, if you have Docker)
└─ README.md           (workflow documentation)

COST-ESTIMATE.md       (budget forecast)
```

## Common Customizations

### 1. Skip Workflow on Certain Paths

```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'package.json'
    paths-ignore:
      - 'docs/**'
      - '*.md'
```

### 2. Matrix Testing

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
    node-version: [18.x, 20.x, 21.x]
  max-parallel: 4
```

### 3. Conditional Steps

```yaml
- name: Deploy to staging
  if: github.ref == 'refs/heads/main'
  run: ./deploy-staging.sh
```

### 4. Approval Gates

For production deployments, add a workflow_dispatch trigger:

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [staging, production]

jobs:
  deploy:
    environment: ${{ github.event.inputs.environment }}
    steps:
      - run: ./deploy.sh ${{ github.event.inputs.environment }}
```

## Troubleshooting

### Workflow takes too long?
1. Add caching for dependencies
2. Parallelize jobs with `strategy.matrix`
3. Split into multiple workflows
4. Request quota exception if legitimate

### Workflow fails constantly?
1. Check logs in Actions tab
2. Test locally: `npm run lint` / `npm test`
3. Update dependencies: `npm install`
4. Contact devops-team if infrastructure issue

### Cost spike?
1. Check COST-CATEGORY label
2. Review recent commits (did you add matrix testing?)
3. See [COST-OPTIMIZATION.md](../../COST-OPTIMIZATION.md)
4. Post in #devops-governance

## Cost Estimates

Based on GitHub's pricing ($0.008/min per ubuntu-latest runner):

| Template | Avg Duration | Monthly (50 runs) | Monthly (100 runs) |
|----------|--------------|------------------|-------------------|
| ci-lint | 10 min | $4 | $8 |
| ci-tests | 20 min | $8 | $16 |
| ci-security | 15 min | $6 | $12 |
| ci-build | 30 min | $12 | $24 |
| **Combined** | **~75 min** | **$30** | **$60** |

**With 100 runs/month (typical)**: ~$60/month per active repository

## Questions?

- **How do I enable a template?** Copy to your repo, customize, commit, enable in Actions → Workflows
- **Can I combine templates?** Yes, combine into single workflow or keep separate (separate = parallel)
- **Do I need all templates?** Minimal: ci-lint + ci-tests. Add ci-security for production.
- **What if my build is different?** Use these as reference, adapt to your tech stack
- **Can I add more jobs?** Yes, but watch quota and cost (post in #devops-governance for large additions)

---

**Last Updated**: April 13, 2026
**Governance Version**: 1.0
**Contact**: devops-team@example.com
