# Changelog

All notable changes to the ElevatedIQ DevOS platform will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub governance automation: documentation gap analysis, API stability auditing
- Issue lifecycle governance enforcement
- Weekly PMO status reports via GitHub Actions

### Changed
- Infrastructure environment consolidation (PRIMARY_HOST, REPLICA_HOST, APEX_DOMAIN)
- Domain variability enforcement (no hardcoded IPs)

### Fixed
- SSOT credential validator false positives (narrowed to real secret fingerprints)
- Health check timeout in dry-run mode (fail-fast behavior)

## [0.4.0] — 2026-04-25

### Added
- P2 #1539: IDE Intelligence Epic Phase 7 — Advanced Team Coordination (1,086 LOC)
  - TeamOrchestratorEngine for distributed task assignment
  - TeamCoordinationHandler for team workload views
  - Real-time team capacity monitoring
  - Workflow template automation
- P3 #1533: Codebase Deduplication Phase 3 (4/4 priorities complete)
  - URL externalization to .env.infrastructure
  - Sourcing consolidation with guards
  - Inline logging standardization
  - 100% GOV-002 header compliance on infrastructure scripts
- P3 #1531: Infrastructure Lifecycle Control Phase 5 (5/5 phases complete)
  - Full deployment and redeploy testing
  - SLA compliance reporting
  - Comprehensive health check infrastructure

### Fixed
- Security CVE remediation (5 CVEs documented and fixed via pnpm.overrides)
- GitHub Dependabot vulnerabilities: form-data, tough-cookie, others

### Security
- All secrets removed from code (real fingerprint detection only)
- Zero hardcoded credentials in infrastructure
- IaC compliance: 100%

## [0.3.0] — 2026-04-23

### Added
- P3 #1550: Sovereign Terraform Drop Package foundation
  - Full module structure with reusable components
  - Parameterized Terraform (zero hardcoded values)
  - One-command deployment capability
- P3 #1552: OPA Policy Engine architecture
  - Core policy library structure
  - ABAC framework ready
  - Integration point specifications
- P3 #1553: env.yaml Environment Parity Engine design
  - Schema v1 specification
  - Service provisioning framework
  - Clone/offline/replay operations

### Changed
- Repository boundary clarification (code-server, source-control, ollama repos)
- Consolidated deployment targets to environment variables

## [0.2.0] — 2026-04-20

### Added
- Zero-trust Terraform configuration
- GitOps drift detection pipeline
- Automated rollback procedures
- Health check infrastructure
- Domain and IP consolidation

### Fixed
- SSL/TLS configuration (Let's Encrypt rate limiting workarounds)
- OAuth2-proxy 502 errors
- Caddyfile dynamic routing

## [0.1.0] — 2026-04-17

### Added
- Initial code-server-enterprise fork from upstream
- Local Docker Desktop deployment support
- Basic infrastructure scripts
- GitHub Actions workflows
- Documentation scaffolding

---

## Version History by Epic

### P2 #1539: IDE Intelligence (8,344 LOC) — ✅ COMPLETE
- Phase 1: KC IDE Branding (860 LOC)
- Phase 2: Copilot Autonomy (1,410 LOC)
- Phase 3: Collaboration Intelligence (1,290 LOC)
- Phase 4: Local Folder Access (996 LOC)
- Phase 5: GitHub OAuth (1,260 LOC)
- Phase 6: Team Communication (1,442 LOC)
- Phase 7: Advanced Team Coordination (1,086 LOC)

### P3 #1531: Infrastructure Lifecycle Control (5/5 Phases) — ✅ COMPLETE
- Phase 1: GitOps CD workflow
- Phase 2: Automated rollback & health checks
- Phase 3: Drift detection & reconciliation
- Phase 4: Configuration SSOT
- Phase 5: Full redeploy test & SLA verification

### P3 #1533: Codebase Deduplication (4/4 Priorities) — ✅ COMPLETE
- Priority 1: URL externalization
- Priority 2: Sourcing consolidation
- Priority 3: Inline logging standardization
- Priority 4: GOV-002 header compliance

---

## Breaking Changes

None in current release.

## Deprecations

None.

## Migration Guide

See [DEPLOYMENT-RUNBOOK.md](docs/operations/DEPLOYMENT-RUNBOOK.md) for deployment instructions.

---

## Contributors

- Joshua Kushnir (kushin77)
- Copilot Agent (autonomous execution)

## License

See LICENSE file.
