# Enterprise Engineering Master Prompt
## Version 2.0 — Architect-Grade Rewrite
> Use this prompt to drive automated GitHub Issue generation across all engineering domains.
> Each domain produces one epic-level issue. Sub-findings become linked child issues.
> Do NOT make changes. Audit, document, and generate issues only.

---

## GLOBAL CONTEXT & INVARIANTS

These rules are non-negotiable and apply to every domain, every repo, every service.

| Rule | Standard |
|------|----------|
| Runtime | Linux only. Zero PowerShell or Windows artifacts. |
| Secrets | Never in code, env files, or logs. Google Secret Manager or HashiCorp Vault only. |
| Domain | `kushnir.cloud` is always a variable. Never hardcoded. |
| IPs | Never hardcoded. DNS-based service discovery only. |
| Branch | `main` is always deployable. No exceptions. |
| Concurrency | Two agents must never edit the same file simultaneously. |
| Immutability | Nothing in production is mutated in place. Replace, never patch. |
| Templating | If it can be a variable, it is. If it can be a template, it is. |
| Cost | Every resource is tagged. Idle, orphaned, and stale resources are tracked and eliminated. |
| Documentation | If it is not documented, it does not scale. Treat docs as code. |
| Testing | If it is not tested, it does not exist. |
| Drift | Anything that can drift will. Prevent it via continuous reconciliation. |

**Infrastructure:**
- Hosts: `192.168.168.31` (primary), `192.168.168.42` (secondary), `192.168.168.56` (NAS)
- Cluster: both hosts act as active cluster nodes with LB and failover
- All host references must use DNS names, not IPs, in configuration

**Repos:**
- Source control + GitLab/GitHub tooling: `https://github.com/kushin77/source-control.git`
- Ollama / AI workloads: `https://github.com/kushin77/ollama.git`
- code-server: dedicated fork of source-control
- All repos follow monorepo governance rules unless explicitly justified

---

## DOMAIN CATALOGUE

---

### D01 — Infrastructure Lifecycle & IaC Governance
**Labels:** `infrastructure` `terraform` `kubernetes` `IaC` `P0`
**Priority:** P0 — Foundational. Everything builds on this.

**What we are enforcing:**
Full lifecycle control over all infrastructure with zero manual intervention at any stage.

**Audit checklist:**
- [ ] All Terraform workspaces are idempotent — running `apply` twice produces no diff
- [ ] Full environment is redeployable from scratch with a single command
- [ ] Zero manual steps documented anywhere in runbooks for normal operations
- [ ] Automated rollback triggers are configured and tested on failed deployments
- [ ] Kubernetes workloads use ephemeral, immutable pod specs — no in-place mutations
- [ ] GitOps reconciliation loop (Flux or ArgoCD) is active and detects drift within 5 minutes
- [ ] All IaC modules are versioned and pinned — no floating `latest` references
- [ ] Resource quotas and namespace limits are enforced in Kubernetes
- [ ] All infrastructure changes go through CI/CD — zero direct `kubectl` or `terraform` runs in production
- [ ] Terraform state is remote, locked, and backed up
- [ ] Destroy protection is enabled on all stateful resources
- [ ] Infrastructure dependency graph is documented (what depends on what, in what order)

**Definition of done:** Full environment torn down and rebuilt from IaC with zero manual steps. Drift detected and auto-corrected within 5 minutes of any out-of-band change.

---

### D02 — CI/CD Pipeline Standards & Stage Gates
**Labels:** `ci-cd` `pipeline` `automation` `quality-gates` `P0`
**Priority:** P0 — No deployment path should bypass this.

**What we are enforcing:**
Every merge to main passes through a hardened, auditable pipeline. Pipeline is code. No snowflake pipelines.

**Audit checklist:**
- [ ] All pipelines are defined as code (no click-configured CI jobs)
- [ ] Pipeline stages enforced in order: lint → unit test → build → SAST → integration test → deploy
- [ ] No stage can be skipped without an explicit override that creates an audit trail
- [ ] Build artifacts are immutable and content-addressed (SHA-pinned)
- [ ] All Docker images are built with multi-stage builds and minimised base images
- [ ] Container images are signed and provenance is recorded (SLSA Level 2 minimum)
- [ ] SBOM (Software Bill of Materials) is generated and stored for every build
- [ ] Dependency versions are pinned — no floating semver ranges in production
- [ ] Supply chain: all third-party actions/orbs are pinned to commit SHA, not tag
- [ ] Pipeline execution time is measured; alert if it exceeds defined threshold
- [ ] Failed pipelines block merge — no bypass without approval trail
- [ ] Pipeline secrets are injected at runtime from Vault — never stored in CI config
- [ ] Canary and blue-green deployment pipelines exist and are tested
- [ ] Feature flags are the mechanism for releasing incomplete features — no `if dev` forks in code

**Definition of done:** Any commit to any repo follows the full pipeline with no manual override paths. Deployment to production requires passing all stage gates.

---

### D03 — Observability, Logging & SLOG
**Labels:** `observability` `logging` `monitoring` `opentelemetry` `alerting` `P0`
**Priority:** P0 — You cannot operate what you cannot see.

**What we are enforcing:**
Full-stack observability via the three pillars: metrics, logs, traces. SLOG captures every error across every layer.

**Audit checklist:**
- [ ] All log sources centralised: infrastructure, application, network, authentication, database
- [ ] OpenTelemetry instrumentation deployed across all services — no proprietary SDKs
- [ ] Distributed tracing connects frontend request → API → service → database → response
- [ ] SLOG captures 100% of errors: hardware, services, serverless, cloud, app, repo, network
- [ ] Log format is structured JSON everywhere — no unstructured log lines
- [ ] Log levels are standardised: DEBUG, INFO, WARN, ERROR, FATAL — no custom levels
- [ ] Sensitive data (PII, tokens, passwords) is never written to logs — validated by automated scan
- [ ] Logs are indexed, searchable, and retained per compliance policy (define retention period)
- [ ] Metrics dashboards exist for: host health, service latency (p50/p95/p99), error rate, saturation
- [ ] SLO burn rate alerts are configured and tested
- [ ] Alerting has defined severity tiers (P0–P3) with escalation paths for each
- [ ] On-call runbook exists for every P0 and P1 alert
- [ ] Synthetic monitoring probes run against all public-facing endpoints every 60 seconds
- [ ] Anomaly detection is configured for traffic, error rate, and latency baselines
- [ ] Audit log (immutable) captures all infrastructure changes, auth events, and secret access

**Definition of done:** Any error anywhere in the stack appears in SLOG within 30 seconds. P0 alert fires and escalates without human intervention.

---

### D04 — API Gateway, Service Mesh & Contract Governance
**Labels:** `api-gateway` `service-mesh` `openapi` `contract` `P1`
**Priority:** P1 — Required before any new service is exposed.

**What we are enforced:**
All inter-service and external communication goes through defined, versioned, documented contracts. No undocumented APIs.

**Audit checklist:**
- [ ] API gateway is in place for all external-facing traffic (Kong, Traefik, or equivalent)
- [ ] Service mesh (Istio or Linkerd) governs all east-west (service-to-service) traffic
- [ ] All APIs have an OpenAPI 3.x spec — contract-first, not documentation-after
- [ ] API versioning strategy is defined and enforced (`/v1/`, `/v2/` — no breaking changes without version bump)
- [ ] Deprecation policy is defined: minimum notice period, sunset date, migration guide required
- [ ] Rate limiting is configured per API endpoint and per consumer
- [ ] mTLS is enforced for all service-to-service communication within the cluster
- [ ] API authentication is consistent: OAuth2 / JWT — no ad-hoc token schemes
- [ ] API contracts are stored in source control and changes require PR review
- [ ] API changelog is maintained and auto-generated from spec diffs
- [ ] Dead-letter queues exist for all async API consumers
- [ ] All APIs return standard error envelopes — no bespoke error formats

**Definition of done:** Every service has an OpenAPI spec in source control. No undocumented internal or external endpoints. Breaking changes require a new version.

---

### D05 — Event-Driven Architecture & Async Messaging Standards
**Labels:** `event-driven` `messaging` `async` `queues` `P1`
**Priority:** P1 — Required for any service that communicates asynchronously.

**What we are enforcing:**
Async communication follows defined patterns. No fire-and-forget without delivery guarantees.

**Audit checklist:**
- [ ] Message broker is defined and standardised (Kafka, RabbitMQ, Pub/Sub — pick one)
- [ ] All async events have a defined schema (Avro, Protobuf, or JSON Schema in a registry)
- [ ] Event schema registry is version-controlled and breaking changes require a new topic/version
- [ ] Dead-letter queues are configured for all consumers
- [ ] Retry policies (with exponential backoff) are defined for all consumers
- [ ] Event ordering guarantees are documented per topic — where ordering matters, it is enforced
- [ ] Idempotency is required for all message consumers — duplicate delivery must be safe
- [ ] Message TTL and retention policies are defined per topic
- [ ] Poison message handling is implemented — bad messages are quarantined, not silently dropped
- [ ] Async flows are traceable end-to-end via correlation IDs surfaced in OpenTelemetry

**Definition of done:** No message is silently lost. Every async failure is captured in a dead-letter queue with full context. Consumers are idempotent.

---

### D06 — Data Layer Governance, Migrations & Backup
**Labels:** `data` `database` `migrations` `backup` `P0`
**Priority:** P0 — Data loss is unrecoverable.

**What we are enforced:**
All data is governed, versioned, backed up, and restorable. No schema changes outside of migration tooling.

**Audit checklist:**
- [ ] All databases use migration tooling (Flyway, Liquibase, or equivalent) — no manual schema changes ever
- [ ] Migrations are versioned, sequential, and reversible where possible
- [ ] All databases are backed up on a defined schedule with tested restore procedures
- [ ] RTO and RPO are defined per database — validated via scheduled restore drills
- [ ] No database is publicly accessible — all access is through application layer or VPN
- [ ] Database credentials rotate on a defined schedule via Vault dynamic secrets
- [ ] Sensitive data is classified (PII, financial, health) and encryption at rest is enforced per class
- [ ] Data retention policies are defined, documented, and enforced automatically
- [ ] Query performance is monitored — slow query log is active and reviewed
- [ ] Database connection pooling is in use — no unbounded connections from application layer
- [ ] Read replicas are configured where read load justifies it
- [ ] Data access is audited — who accessed what, when (immutable audit log)

**Definition of done:** Restore drill succeeds from backup. RTO/RPO targets are met. Zero manual schema changes exist in any environment.

---

### D07 — Security & Compliance (Fort Knox Standard)
**Labels:** `security` `compliance` `secrets` `SAST` `zero-trust` `P0`
**Priority:** P0 — Non-negotiable baseline.

**What we are enforcing:**
Zero-trust security posture across every layer. No exceptions, no temporary workarounds.

**Audit checklist:**
- [ ] Scan all repos for hardcoded secrets — zero tolerance policy, block on detection
- [ ] All secrets managed via Google Secret Manager or HashiCorp Vault
- [ ] Secret rotation policy defined and automated — no long-lived static credentials
- [ ] Layered security validated: Network → DNS → TLS/SSL → Service Mesh → Containers → Code
- [ ] Zero-trust network model: every service authenticates every request regardless of origin
- [ ] Cloudflare free-tier protections fully maximised: WAF, DDoS, bot management, rate limiting
- [ ] SAST scan runs on every PR — findings block merge above defined severity threshold
- [ ] DAST scan runs against staging environment on every deployment
- [ ] Dependency vulnerability scan (OWASP, Snyk, or Trivy) runs in pipeline — critical findings block deploy
- [ ] Container images are scanned for CVEs before deployment
- [ ] Network segmentation: services can only communicate with what they need (allowlist model)
- [ ] All TLS certificates are managed, auto-renewed (cert-manager), and expiry is monitored
- [ ] Browser security headers enforced: CSP, HSTS, X-Frame-Options, Referrer-Policy
- [ ] Air-gapped environment exists for sensitive workloads where required
- [ ] Pen test executed against both hosts — findings tracked as P0 issues
- [ ] Compliance posture documented: which controls map to SOC2 / ISO27001 requirements
- [ ] Incident response plan exists and has been table-top tested
- [ ] Linux-only runtime confirmed — no PowerShell or Windows artifacts anywhere

**Definition of done:** Zero hardcoded secrets. SAST/DAST clean. Pen test complete. Incident response plan tested.

---

### D08 — Codebase Hygiene, Architecture & Complexity
**Labels:** `code-quality` `architecture` `refactor` `cyclomatic-complexity` `P1`
**Priority:** P1 — Technical debt compounds.

**What we are enforcing:**
Clean, modular, documented code with measured complexity. No orphaned code, no dead paths.

**Audit checklist:**
- [ ] Full dead code audit — remove duplicate, stale, deprecated, and orphaned components
- [ ] `kushnir.cloud` domain is a variable in every file — validated by automated grep/scan
- [ ] All environment-specific values externalised — no hardcoded config of any kind
- [ ] Cyclomatic complexity measured per function/module — anything above threshold flagged
- [ ] Service independence enforced — no direct database sharing between microservices
- [ ] Shared libraries have internal documentation and changelogs
- [ ] SDLC lifecycle standardised across all repos — same stages, same gates
- [ ] Architecture Decision Records (ADRs) maintained for all significant decisions
- [ ] RFC process defined for any change that affects more than one service
- [ ] Canonical patterns documented (error handling, logging, auth, config loading) — no variance
- [ ] Dependency injection used where appropriate — no service locator anti-pattern
- [ ] No `TODO` or `FIXME` comments in main branch — all converted to tracked issues

**Definition of done:** Zero hardcoded config. Complexity below threshold. All architectural decisions recorded as ADRs.

---

### D09 — Repository Governance & Monorepo Standards
**Labels:** `repo-governance` `git-hygiene` `monorepo` `pnpm` `P1`
**Priority:** P1 — Repo hygiene prevents compounding disorder.

**What we are enforcing:**
FAANG-grade repository structure with zero tolerance for drift, sprawl, or ambiguity.

**Audit checklist:**
- [ ] FAANG-style naming conventions enforced across all repos — documented and linted
- [ ] Directory hierarchy follows defined standard — no loose files outside of spec
- [ ] `pnpm` is the sole dependency manager in monorepo — `npm` and `yarn` lock files removed
- [ ] `pnpm` workspace configuration is correct and all internal packages resolve locally
- [ ] Folder structure enforced to as many subdirectories as needed — no flat dumping
- [ ] All stale local and remote branches identified and eliminated
- [ ] Branch auto-delete on merge configured in all repos
- [ ] Merge-to-main discipline enforced — feature branches are short-lived (< 3 days)
- [ ] Branch naming convention enforced: `feature/`, `fix/`, `chore/`, `release/`
- [ ] SSOT confirmed: code, config, and documentation have one canonical source each
- [ ] No two agents or contributors edit the same file simultaneously — detection mechanism in place
- [ ] `.gitignore` is comprehensive and standardised across all repos
- [ ] Git hooks enforce: commit message format, pre-commit lint, secret scan
- [ ] CODEOWNERS file defines clear ownership for every directory

**Definition of done:** Repository passes automated structure linting. Zero stale branches. CODEOWNERS covers 100% of directories.

---

### D10 — Networking, DNS, Performance & Service Discovery
**Labels:** `networking` `dns` `performance` `service-discovery` `P1`
**Priority:** P1 — Network issues cascade everywhere.

**What we are enforcing:**
All communication is name-based. Performance is measured. No hardcoded routing.

**Audit checklist:**
- [ ] All hardcoded IPs replaced with DNS names — validated by automated scan
- [ ] Internal service discovery uses consistent mechanism (CoreDNS, Consul, or k8s Service DNS)
- [ ] External DNS entries are managed as code — no manual DNS record changes
- [ ] NAS / 10G network throughput benchmarked and documented — alert if below baseline
- [ ] Caching strategy defined per service: what is cached, TTL, invalidation mechanism
- [ ] CDN caching behaviour documented and tested for all static assets
- [ ] DNS failover tested: primary down → secondary resolves within defined TTL
- [ ] Network latency between hosts measured and baselined — alert on regression
- [ ] HTTP/2 or HTTP/3 enforced for all external-facing services
- [ ] Connection timeouts and retry budgets defined for all service clients
- [ ] Network policies (Kubernetes NetworkPolicy) enforce allowlist-only traffic flows
- [ ] Bandwidth and throughput monitored per node — alert on saturation

**Definition of done:** Zero hardcoded IPs. DNS failover tested. Network baselines documented with alerting in place.

---

### D11 — Testing, QA & Production Readiness
**Labels:** `testing` `E2E` `QA` `playwright` `stress-test` `chaos` `P1`
**Priority:** P1 — Untested code is undeployed code.

**What we are enforcing:**
100x testing coverage. Every user flow is automated. Production readiness is a gate, not a goal.

**Audit checklist:**
- [ ] Unit tests cover all business logic — coverage threshold defined and enforced in pipeline
- [ ] Integration tests cover all service boundaries
- [ ] System tests cover all critical user journeys end-to-end
- [ ] Regression suite runs on every deployment to staging
- [ ] Playwright E2E suite implemented using QA account with visible browser mode for onboarding
- [ ] E2E covers: OAuth login (all providers), profile setup, repo management, folder/file operations
- [ ] E2E covers: IDE usage, code-server functionality, all user-facing features
- [ ] VPN-based validation flows executed and documented
- [ ] UAT executed covering all user-facing functionality — documented sign-off
- [ ] Stress test: CPU and GPU on both hosts under sustained load — document limits and degradation
- [ ] Pen test executed — all findings tracked as P0 security issues
- [ ] Chaos test: random service kills, network partitions, disk pressure — document all failures
- [ ] Reboot test: reboot host 1, wait for full recovery and log collection, then reboot host 2
- [ ] Each service restarted individually on both hosts — functionality verified after each
- [ ] Zero unfinished features in main branch
- [ ] Zero temporary code, workarounds, or `TODO` items in main branch
- [ ] Test data management strategy defined — no production data in test environments
- [ ] Test environments are isolated, reproducible, and destroyed after use

**Definition of done:** All test suites pass. Chaos and reboot tests completed with logs collected. Zero temp code in main.

---

### D12 — GitHub / GitLab Integration & PMO Automation
**Labels:** `github` `gitlab` `automation` `PMO` `workflow` `P1`
**Priority:** P1 — Issue and workflow hygiene is engineering discipline.

**What we are enforcing:**
Fully automated issue lifecycle. No manual project management overhead. GitHub is the SSOT for work.

**Audit checklist:**
- [ ] All GitHub API 403 and permission errors resolved — permissions documented as IaC
- [ ] Issue lifecycle fully automated: create → assign → update → link → close
- [ ] PMO workflow auto-creates issues from: failed deployments, security scan findings, drift detection
- [ ] All GitLab/GitHub tooling code lives in `kushin77/source-control` — code-server in its own fork
- [ ] Milestones and epics defined for all active domains
- [ ] Labels are standardised across all repos — label taxonomy documented
- [ ] GitHub Projects board reflects real work — stale issues are aged out automatically
- [ ] Documentation scan executed — all gaps tracked as issues with priority labels
- [ ] Gap analysis completed — findings linked to parent domain epics
- [ ] Webhook integrations tested and reliable — no silently failing webhooks
- [ ] GitHub free-tier limits audited — usage optimised to stay within bounds
- [ ] Branch protection rules enforced: required reviews, status checks, no force push to main

**Definition of done:** Zero manual project management tasks. All pipeline events produce issues automatically. Label taxonomy enforced.

---

### D13 — Developer Experience, Sovereign IDE & Collaboration
**Labels:** `developer-experience` `IDE` `copilot` `collaboration` `sovereign-platform` `P2`
**Priority:** P2 — Strategic differentiator for the platform.

**What we are enforcing:**
code-server evolves into a sovereign, home-grown developer operating system. Users never see infrastructure.

**Audit checklist:**
- [ ] Gap analysis: code-server current state vs sovereign IDE product roadmap — document all gaps
- [ ] Users can open local folders on their host without any infrastructure exposure
- [ ] Users can access their GitHub account from within the IDE
- [ ] Users never see, access, or are aware of the background infrastructure code-server runs on
- [ ] Copilot agents reference docs, logs, open/closed issues, and system memory before prompting
- [ ] Copilot reduces unnecessary user prompts by 80% via context awareness
- [ ] Overlapping-edit detection: alert when two users edit the same file — AI-assisted resolution suggested
- [ ] Encrypted sidebar communication (Google Chat / Google Meet) integrated and tested
- [ ] Developer onboarding standard documented — new developer productive within defined time
- [ ] IDE extensions and configuration managed as code — no manual setup on new machine
- [ ] All IDE configuration is user-scoped and synced — no host-specific state
- [ ] Real-time collaboration features tested under concurrent user load

**Definition of done:** Zero infrastructure leakage to users. Onboarding standard documented. Copilot context awareness verified.

---

### D14 — Identity, Access Management & Zero-Trust Auth
**Labels:** `IAM` `security` `SSO` `zero-trust` `least-privilege` `P0`
**Priority:** P0 — Identity is the perimeter.

**What we are enforcing:**
Every identity is verified. Every access is scoped. Nothing is assumed trusted.

**Audit checklist:**
- [ ] All SSH keys and service credentials managed as IaC — no manually created credentials
- [ ] All credentials are immutable and idempotent — recreate, never rotate manually
- [ ] All service accounts follow least-privilege principle — verified by automated policy scanner
- [ ] SSO enforced for all user-facing services — no service has its own auth database
- [ ] OAuth2 / OIDC is the standard — no bespoke token systems
- [ ] MFA enforced for all human identities accessing production systems
- [ ] Service-to-service authentication uses short-lived tokens from Vault — no long-lived service passwords
- [ ] Zero-trust model: no implicit trust based on network location
- [ ] Access reviews scheduled quarterly — stale accounts and over-privileged roles flagged
- [ ] Privileged access (root, admin) is just-in-time and requires explicit approval
- [ ] All auth events are logged to immutable audit trail
- [ ] SSO flows tested: login, logout, token refresh, session expiry, MFA challenge

**Definition of done:** Zero manually managed credentials. SSO covers 100% of user-facing services. Least-privilege verified by scanner.

---

### D15 — Container Registry & Image Governance
**Labels:** `containers` `registry` `SBOM` `supply-chain` `P1`
**Priority:** P1 — Untrusted images are an attack surface.

**What we are enforcing:**
Every container image is known, scanned, signed, and traceable to its source commit.

**Audit checklist:**
- [ ] Private container registry in use — no pulling from Docker Hub in production without mirroring
- [ ] All images are built from pinned, minimal base images — no `latest` tags in production
- [ ] Images are tagged with: git SHA, branch, build timestamp — never just `latest`
- [ ] All images are signed (cosign or Notary v2) — unsigned images rejected by admission controller
- [ ] SBOM generated for every image build and stored alongside the image
- [ ] CVE scan (Trivy or Grype) runs on every image build — critical CVEs block deployment
- [ ] Old/untagged images are pruned on a defined schedule
- [ ] Registry access is controlled — only CI/CD pipeline can push; pull requires authentication
- [ ] Base image updates trigger downstream rebuild and redeployment automatically
- [ ] Image provenance is traceable: image SHA → build log → source commit

**Definition of done:** Every deployed image has a signature, SBOM, and CVE scan result. No unsigned or unscanned images in production.

---

### D16 — Endpoint, Portal & SSO Validation
**Labels:** `SSO` `oauth` `portal` `endpoint` `multi-tenant` `P1`
**Priority:** P1 — The user-facing surface of the platform.

**What we are enforcing:**
kushnir.cloud is a fully functional SaaS portal. Multi-tenancy is a first-class design concern.

**Audit checklist:**
- [ ] `kushnir.cloud` opens to Appsmith/Backstage portal with all navigation options accessible
- [ ] `ide.kushnir.cloud` is OAuth-protected, stable, and loads within defined latency threshold
- [ ] Single OAuth session covers all repo endpoint management — no re-authentication between services
- [ ] Multi-tenancy model defined: user / group / org / whitelabel — isolation validated
- [ ] Users can add custom domains without infrastructure access
- [ ] Users can connect external cloud resources (AWS, GCP, etc.) via API key management UI
- [ ] SaaS management: create/update/suspend/delete orgs and users via admin portal
- [ ] Whitelabel: tenant-specific branding (logo, domain, color) works without code changes
- [ ] Repeatable SSO login flows tested via QA account — no flakiness
- [ ] VPN-based SSO validation executed and documented
- [ ] All portal endpoints have synthetic monitoring — alert on availability < 99.9%
- [ ] Portal performance tested under concurrent user load — document degradation threshold

**Definition of done:** Full multi-tenant lifecycle tested. Custom domain and external resource addition validated. SSO flows stable under load.

---

### D17 — Storage, Resource Hygiene & FinOps
**Labels:** `storage` `cost-optimisation` `finops` `cleanup` `tagging` `P2`
**Priority:** P2 — Cost compounds silently.

**What we are enforcing:**
Every resource is tagged, attributed, and justified. Idle and orphaned resources are eliminated automatically.

**Audit checklist:**
- [ ] Tagging strategy defined: every resource carries service, owner, environment, cost-centre tags
- [ ] Orphaned storage volumes and artifacts identified and removed
- [ ] Stale containers and images pruned across both hosts on a defined schedule
- [ ] Unused Kubernetes namespaces, ConfigMaps, and Secrets cleaned up
- [ ] Cost per service measured and tracked over time — alert on unexpected growth
- [ ] Rate-limited APIs identified — usage patterns reviewed and optimised
- [ ] Idle compute resources (host CPU < 5% sustained) flagged for right-sizing
- [ ] Resource lifecycle policies enforced: automatically expire test/preview environments
- [ ] NAS storage usage baselined — alert at defined utilisation threshold
- [ ] Docker volume cleanup automated — no unbounded volume accumulation

**Definition of done:** 100% of resources tagged. Automated cleanup runs on schedule. Cost per service tracked with alerting.

---

### D18 — Failover, Clustering, Load Balancing & Chaos Resilience
**Labels:** `cluster` `failover` `load-balancing` `chaos-testing` `resilience` `P0`
**Priority:** P0 — Two hosts means nothing if failover is untested.

**What we are enforcing:**
Both hosts operate as an active cluster. Failure of either host is transparent to users.

**Audit checklist:**
- [ ] Cluster configuration validated: 192.168.168.31, 192.168.168.42, and NAS 192.168.168.56
- [ ] Load balancing distributes traffic across both hosts — distribution ratio documented
- [ ] Failover tested: take host 1 offline, confirm host 2 absorbs 100% of load within defined RTO
- [ ] Failover tested: take host 2 offline, confirm host 1 absorbs 100% of load within defined RTO
- [ ] NAS failover tested: validate data access degradation and recovery
- [ ] Each service restarted individually on both hosts — functionality verified after each restart
- [ ] Chaos test: random pod/container kills — system self-heals within defined SLO
- [ ] Chaos test: network partition between hosts — split-brain prevention validated
- [ ] Chaos test: disk pressure on each host — service degradation is graceful, not catastrophic
- [ ] Chaos test: CPU/GPU saturation on each host — load shedding and backpressure verified
- [ ] Reboot test: reboot host 1, wait for full recovery, collect logs, then reboot host 2
- [ ] Full recovery time documented for each host reboot — must meet defined RTO
- [ ] Health checks and readiness probes configured for every service
- [ ] Circuit breakers configured for all inter-service calls — open state is logged and alerted

**Definition of done:** Both hosts rebooted sequentially with full log collection. Chaos suite passes. RTO targets met and documented.

---

### D19 — Disaster Recovery, Backup & Business Continuity
**Labels:** `disaster-recovery` `backup` `RTO` `RPO` `business-continuity` `P0`
**Priority:** P0 — A backup never tested is not a backup.

**What we are enforcing:**
Defined, documented, and regularly tested DR strategy with clear RTO and RPO targets.

**Audit checklist:**
- [ ] DR strategy documented: what fails over where, in what order, with what tooling
- [ ] RTO defined per service tier: Tier 1 (< 5 min), Tier 2 (< 30 min), Tier 3 (< 4 hr)
- [ ] RPO defined per data class: transactional (< 1 min), operational (< 15 min), archive (< 24 hr)
- [ ] Full backup runs on defined schedule — backup completion monitored and alerted
- [ ] Restore drill executed: full environment restored from backup — time and outcome documented
- [ ] Backup integrity verified: checksums validated, not just file existence
- [ ] Backups stored off-host: not on the same machine being backed up
- [ ] DR runbook is step-by-step, tested by a person who did not write it
- [ ] Communication plan defined: who is notified, in what order, using what channel
- [ ] Post-incident review process defined — blameless retrospective template exists

**Definition of done:** Restore drill completed successfully. RTO/RPO targets met. Runbook tested by someone other than the author.

---

### D20 — AI, Ollama & Model Governance
**Labels:** `AI` `ollama` `model-governance` `repo-governance` `P2`
**Priority:** P2 — AI workloads need the same rigour as everything else.

**What we are enforcing:**
AI code is isolated, versioned, and governed like any other service. Model usage is audited.

**Audit checklist:**
- [ ] All AI and Ollama code isolated in `kushin77/ollama.git` — zero leakage into other repos
- [ ] code-server AI integration in its dedicated fork — no AI code in main source-control repo
- [ ] Model versions are pinned — no auto-updating to new model versions without explicit review
- [ ] Ollama resource limits defined — GPU/CPU quotas enforced to prevent starvation of other services
- [ ] Model inference requests are logged (input hash, output hash, latency, model version) — no raw content
- [ ] Prompt injection mitigations in place for any user-facing AI feature
- [ ] AI feature flags exist — model can be disabled without code deployment
- [ ] Sensitive data is never sent to external AI APIs — validated by automated scan
- [ ] Cost per model invocation tracked — alert on unexpected usage spikes

**Definition of done:** Zero AI code outside designated repos. Model versions pinned. Inference logging active.

---

### D21 — Developer Onboarding, Runbooks & Institutional Knowledge
**Labels:** `documentation` `runbooks` `onboarding` `knowledge-management` `P2`
**Priority:** P2 — Knowledge that lives in one person's head is a single point of failure.

**What we are enforcing:**
Every operational procedure is documented. New engineer is productive within a defined time. Nothing undocumented reaches production.

**Audit checklist:**
- [ ] Developer onboarding guide: new engineer productive within defined hours, no tribal knowledge required
- [ ] Runbook exists for every P0 and P1 alert — linked directly from the alert
- [ ] Architecture Decision Records (ADRs) maintained for all significant decisions — searchable
- [ ] RFC template and process defined for cross-service changes
- [ ] Service catalogue documents every service: owner, purpose, dependencies, SLO, runbook link
- [ ] Postmortem template exists — all P0 incidents produce a published postmortem within 48 hours
- [ ] Internal API documentation auto-generated from OpenAPI specs — always in sync with code
- [ ] Shared library documentation generated and versioned alongside code
- [ ] "Golden rules" are encoded as linting rules and policy-as-code — not just a document
- [ ] Documentation is tested: links checked, examples run in CI, accuracy reviewed quarterly

**Definition of done:** Onboarding guide validated by a new engineer. Every P0/P1 alert has a linked runbook. Service catalogue complete.

---

### D22 — Policy-as-Code, Templates & Compliance Automation
**Labels:** `policy` `compliance` `templates` `OPA` `P2`
**Priority:** P2 — Policies that exist only in documents are not enforced.

**What we are enforcing:**
Every governance rule is encoded as machine-readable policy. Compliance is continuous, not periodic.

**Audit checklist:**
- [ ] OPA (Open Policy Agent) or equivalent enforces policies in CI/CD pipeline and Kubernetes admission
- [ ] All governance rules converted to reusable templates within code-server environments
- [ ] Security policies inherited automatically by all new repos/services — no opt-in required
- [ ] Repo compliance enforced: required files (CODEOWNERS, README, CHANGELOG) linted in pipeline
- [ ] Naming convention policies enforced by linting — violations block PR merge
- [ ] Branch protection policies enforced as IaC — not manually configured per repo
- [ ] Compliance posture dashboard: real-time view of which services meet which policies
- [ ] Policy violations produce GitHub Issues automatically — not just CI failures
- [ ] Policy-as-code is itself tested — policies have unit tests
- [ ] Compliance evidence auto-collected for SOC2/ISO27001 audit readiness

**Definition of done:** 100% of governance rules expressed as code. Compliance dashboard live. Policy violations produce issues automatically.

---

## GOLDEN RULES (Encoded — Not Just Documented)

These must be enforced by tooling, not by trust:

| Rule | Enforcement Mechanism |
|------|-----------------------|
| Everything is IaC | CI blocks any manual change not in source |
| Nothing is mutable | Immutability enforced by admission controllers |
| No secrets in code | Secret scan blocks PR merge |
| Main is always deployable | Branch protection + full pipeline gate |
| If not tested, it doesn't exist | Coverage threshold enforced in pipeline |
| If not documented, it doesn't scale | Runbook required for every P0/P1 alert |
| If it can drift, prevent it | GitOps reconciliation detects and corrects within 5 min |
| If it's not tagged, it's not tracked | Tagging policy blocks untagged resource creation |
| If it's not signed, it doesn't deploy | Admission controller rejects unsigned images |
| If there's no runbook, there's no deploy | Service catalogue completeness gate before production |

---

## ISSUE GENERATION INSTRUCTIONS

For each domain above, generate one GitHub Issue with the following structure:

```
Title:    [D##] <Domain name> — Audit & remediation
Labels:   <labels listed in domain header>
Body:

## Objective
<one-sentence statement of what this domain enforces>

## Audit checklist
- [ ] <item 1>
- [ ] <item 2>
...

## Gaps found
<!-- To be populated by the auditing agent -->

## Sub-issues
<!-- Link any child issues created from findings here -->

## Definition of done
<definition listed in domain>

## References
- Hosts: 192.168.168.31, 192.168.168.42, NAS 192.168.168.56
- Domain variable: kushnir.cloud
- Source control: https://github.com/kushin77/source-control.git
- Ollama: https://github.com/kushin77/ollama.git
- Priority: <P0/P1/P2>
```

Generate all 22 issues. Do not make any changes. Audit only.
