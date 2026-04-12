# 003. Terraform for Infrastructure as Code

**Status**: Accepted  
**Date**: 2026-01-27  
**Author(s)**: @kushin77  
**Related ADRs**: [ADR-001: Containerized Deployment](001-containerized-deployment.md)  

---

## Context

Infrastructure previously managed:
- **Manually** via cloud console clicks (error-prone)
- **Inconsistently** across dev/staging/production
- **Without version control** — impossible to audit who changed what
- **Without repeatability** — new environment required manual recreation
- **Without testing** — infrastructure changes deployed without validation

Enterprise requirements:
- **Version controlled infrastructure** — all changes in Git, reviewable
- **Policy enforcement** — prevent insecure configurations (OPA/Conftest)
- **Automated testing** — infrastructure validated before deployment
- **Disaster recovery** — ability to rebuild infrastructure from code
- **Cost management** — infrastructure declared explicitly, easy to audit spending

We needed Infrastructure as Code tooling to bring engineering discipline to infrastructure.

---

## Decision

We will use **Terraform** to manage all cloud infrastructure:

```
Cloud Provider (GCP, AWS)
    ↑
  Terraform (state management, planning, applying)
    ↑
  Git (source of truth, versioning, code review)
    ↑
  CI/CD (validate, plan, apply)
```

Key decisions:
- **Provider**: GCP (aligns with landing zone architecture)
- **State storage**: GCS remote backend (encrypted, versioned)
- **Plan review**: All terraform apply gated by PR approval + CI
- **Policy enforcement**: OPA/Conftest validates security policies
- **Secrets management**: GCP Secret Manager, never in code
- **Versioning**: Terraform pinned to specific version for reproducibility

---

## Alternatives Considered

### Alternative 1: CloudFormation (AWS)
**Pros**: 
- AWS-native, integrated with AWS console
- Good parameter handling

**Cons**: 
- **Vendor lock-in** — can't switch clouds
- **JSON-based** — verbose, error-prone
- **Ecosystem** — smaller community, fewer modules
- **Company uses GCP** — CloudFormation requires AWS

**Why not chosen**: Company standardized on GCP (landing zone architecture).

### Alternative 2: Pulumi
**Pros**: 
- General-purpose languages (Python, Go, etc.)
- Advanced programming constructs

**Cons**: 
- **Learning curve** — more complex than HCL
- **Ecosystem** — smaller than Terraform
- **Cost** — requires Pulumi service account for state management
- **Team expertise** — team knows Terraform better

**Why not chosen**: Terraform sufficient, team expertise favors it.

### Alternative 3: Manual Scripts
**Pros**: 
- Maximum flexibility
- Minimal abstraction

**Cons**: 
- **No auditability** — changes not reviewable
- **Drift-prone** — manual changes diverge from scripts
- **Not idempotent** — rerunning scripts might fail
- **Error-prone** — shell scripts error handling complex
- **Scaling nightmare** — multi-environment management impossible

**Why not chosen**: Does not meet enterprise standards.

---

## Consequences

### Positive Consequences
- ✅ **Version controlled** — all infrastructure changes in Git, auditable
- ✅ **Code reviewed** — infrastructure changes peer-reviewed before deployment
- ✅ **Reproducible** — same code produces identical infrastructure
- ✅ **Disaster recovery** — can rebuild infrastructure from code
- ✅ **Cost visibility** — infrastructure declared explicitly, spending tracked
- ✅ **Policy enforcement** — OPA/Conftest prevents insecure configs
- ✅ **Faster provisioning** — new environments stand up in minutes

### Negative Consequences (Accepted Risks)
- ⚠️ **State file management** — state is sensitive (contains secrets, resource IDs)
  - Mitigated: Remote state in GCS with encryption, access control, versioning
- ⚠️ **Terraform lock state** — can block deployments if lock not released
  - Mitigated: Lock timeout configured, manual unlock procedure documented
- ⚠️ **Learning curve** — team must learn HCL, Terraform concepts
- ⚠️ **Dependency on Terraform** — if Terraform breaks, infrastructure management blocked
  - Mitigated: Regular terraform plan/validate in CI catches issues early
- ⚠️ **Expensive mistakes possible** — `terraform destroy` accidentally can delete resources
  - Mitigated: Confirmation required, no `destroy` allowed in automated CI

---

## Security Implications

- **Trust boundaries**: 
  - State file is trust boundary (contains secrets, resource IDs)
  - Terraform execution environment must be secure (CI/CD runner)
  - Only authorized personnel can approve/apply changes
  
- **Attack surface**: 
  - **New**: State file exposure (mitigated: encrypted in GCS, access control, versioning)
  - **New**: Terraform execution environment compromise (mitigated: CI/CD runner security, audit logging)
  - **Reduced**: Fewer manual cloud console changes = fewer opportunities for errors
  
- **Data exposure**: 
  - State file may contain secrets in plaintext (sensitive)
  - Mitigated: Encrypt sensitive data at rest, use GCP Secret Manager for secret values
  
- **Authentication/Authorization**: 
  - ✅ Terraform execution uses GCP service account (least privilege RBAC)
  - ✅ GitHub OIDC federation (no long-lived credentials)
  - ✅ Approval required for apply (code owner review)
  
- **Mitigation strategy**: 
  - State encryption: GCS bucket encryption at rest
  - Access control: IAM roles restrict who can read/modify state
  - Change audit: All changes tracked in Git, reviewed before apply
  - Regular backup: Terraform state versioned in GCS (point-in-time recovery)
  - Sensitive data: Use GCP Secret Manager, reference in Terraform (not stored in state)

---

## Performance & Scalability Implications

- **Horizontal scaling**: 
  - ✅ Terraform can manage arbitrary number of resources
  - Multi-region deployments: add variables, reuse modules
  - Multi-environment (dev/staging/prod): separate state files, code reuse via modules
  
- **Bottlenecks**: 
  - State file size: grows with infrastructure complexity (typical: <10MB)
  - Plan time: O(n resource count), typical: <30 seconds for thousands of resources
  - Apply time: depends on resource creation speed (typical: <5 minutes for full environment)
  
- **Resource usage**: 
  - Terraform binary: ~100MB
  - RAM: <1GB for typical infrastructure
  - Storage: state file <10MB
  
- **Plan validation time**: 
  - Lint: <5 seconds
  - Format check: <5 seconds
  - Policy check (OPA): <30 seconds for complex policies
  - Plan: <30 seconds typical
  
- **Deployment throughput**: 
  - Single apply: ~5 minutes (depends on resource count)
  - Parallel team applies: restricted by state lock (sequential)
  - Mitigation: Split infrastructure into modules/state files per team

---

## Operational Impact

- **Deployment workflow**: 
  1. Engineer submits PR with .tf changes
  2. CI runs `terraform fmt`, `terraform validate`, lint, policy checks
  3. On approval, CI runs `terraform plan` (human review artifact)
  4. On merge, CD runs `terraform apply` (automated deployment)
  
- **Monitoring**: 
  - Terraform apply logs streamed to CI output
  - Cloud infrastructure changes logged via Cloud Audit Logs
  - Alert if terraform apply fails
  
- **Alerting**: 
  - Alert if terraform plan succeeds but apply fails (divergence)
  - Alert if state file lock held > 15 minutes (possible hang)
  - Alert on cloud resource deletion via Terraform (audit)
  
- **Rollback**: 
  - ✅ Git revert: reverts .tf changes, apply re-converges
  - ✅ Terraform state rollback: restore from GCS versions (point-in-time)
  - ⚠️ Some resources difficult to rollback (data deletion permanent)
  - Mitigation: Pre-deletion backups, soft-delete where possible
  
- **On-call**: 
  - Understanding Terraform state management
  - Diagnosing apply failures (provider errors, quota issues)
  - Manual state editing (debugging only, rare)
  - Runbook for common issues (see [RUNBOOKS.md](../../RUNBOOKS.md))

---

## Implementation Notes

**State Management**:
- Remote backend: GCS bucket (`state-bucket-project-id`)
- Encryption: GCS encryption at rest (default)
- Access control: IAM role `roles/storage.admin` restricted to service account
- Versioning: Enabled for point-in-time recovery

**Secrets Handling**:
- Do NOT store secrets in .tf files or state
- Use GCP Secret Manager: `data.google_secret_manager_secret_version`
- Reference in code: `secret_value = data.google_secret_manager_secret_version.my_secret.secret_data`
- Secret Manager handles encryption, access control

**Module Structure**:
```
terraform/
├── main.tf              (provider config, root resources)
├── variables.tf         (input variables)
├── outputs.tf           (outputs for downstream modules)
├── terraform.tfvars     (variable values, GIT IGNORED)
├── modules/
│   ├── code-server/     (code-server infrastructure)
│   ├── networking/      (VPC, firewall, etc.)
│   └── security/        (IAM, secrets, etc.)
└── policies/
    └── opa/             (OPA/Conftest policies)
```

**CI/CD Integration**:
- `terraform validate`: syntax check
- `terraform fmt --check`: formatting validation
- `terraform plan`: generate plan artifact
- OPA/Conftest: policy validation
- `terraform apply`: deploy (only on main, requires approval)

---

## Validation Criteria

- [x] **Infrastructure reproducible**: Running terraform apply produces identical infrastructure
- [x] **State secure**: Remote state encrypted, versioned, access controlled
- [x] **Secrets not in code**: All secrets sourced from GCP Secret Manager
- [x] **Policy validation**: OPA policies enforced in CI
- [ ] **Team scaling**: Multiple teams can deploy simultaneously (pending state locking strategy)
- [ ] **Disaster recovery**: Infrastructure can be rebuilt from code in < 30 minutes (pending testing)
- [ ] **Cost visibility**: Monthly infrastructure cost visible and auditable (pending cost alerts)

---

## References

- [Terraform Documentation](https://www.terraform.io/docs/)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GCS Remote Backend](https://www.terraform.io/docs/language/settings/backends/gcs.html)
- [GCP Secret Manager Integration](https://www.terraform.io/docs/providers/google/d/secret_manager_secret_version.html)
- [OPA/Conftest for Policy](https://www.conftest.dev/)
- [OWASP: Infrastructure as Code Security](https://owasp.org/www-community/Infrastructure_as_Code_Insecurities)

---

## Sign-off

- [x] Technical review: @kushin77
- [x] Security review: @kushin77
- [x] Operations review: @kushin77
- [x] Architecture consensus: @kushin77