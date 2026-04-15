# ⛔ DEPRECATED — Windows Scripts Archive

> **These PowerShell scripts are deprecated.**  
> **Windows is NOT a supported deployment platform.**  
> **Use bash/Linux only. See [SUPPORTED-PLATFORMS.md](../../SUPPORTED-PLATFORMS.md)**

---

## Why These Exist

These scripts were created during an early phase of the project when Windows was
considered as a possible developer platform. That decision was reversed in Phase 5
(April 2026). All production deployment is Linux-only.

## Why Windows Was Removed

1. **Deployment target is Linux**: Production runs on Ubuntu 22.04 on bare metal
2. **Docker complexity**: Windows Docker engine behaves differently from Linux
3. **SSH simplicity**: All deployments are `ssh akushnir@192.168.168.31` commands
4. **CI/CD is bash-only**: GitHub Actions runs on ubuntu-latest, no Windows runners
5. **Bash-first tooling**: All scripts use bash features (arrays, process substitution, etc.)

## Files in This Directory

| File | Original Purpose | Status |
|------|-----------------|--------|
| `Validate-ConfigSSoT.ps1` | Phase 1 config validation | DEPRECATED — Replaced by `scripts/validate-config.sh` |

## Do Not Use These Scripts

Running these scripts will not work. They may:
- Reference Windows paths that don't exist in production
- Use PowerShell syntax incompatible with the Linux deployment target
- Produce incorrect validation results

## Equivalent Linux Commands

All PowerShell scripts have bash equivalents in `scripts/`:
- `Validate-ConfigSSoT.ps1` → `scripts/validate-config.sh`

## Contacts

Questions about Windows elimination? See `CONTRIBUTING.md` or open an issue.

---

**Last Updated**: April 2026  
**Decision**: Windows eliminated — Linux/bash only deployment  
**See**: [SUPPORTED-PLATFORMS.md](../../SUPPORTED-PLATFORMS.md) for current platform requirements
