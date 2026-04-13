# GitHub Actions Best Practices

## Workflow Design

### 1. Clear Job Names
Use descriptive job names that indicate what they test/deploy.

```yaml
jobs:
  validate:               # Not: "Test 1"
    name: Terraform Validate
  build:
    name: Build Docker Image
```

### 2. Concurrency Management
Prevent multiple deployments from running simultaneously.

```yaml
concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false  # Don't cancel pending deploys
```

### 3. Conditional Execution
Use `if` conditions to control job flow.

```yaml
- name: Deploy Production
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  run: terraform apply

- name: Rollback on Failure
  if: failure() && github.event_name == 'push'
  run: kubectl rollout undo deployment/code-server
```

### 4. Error Handling
Distinguish between fatal and non-fatal failures.

```yaml
- name: Run Tests
  run: npm test
  continue-on-error: false  # Block workflow if tests fail

- name: Generate Report
  run: npm run report
  continue-on-error: true   # Non-blocking report generation
```

## Security

### 1. Secrets Management
- Never log secrets
- Use masked secrets
- Rotate keys regularly

```yaml
- name: Deploy
  env:
    API_KEY: ${{ secrets.API_KEY }}  # Masked in logs
  run: ./deploy.sh
```

### 2. Permissions
Use minimal permissions per job.

```yaml
permissions:
  contents: read        # Only read code
  pull-requests: write  # Only write PR comments
```

### 3. OIDC Authentication
Use OpenID Connect instead of static tokens.

```yaml
- name: Assume AWS Role
  uses: aws-actions/configure-aws-credentials@v2
  with:
    aws-region: us-east-1
    role-to-assume: ${{ secrets.AWS_ROLE }}
```

## Performance

### 1. Caching
Cache dependencies to speed up workflows.

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: '18'
    cache: 'npm'  # Automatically cache node_modules
    cache-dependency-path: 'package-lock.json'
```

### 2. Matrix Builds
Run multiple jobs in parallel.

```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: [16, 18, 20]
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
```

### 3. Docker BuildKit Cache
Use buildx for efficient Docker builds.

```yaml
- uses: docker/setup-buildx-action@v2
- uses: docker/build-push-action@v4
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

## Monitoring

### 1. Notifications
Send notifications on workflow completion.

```yaml
- name: Notify Slack
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
```

### 2. Annotations
Mark specific issues in logs.

```yaml
- name: Upload Test Results
  if: failure()
  run: |
    echo "::error::Test failed in module X"
    echo "::warning::Deprecated API usage detected"
```

### 3. Status Checks
Define required checks for branch protection.

GitHub Settings → Branches → Protection Rules → Require status checks:
- ✓ terraform-validate
- ✓ test-suite
- ✓ deploy-staging (for develop branch)

## Maintenance

### 1. Keep Actions Updated
Regularly update action versions.

```bash
# Check for updates
git log --oneline -20 .github/workflows/

# Update actions
dependabot auto-update
```

### 2. Review Logs
Check workflow logs for issues.

- GitHub Actions → [Workflow] → Recent runs
- Look for warnings and deprecations
- Optimize slow steps

### 3. Cost Management
Monitor GitHub Actions usage.

GitHub Settings → Billing → Actions:
- View monthly usage
- Set spending limits
- Optimize concurrent jobs

## Common Patterns

### Feature → Staging → Production

```yaml
# On develop branch
on:
  push:
    branches: [develop]

# Deploys to staging
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Deploy
        run: terraform apply -var-file=tfvars.staging
```

```yaml
# On main branch
on:
  push:
    branches: [main]

# Requires manual approval
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Deploy
        run: terraform apply -var-file=tfvars.production
```

### Scheduled Tasks

```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC

jobs:
  nightly-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Integration Tests
        run: npm run test:integration
```

### Workflow Dispatch (Manual Trigger)

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options:
          - staging
          - production
      action:
        type: choice
        options:
          - deploy
          - rollback

jobs:
  manual-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to ${{ inputs.environment }}
        run: echo "Deploying ${{ inputs.action }} to ${{ inputs.environment }}"
```

## Troubleshooting

### Workflow Won't Trigger
- Check branch name matches `on.branches`
- Verify file paths match `on.paths`
- Check if workflow file is on the right branch

### Job Timeout
- Increase timeout-minutes (max 360)
- Optimize slow steps
- Use caching

### Secret Not Available
- Verify secret is defined
- Check environment has secret access
- Check job permissions

### Docker Build Fails
- Check Dockerfile syntax
- Verify base image exists
- Check disk space in runner

---

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Events](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows)
- [Security Best Practices](https://docs.github.com/en/actions/security-guides)
