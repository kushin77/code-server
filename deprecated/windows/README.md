# DEPRECATED — Windows PowerShell Scripts

> **Status: DEPRECATED**  
> Windows is **not a supported deployment platform** for this project.  
> All tooling is Linux/bash-only. Do not add PowerShell scripts here or anywhere in the repo.

---

## Why Windows Support Was Removed

This project deploys to on-premises Linux hosts (`192.168.168.31` and `192.168.168.42`).
All deployment, validation, and operational tooling is bash-based and runs on Linux.

Windows-specific scripts caused:
1. **Deployment failures** — Docker daemon not available on Windows; `terraform apply` fails locally
2. **Platform confusion** — Engineers running PS1 scripts locally instead of deploying to the production host
3. **Security risk** — Windows credential storage patterns (APPDATA, credential manager) don't apply to Linux production
4. **Maintenance burden** — Dual-platform scripts become inconsistent over time

See `CONTRIBUTING.md#shell-script-standards` for the bash-only policy.

---

## Scripts Removed (History)

The following PowerShell scripts were referenced in early code reviews but were never committed to the
main codebase (they existed only in local development environments). They have been superseded by
bash equivalents:

| PowerShell Script (removed) | Bash Replacement |
|----------------------------|-----------------|
| `BRANCH_PROTECTION_SETUP.ps1` | `.github/workflows/enforce-priority-labels.yml` |
| `deploy-iac.ps1` | `scripts/deploy.sh` |
| `ci-merge-automation.ps1` | `.github/workflows/ci-validate.yml` |
| `admin-merge.ps1` | `gh pr merge` via CLI on production host |
| `Validate-ConfigSSoT.ps1` | `scripts/validate-env.sh` + `scripts/lib/global-quality-gate.sh` |

---

## Enforcement

- `CI: validate-linux-only.yml` blocks any new `.ps1` files outside this `deprecated/` directory
- Pre-commit hook in `.pre-commit-config.yaml` enforces no Windows paths in IaC files
- `CONTRIBUTING.md` documents the shell-script-only mandate

---

## Reference Issues

- Closes #398: Archive and deprecate remaining PowerShell scripts
- Related: #399 (CI enforcement: Linux-only validation)
- Related: #400 (Shell script standards + shellcheck)
