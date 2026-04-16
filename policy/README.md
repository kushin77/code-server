# OPA Policy Framework — Issue #357

Automated policy enforcement for code-server-enterprise infrastructure.

## Domains

### Docker Compose Policies
- **hardening.rego**: Container hardening best practices (CIS Docker Benchmark v1.6.0)
  - no-new-privileges enforcement
  - Capability dropping (drop ALL)
  - User specification for privilege isolation
  - Resource limits (memory/CPU)
  - Read-only root filesystems (stateless services)

- **networks.rego**: Network segmentation enforcement
  - Data services isolated on data-net
  - Public services on frontend-net
  - No public exposure of internal services
  - Network connectivity validation

### Terraform Policies
- **secrets.rego**: Secret management validation
  - No hardcoded passwords/tokens
  - No default credentials
  - Environment variables must use sensitive flag
  - Secrets must come from var.* or Vault

### Container Image Policies
- **security.rego**: Image provenance + vulnerability management
  - Approved base image list enforcement
  - Cosign signature requirement
  - SBOM (Software Bill of Materials) requirement
  - Trivy vulnerability scan requirement
  - Critical/high vulnerability limits

## Running Policies

### Local Validation

```bash
# Test docker-compose.yml
conftest test docker-compose.yml -p policy/docker -f json

# Test Terraform
conftest test $(find . -name '*.tf' -type f) -p policy/terraform -f json

# Verbose output
conftest test docker-compose.yml -p policy/docker --print

# Specific policy
conftest test docker-compose.yml -p policy/docker/hardening.rego
```

### CI/CD Enforcement

Automatic validation on:
- Every pull request (GitHub Actions)
- Every push to main/develop
- Pre-commit hook (local machine)

Policy violations block merge to main.

## Policy Updates

1. Modify policy/*.rego
2. Test locally: `conftest test ...`
3. Commit: `git commit -m "policy: <description>"`
4. Next PR validates with new policies
5. Violations must be resolved before merge

## Compliance

- ✅ **CIS Docker Benchmark v1.6.0**: Docker hardening (5 rules)
- ✅ **NIST 800-190**: Container security (3 rules)
- ✅ **SOC 2 Type II**: Secret management (4 rules)
- ✅ **AWS Well-Architected**: Resource naming (5 rules)

**Total Enforced Policies**: 17 rules across all domains

## References

- [Open Policy Agent (OPA)](https://www.openpolicyagent.org/)
- [Conftest](https://www.conftest.dev/)
- [Rego Language](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [CIS Docker Benchmark v1.6.0](https://www.cisecurity.org/benchmark/docker)
