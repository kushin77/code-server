# Supported Platforms

> **Linux (Ubuntu 22.04+) is the only supported deployment platform.**  
> **Windows is NOT supported as a deployment platform.**

---

## Production Deployment Platform

| Platform | Support | Notes |
|----------|---------|-------|
| **Ubuntu 22.04 LTS** | ✅ **Fully Supported** | Primary production OS |
| **Ubuntu 24.04 LTS** | ✅ Supported | Tested and validated |
| **Debian 12** | ⚠️ Best effort | Should work, not CI-tested |
| **Other Linux** | ⚠️ Best effort | Docker + bash required |
| **Windows** | ❌ **Not Supported** | No PowerShell, no Windows Docker |
| **macOS** | ⚠️ Dev only | Can run scripts locally, deploy via SSH |

---

## Deployment Requirements

### Required on Deployment Host

```bash
# Ubuntu 22.04+ requirements:
- Docker CE 24.0+
- docker-compose v2.20+
- bash 5.0+
- git 2.30+
- yq 4.30+ (for YAML parsing)
- age + sops (for secrets management)
- ssh client
```

### Development Machine Requirements

Development work can be done on **any OS** (Windows, macOS, Linux) using:
- SSH to `akushnir@192.168.168.31` (primary host)
- VS Code Remote SSH extension
- Git + any editor

**All execution happens on the Linux host via SSH.**  
The local machine is only used as an editor/terminal.

---

## Production Hosts

| Host | IP | OS | Role |
|------|----|----|------|
| Primary | `192.168.168.31` | Ubuntu 22.04 | All services |
| Replica | `192.168.168.42` | Ubuntu 22.04 | PostgreSQL replica, HAProxy |
| NAS | `192.168.168.56` | TrueNAS | Storage |

---

## CI/CD Platform

All CI/CD runs on **Linux**:
- GitHub Actions: `ubuntu-latest` runners only
- No `windows-latest` or `macos-latest` runners
- All workflow scripts use bash (`#!/bin/bash`)
- No PowerShell in CI workflows

---

## Shell Script Standards

All scripts MUST:
- Use `#!/bin/bash` shebang (not `/bin/sh`, not `/usr/bin/env bash`)
- Pass `shellcheck` with no warnings
- Work on Ubuntu 22.04+

No PowerShell scripts (`.ps1`) in active directories.

---

## What Happened to Windows Support

Windows deployment support was evaluated and removed in **Phase 5 (April 2026)**:

- **Decision**: Linux-only deployment reduces complexity and eliminates platform drift
- **Evidence**: All production infrastructure is bare-metal Linux (192.168.168.31/42)
- **Migration**: Windows-targeting scripts archived to `deprecated/windows/`
- **Developer impact**: None — development via VS Code Remote SSH works from any OS

---

## Contributing on Windows

If you are a developer using a Windows machine, you can still contribute:

1. Install VS Code + Remote SSH extension
2. SSH to `akushnir@192.168.168.31` 
3. Open VS Code with Remote SSH
4. Work directly on the Linux host — all tools are available there
5. **Do not run deployment scripts locally on Windows**

See [CONTRIBUTING.md](CONTRIBUTING.md) for full contribution guidelines.

---

**Document Owner**: Infrastructure Team  
**Last Updated**: April 2026  
**Status**: Authoritative — this document is the source of truth for platform requirements
