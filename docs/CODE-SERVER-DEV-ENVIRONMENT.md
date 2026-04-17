# Code-Server Development Environment - Admin Runbook

**Document**: Code-Server Enterprise Development Environment Setup
**Version**: 1.0.0
**Created**: April 17, 2026
**Owner**: Platform Team
**Status**: Active

---

## Overview

This document describes how code-server users get a complete development environment **without manual package installation**. All dependencies are **baked into the container image** at build time, ensuring:

- ✅ **Immutability**: Same image = same tools, every time
- ✅ **Idempotency**: Rebuild produces identical result
- ✅ **No User Friction**: Developers start with Python, Node, Go, Rust, etc. already installed
- ✅ **Audit Trail**: All package additions tracked in git
- ✅ **Admin Control**: Only admins can trigger package installations via IaC

---

## What's Already Installed

The custom `Dockerfile.code-server` includes:

### System Tools
- `git`, `curl`, `wget`, `openssh-client`, `tmux`, `screen`
- Docker CLI, kubectl, docker-compose
- `jq`, `yq`, `httpie` (API development)

### Interpreters & Runtimes
- **Python 3** (+ pip, virtualenv, poetry, pipenv)
- **Node.js 18** (+ npm, TypeScript, webpack, gulp, Jest, Vitest)
- **Go 1.21** (+ golangci-lint, goimports, dlv)
- **Rust** (+ rustfmt, clippy)
- **Ruby** and **Perl**

### Development Utilities
- `build-essential`, `cmake`, `autoconf`, `make`
- `gdb`, `valgrind`, `strace`, `ltrace` (debugging)
- `postgresql-client`, `redis-tools`, `sqlite3` (database clients)

### Python Packages (Pre-installed)
- `black`, `pylint`, `flake8`, `mypy`, `pytest`, `pre-commit`
- `ipython`, `jupyter`, `pandas`, `numpy`

### Node.js Global Packages
- `typescript`, `ts-node`, `eslint`, `prettier`
- `@angular/cli`, `webpack-cli`, `jest`, `vitest`

---

## For Code-Server Users

### Scenario 1: User Needs a Pre-Installed Tool

**Example**: Developer logs into code-server and opens terminal

```bash
# Python is already available
$ python3 --version
Python 3.10.12

$ pip3 install requests  # can install to user profile if needed

# Node.js is ready
$ node --version
v18.17.1

$ npm install -g create-react-app  # global npm packages work

# Go is ready
$ go version
go version go1.21.0

# Rust is ready
$ rustc --version
rustc 1.73.0

# Docker client is available (connects to host Docker daemon)
$ docker ps
```

✅ **No installation required** — user can immediately develop

---

### Scenario 2: User Needs a Tool NOT Pre-Installed

**Example**: Developer needs `gcc-arm` (ARM cross-compiler) or `postgres` server

**Step 1**: Open terminal in code-server and try the tool

```bash
$ arm-none-eabi-gcc
bash: arm-none-eabi-gcc: command not found
```

**Step 2**: Contact platform admin with request:

```
Subject: Request: Add arm-none-eabi-gcc to code-server dev environment

I need to develop ARM firmware. Please add:
- arm-none-eabi-gcc
- arm-none-eabi-gdb
- stm32cubemx (if available in apt)

Thanks!
```

**Step 3**: Admin processes the request (see next section)

---

## For Admins: Adding New Packages

### Prerequisites

- SSH access to 192.168.168.31
- Sudo/admin privileges in the container infrastructure
- Git commit access to kushin77/code-server

### Workflow

#### Option 1: Interactive Mode (Recommended for First-Time)

```bash
# SSH to production host
ssh akushnir@192.168.168.31

# Navigate to repo
cd code-server-enterprise

# Run interactive installer
sudo bash scripts/admin-dev-tools-add.sh
```

**Output**:
```
════════════════════════════════════════════════════════════════
🔧 DEVELOPMENT PACKAGE INSTALLER (Admin-Only)
════════════════════════════════════════════════════════════════

📦 Package name(s) [comma-separated]: arm-none-eabi-gcc,arm-none-eabi-gdb
📌 Version (leave blank for latest): 
🏷️  Category [system-utilities/interpreters/tools/other]: tools
🔍 Dry-run first? [y/n]: y

════════════════════════════════════════════════════════════════
📋 PACKAGE ADDITION SUMMARY
════════════════════════════════════════════════════════════════
Package(s): arm-none-eabi-gcc,arm-none-eabi-gdb
Version: latest
Category: tools
Mode: DRY-RUN
```

#### Option 2: Direct Command (For Scripts/Automation)

```bash
# Add single package
sudo bash scripts/admin-dev-tools-add.sh \
  --package arm-none-eabi-gcc \
  --version 12-2023.03 \
  --category tools

# Add multiple packages
sudo bash scripts/admin-dev-tools-add.sh \
  --package gcc-arm-linux-gnueabihf,g++-arm-linux-gnueabihf \
  --version 10-2020.09 \
  --category compilers

# Dry-run first to preview
sudo bash scripts/admin-dev-tools-add.sh \
  --package cargo \
  --version 1.73.0 \
  --dry-run
```

#### Option 3: Manual Edit + Rebuild

For complex additions (e.g., adding Rustup, NodeSource, custom repos):

```bash
# Edit Dockerfile directly
vim Dockerfile.code-server

# Preview Dockerfile changes
git diff Dockerfile.code-server

# Rebuild image
docker build -f Dockerfile.code-server -t code-server-enterprise:latest .

# Update docker-compose to reference new image
# (Usually automatic with build: section)

# Redeploy
docker-compose up -d code-server

# Verify
docker exec code-server which <package>
```

### What Happens During Installation

1. **Dockerfile Updated**: New package added to apt-get section with pinned version
2. **Image Rebuilt**: `docker build` runs, installing all packages (takes 5-15 min depending on package)
3. **docker-compose Updated**: Image tag updated (auto-timestamped)
4. **Git Commit**: Changes tracked with audit trail
5. **Container Redeployed**: Old container stopped, new one started with fresh image
6. **Health Check**: Automatic verification the new tool is available

### Verification

After deployment, verify the package is available to users:

```bash
# Check package exists in running container
docker exec code-server which <package>
# Output: /usr/bin/<package> or /usr/local/bin/<package>

# Or test directly
docker exec code-server <package> --version

# Example:
docker exec code-server gcc --version
docker exec code-server go version
docker exec code-server npm list -g typescript
```

---

## Design Principles

## Profile Durability Runbook

Profile state is designed to survive user logins, container recreation, and code-server version updates.

### Persistence Layout

- Home volume mount: `/home/coder`
- User profile: `/home/coder/.local/share/code-server/User`
- Extensions: `/home/coder/.local/share/code-server/extensions`
- Backup volume: `code-server-enterprise_code-server-profile-backups`
- Backup container: `code-server-profile-backup`

### Validate On Host

```bash
ssh akushnir@192.168.168.31
cd /home/akushnir/code-server-enterprise
docker-compose ps --format 'table {{.Names}}\t{{.Status}}' | egrep '^(code-server|code-server-profile-backup)\s'
docker exec code-server sh -lc 'ls -la /home/coder/.local/share/code-server/User | head -20'
docker run --rm -v code-server-enterprise_code-server-profile-backups:/b alpine:3.20 ls -la /b
```

### Restore Procedure

```bash
ssh akushnir@192.168.168.31
docker run --rm \
  -v code-server-enterprise_code-server-data:/target \
  -v code-server-enterprise_code-server-profile-backups:/backups \
  alpine:3.20 \
  sh -lc 'tar -xzf /backups/code-server-user-profile-YYYYMMDD-HHMMSS.tgz -C /target'

cd /home/akushnir/code-server-enterprise
docker-compose up -d --force-recreate code-server
```

### Notes

- Restore extracts the saved `User` subtree into the persisted home volume.
- Use the most recent backup artifact unless a point-in-time rollback is needed.
- Keep this runbook aligned with compose template changes in `docker-compose.tpl`.

### ✅ Immutability

All packages are installed during image build, not at runtime:
- ❌ WRONG: Users `apt-get install` in running container → lost on restart
- ✅ CORRECT: Admin adds to Dockerfile → rebuild → deployed to all users

### ✅ Idempotency

Rebuilding the image multiple times produces identical result:
- All versions explicitly pinned (no `latest`, no `*`)
- Same base image (`codercom/code-server:4.115.0`)
- Deterministic apt-get with specific version constraints

### ✅ Auditability

All changes tracked in git:
```bash
git log --oneline -- Dockerfile.code-server
# Output:
# abc1234 chore(container): add development packages: arm-none-eabi-gcc
# def5678 chore(container): add development packages: python3-dev
# ghi9012 feat(container): initial development environment setup
```

### ✅ Scalability

When changes are needed:
- **Scenario 1**: Single admin adds package (5 min)
- **Scenario 2**: 100 developers immediately have it on next redeploy
- **Scenario 3**: New node replicates identical image from registry

---

## Troubleshooting

### Problem: Package not found in apt repositories

**Cause**: Package is in a non-standard repository or has different name

**Solution**:

```bash
# Search for package variants
apt-cache search gcc | grep arm

# Add repository first, then package
# Edit Dockerfile to add repository before apt-get install

# Example for NodeSource:
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
```

### Problem: Package has native dependencies

**Cause**: Package requires build-essential or other system libraries

**Solution**:

```bash
# Ensure build-essential is listed (it already is in our Dockerfile)
# Add specific -dev packages if needed:

RUN apt-get install -y --no-install-recommends \
    package-name=X.Y.Z \
    package-name-dev=X.Y.Z \
    # ...
```

### Problem: Version conflicts between packages

**Cause**: Two packages require conflicting versions of a library

**Solution**:

```bash
# Use dry-run to test first
sudo bash scripts/admin-dev-tools-add.sh --package pkg1,pkg2 --dry-run

# If conflict appears, resolve manually in Dockerfile:
# - Option A: Choose different versions
# - Option B: Use virtual environments (Python venv, Node .nvm)
# - Option C: Install in non-standard location
```

### Problem: Container fails to start after adding package

**Cause**: Package installation failed, or broke existing dependencies

**Solution**:

```bash
# Check build logs
docker build -f Dockerfile.code-server . 2>&1 | tail -50

# Rollback to backup
cp Dockerfile.code-server.backup.YYYYMMDD-HHMMSS Dockerfile.code-server

# Re-run last known good deployment
docker-compose up -d code-server

# Investigate and fix Dockerfile issue
```

---

## Best Practices for Admins

### DO ✅

- **Pin versions explicitly**: `python3=3.10.12-1~20.04` (not `python3`)
- **Commit meaningful messages**: `chore(container): add Python dev tools (black, pytest)`
- **Test in dry-run first**: Before actual rebuild
- **Verify after deployment**: `docker exec code-server which <package>`
- **Update documentation**: Add new tools to this runbook under "What's Already Installed"
- **Batch related packages**: Add `arm-none-eabi-gcc`, `arm-none-eabi-gdb`, `arm-none-eabi-newlib` in one commit
- **Communicate to users**: Announce new tools in team channels

### DON'T ❌

- **Manually `apt-get install` in running container** → lost on restart
- **Use image tags like `latest`** → always use timestamps or versions
- **Leave unversioned packages** → breaks reproducibility
- **Forget to git commit** → loses audit trail
- **Skip health checks** → broken image gets deployed

---

## Common Package Requests & Additions

### Request: "I need Rust development"

```bash
# Already installed! Users have:
$ rustc --version
rustc 1.73.0

$ cargo --version
cargo 1.73.0

# If additional Rust tools needed:
sudo bash scripts/admin-dev-tools-add.sh \
  --package rustfmt,clippy,cargo-watch \
  --category rust-tools
```

### Request: "I need database servers (not just clients)"

```bash
# Client tools already available:
$ psql --version  # PostgreSQL client
$ mysql -V        # MySQL client
$ sqlite3 --version

# For full PostgreSQL/MySQL servers in the container:
sudo bash scripts/admin-dev-tools-add.sh \
  --package postgresql-15,postgresql-contrib-15 \
  --category database-servers

# Note: Better approach might be separate service containers in docker-compose
# See docker-compose.yml postgres service
```

### Request: "I need Java for development"

```bash
sudo bash scripts/admin-dev-tools-add.sh \
  --package openjdk-17-jdk,maven,gradle \
  --version 17.0.0~11-0ubuntu1 \
  --category java-runtime
```

---

## Monitoring & Maintenance

### Disk Usage

Container images grow with each new package. Monitor size:

```bash
# Check image size
docker images code-server-enterprise --format "{{.Repository}}:{{.Tag}} {{.Size}}"

# If >2GB, consider:
# - Removing unused tools
# - Splitting into separate specialized images
# - Using multi-stage builds
```

### Update Cycle

Keep packages current on a regular schedule:

```bash
# Monthly: Update all packages to latest patch versions
# (but keep major/minor versions pinned for stability)

# Quarterly: Consider major version upgrades for:
# - Python 3.10 → 3.11 (e.g.)
# - Node 18 → 20
# - Go 1.21 → 1.22
```

---

## Quick Reference

| Task | Command |
|------|---------|
| List all installed dev tools | `docker exec code-server apt list --installed \| grep -E 'python\|node\|go\|rust'` |
| Show all Python packages | `docker exec code-server pip list` |
| Show all global npm packages | `docker exec code-server npm list -g --depth=0` |
| Rebuild and redeploy | `docker-compose up -d --build code-server` |
| View Dockerfile changes | `git diff Dockerfile.code-server` |
| View container build history | `docker history code-server-enterprise:latest` |

---

## Related Documentation

- [Dockerfile.code-server](../Dockerfile.code-server) — The source of truth for image definition
- [docker-compose.yml](../docker-compose.yml) — How the image is deployed
- [DEVELOPMENT.md](../docs/DEVELOPMENT.md) — Developer quickstart guide
- [GOVERNANCE.md](../docs/GOVERNANCE.md) — IaC governance standards this follows

---

**Last Updated**: April 17, 2026
**Next Review**: July 17, 2026 (quarterly)
