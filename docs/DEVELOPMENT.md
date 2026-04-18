# Development Guide

Welcome to the code-server development environment! This guide covers everything you need to know to contribute effectively.

---

## Quick Start (5 minutes)

```bash
# Run onboarding script
bash onboard-dev.sh

# Navigate to repository
cd repos/code-server

# Start development server
make dev

# In browser: http://localhost:8080
```

---

## Development Environment

### Tools Installed
- **Docker** - Containerization & local services
- **kubectl** - Kubernetes cluster management
- **Dagger** - CI/CD pipeline framework
- **ArgoCD** - GitOps deployment tool
- **Node.js** - JavaScript runtime & package management
- **Python** - Scripting & data tools

### Directory Structure
```
repos/code-server/
├── apps/
│   ├── backend/       # Backend application
│   ├── frontend/      # React web UI
│   └── extensions/    # VS Code extensions
├── backend -> apps/backend       # Compatibility symlink during migration
├── frontend -> apps/frontend     # Compatibility symlink during migration
├── extensions -> apps/extensions # Compatibility symlink during migration
├── scripts/           # Automation scripts
├── services/          # Microservices
├── config/            # Configuration files
├── docs/              # Documentation
├── Makefile          # Build automation
├── docker-compose.yml # Local services
└── package.json      # Node.js dependencies
```

### Configuration Files
- `.env.development` - Local development settings (created by onboard-dev.sh)
- `.env.local` - Local overrides (not committed)
- `.gitconfig` - Git configuration
- `~/.kube/config` - Kubernetes access

---

## Building & Running

### Development Server
```bash
# Start development server (watch mode)
make dev

# Server runs on http://localhost:8080
# Hot reload enabled for frontend changes
```

### Build for Production
```bash
make build          # Build all components
make build-backend  # Build Go backend
make build-frontend # Build React UI
```

### Running Tests
```bash
make test           # Run all tests
make test-unit      # Unit tests only
make test-integration # Integration tests
make test-coverage   # Coverage report
```

### Code Quality
```bash
make lint           # Run linters
make format         # Auto-format code
make validate       # Run all validations
```

---

## Git Workflow

### Creating a Feature Branch
```bash
# Update main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/my-feature

# Make changes & commit
git add .
git commit -m "feat: description of feature"
```

### Pre-Commit Hooks
Pre-commit hooks automatically run before each commit:
- Lint checks
- Format validation
- Test validation
- Security scans

If pre-commit fails, fix issues and commit again.

### Creating a Pull Request
```bash
# Push your branch
git push origin feature/my-feature

# Go to GitHub and create PR
# Link related issues: Closes #123
# Ensure all CI checks pass
```

### Code Review
1. Keep PRs small (<500 lines)
2. Reference related issues
3. Respond to review comments
4. Re-request review after changes
5. Merge after approval

---

## Architecture Overview

### Lean Remote Developer Access (EPIC #189)

The system provides secure remote IDE access with zero SSH key exposure:

```
Developer's IDE Terminal
    ↓
Cloudflare Tunnel (secure encrypted tunnel)
    ↓
code-server Instance (home server)
    ├─ Read-only code viewing (Issue #187)
    ├─ Git operations via proxy (Issue #184)
    ├─ Audit logging (Issue #183)
    ├─ Latency optimization (Issue #182)
    └─ Developer provisioning (Issue #186)
```

### Components
- **Cloudflare Tunnel** (#185): Secure zero-IP ingress without exposed ports
- **Code-Server**: VS Code in browser, runs on home server
- **Git Proxy** (#184): Proxy for git ops (no SSH key to developer)
- **Read-Only Control** (#187): Prevent file downloads, limit to IDE
- **Audit Logging** (#183): Complete activity trail for compliance
- **Latency Optimization** (#182): Terminal acceleration & output batching
- **Developer Provisioning** (#186): One-command access grant/revoke

---

## Common Development Tasks

### Adding a Feature
```bash
# 1. Create branch
git checkout -b feature/my-feature

# 2. Make changes
# Edit files...

# 3. Test locally
make test
make lint

# 4. Commit
git add .
git commit -m "feat: description"

# 5. Push & create PR
git push origin feature/my-feature
# Go to GitHub to create PR
```

### Fixing a Bug
```bash
# 1. Reference issue
git checkout -b fix/#123-bug-description

# 2. Create test that reproduces bug
# Add test in appropriate test file...

# 3. Fix the bug
# Edit implementation...

# 4. Verify test passes
make test

# 5. Commit with issue reference
git commit -m "fix: #123 - description of fix"
git push origin fix/#123-bug-description
```

### Updating Documentation
```bash
# 1. Edit .md file
# e.g., docs/API.md

# 2. Preview locally
# Most markdown viewers support GitHub-flavored markdown

# 3. Commit
git add docs/
git commit -m "docs: update documentation"

# 4. PR automatically updates
```

### Running Services Locally
```bash
# Start all services (Docker Compose)
make compose-up

# View logs
make logs

# Stop services
make compose-down

# Restart services
make compose-restart
```

---

## Debugging

### Enable Debug Logging
```bash
# Set debug env var
export DEBUG=*

# Start development server
make dev

# Verbose logging for all modules
```

### VS Code Debugging
1. Open code-server (http://localhost:8080)
2. Open Debug panel (Ctrl+Shift+D)
3. Select configuration (e.g., "Node: Launch")
4. Set breakpoints and click Debug▶

### Docker Container Debugging
```bash
# View container logs
docker-compose logs -f service-name

# Execute command in container
docker-compose exec service-name bash

# Inspect container
docker-compose exec service-name env
docker-compose exec service-name ps aux
```

### Health Checks
```bash
# System health check
make health-check

# Individual service checks
make logs SERVICE=cloudflared
make logs SERVICE=git-proxy
make logs SERVICE=audit

# Test connectivity
curl -v http://localhost:8080
kubectl get pods
```

---

## Testing

### Running Tests
```bash
# Run all tests
make test

# Run specific test file
npm test -- src/tests/specific.test.ts

# Run with coverage
npm test -- --coverage

# Watch mode (re-run on changes)
npm test -- --watch
```

### Writing Tests
Place test files next to implementation:
```
src/
├── utils.ts
└── utils.test.ts    # Test file
```

Test example:
```typescript
describe('myFunction', () => {
  it('should do something', () => {
    const result = myFunction(input);
    expect(result).toBe(expected);
  });
});
```

### Test Coverage
```bash
# Generate coverage report
make test-coverage

# View HTML coverage report
open coverage/index.html
```

---

## Performance & Optimization

### Latency Optimization
The system includes several latency-reducing features:
- **Terminal Output Batching** (#182): Groups output frames to reduce WebSocket overhead
- **Edge Caching**: Cloudflare caching layer for static assets
- **Connection Pooling**: Reuse SSH/git connections
- **Compression**: gzip compression on responses

Monitor latency:
```bash
make latency-test
make latency-report
make latency-dashboard
```

### Memory Usage
Monitor memory:
```bash
# Check node process memory
ps aux | grep node

# Get heap snapshot
node --inspect=:9229 app.js

# Connect DevTools to inspect
chrome://inspect
```

---

## Troubleshooting

### Common Issues

**Port Already in Use (8080)**
```bash
# Find process using port
lsof -i :8080

# Kill process
kill -9 PID

# Or use different port
PORT=8081 make dev
```

**Docker Connection Refused**
```bash
# Ensure Docker daemon is running
docker ps

# Linux: start Docker service
sudo systemctl start docker

# Give user Docker permissions
sudo usermod -aG docker $USER
# Logout & login to apply
```

**kubectl: No context**
```bash
# Check if kubeconfig present
ls ~/.kube/config

# Add kubeconfig
export KUBECONFIG=/path/to/kubeconfig

# Verify context
kubectl config current-context
```

**Pre-commit Failures**
```bash
# Re-run hooks manually
pre-commit run --all-files

# Skip hooks (not recommended)
git commit --no-verify

# Update hook definitions
pre-commit autoupdate
```

---

## IDE Configuration

### VS Code Settings
Recommended extensions already installed:
- **ESLint** - JavaScript linting
- **Prettier** - Code formatter
- **Go** - Go language support
- **Docker** - Docker integration
- **Kubernetes** - K8s support
- **GitLens** - Git integration
- **Thunder Client** - API testing

Settings in `.vscode/settings.json`:
```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "eslint.validate": ["javascript", "typescript"]
}
```

---

## Contributing Guidelines

### Code Style
- **JavaScript/TypeScript**: Prettier formatting, ESLint rules
- **Go**: `gofmt` + `golint`
- **Bash**: ShellCheck validation
- **Markdown**: 80-character line limit

### Commit Messages
- Start with type: `feat:` `fix:` `docs:` `refactor:` `test:`
- Keep to 72 characters
- Reference issues: `Closes #123` or `Refs #123`

Example:
```
feat: implement latency optimization for terminal output

- Add output batching to reduce WebSocket frames
- Implement frame coalescing (50ms window)
- Reduce p99 latency by ~40%

Closes #182
```

### Review Process
1. Self-review your code first
2. Link related issues
3. Ensure CI passes
4. Respond to review feedback promptly
5. Merge after approval

---

## Resources

- [Architecture](docs/ARCHITECTURE.md)
- [API Documentation](../apps/frontend/API.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)

---

## Getting Help

- **Issues**: Use GitHub issues for bugs/feature requests
- **Discussions**: Use GitHub discussions for questions
- **Docs**: Check docs/TROUBLESHOOTING.md
- **Slack**: Ask team members (if applicable)

---

**Happy developing! 🚀**
