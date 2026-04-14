# Development Guide — Production-First Workflow

## Quick Start: 5-Minute Setup

```bash
# 1. Clone repository
git clone https://github.com/kushin77/code-server.git
cd code-server

# 2. Install development tools
pip install pre-commit pytest pytest-cov black pylint mypy bandit
npm install --save-dev eslint prettier

# 3. Setup pre-commit hooks (auto-validates every commit)
pre-commit install

# 4. Verify everything works
pre-commit run --all-files
pytest tests/ --cov=src/ --cov-fail-under=85
```

Done! You're ready to develop.

---

## Development Workflow (Step-by-Step)

### 1. Start Work on a Feature

```bash
# Create issue in GitHub (importance: set Priority label P0-P3)
# Issue #123: "Add user authentication with OIDC"

# Create local branch from main
git checkout main
git pull origin main
git checkout -b feat/user-oidc-auth
```

### 2. Write Code (Production-First Mindset)

Before writing ANY code, ask:

- Will this work at 1M RPS? (Design stateless/horizontal scaling)
- Will this survive 3x traffic? (Add load testing)
- Can we rollback in 60 seconds? (Feature flags/migrations)
- What breaks when this fails? (Design isolation + alerts)

**If NO to any question → Redesign first.**

Write code:
```bash
# Example: Add authentication service
src/services/auth/oidc_provider.py
src/tests/unit/test_oidc_provider.py
src/tests/integration/test_oidc_flow.py
src/tests/chaos/test_auth_failures.py
```

### 3. Test Everything (95%+ Coverage Required)

```bash
# Run unit tests
pytest tests/unit/ -v --cov=src/ --cov-fail-under=85

# Run integration tests (needs real DB)
pytest tests/integration/ -v

# Run chaos tests (failure scenarios)
pytest tests/chaos/ -v

# Run load tests (performance baseline)
locust -f tests/load/locustfile.py --headless -u 1000 -r 100 -t 5m

# Check coverage detail
coverage report --skip-empty
coverage html  # Open htmlcov/index.html
```

**No gaps = DO NOT PROCEED.**

### 4. Format & Lint Locally

```bash
# Format code
black src/ tests/

# Type check
mypy src/ --strict

# Security scan
bandit -r src/

# Run pre-commit hooks
pre-commit run --all-files

# Fix any issues found
# Then re-run pre-commit
```

### 5. Commit Your Work

```bash
git add .
pre-commit run --all-files  # Must pass
git commit -m "feat(auth): add OIDC authentication

- Implement OpenID Connect provider
- Add automatic token refresh
- Add distributed tracing
- Performance: p99 < 50ms

Fixes #123
Tests: 3 unit + 2 integration + 1 chaos
"
```

### 6. Push & Create Pull Request

```bash
git push origin feat/user-oidc-auth

# Create PR on GitHub with description:
# - Link to issue: Fixes #123
# - Summary of changes
# - Production deployment plan
# - Monitoring/alerts configured
# - Rollback strategy documented
```

### 7. Address Code Review

```bash
# Reviewer leaves comments
# You make changes
git add .
git commit -m "fix: address code review comments - security hardening"
git push origin feat/user-oidc-auth

# Reviewer approves with explicit statement:
# "This is production-ready"
```

### 8. Merge to Main

```bash
# GitHub merges PR (auto-triggered deployment)
# CI/CD pipeline:
# - All tests pass
# - Security scans pass
# - Container image builds + scanned
# - Canary deployment (1% traffic)
# - Automatic rollback if issues
# - Full rollout (100% traffic)
```

### 9. Monitor Post-Deployment

```bash
# You monitor for 1 hour after deployment
# - Check error rates (should be 0)
# - Check latency (should be baseline)
# - Check resource usage (normal)
# - Verify feature works end-to-end
# - Check that alerts fire correctly

# If problems found → Execute rollback immediately
git revert <commit-sha>
git push origin main  # Auto-redeploys
```

### 10. Close Issue

After production verification:
```bash
# Add deployment summary to issue
# Close issue with "Deployed to production 2026-04-14 10:30 UTC"
```

---

## Code Review Checklist (For Reviewers)

Ask yourself: **"Would Google/Meta/Amazon ship this AS-IS?"**

If NO → Reject with explanation.

### Architecture
- [ ] Stateless design (horizontal scaling possible)
- [ ] No single point of failure (everything redundant)
- [ ] Dependencies explicit and bounded
- [ ] Failure isolation designed (no cascades)

### Security
- [ ] Zero hardcoded secrets (scanned + verified)
- [ ] Zero default credentials
- [ ] Input validation comprehensive (all paths)
- [ ] Authentication/authorization correct
- [ ] Encryption in-flight + at-rest
- [ ] Audit logging for sensitive ops

### Performance
- [ ] No blocking operations in critical path
- [ ] No N+1 query patterns
- [ ] Resource limits defined
- [ ] Latency benchmarked on target HW
- [ ] Load tested (1x, 2x, 5x, 10x traffic)
- [ ] No memory leaks (validated via tests)

### Reliability
- [ ] Error handling comprehensive
- [ ] Timeouts set for external calls
- [ ] Retries with exponential backoff
- [ ] Circuit breakers where needed
- [ ] Graceful degradation designed

### Observability
- [ ] Logging: structured JSON + correlation IDs
- [ ] Metrics: Prometheus format for all operations
- [ ] Tracing: OpenTelemetry enabled
- [ ] Health endpoints: readiness + liveness
- [ ] Alerts: defined for failure scenarios
- [ ] Runbook: incident response documented

### Testing
- [ ] Coverage: 95%+ for business logic
- [ ] Unit tests: fast, isolated, deterministic
- [ ] Integration tests: real dependencies
- [ ] Chaos tests: failure scenarios
- [ ] Load tests: performance validated

### Documentation
- [ ] Code comments explain WHY not WHAT
- [ ] API docs: endpoints, schemas, examples
- [ ] Deployment guide: step-by-step + rollback
- [ ] Runbook: incident response procedures
- [ ] Architecture: decision recorded (ADR)

---

## Production Deployment Process

### Before Merge

✅ All tests passing (unit + integration + chaos + load)  
✅ All scans passing (lint + security + vulnerability + container)  
✅ Code review approval (explicit "production-ready" statement)  
✅ Monitoring configured (dashboards, alerts, runbooks)  
✅ Rollback tested (<60 second validation)

### Merge to Main Triggers

1. **Automated CI/CD Pipeline**
   ```
   GitHub Push → GitHub Actions
   ├─ Run all tests
   ├─ Run security scans
   ├─ Build container image
   ├─ Scan container image
   ├─ Push to registry
   └─ Trigger deployment
   ```

2. **Canary Deployment (1% traffic)**
   ```
   New version receives 1% of traffic
   Monitor for 5 minutes:
   - Error rate (should be normal)
   - Latency (should be baseline)
   - Resource usage (normal)
   If any anomaly → Auto-rollback
   ```

3. **Gradual Rollout**
   ```
   If canary healthy:
   1% → 10% (5 min soak)
   10% → 50% (5 min soak)
   50% → 100% (5 min soak)
   ```

4. **Post-Deploy Monitoring** (1 hour)
   ```
   Author monitors:
   - Error rate dashboard
   - Latency dashboard
   - Resource usage
   - Alert status
   
   If issue → Immediate rollback
   ```

### Manual Rollback

```bash
# If post-deploy issues found
git revert <commit-sha>
git push origin main
# CI/CD auto-deploys previous version (< 5 minutes)
```

---

## Local Development Environment

### Required Tools

```bash
# Python
pip install --upgrade pip
pip install pre-commit pytest pytest-cov pytest-asyncio
pip install black pylint mypy bandit
pip install -r requirements.txt

# JavaScript
npm install --save-dev eslint prettier @typescript-eslint/eslint-plugin
npm install -r package.json

# Infrastructure
brew install terraform checkov  # macOS
sudo apt-get install terraform checkov  # Ubuntu
```

### Environment Setup

```bash
# Copy template files
cp .env.example .env
cp terraform.tfvars.example terraform.tfvars

# Start local services (Docker Compose)
docker-compose -f docker-compose.yml up -d

# Run database migrations
python scripts/migrate_db.py

# Verify setup
./scripts/validate.sh
```

### IDE Configuration

**VS Code (Recommended)**

```json
// .vscode/settings.json
{
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.linting.mypyEnabled": true,
  "python.formatting.provider": "black",
  "[python]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "ms-python.python"
  },
  "[javascript][typescript]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
```

### Useful Make Targets

```bash
make test           # Run all tests
make coverage       # Generate coverage report
make lint           # Run linters
make format         # Auto-format all code
make security       # Run security scans
make local-deploy   # Deploy to local environment
make validate       # Validate all standards
```

---

## Troubleshooting

### Tests Failing

```bash
# 1. Run with verbose output
pytest tests/ -vv --tb=short

# 2. Check coverage gaps
coverage report --skip-empty | grep -v "100%"

# 3. Run specific failing test
pytest tests/test_specific.py::test_function -vv

# 4. Debug with pdb
pytest tests/ -vv -s --pdb
```

### Pre-Commit Hooks Failing

```bash
# 1. See what failed
pre-commit run --all-files

# 2. See detailed error
pre-commit run <hook-name> --all-files -v

# 3. For auto-fixable issues
pre-commit run --all-files --hook-stage manual

# 4. Bypass only if emergency (NOT RECOMMENDED)
git commit --no-verify  # ⚠️ Use sparingly
```

### Deployment Issues

```bash
# 1. Check pod status
kubectl get pods -n production

# 2. Check logs
kubectl logs -n production <pod-name> --tail 100

# 3. Check metrics
# Visit Prometheus: http://localhost:9090
# Visit Grafana: http://localhost:3000 (admin/admin)

# 4. Execute rollback
git revert <commit-sha>
git push origin main
```

---

## Learning Resources

- [PRODUCTION-STANDARDS.md](PRODUCTION-STANDARDS.md) - Standards guide
- [Architecture Decision Records](architecture/) - Design decisions
- [Runbooks](runbooks/) - Incident response
- [API Documentation](docs/api.md) - API reference
- [Deployment Guide](docs/deployment.md) - Step-by-step deployment

---

## Getting Help

- **Code Questions:** Create GitHub Discussion
- **Bug Reports:** Create GitHub Issue (add P0-P3 label)
- **Security Issues:** Email security@company.com (do NOT create public issue)
- **Architecture Questions:** Create GitHub Issue with `architecture` label

---

**Remember: Production-first is not optional. Everything you write goes live.**  
**Last Updated: April 14, 2026**
