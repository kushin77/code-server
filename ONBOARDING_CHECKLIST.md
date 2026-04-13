# New Developer Onboarding Checklist

Use this checklist to track your onboarding progress. Check off each item as you complete it!

---

## 📋 Pre-Onboarding (Day 0)

- [ ] Receive GitHub access
- [ ] Receive SSH access to home server (192.168.168.31)
- [ ] Verify email in organization
- [ ] Set up SSH key for GitHub (if needed)

---

## ⚙️ Environment Setup (15-20 minutes)

### Run Automated Setup
- [ ] Clone code-server repository
- [ ] Run: `bash onboard-dev.sh`
- [ ] Verify all tools installed
- [ ] Verify kubeconfig configured
- [ ] Verify code-server starting

### Verify Tools
- [ ] `docker --version` works
- [ ] `kubectl config view` shows context
- [ ] `dagger version` works
- [ ] `argocd version` works
- [ ] `node --version` shows 18+
- [ ] `python3 --version` works

---

## 🔑 Authentication & Access (10 minutes)

### GitHub Access
- [ ] Can access GitHub organization repositories
- [ ] Can clone repositories via HTTPS or SSH
- [ ] Have write access to feature branches

### Kubernetes Access
- [ ] Can connect to cluster: `kubectl get nodes`
- [ ] Can view deployments: `kubectl get deployments -A`
- [ ] Can access cluster dashboard (if available)

### Code-Server Access
- [ ] Access code-server at http://localhost:8080
- [ ] Can edit files in editor
- [ ] Terminal access works in IDE
- [ ] Can view application logs

---

## 📖 Documentation (15-20 minutes)

### Read Foundation Docs
- [ ] Read [DEVELOPMENT.md](DEVELOPMENT.md) (this repo)
- [ ] Read [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design
- [ ] Read [API.md](frontend/API.md) - API reference
- [ ] Read [DEPLOYMENT.md](docs/DEPLOYMENT.md) - How we deploy
- [ ] Read [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues

### Understand Project
- [ ] Understand project structure (backend/frontend/services)
- [ ] Know where to find configuration files
- [ ] Know build process: `make build`
- [ ] Know test process: `make test`
- [ ] Know deployment process: `make deploy`

---

## 💻 Development Setup (10-15 minutes)

### Configure Git
- [ ] Git user configured: `git config user.name`
- [ ] Git email configured: `git config user.email`
- [ ] SSH key working (or HTTPS token)
- [ ] Pre-commit hooks installed

### Verify Build
- [ ] Running `make validate` succeeds
- [ ] Running `make build` succeeds
- [ ] Running `make test` succeeds (all passing)
- [ ] Running `make dev` starts server

### Create Feature Branch
- [ ] Created feature branch: `git checkout -b feature/test-branch`
- [ ] Made a test commit
- [ ] Pushed to origin

---

## 🔐 Security & Compliance (5 minutes)

### Understand Security
- [ ] Understand SSH key security (never exposed)
- [ ] Understand audit logging (all activity logged)
- [ ] Know how to report security issues
- [ ] Familiar with branch protection rules
- [ ] Know protected branches (main, master, develop)

### Environment Security
- [ ] No secrets in .env.development
- [ ] No API keys in code
- [ ] Using secure credential storage
- [ ] Pre-commit hooks validating security

---

## 👥 Team Onboarding (15 minutes)

### Meet the Team
- [ ] Have lead engineer contact info
- [ ] Know who to ask for help
- [ ] Have team Slack/Discord (if applicable)
- [ ] Understand team conventions

### Code Review
- [ ] Understand code review process
- [ ] Know how to request review
- [ ] Know how to respond to feedback
- [ ] Familiar with CI/CD process (GitHub Actions)

---

## ✅ First Contribution (30-60 minutes)

### Make First Change
- [ ] Identified a small task or bug to work on
- [ ] Created feature branch
- [ ] Made code changes
- [ ] Added tests for changes
- [ ] Running `make validate` succeeds
- [ ] Running `make test` succeeds

### Create First PR
- [ ] Committed changes with descriptive message
- [ ] Pushed to origin
- [ ] Created pull request on GitHub
- [ ] Linked related issues (if any)
- [ ] PR description explains changes
- [ ] All CI checks passed

### Review Process
- [ ] Requested review from team lead
- [ ] Responded to review feedback
- [ ] Made requested changes
- [ ] Re-requested review
- [ ] PR merged to main

---

## 🎯 Productive (by end of day 1)

By end of first day, you should:
- [ ] Have fully functional development environment
- [ ] Have made at least one successful commit
- [ ] Have created and merged a PR
- [ ] Be able to independently:
  - [ ] Build the project
  - [ ] Run tests
  - [ ] Make code changes
  - [ ] Create PRs
  - [ ] Review your own code
  - [ ] Fix simple bugs

---

## 📚 Optional: Go Deeper (Over time)

As you get more comfortable:

### Kubernetes
- [ ] Deploy to dev cluster
- [ ] View logs from deployed pods
- [ ] Scale deployments
- [ ] Understand networking policies

### CI/CD
- [ ] Understand GitHub Actions workflows
- [ ] Understand deployment process
- [ ] Monitor production systems
- [ ] Handle incident response

### Performance
- [ ] Run performance tests
- [ ] Profile application
- [ ] Optimize slow operations
- [ ] Monitor metrics

### Security
- [ ] Run security scans
- [ ] Review audit logs
- [ ] Test access controls
- [ ] Participate in security reviews

---

## 🎓 Learning Resources

### Articles & Guides
- [Lean Remote Developer Access System](docs/ARCHITECTURE.md) - Our architecture
- [Cloudflare Tunnel Guide](docs/CLOUDFLARE_TUNNEL_SETUP.md) - Secure access
- [Git Commit Proxy](docs/GIT_COMMIT_PROXY.md) - Git without SSH keys
- [Audit Logging](docs/AUDIT_LOGGING_INTEGRATION.md) - Compliance & security

### Commands Cheatsheet
```bash
# Build and test
make build && make test && make lint

# Development
make dev            # Start dev server (http://localhost:8080)
make logs           # View logs
make health-check   # System status

# Git workflow
git checkout -b feature/my-feature
git commit -m "feat: description"
git push origin feature/my-feature
# Create PR on GitHub

# Debugging
DEBUG=* make dev    # Verbose debugging
docker-compose logs -f  # Container logs
kubectl logs -f deployment/...  # K8s logs
```

---

## 🤝 Getting Help

If you get stuck:

1. **Check documentation** - Start with TROUBLESHOOTING.md
2. **Search GitHub issues** - Someone may have had the same problem
3. **Check logs** - Run `make logs` to see what's happening
4. **Ask the team** - Post in Slack or comment on issue
5. **Open an issue** - If it's a real bug/issue

---

## ✨ Success Criteria

You're successfully onboarded when you can:

- ✅ Start development environment in <5 minutes
- ✅ Understand basic project structure
- ✅ Build and test project locally
- ✅ Make code changes and create PR
- ✅ Understand security model (no SSH key exposure)
- ✅ Know how to get help when stuck
- ✅ Feel comfortable modifying code

---

**Welcome to the team! 🎉**

If anything in this checklist is unclear or broken, please open an issue or let the team know so we can improve the onboarding process.
