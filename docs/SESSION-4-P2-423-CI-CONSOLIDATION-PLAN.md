# P2 #423: CI Workflow Consolidation - Execution Plan

**Status**: IN PROGRESS  
**Priority**: P2 🟡 HIGH  
**Target**: Consolidate 28+ workflows → clean SSOT set  
**Timeline**: 4 hours execution  

---

## CURRENT STATE - 28 WORKFLOWS (DUPLICATES & OVERLAPS)

### Core CI/CD (Essential - Keep & Consolidate)
- `ci.yml` - Main CI pipeline
- `terraform-apply.yml` - Terraform deployment
- `terraform-validate.yml` - Terraform validation (from Session 3)
- `terraform-plan.yml` - Terraform planning (from Session 3)
- `security.yml` - Security scanning
- `pr-quality-gates.yml` - PR checks

### Governance/Policy (Overlapping - Consolidate to 1)
- `governance.yml` - Policy enforcement
- `governance-enforcement.yml` - DUPLICATE/OVERLAP
- `governance-report.yml` - DUPLICATE/OVERLAP
- `iac-governance.yml` - OVERLAP with governance.yml
- `enforce-priority-labels.yml` - Subset of governance
- `information-architecture-gate.yml` - MERGE into governance

### Security (Overlapping - Keep 1)
- `security.yml` - Main security
- `security-gate-required.yml` - DUPLICATE

### Deployment (Overlapping - Consolidate)
- `deploy.yml` - Main deployment
- `deploy-primary.yml` - DUPLICATE/SUBSET
- `deploy-replica.yml` - DUPLICATE/SUBSET
- `post-merge-cleanup-deploy.yml` - MERGE into deploy.yml

### Monitoring/Operational (Low Priority - Archive)
- `cost-monitoring.yml` - P3, archive
- `dns-monitor.yml` - P3, archive
- `godaddy-registrar-monitor.yml` - P3, archive
- `dagger-cicd-pipeline.yml` - DUPLICATE/TEST

### QA/Quality Gates (Overlapping - Consolidate)
- `pr-quality-gates.yml` - Main QA
- `qa-coverage-gates.yml` - SUBSET/OVERLAP
- `shell-lint.yml` - MERGE into QA
- `validate-linux-only.yml` - MERGE into QA

---

## CONSOLIDATION STRATEGY

### Target: 6-8 Essential Workflows (from 28)

**GROUP 1: CI VALIDATION (ci-validate.yml)**
- Merge: `ci.yml`, `shell-lint.yml`, `validate-linux-only.yml`
- Purpose: Syntax, lint, format validation for all PRs
- Trigger: PR open/update, push to main

**GROUP 2: TERRAFORM (terraform.yml)**
- Merge: `terraform-validate.yml`, `terraform-plan.yml`, `terraform-apply.yml`
- Purpose: Unified terraform workflow with approval gates
- Trigger: Terraform file changes, manual trigger

**GROUP 3: SECURITY (security.yml) - KEEP**
- Merge: `security.yml`, `security-gate-required.yml`
- Purpose: SAST, dependency scanning, vulnerability checks
- Trigger: PR open/update, push to main

**GROUP 4: QUALITY GATES (quality-gates.yml)**
- Merge: `pr-quality-gates.yml`, `qa-coverage-gates.yml`
- Purpose: Code coverage, test coverage, quality thresholds
- Trigger: PR open/update

**GROUP 5: GOVERNANCE (governance.yml)**
- Merge: `governance.yml`, `governance-enforcement.yml`, `governance-report.yml`, `iac-governance.yml`, `enforce-priority-labels.yml`, `information-architecture-gate.yml`
- Purpose: Policy compliance, label enforcement, reporting
- Trigger: PR open/update, issue created

**GROUP 6: DEPLOYMENT (deploy.yml)**
- Merge: `deploy.yml`, `deploy-primary.yml`, `deploy-replica.yml`, `post-merge-cleanup-deploy.yml`
- Purpose: Unified deployment with approval gates, primary/replica support
- Trigger: Manual trigger with approval, tag push

**ARCHIVE (Move to .github/workflows/archived/)**
- `cost-monitoring.yml` - P3 work
- `dns-monitor.yml` - P3 work
- `godaddy-registrar-monitor.yml` - P3 work
- `dagger-cicd-pipeline.yml` - Test/duplicate

---

## IMPLEMENTATION STEPS

### Step 1: Create Consolidated Workflows (2 hours)
- [ ] ci-validate.yml (linting, format, syntax)
- [ ] terraform.yml (unified validate → plan → apply)
- [ ] security.yml (enhanced with all security checks)
- [ ] quality-gates.yml (coverage + thresholds)
- [ ] governance.yml (complete policy enforcement)
- [ ] deploy.yml (unified deployment with approval)

### Step 2: Archive Old Workflows (30 min)
- [ ] Create .github/workflows/archived/ directory
- [ ] Move 4 P3 workflows to archive
- [ ] Keep archive workflows as reference

### Step 3: Remove Duplicates (30 min)
- [ ] Delete old ci.yml, terraform-*.yml, deploy-*.yml
- [ ] Verify no broken references
- [ ] Test workflow syntax

### Step 4: Test Consolidation (1 hour)
- [ ] Trigger all 6 consolidated workflows manually
- [ ] Verify each executes correctly
- [ ] Check all approval gates work
- [ ] Verify logging and reporting

### Step 5: Documentation & Closure (30 min)
- [ ] Create WORKFLOWS.md with consolidated workflow guide
- [ ] Document approval gates and triggers
- [ ] Update CONTRIBUTING.md with CI/CD flow
- [ ] Close P2 #423 on GitHub

---

## CONSOLIDATED WORKFLOW SPECIFICATIONS

### ci-validate.yml (PR Validation)
```yaml
name: CI Validation
on:
  pull_request:
    types: [opened, synchronize, reopened]
  push:
    branches: [main, develop]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      # Shell lint
      - uses: shellcheck-py/shellcheck-py@v1
      # YAML lint
      - uses: ibiqlik/action-yamllint@v3
      # Terraform format
      - uses: terraform-linters/tflint@v4
      # Markdown lint
      - uses: nosborn/github-action-markdown-cli@v3.3.0
```

### terraform.yml (IaC Validation & Deployment)
```yaml
name: Terraform
on:
  push:
    paths: ['terraform/**']
    branches: [main]
  pull_request:
    paths: ['terraform/**']
  workflow_dispatch:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - terraform fmt -check
      - terraform validate
      - terraform plan -var-file=production.tfvars

  apply:
    needs: validate
    if: github.event_name == 'push'
    environment:
      name: production
      required_reviewers: ['@kushin77']
    steps:
      - terraform apply -auto-approve -var-file=production.tfvars
```

### security.yml (Security Scanning)
```yaml
name: Security
on:
  pull_request:
    types: [opened, synchronize]
  push:
    branches: [main]

jobs:
  sast:
    runs-on: ubuntu-latest
    steps:
      - uses: ShiftLeftSecurity/scan-action@master
      
  dependency-check:
    runs-on: ubuntu-latest
    steps:
      - uses: dependency-check/Dependency-Check_Action@main
      
  container-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: aquasecurity/trivy-action@master
```

### quality-gates.yml (Coverage & Thresholds)
```yaml
name: Quality Gates
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: codecov/codecov-action@v3
        with:
          fail_ci_if_error: true
          minimum_coverage: 85
          
  metrics:
    runs-on: ubuntu-latest
    steps:
      - uses: dorny/test-reporter@v1
        with:
          name: Test Coverage Report
          path: coverage/report.json
```

### governance.yml (Policy Enforcement)
```yaml
name: Governance
on:
  pull_request:
    types: [opened, synchronize, labeled, unlabeled]
  issues:
    types: [opened, labeled]
  push:
    branches: [main]

jobs:
  labels:
    runs-on: ubuntu-latest
    steps:
      - name: Enforce Priority Labels
        if: github.event_name == 'pull_request'
        run: |
          labels=$(gh pr view --json labels -q '.labels[].name' $PR_NUMBER)
          if ! echo "$labels" | grep -qE 'P[0-3]'; then
            echo "ERROR: PR must have priority label (P0-P3)"
            exit 1
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          
  policy-check:
    runs-on: ubuntu-latest
    steps:
      - uses: instrumenta/conftest-action@master
        with:
          files: terraform/
          policy: policy/opa/
```

### deploy.yml (Production Deployment)
```yaml
name: Deploy
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      target:
        description: 'Deployment target (primary/replica/both)'
        required: true
        default: 'primary'

jobs:
  approve:
    runs-on: ubuntu-latest
    environment:
      name: production
      required_reviewers: ['@kushin77']
    steps:
      - name: Deployment approved
        run: echo "Deployment approved for ${{ github.event.inputs.target || 'primary' }}"

  deploy:
    needs: approve
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy Primary
        if: ${{ inputs.target == 'primary' || inputs.target == 'both' }}
        run: |
          ssh akushnir@192.168.168.31 "cd code-server-enterprise && docker-compose up -d"
          
      - name: Deploy Replica
        if: ${{ inputs.target == 'replica' || inputs.target == 'both' }}
        run: |
          ssh akushnir@192.168.168.42 "cd code-server-enterprise && docker-compose up -d"
```

---

## BENEFITS

✅ **Reduced Complexity**: 28 workflows → 6 consolidated  
✅ **No Duplicates**: SSOT for each purpose  
✅ **Easier Maintenance**: Single file per function  
✅ **Clear Intent**: Easy to understand trigger/action flow  
✅ **Better Performance**: Fewer redundant jobs  
✅ **Improved Debugging**: Consolidated logs  
✅ **Consistent Naming**: Clear workflow purposes  

---

## ACCEPTANCE CRITERIA

- [ ] All 6 consolidated workflows created
- [ ] Old duplicate workflows archived
- [ ] All workflows tested and passing
- [ ] No broken references in repository
- [ ] Approval gates working for sensitive workflows
- [ ] Documentation updated (WORKFLOWS.md)
- [ ] CONTRIBUTING.md updated with CI/CD flow
- [ ] P2 #423 closed on GitHub

---

## RISK MITIGATION

**Risk**: Deployment workflows break  
**Mitigation**: Test in staging first, keep old deploy.yml as backup until verified

**Risk**: Governance policies fail**  
**Mitigation**: Run governance checks in non-blocking mode first

**Risk**: Missing workflows after cleanup  
**Mitigation**: Archive all removed workflows (not delete) for recovery

---

## TIMELINE

- **Hour 1**: Create consolidated workflows (ci-validate, terraform)
- **Hour 2**: Create remaining workflows (security, quality, governance, deploy)
- **Hour 3**: Test all workflows, fix issues
- **Hour 4**: Archive old workflows, document, close issue

---

## NEXT STEPS AFTER P2 #423

1. P2 #419: Alert rule consolidation (SSOT for SLO)
2. P2 #430: Kong hardening
3. P2 #425: Container hardening
4. P2 #421: Script sprawl elimination (263 scripts)

---

*P2 #423 Execution Plan - Ready for Implementation*
