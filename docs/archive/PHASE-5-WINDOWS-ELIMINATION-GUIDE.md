# Phase 5: Windows Elimination - IMPLEMENTATION GUIDE

**Status**: 🚀 **QUEUED**  
**Duration**: 4 hours  
**Priority**: 🔴 P0 CRITICAL  
**Objective**: Remove all Windows dependencies, migrate to Linux-only deployment  

---

## 🎯 MISSION

Eliminate Windows as a deployment platform. All CI/CD, build systems, SSH tooling, and orchestration move to Linux. This reduces:
- Attack surface (one OS to maintain)
- Build complexity (no shell compatibility issues)
- License costs ($0 vs Windows licensing)
- Support burden

---

## 🔍 AUDIT: Windows Dependencies Identified

### Category 1: Development Tools (Windows)
**Currently On**: Developer machine (Windows)
**Action**: Already Linux-based (WSL2 / SSH to .31)
**Status**: ✅ OK - No action needed

### Category 2: SSH Keys & Auth
**Location**: `~/.ssh/akushnir-31` (Windows)
**Issue**: PowerShell SSH integration adds complexity
**Action**: Migrate to Linux SSH client (use WSL2 native openssh)

### Category 3: Build Pipeline (PowerShell Scripts)
**Location**: scripts/*.ps1 files (some may still exist)
**Issue**: PS1 scripts require PowerShell, not portable to Linux
**Action**: Convert all .ps1 → .sh (bash)

### Category 4: Terminal/Shell Execution
**Location**: PowerShell usage in CI/CD
**Issue**: GitHub Actions runners use bash, not PowerShell
**Action**: Ensure all scripts are bash-compatible

### Category 5: Documentation
**Location**: Windows-specific build instructions
**Action**: Update docs to Linux-only

---

## ✅ PHASE 5 IMPLEMENTATION STEPS

### Step 1: Audit Existing PowerShell Scripts (30 min)
**Goal**: Find all .ps1 files, assess conversion effort

```bash
# Find all PowerShell scripts
find . -name "*.ps1" -type f

# Check line count per file (effort estimate)
find . -name "*.ps1" -exec wc -l {} \; | sort -n

# Expected findings:
# - Validate-ConfigSSoT.ps1 (310 lines) → already have bash equivalent
# - validate-config-ssot.sh (200+ lines) ✅
```

### Step 2: Convert Remaining PowerShell Scripts to Bash (1 hour)
**Goal**: All executable scripts are bash (.sh)

#### 2.1 Validate-ConfigSSoT.ps1 → validate-config-ssot.sh
**Status**: ✅ Already have bash version  
**Action**: Delete .ps1, confirm .sh is used in CI/CD

```bash
# Verify bash version exists
ls -la scripts/validate-config-ssot.sh

# Delete PowerShell version
rm scripts/Validate-ConfigSSoT.ps1

# Verify it's referenced in CI/CD
grep "validate-config-ssot.sh" .github/workflows/*.yml
```

#### 2.2 Other Scripts
Check for any remaining platform-specific scripts:

```bash
# Find scripts with Windows-specific commands
grep -r "powershell\|cmd.exe\|Get-\|Set-\|Remove-Item" scripts/ *.md || echo "None found"

# Find scripts with Windows paths
grep -r "C:\\\|\\\\Program Files\\\|%USERPROFILE%" scripts/ *.md || echo "None found"

# Convert any remaining scripts
# Rule: All scripts use bash (#! /bin/bash)
```

### Step 3: Update GitHub Actions Workflows (1 hour)
**Goal**: All CI/CD uses bash, never PowerShell

#### 3.1 Check .github/workflows/*.yml
```bash
# Find any PowerShell references
grep -r "shell: powershell\|shell: pwsh" .github/workflows/

# If found, convert to bash:
# OLD:
#   shell: powershell
#   run: $env:VAR = "value"
#
# NEW:
#   shell: bash
#   run: export VAR="value"
```

#### 3.2 Update CI/CD Runners
**Ensure all workflows specify bash**:

```yaml
# .github/workflows/deploy.yml
name: Deploy Phase 4-8

on:
  push:
    branches: [main, feat/elite-*]

jobs:
  validate:
    runs-on: ubuntu-latest  # ← Linux runner (not windows-latest)
    steps:
      - uses: actions/checkout@v4
      
      # ALL steps use bash
      - name: Run validation
        shell: bash  # ← Explicitly set bash
        run: |
          bash scripts/validate-config-ssot.sh
          bash scripts/secrets-validation.sh
      
      - name: Terraform validate
        shell: bash
        run: terraform -chdir=terraform validate
```

### Step 4: Update SSH Client Configuration (30 min)
**Goal**: SSH client works on Linux without PowerShell complexity

#### 4.1 Create ~/.ssh/config (Linux)
```bash
# ~/.ssh/config
Host 192.168.168.31
  Hostname 192.168.168.31
  User akushnir
  IdentityFile ~/.ssh/akushnir-31-elite
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ServerAliveInterval 300
  ServerAliveCountMax 2
  ControlMaster auto
  ControlPath /tmp/ssh-%r@%h:%p
  ControlPersist 600
```

#### 4.2 SSH Key Permissions
```bash
# Ensure key has correct permissions (400 = read-only by owner)
chmod 400 ~/.ssh/akushnir-31-elite
chmod 644 ~/.ssh/akushnir-31-elite.pub

# Verify
ssh -i ~/.ssh/akushnir-31-elite akushnir@192.168.168.31 "uname -a"
```

### Step 5: Update Build & Deployment Scripts (1 hour)
**Goal**: All deployment scripts use bash, not PowerShell

#### 5.1 Create scripts/deploy.sh (bash only)
```bash
#!/bin/bash
# Deploy Phase 4-8 to production

set -e

DEPLOY_HOST="192.168.168.31"
DEPLOY_USER="akushnir"
DEPLOY_KEY="$HOME/.ssh/akushnir-31-elite"

echo "[*] Deploying Phase 4-8 to $DEPLOY_HOST..."

# Phase 4: Secrets Management
echo "[+] Phase 4: Setting up Vault..."
ssh -i "$DEPLOY_KEY" "$DEPLOY_USER@$DEPLOY_HOST" \
  'cd ~/code-server-enterprise && bash scripts/vault-setup.sh'

# Phase 5: Windows Elimination (this script!)
echo "[+] Phase 5: Linux-only migration..."
# Already executing

# Phase 6: Code Review
echo "[+] Phase 6: Code consolidation..."
# Orchestrated by GitHub Actions

# Phase 7: Branch Hygiene
echo "[+] Phase 7: Validating branches..."
bash scripts/branch-validate.sh

# Phase 8: Production Readiness
echo "[+] Phase 8: Final deployment checks..."
bash scripts/production-readiness.sh

echo "✅ Phases 4-8 deployment complete"
```

#### 5.2 Ensure All Shell Scripts Have Unix Line Endings
```bash
# Check for CRLF (Windows) line endings
find scripts/ -name "*.sh" -exec grep -l $'\r' {} \;

# If any found, convert to Unix (LF) line endings
find scripts/ -name "*.sh" -exec sed -i 's/\r$//' {} \;

# Verify
file scripts/*.sh | grep CRLF || echo "✅ All files have Unix line endings"
```

### Step 6: Update Documentation (30 min)
**Goal**: All build/deploy docs are Linux-only

#### 6.1 Update README.md
```markdown
# Build & Deployment

## Prerequisites (Linux)

- Linux shell (bash 4.0+)
- SSH client (`openssh-client`)
- Git 2.30+
- Terraform 1.0+
- Docker (optional for local testing)

## Build

```bash
bash scripts/build.sh
```

## Deploy

```bash
bash scripts/deploy.sh
```

## Troubleshooting

❌ **NOT SUPPORTED**: Windows/PowerShell
✅ **SUPPORTED**: Linux/macOS/WSL2

## Running on Windows

Use Windows Subsystem for Linux (WSL2):

```powershell
# PowerShell (Windows)
wsl bash scripts/deploy.sh
```
```

#### 6.2 Update CONTRIBUTING.md
```markdown
# Development Workflow

All scripts are bash-only. No PowerShell or Windows batch files.

### Shell Requirements

- `#!/bin/bash` header on all executable scripts
- Unix line endings (LF, not CRLF)
- POSIX-compliant commands only
- Shellcheck validation required

### Testing Scripts

```bash
# Validate bash syntax
bash -n scripts/script-name.sh

# Test with shellcheck
shellcheck scripts/script-name.sh
```
```

### Step 7: Add Shellcheck Validation to CI/CD (30 min)
**Goal**: Catch bash script errors before merge

#### 7.1 Add to .github/workflows/validate.yml
```yaml
- name: Validate bash scripts
  run: |
    sudo apt-get install -y shellcheck
    shellcheck scripts/*.sh
```

#### 7.2 Local pre-commit hook
```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Validating bash scripts..."
bash -n scripts/*.sh || exit 1
shellcheck scripts/*.sh || exit 1

echo "✅ Bash validation passed"
```

---

## 🗑️ CLEANUP: Remove Windows Artifacts

### Delete These Files
```bash
# PowerShell scripts
rm -f scripts/Validate-ConfigSSoT.ps1
rm -f scripts/*.ps1

# Windows batch files (if any)
rm -f scripts/*.bat
rm -f scripts/*.cmd

# Windows-specific configs
rm -f config/Windows-*
rm -f docs/*-Windows.md
```

### Git Cleanup
```bash
# Remove from git history (if in previous commits)
git filter-branch --tree-filter 'rm -f scripts/*.ps1 scripts/*.bat' -- --all
git push --force origin main

# Or cleaner approach: just add to .gitignore and remove from tracking
echo "*.ps1" >> .gitignore
echo "*.bat" >> .gitignore
git rm --cached scripts/*.ps1 2>/dev/null || true
git commit -m "refactor: Remove Windows PowerShell scripts"
```

---

## 🎯 PHASE 5 DELIVERABLES

### Completed
- [ ] All .ps1 files converted or deleted
- [ ] GitHub Actions use bash exclusively
- [ ] SSH client configured for Linux
- [ ] All scripts have Unix line endings
- [ ] Shellcheck validation added to CI/CD
- [ ] Documentation updated (Linux-only)
- [ ] Pre-commit hooks configured
- [ ] Git history cleaned (Windows artifacts removed)

### Verification Commands
```bash
# Check for Windows artifacts
find . -name "*.ps1" -o -name "*.bat" -o -name "*.cmd" | wc -l
# Should return: 0

# Validate all bash scripts
shellcheck scripts/*.sh
# Should return: No errors

# Check line endings
file scripts/*.sh | grep CRLF | wc -l
# Should return: 0

# Verify GitHub Actions workflows
grep -r "shell: powershell" .github/workflows/ | wc -l
# Should return: 0
```

### Success Criteria
- ✅ Zero PowerShell scripts in repository
- ✅ All CI/CD workflows use bash
- ✅ All scripts pass shellcheck validation
- ✅ Documentation is Linux-only
- ✅ SSH client works natively
- ✅ No CRLF line endings

---

## 📊 TIME ALLOCATION

| Task | Duration | Status |
|------|----------|--------|
| Audit PS1 scripts | 30 min | ⏳ Pending |
| Convert to bash | 1 hour | ⏳ Pending |
| Update CI/CD workflows | 1 hour | ⏳ Pending |
| SSH client config | 30 min | ⏳ Pending |
| Update docs | 30 min | ⏳ Pending |
| Add shellcheck validation | 30 min | ⏳ Pending |
| **Total Phase 5** | **4 hours** | 🚀 Ready |

---

**Next Phase**: Phase 6 - Code Review & Consolidation (8 hours)  
**Total Remaining**: Phases 4-8 = 26 hours  
**Target Completion**: April 18, 2026  

