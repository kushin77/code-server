# Deduplication-as-Policy Framework

**Policy Version**: 1.0 (April 17, 2026)  
**Owner**: Enterprise Infrastructure  
**Status**: ACTIVE - Enforced in CI

---

## Overview

This document establishes the canonical registry of reusable helpers and enforces deduplication controls across shell scripts, Terraform configurations, docker-compose files, and IDE policies.

The goal: Make duplication hard to introduce by establishing:
1. **Canonical helper registry** — single source of truth for each capability
2. **CI/CD detection gates** — automated discovery of duplicate patterns
3. **IDE integration** — hints and quick-fixes for preferred shared libraries
4. **Governance waivers** — documented exceptions with audit trail

---

## Canonical Helper Registry

### Shell Script Helpers

| Helper Name | File | Purpose | Usage | Non-Example |
|---|---|---|---|---|
| `log_info` | `scripts/_common/logging.sh` | Standard info-level logging | `log_info "service started"` | ❌ `echo "INFO: ..."` |
| `log_error` | `scripts/_common/logging.sh` | Standard error-level logging | `log_error "failed"` | ❌ `echo "ERROR: ..."` |
| `log_fatal` | `scripts/_common/logging.sh` | Fatal error + exit | `log_fatal "cannot continue"` | ❌ `echo "FATAL:"; exit 1` |
| `log_debug` | `scripts/_common/logging.sh` | Debug-level logging (conditional) | `log_debug "var=$var"` | ❌ Custom debug output |
| `log_warn` | `scripts/_common/logging.sh` | Warning-level logging | `log_warn "deprecated"` | ❌ `echo "WARN: ..."` |
| `require_var` | `scripts/_common/utils.sh` | Validate variable is set | `require_var "DOMAIN"` | ❌ `[ -z "$DOMAIN" ] && die` |
| `require_command` | `scripts/_common/utils.sh` | Validate command in PATH | `require_command docker` | ❌ `which docker > /dev/null` |
| `require_file` | `scripts/_common/utils.sh` | Validate file exists | `require_file /etc/config` | ❌ `[ ! -f /etc/config ] && die` |
| `die` | `scripts/_common/utils.sh` | Fatal error with cleanup | `die "message"` | ❌ `exit 1` directly |
| `retry` | `scripts/_common/utils.sh` | Retry logic with backoff | `retry 5 docker pull image` | ❌ Manual retry loops |
| `load_env` | `scripts/_common/config.sh` | Load .env file | `load_env .env` | ❌ `source .env` directly |
| `export_vars` | `scripts/_common/config.sh` | Export to subshell | `export_vars VAR1 VAR2` | ❌ Manual export statements |
| `get_secret` | `scripts/lib/secrets.sh` | Fetch secret from GSM or .env | `get_secret "db-password"` | ❌ Hardcoded secrets |
| `mount_nas` | `scripts/lib/nas.sh` | Mount NAS volume | `mount_nas 192.168.1.10 /data` | ❌ Direct NFS mount |

### Terraform Patterns

| Pattern | Module | Purpose | Location | Non-Example |
|---|---|---|---|---|
| Docker provider | `modules/core/main.tf` | Remote Docker execution | Use for container management | ❌ Local docker provider |
| Data source queries | `modules/data/main.tf` | PostgreSQL schema checks | Idempotent migrations | ❌ Hardcoded resource IDs |
| Variable validation | `variables.tf` | Runtime input checks | All variable files | ❌ `locals { validated = ... }` |

### Docker Compose Patterns

| Pattern | File | Purpose | Example | Non-Example |
|---|---|---|---|---|
| Environment template | `.env.template` | Set defaults | `DOMAIN=192.168.168.31.nip.io` | ❌ Hardcoded in compose |
| Port parameterization | `docker-compose.yml` | Use env vars | `${SERVICE_PORT:-8080}` | ❌ `ports: "8080:8080"` |
| Health checks | Service definition | Liveness probes | `healthcheck: { test: [...] }` | ❌ No health check |

### IDE Configuration Patterns

| Pattern | File | Purpose | Location | Non-Example |
|---|---|---|---|---|
| Git credential helper | `code-server-entrypoint.sh` | GSM integration | Automatic at startup | ❌ Manual credential entry |
| Default workspace settings | `default-settings.json` | Enterprise defaults | Merged at startup | ❌ Per-user modification |

---

## Lookup Order: "Where Should I Put This?"

When writing a new helper or configuration:

1. **Check `scripts/_common/`** — Canonical location for fundamental utilities
   - Logging: `logging.sh`
   - Config: `config.sh`
   - Initialization: `init.sh`
   - Basic utilities: `utils.sh`

2. **Check `scripts/lib/`** — Domain-specific helpers
   - Secrets: `secrets.sh`
   - NAS: `nas.sh`
   - OPA/security: `opa-validator.sh`
   - Deployment: `deploy-utils.sh`

3. **Check existing service utilities** — Feature-specific scripts
   - OIDC configuration
   - Kubernetes helpers
   - Monitoring setup

4. **If not found, discuss with team** — New capability requires:
   - RFC documenting why it doesn't fit existing locations
   - Placement decision (new file in `_common` or `lib`?)
   - Add to this registry

**NEVER** create a new helper if it exists elsewhere — refactor into shared library instead.

---

## CI/CD Detection Gates

### Duplicate Helper Detection (`detect-duplicate-helpers.sh`)

Scans all shell scripts for:
- Function signatures with identical logic (high confidence)
- Duplicate logging patterns (`echo "ERROR:"` instead of `log_error`)
- Duplicate error handling patterns
- Re-implemented utilities that exist in `_common`

**Trigger**: On every PR  
**Failure criteria**: High-confidence duplicate found without documented waiver  
**Output**: List of duplicate locations + suggested canonical reference

### Duplicate Compose Key Detection (`detect-duplicate-compose-keys.sh`)

Scans `docker-compose*.yml` for:
- Repeated environment blocks that should be templated
- Duplicate service fragments (e.g., same health checks)
- Hardcoded values that should use env vars

**Trigger**: On every PR with compose changes  
**Failure criteria**: High-confidence duplicate found  
**Output**: Consolidation suggestions

### Dedup Score Report (`dedup-score-report.sh`)

Calculates PR deduplication score:
- **100**: No duplicates, all patterns use canonical helpers
- **80-99**: Minor overlap detected (warnings only)
- **60-79**: Moderate overlap (requires review)
- **<60**: Significant duplication (blocks merge without waiver)

**Output format**:
```
DEDUP_SCORE=87
DUPLICATE_COUNT=2
SUGGESTED_REFACTORINGS="log wrapper in deploy.sh; retry logic in health-check.sh"
WAIVER_ISSUE=""
```

---

## Waiver Process

When you MUST violate deduplication (rare):

1. **Create issue** with label `dedup-waiver-request`
   - **Title**: "Waiver: [reason] — [location]"
   - **Body**: Explain why canonical helper won't work
   - **Example**: "Waiver: Retry logic in air-gapped environment — network unavailable in this context"

2. **Link PR to issue** in commit message:
   - `Waiver-Issue: #NNN`

3. **Owner approval** — infrastructure owner must approve
   - Comment: `Approved for 30 days: [reason]`
   - Sets expiration date

4. **Audit trail** — All waivers tracked in `WAIVER-AUDIT.md`

---

## Enforcement Rules

### Branch Protection Policy

| Rule | Enforced In | Action |
|---|---|---|
| No duplicates of `log_*` | `deduplication-guard.yml` CI job | FAIL merge |
| No reimplementation of `require_*` | `deduplication-guard.yml` CI job | FAIL merge |
| No duplicate retry logic | `deduplication-guard.yml` CI job | FAIL merge |
| Compose keys consolidated | `detect-duplicate-compose-keys.sh` | WARN (advisory) |
| Dedup score >= 70 | `dedup-score-report.sh` | FAIL merge if < 60 |

**Exception**: Temporary waivers with owner approval + expiration date

---

## IDE Integration

### VS Code Hints (`config/code-server/DEDUP-HINTS.json`)

```json
{
  "patterns": {
    "logging": {
      "intent": "output a message",
      "canonical": "scripts/_common/logging.sh:log_info|log_error|log_warn",
      "avoid": ["echo", "printf", "custom log wrapper"],
      "example": "log_info \"Service started on port $PORT\""
    },
    "error_handling": {
      "intent": "stop execution on error",
      "canonical": "scripts/_common/utils.sh:die",
      "avoid": ["exit 1", "return 1 directly"],
      "example": "die \"Cannot find required file: $FILE\""
    },
    "retry_logic": {
      "intent": "retry flaky operation",
      "canonical": "scripts/_common/utils.sh:retry",
      "avoid": ["manual for/while loops", "sleep + manual retry"],
      "example": "retry 5 docker pull $IMAGE"
    }
  }
}
```

**Integration**: Copilot hints when detecting new helper patterns

---

## Metrics & Reporting

### Monthly Deduplication Report

Generated by `dedup-score-report.sh` and posted to `#infrastructure-status`:

```
Deduplication Health — April 2026
- Average PR score: 82/100 (+3 from last month)
- Issues with duplicates: 2 (down from 4)
- Waivers active: 1 (expires 2026-05-15)
- High-confidence duplication: 0
- Refactoring candidates: 3
```

### Deduplication Targets

- **By end of Q2 2026**: Average PR score >= 85
- **By end of Q3 2026**: Zero high-confidence duplicates on main
- **By end of Q4 2026**: 95% of helpers using canonical locations

---

## Related Documents

- [SCRIPT-WRITING-GUIDE.md](SCRIPT-WRITING-GUIDE.md) — How to write scripts that avoid duplication
- [DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md](DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md) — Audit of existing duplication (April 2026)
- [Copilot Instructions](../.github/copilot-instructions.md) — Rule 6: Deduplication enforcement

---

## Implementation Timeline

| Phase | Timeline | Deliverable |
|---|---|---|
| **Phase 1** | Week 1 (Apr 17-21) | Helper registry + lookup guide |
| **Phase 2** | Week 2 (Apr 24-28) | CI detection scripts + GitHub workflow |
| **Phase 3** | Week 3 (May 1-5) | IDE hints + Copilot integration |
| **Phase 4** | Week 4 (May 8-12) | Waiver system + enforcement |
| **Phase 5** | Ongoing | Monthly reporting + backlog refinement |

---

**Last Updated**: April 17, 2026  
**Next Review**: May 17, 2026
