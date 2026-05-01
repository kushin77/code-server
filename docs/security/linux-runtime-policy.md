# Linux-Only Runtime Policy

**Issue:** #3154 - Fort-Knox Security Program: Secrets, Scanning, Layered Controls, Linux-Only Runtime
**Status:** Active policy reference
**Scope:** Runtime-owned repository artifacts only

## Purpose

The production runtime for this repository is Linux-only. Runtime-owned code and automation must not introduce PowerShell, batch, or Windows shell artifacts into the execution path.

This policy applies to:

- [scripts/](../../scripts/)
- [.github/workflows/](../../.github/workflows/)
- [terraform/](../../terraform/)
- [apps/](../../apps/)
- [config/](../../config/)
- root `docker-compose*.yml` files

Archived documentation, migration notes, and editor task files are not part of the runtime enforcement surface.

## Allowed Artifacts

- Bash shell scripts (`.sh`)
- Linux container images and Linux-first Compose definitions
- Terraform and workflow definitions that call Linux shell entry points
- Linux-compatible runtime configuration files

## Rejected Artifacts

- PowerShell scripts (`.ps1`)
- Batch files (`.bat`, `.cmd`)
- Runtime commands that invoke `pwsh`, `powershell.exe`, or `cmd.exe`
- Windows-specific bootstrap logic in runtime-owned code paths

## Enforcement

Runtime validation is performed by [scripts/security/linux-runtime-policy-validator.sh](../../scripts/security/linux-runtime-policy-validator.sh) and the [Linux Runtime Policy workflow](../../.github/workflows/linux-runtime-policy.yml).

The validator scans the active runtime surface and fails if it finds Windows-only artifacts. This keeps the runtime boundary aligned with the platform's Linux deployment model.

## Maintenance Notes

- Prefer Bash entry points for automation.
- Keep any Windows-specific references confined to archived documentation or editor-only tasks.
- If a Windows artifact is required for non-runtime reasons, document the exception in a tracked issue and keep it outside the runtime-owned paths.

---

**Last Updated:** May 1, 2026
**Owner:** Security / Platform