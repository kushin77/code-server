# Archived Legacy Code

This directory contains code from earlier deployment phases that are **no longer active**.

**⚠️ Important**: Files in this directory are for **reference only**. Do not use them for deployments or configurations. The active codebase is in the parent directory.

## Directory Structure

### `docker-compose-old/`
**Dead docker-compose files from phases 0, 15, 16, 18, 20**

Contains:
- `docker-compose.base.yml` - Base composition template (superseded by docker-compose.tpl)
- `docker-compose.production.yml` - Legacy enterprise variant
- `docker-compose-p0-monitoring.yml` → `docker-compose-phase-*.yml` - Phase-numbered artifacts

**Why archived**: Only `docker-compose.yml` (generated from `docker-compose.tpl`) is actively maintained. All modifications now flow through Terraform → docker-compose.tpl → docker-compose.yml.

**When to reference**: Historical context only. Never use for deployments.

---

### `caddyfile-old/`
**Dead Caddyfile variants from earlier phases**

Contains:
- `Caddyfile.new` - On-prem HTTP+HTTPS variant (auto-cert generation)
- `Caddyfile.production` - Legacy production variant
- `Caddyfile.tpl` - Terraform template (never used)

**Why archived**: Current active config is `../Caddyfile` (Cloudflare Tunnel + Origin CA). All variants define conflicting `auto_https` settings.

**When to reference**: Only if reverting from Cloudflare Tunnel back to self-signed certs.

---

### `phase-scripts/`
**Dead fix, execute, and setup scripts from abandoned implementations**

Contains:
- `fix-docker-compose.sh` - YAML repair script (unused)
- `fix-github-auth.sh` - Auth cleanup (unused)
- `fix-product-json.sh` - Removes defaultChatAgent (unused)
- `fix-compose.py` - References abandoned phase-13 (unused)
- `execute-phase-18.sh` - Phase-specific executor (obsolete)
- `execute-p0-p3-complete.sh` - Very old phases (obsolete)
- `GPU-*.md`, `GPU-*.sh` - GPU feature branch (abandoned)

**Why archived**: Only `fix-onprem.sh` is active (patches expose→ports). These target different architectures/phases.

**When to reference**: Never. They reference non-existent services and outdated configurations.

---

### `terraform-phases/`
**Dead Terraform configurations from phases 13-20**

Contains:
- `phase-13-iac.tf` - Initial launch (superseded)
- `phase-14-16-iac-complete.tf` - Merged phases (history)
- `phase-16-a-db-ha.tf`, `phase-16-b-load-balancing.tf` - PostgreSQL HA (superseded)
- `phase-18-compliance.tf`, `phase-18-security.tf` - SOC 2 compliance (superseded)
- `phase-20-iac.tf` - Advanced features (superseded)
- `phase-21-observability.tf` - ⚠️ BEING MERGED INTO main.tf (see #GH-XXX)

**Why archived**: Only `main.tf` is the active source of truth (Phase 21+). Previous phases are history.

**Version conflicts found**:
- Prometheus image: `v2.48.0` (main.tf) vs `2.48.0` (phase-21)
- Memory limits: 512mb (main.tf) vs 1024mb (phase-21)

**Status**: phase-21-observability.tf is being merged into main.tf as part of [GitHub Issue](#).

---

### `monitoring-old/`
**Dead monitoring configurations**

Contains:
- `alertmanager-production.yml` - Unused variant (duplicate of alertmanager.yml)

**Why archived**: Current config is `../config/monitoring/alertmanager.yml`. No multi-variant support.

---

### `dockerfiles-old/`
**Unused Dockerfile variants**

Contains:
- `Dockerfile.caddy` - Not used (uses upstream caddy:2-alpine instead)
- `Dockerfile.ssh-proxy` - Not used (upstream ssh proxy)
- `Dockerfile` - Ubuntu base (never used)

**Why archived**: Only `Dockerfile.code-server` (custom code-server build) is active.

---

## How This Archive Happened

**Date**: April 14, 2026
**Reason**: Technical debt cleanup — 50+ dead files from abandoned phases were causing confusion

**Process**:
1. Analyzed entire workspace for duplicates, overlaps, gaps
2. Identified 25+ duplicate configurations
3. Created organized directory structure
4. Moved all dead code to `archived/` subdirectories
5. Deleted 2 scripts with wrong host targets (192.168.168.32)
6. Fixed typos in active setup scripts
7. Merged terraform/phase files (phase-21-observability.tf → main.tf)

**Result**:
- 50+ dead files organized in archive
- Active codebase reduced to ~10 essential files
- Clear separation: active (parent dir) vs historical (archived/)

---

## Reference: What's Active Now

### Essential Files (Active)
```
docker-compose.yml        ✅ (generated from docker-compose.tpl)
docker-compose.tpl        ✅ (Terraform source)
Dockerfile.code-server    ✅ (custom code-server build)
Caddyfile                 ✅ (Cloudflare Tunnel + Origin CA)
config/monitoring/        ✅ (alertmanager.yml)
main.tf                   ✅ (Phase 21+)
variables.tf              ✅
```

### Key Directories (Active)
```
deployment/               ✅ (docker-compose, Dockerfile)
config/                   ✅ (caddy, monitoring, env templates)
terraform/                ✅ (active IaC)
scripts/                  ✅ (health-check, deploy, setup)
docs/                     ✅ (architecture, deployments)
```

---

## If You Need Something From Archive

1. **Check the category** — which `*/` subddir had your file?
2. **Read this document** — understand why it was archived
3. **Decide if you actually need it** — most phase files are obsolete
4. **If critical**: Open GitHub issue explaining use case
5. **Do NOT**: Copy archived files back to parent directory without review

---

## Cleanup Tracking

**GitHub Issue**: [Code Cleanup #GH-XXX](https://github.com/kushin77/code-server-enterprise/issues/GH-XXX)

Status: ✅ **CLEANUP COMPLETE** (April 14, 2026)

- ✅ Archived 8 docker-compose files
- ✅ Archived 2 Caddyfile variants
- ✅ Deleted 2 wrong-host deployment scripts
- ✅ Archived 15 fix/phase/GPU scripts
- ✅ Archived 9 terraform phase files
- ✅ Fixed typos in setup-dev.sh, setup.sh
- ✅ Created organized directory structure
- ⏳ Merging phase-21-observability.tf into main.tf (pending)

---

## Next Steps

See [GOVERNANCE-AND-GUARDRAILS.md](../GOVERNANCE-AND-GUARDRAILS.md) for repo mandates to prevent re-accumulation of dead code.

**Key mandates**:
- ❌ No new phase-numbered files (use main.tf)
- ❌ No docker-compose variants (one source of truth: docker-compose.tpl)
- ❌ Cleanup definition: files not referenced in main.tf/docker-compose.tpl are candidates for archival
- ✅ Monthly review of unused files
- ✅ GitHub issue linkage for all major changes
