# Standards

**Purpose**: Standards reference document.

---
title: Documentation Standards and Taxonomy
description: Canonical structure, frontmatter format, and CI enforcement for all repository documentation
owner: "@kushin77"
last_review_date: 2026-04-19
status: active
---

# Documentation Standards and Taxonomy

**Version**: 1.0  
**Effective Date**: April 19, 2026  
**Owner**: @kushin77  
**Status**: Active (enforced via CI)

---

## Table of Contents

1. [Canonical Taxonomy](#canonical-taxonomy)
2. [Frontmatter Format](#frontmatter-format)
3. [Document Types](#document-types)
4. [Cross-referencing Rules](#cross-referencing-rules)
5. [CI Enforcement](#ci-enforcement)
6. [Best Practices](#best-practices)
7. [Migration Guide](#migration-guide)

---

## Canonical Taxonomy

All documentation must be organized in the following canonical structure under `docs/`:

```
docs/
├── STANDARDS.md                    # THIS FILE - How to write docs
├── runbooks/
│   ├── operational/
│   │   ├── redeploy.md            # Full redeploy procedure
│   │   ├── rollback.md            # Rollback to last known-good
│   │   ├── failover-promote.md    # Promote replica to primary
│   │   └── [operational procedures]
│   └── incident-response/
│       ├── critical-outage.md     # P0 incident playbook
│       ├── data-loss.md           # Data loss recovery
│       └── [incident procedures]
├── architecture/
│   ├── infrastructure/
│   │   ├── deployment-model.md    # On-prem architecture
│   │   ├── networking.md          # Network topology
│   │   ├── storage.md             # NAS, volumes, persistence
│   │   └── [infrastructure docs]
│   └── application/
│       ├── service-topology.md    # Service graph
│       ├── data-model.md          # Database schema
│       └── [app architecture]
├── security/
│   ├── authentication.md          # OAuth2, OIDC, user identity
│   ├── authorization.md           # RBAC, access control
│   ├── secrets-management.md      # Vault, GSM, credential handling
│   ├── incident-response.md       # Security incident procedures
│   └── [security procedures]
├── operations/
│   ├── monitoring.md              # Prometheus, Grafana, alerts
│   ├── troubleshooting.md         # Common issues & solutions
│   ├── capacity-planning.md       # Resource requirements
│   └── [operational guidance]
├── development/
│   ├── setup.md                   # Dev environment setup
│   ├── contributing.md            # PR process, code standards
│   ├── testing.md                 # Test execution guide
│   └── [developer guidance]
├── status/
│   ├── production-status.md       # Current production state
│   ├── deployment-history.md      # Release timeline
│   └── [status reports]
└── archives/
    ├── deprecated/                # Deprecated docs (with pointers)
    └── legacy-analysis/           # Historical decision records
```

### Placement Rules

| Document Type | Location | Required | Notes |
|---|---|---|---|
| Operational runbooks (redeploy, failover, backup) | `docs/runbooks/operational/` | YES | Must have executable version in `scripts/ops/` |
| Incident response playbooks | `docs/runbooks/incident-response/` | YES | Time-critical; must be tested quarterly |
| Architecture decisions (ADR) | `docs/architecture/` | YES | Link to GitHub issue #<N> |
| Security procedures | `docs/security/` | YES | Must include audit trail & compliance refs |
| Monitoring/troubleshooting | `docs/operations/` | YES | Must link to service registry (#870) |
| Developer guides | `docs/development/` | YES | Must be tested in CI (e.g., setup guide) |
| Status reports/snapshots | `docs/status/` | NO | Regenerated automatically; don't commit |
| Deprecated content | `docs/archives/deprecated/` | YES (as pointer) | Archive with pointer to canonical version |
| Config examples | `config/` or `.env.template` | YES | Not in `docs/`; config is SSOT |

---

## Frontmatter Format

Every documentation file **must** begin with a YAML frontmatter block. Frontmatter enables:
- Automated validation (metadata enforcement)
- Stale document detection (based on last review)
- Ownership tracking (for updates and escalations)
- Status visibility (draft vs active)

### Frontmatter Template

```yaml
---
title: <Required - Human-readable title>
description: <Required - One-liner purpose>
owner: "@<github-username>"
last_review_date: YYYY-MM-DD  # ISO 8601 format required
status: <active|draft|archived>
related_issues: [#123, #456]   # GitHub issue references
version: <optional - document version>
deprecation_warning: <optional - if archived>
---
```

### Frontmatter Field Reference

| Field | Required | Format | Notes |
|-------|----------|--------|-------|
| `title` | YES | String (50-150 chars) | Appears in docs index and search results |
| `description` | YES | String (50-200 chars) | One-line purpose; used in taxonomy |
| `owner` | YES | @github-username | Single owner responsible for accuracy |
| `last_review_date` | YES | YYYY-MM-DD | Max 90 days old before marked stale |
| `status` | YES | active\|draft\|archived | Only `active` appears in index |
| `related_issues` | NO | [#123, #456] | Link actionable items to GitHub issues |
| `version` | NO | semver | Optional, e.g., "1.2.3" |
| `deprecation_warning` | ARCHIVED ONLY | String | Reason + pointer to replacement doc |

### Example Frontmatter (Runbook)

```yaml
---
title: Redeploy from Scratch
description: Full redeploy procedure from terraform apply through health verification
owner: "@kushin77"
last_review_date: 2026-04-19
status: active
related_issues: [#771, #882]  # Redeploy issue, machine-readable runbooks
version: 2.1
---
```

### Example Frontmatter (Archived/Deprecated)

```yaml
---
title: Deprecated GPU Upgrade Notes (Legacy)
description: DEPRECATED - See canonical version
owner: "@kushin77"
last_review_date: 2026-04-15
status: archived
deprecation_warning: "Replaced by docs/operations/gpu-upgrade-path.md (see that doc instead)"
---

> **⚠️ DEPRECATED**: This document is archived. Use docs/operations/gpu-upgrade-path.md instead.
```

---

## Document Types

### 1. Runbooks (Operational Procedures)

**Location**: `docs/runbooks/operational/` or `docs/runbooks/incident-response/`

**Purpose**: Step-by-step procedures for operations tasks and incident response

**Requirements**:
- Must have executable counterpart in `scripts/ops/<name>.sh` (#882)
- Frontmatter with owner and last review date
- Each step numbered and clear
- Pre-conditions and post-conditions explicitly stated
- Estimated duration for the procedure
- Rollback instructions if procedure fails

**Template**:
```markdown
---
title: Redeploy from Scratch
description: ...
owner: "@kushin77"
last_review_date: 2026-04-19
status: active
---

## Overview
[Detailed context and when to use this procedure]

## Pre-conditions
- [ ] All services backed up
- [ ] Change ticket created (#XXXX)
- [ ] Team notified in #ops-oncall

## Steps

1. **Stop application** (5 min)
   - Command: `docker compose down`
   - Verify: All containers stopped

2. **Backup current state** (10 min)
   ...

## Post-conditions
- [ ] All health checks pass
- [ ] Metrics show baseline traffic
- [ ] No errors in logs

## Rollback
If deployment fails at step 3:
[Rollback procedure]

## Related
- Executable: `scripts/ops/redeploy.sh --dry-run` (test before running)
- Issue: #771
- SLA: 30-minute RTO
```

### 2. Architecture Decision Records (ADRs)

**Location**: `docs/architecture/`

**Purpose**: Record important architectural decisions and trade-offs

**Requirements**:
- Frontmatter linking to decision issue (#XXX)
- Problem statement and constraints
- Options considered with pros/cons
- Selected option with justification
- Consequences and trade-offs
- Reference to any ADR this supersedes

**Template**:
```markdown
---
title: "ADR-006: Unified Identity with OAuth2 + OIDC"
description: Architectural decision to use OAuth2/OIDC for unified multi-tenant identity
owner: "@kushin77"
last_review_date: 2026-04-19
status: active
related_issues: [#388, #450]
version: 1.0
---

## Problem
[Clear statement of the architectural challenge]

## Constraints
- Must support X users concurrently
- Must integrate with existing Y system
- SLA requirement: Z

## Options Considered

### Option A: [approach]
Pros: X, Y, Z
Cons: A, B, C

### Option B: [approach]
Pros: X, Y, Z
Cons: A, B, C

## Decision
**Selected: Option A (OAuth2 + OIDC)**

Rationale: [Explain why this option best satisfies constraints]

## Consequences
- **Positive**: Easier user management, audit trail
- **Negative**: Requires external IdP (Keycloak/Okta)

## Related ADRs
- Supersedes: ADR-002 (SAML)
```

### 3. Troubleshooting Guides

**Location**: `docs/operations/troubleshooting.md`

**Purpose**: Common issues, symptoms, and solutions

**Template**:
```markdown
---
title: Troubleshooting Guide
description: Common issues, symptoms, diagnosis, and resolution
owner: "@kushin77"
last_review_date: 2026-04-19
status: active
---

## Issue: Service X Won't Start

**Symptoms**:
- Pod shows CrashLoopBackOff
- Logs: "Connection refused"

**Diagnosis**:
```bash
kubectl logs <pod> -f
docker compose logs service-x
```

**Resolution**:
1. Check connectivity: `curl -v http://dependency:port/health`
2. Restart: `docker compose restart service-x`
3. Verify: `curl http://service-x:port/health`

**Related Issues**: #123, #456
```

### 4. Configuration Documentation

**Location**: NOT `docs/` (config is SSOT, not documentation)

**Rules**:
- Authoritative config lives in: `.env.schema.json`, `terraform/variables.tf`, `docker-compose.yml`
- Use frontmatter in `.env.schema.json` comments
- Link to canonical config source in any prose docs

---

## Cross-referencing Rules

### Linking to GitHub Issues

Every actionable item in documentation must link to a GitHub issue:

```markdown
## Future Work
- [ ] Implement GPU acceleration ([Issue #895](https://github.com/kushin77/code-server/issues/895))
- [ ] Add read replicas ([Issue #896](https://github.com/kushin77/code-server/issues/896))
```

**NOT ALLOWED**:
```markdown
TODO: Implement GPU acceleration  # ❌ No issue link
FIXME: Add read replicas          # ❌ No issue link
```

### Linking Between Docs

Reference other docs by relative path with descriptive text:

```markdown
See Deployment Architecture for details.

Incident Response Procedures outline steps to follow.
```

**NOT**:
```markdown
See ../architecture/deployment.md  # ❌ No description
```

---

## CI Enforcement

The following CI checks run on every PR and main branch:

### 1. Broken Link Detection

**Script**: `scripts/ci/check-docs-broken-links.sh`

Scans all `docs/**/*.md` for:
- Internal links to non-existent files
- External URLs returning 4xx/5xx
- Malformed markdown links

**Enforcement**: 🚫 Fails PR if broken links detected

### 2. Frontmatter Validation

**Script**: `scripts/ci/check-docs-metadata.sh`

Validates every doc has:
- ✅ YAML frontmatter block
- ✅ Required fields: title, description, owner, last_review_date, status
- ✅ Valid YAML syntax
- ✅ last_review_date not older than 90 days (warning)
- ✅ owner is valid GitHub username

**Enforcement**: 🚫 Fails PR if metadata missing

### 3. Stale Document Detection

**Script**: `scripts/ci/check-docs-staleness.sh`

Identifies docs with `last_review_date` > 90 days old:

**Enforcement**: ⚠️ Creates issue listing stale docs (not blocking)

### 4. Duplicate Detection

**Script**: `scripts/ci/check-docs-duplicates.sh`

Finds:
- Docs with identical content (different files)
- Docs that reference each other (should be one)
- Archive pointers to missing canonical versions

**Enforcement**: 📋 Reports in artifacts; escalates to owners for consolidation

### 5. Issue Cross-Reference Validation

**Script**: `scripts/ci/check-docs-issue-links.sh`

For docs with `related_issues: [#123, ...]`:
- Verifies issues exist
- Verifies they're not closed (unless explicitly intended)
- Warns if issue status doesn't match doc status

**Enforcement**: ⚠️ Warnings on PR comments

---

## CI Workflow

**File**: `.github/workflows/docs-standards-enforcement.yml`

Runs on:
- Every PR touching `docs/**`
- Every merge to `main` (to catch issues)
- Weekly scheduled check (Monday 2 AM UTC)

Jobs:
1. `check-frontmatter` — Validates metadata on all docs
2. `check-broken-links` — Scans for dead links
3. `check-staleness` — Identifies docs > 90 days old
4. `check-duplicates` — Finds duplicate/consolidated content
5. `check-cross-refs` — Validates issue links in docs

Reports:
- PR comment with summary
- GitHub Artifacts with detailed reports
- Automated issues for staleness/duplicates (assigned to doc owner)

---

## Best Practices

### DO ✅

- ✅ Write in plain English, second person (e.g., "You must...")
- ✅ Use code blocks with syntax highlighting
- ✅ Include examples and real commands
- ✅ Break long docs into sections with table of contents
- ✅ Add diagrams for architecture (ASCII or images in `docs/assets/`)
- ✅ Update `last_review_date` every 90 days (set calendar reminder)
- ✅ Link to related GitHub issues in `related_issues: [#...]`
- ✅ Include estimated time for runbook procedures
- ✅ Document assumptions and pre-conditions

### DON'T ❌

- ❌ Hardcode IPs or domain names (use env vars in examples)
- ❌ Leave TODOs without issue links
- ❌ Duplicate content across docs (use pointers instead)
- ❌ Document past decisions without linking to issues
- ❌ Write passive voice when active is clearer
- ❌ Forget to update docs after code changes
- ❌ Leave stale docs without marking them `archived`

---

## Migration Guide

### For Existing Docs

**Phase 1** (This PR):
1. Add frontmatter to all `docs/**/*.md` files
2. Verify no broken internal links
3. Enable CI enforcement workflow

**Phase 2** (Next sprint):
1. Assign owners to stale docs (via automated issues)
2. Consolidate duplicates
3. Archive docs that are no longer active

### For Contributors

When creating a new doc:
1. Choose appropriate location from taxonomy
2. Create file with frontmatter block
3. Write content following best practices
4. PR will run all CI checks; fix any failures
5. After merge, set `last_review_date` reminder in calendar (90 days)

### Converting Prose Runbooks to Executable

If a runbook exists in `docs/runbooks/operational/`:

1. Create executable version in `scripts/ops/<name>.sh` (#882)
2. Update prose doc frontmatter: `related_issues: [#XXX]` → include both runbook issue AND #882 (machine-readable runbooks)
3. Add note at top of prose doc: "Executable version: `scripts/ops/<name>.sh`"
4. CI will link them automatically via related issues

---

## Template Examples

See `docs/` directory for:
- `RUNBOOK-TEMPLATE.md` — Operational procedure template
- `ADR-TEMPLATE.md` — Architecture decision record template
- `TROUBLESHOOTING-TEMPLATE.md` — Issue diagnosis template

Copy and customize for your doc.

---

## Related Issues

- **#894** — Documentation standardization program (this)
- **#870** — Service registry SSOT (referenced for service docs)
- **#882** — Machine-readable runbooks (executable counterparts)
- **#866** — Phase 2 Deep Engineering (parent epic)

---

**Document Version**: 1.0  
**Last Updated**: April 19, 2026  
**Owner**: @kushin77  
**Status**: Active (enforced via CI)
