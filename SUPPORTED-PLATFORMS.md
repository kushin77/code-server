# Supported Platforms

> **Linux (Ubuntu 22.04+) is the ONLY supported deployment platform.**
> **Windows is NOT a supported deployment platform. No exceptions.**

This is the authoritative, canonical platform requirements document.
All other documents referencing platform support are superseded by this file.

---

## Platform Support Matrix

| Platform | Deployment | Development | Notes |
|----------|-----------|-------------|-------|
| **Ubuntu 22.04 LTS** | ✅ **Fully Supported** | ✅ Supported | Primary production OS |
| **Ubuntu 24.04 LTS** | ✅ Supported | ✅ Supported | Tested and validated |
| **Debian 12** | ⚠️ Best-effort | ✅ Supported | Docker + bash required; not CI-tested |
| **Other Linux** | ⚠️ Best-effort | ✅ Supported | Docker CE + bash 5.0+ required |
| **macOS** | ❌ Not supported | ⚠️ Dev only | SSH to 192.168.168.31 for deployment |
| **Windows** | ❌ **NOT SUPPORTED** | ⚠️ WSL2 only | See WSL2 section below |
| **Windows native** | ❌ **BLOCKED** | ❌ **BLOCKED** | No PowerShell, no Windows Docker |

---

## Production Deployment Requirements

All production deployments run on:
- **Primary host**: `192.168.168.31` (Ubuntu 22.04 LTS)
- **Replica host**: `192.168.168.42` (Ubuntu 22.04 LTS)

### Required on Deployment Host

```bash
# Minimum requirements (Ubuntu 22.04+):
docker-ce 24.0+          # Container runtime
docker-compose v2.20+    # Orchestration
bash 5.0+                # Shell scripting
git 2.30+                # Version control
yq 4.30+                 # YAML processing
age 1.1.1+               # Encryption (for secrets)
sops 3.8.0+              # Secrets management
terraform 1.7+           # IaC
ssh-client               # Remote access
```

### Installation (Ubuntu 22.04)

```bash
# Docker CE
curl -fsSL https://get.docker.com | bash
systemctl enable --now docker

# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update && apt-get install -y terraform

# yq
wget https://github.com/mikefarah/yq/releases/download/v4.40.5/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# age + sops
apt-get install -y age
wget https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 -O /usr/local/bin/sops
chmod +x /usr/local/bin/sops
```

---

## Windows Users

**Windows is not a supported deployment platform.** However, Windows developers can:

### Option 1: SSH to Production Host (Recommended)

```bash
# All work happens on the Linux production host
ssh akushnir@192.168.168.31

# Development workflow
cd /home/akushnir/code-server-enterprise
# Edit files, run scripts, deploy — all on Linux
```

### Option 2: VS Code Remote SSH (Recommended for Development)

1. Install [VS Code](https://code.visualstudio.com/)
2. Install the "Remote - SSH" extension
3. Connect to `akushnir@192.168.168.31`
4. All editing and terminal work happens on the Linux host

### Option 3: WSL2 (Local Development Only)

WSL2 (Windows Subsystem for Linux) is acceptable **for local development only**, **not for production deployments**:

```bash
# WSL2 setup (Windows 11 / Windows 10 build 19041+)
wsl --install -d Ubuntu-22.04

# Then use Linux commands normally inside WSL2
# IMPORTANT: Deploy FROM WSL2 via SSH to production host, not from WSL2 directly
ssh akushnir@192.168.168.31
```

**WSL2 Limitations**:
- Docker in WSL2 has performance limitations
- VPN routing may not work correctly through WSL2
- Production deployments MUST run on native Linux hosts (192.168.168.31, .42)
- CI/CD always runs on Ubuntu (GitHub Actions `ubuntu-latest`)

### What Does NOT Work on Windows

```
❌ scripts/*.sh              # Bash scripts require Linux
❌ docker-compose.yml        # Linux Docker paths, volume mounts
❌ terraform apply           # Docker provider requires Linux Docker daemon
❌ Vault operations          # TLS paths are Linux-native
❌ scripts/vpn-enterprise-endpoint-scan.sh  # Requires VPN interface (wg0)
```

---

## CI/CD Platform Requirements

All CI/CD pipelines run on **Ubuntu** exclusively:

```yaml
# .github/workflows/*.yml — ALL workflows use ubuntu-latest
jobs:
  build:
    runs-on: ubuntu-latest  # ← This is the ONLY supported runner
```

No `windows-*` or `macos-*` GitHub Actions runners are used.

---

## Shell Script Standards

All scripts in this repository are **bash scripts** for Linux:

```bash
#!/bin/bash
# All scripts start with this exact shebang
# No #!/bin/sh, no #!/usr/bin/env bash, no PowerShell
```

**Script requirements**:
- `#!/bin/bash` shebang (enforced by `shell-lint.yml` CI)
- `set -euo pipefail` error handling
- shellcheck-clean (enforced by CI)
- Linux paths only (no `C:\`, `$env:`, `%APPDATA%`)

---

## FAQ

### "I'm a developer on Windows — how do I contribute?"

Use VS Code Remote SSH to connect to `192.168.168.31` and do all your work there. The host has code-server running — you can also access it via browser.

### "Can I run docker-compose locally on Windows?"

No. Docker volumes, networking, and file permissions behave differently on Windows. Use the production host instead.

### "Why isn't Windows supported?"

1. **Security**: Windows has a different security model — no SELinux, different iptables, different user namespaces
2. **Consistency**: All production infrastructure is Linux; dev/prod parity requires Linux
3. **Toolchain**: bash, yq, age, sops, and terraform all work natively on Linux
4. **Operations**: All runbooks, troubleshooting guides, and operational procedures assume Linux

### "What about PowerShell?"

PowerShell is not used in this project. All scripts are bash. If you find a PowerShell reference in active code (not in `deprecated/`), please open an issue.

---

## Enforcement

Platform requirements are enforced by:

| Mechanism | File | What It Checks |
|-----------|------|----------------|
| CI lint | `.github/workflows/validate-linux-only.yml` | Windows paths, .ps1 refs, windows-* runners |
| CI lint | `.github/workflows/shell-lint.yml` | `#!/bin/bash` shebangs, shellcheck |
| Pre-commit | `.pre-commit-config.yaml` | Windows paths in committed files |

PRs that violate platform requirements will **fail CI** and **block merge**.

---

## Historical Context

Prior to April 2026, some documentation referenced Windows paths (`C:\code-server-enterprise`) and a `scripts/redeploy.ps1` script. These were:

- Documentation artifacts from when development was done on Windows
- The actual deployment always ran on Linux
- All Windows references have been removed as of April 2026

If you encounter any Windows-specific references in active documentation (not in `deprecated/` or `archived/`), please file an issue.

---

## Related Documents

- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution guidelines (Linux-only)
- [DEVELOPMENT-GUIDE.md](DEVELOPMENT-GUIDE.md) — Developer setup
- [deprecated/windows/README.md](deprecated/windows/README.md) — Deprecated Windows scripts
- [.github/workflows/validate-linux-only.yml](.github/workflows/validate-linux-only.yml) — CI enforcement

---

**Last Updated**: April 2026  
**Authoritative Source**: This document  
**Supersedes**: All other platform requirements documents
