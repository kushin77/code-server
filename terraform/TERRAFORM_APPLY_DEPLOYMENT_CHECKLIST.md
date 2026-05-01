# Terraform Apply & Deployment Checklist

**Phase**: Infrastructure Deployment (Post-Code-Review Remediation)  
**Date**: April 30, 2026  
**Status**: Ready for Execution  
**Ref**: IaC Code Review - 9 Findings Resolved

---

## Objective

Deploy the fixed Terraform infrastructure code (commit 9668d9a4) to both cluster nodes (primary: 192.168.168.31, replica: 192.168.168.42). Validate all 82 containers (41 per host) start cleanly with new configurations.

---

## Pre-Deployment Checklist

- [ ] **Verify Git Branch**: Confirm all fixes committed to fix/domain-variability-caddy
  - Command: `git log -1 --oneline | grep "fix(terraform)"`
  - Expected: Shows commit 9668d9a4

- [ ] **Terraform Validate**: Re-run validation in terraform/environments/private
  - Command: `cd terraform/environments/private && terraform validate`
  - Expected: "Success! The configuration is valid."

- [ ] **Review Changes**: Inspect terraform plan to understand resource updates
  - Command: `terraform plan -out=tfplan`
  - Verify: All 82 containers accounted for, no surprise deletions

- [ ] **Secrets Configuration**: Prepare TF_VAR_* environment variables
  - Variables needed: db_password, grafana_admin_password, oauth2_client_secret, qdrant_api_key, scheduler_api_key, oauth2_cookie_secret
  - Source: Load from GCP Secret Manager or .env.secrets (gitignored)

---

## Deployment Execution

### Task 1: Deploy to Primary Host (192.168.168.31)

- [ ] SSH into primary host with Docker socket access
  - Command: `ssh -i ~/.ssh/code-server-deploy ubuntu@192.168.168.31`

- [ ] Run terraform apply with secrets injected
  - Command: `cd terraform/environments/private && TF_VAR_db_password="..." terraform apply -var-file=terraform.tfvars -target=module.stack_primary`
  - Expected: Outputs showing 41 containers starting

- [ ] Validate container startup
  - Command: `docker ps --filter "label=io.elevatediq.project=code-server" | wc -l`
  - Expected: 41 containers running

- [ ] Health check: Verify critical services
  - Prometheus: `curl -s http://localhost:9090/-/healthy`
  - Grafana: `curl -s http://localhost:3000/api/health`
  - PostgreSQL: `pg_isready -h postgres -U postgres -d postgres`

### Task 2: Deploy to Replica Host (192.168.168.42)

- [ ] SSH into replica host
  - Command: `ssh -i ~/.ssh/code-server-deploy ubuntu@192.168.168.42`

- [ ] Run terraform apply for replica
  - Command: `cd terraform/environments/private && TF_VAR_db_password="..." terraform apply -var-file=terraform.tfvars -target=module.stack_replica`
  - Expected: Outputs showing 41 containers starting on replica

- [ ] Validate replica container startup
  - Command: `docker ps --filter "label=io.elevatediq.project=code-server" | wc -l`
  - Expected: 41 containers running

- [ ] Verify HA replication (PostgreSQL)
  - Primary: `psql -U postgres -h postgres -c "SELECT pg_is_wal_replay_paused()"`
  - Replica: Should show standby mode active

---

## Post-Deployment Validation

- [ ] **Service Connectivity**: All inter-service communications working
  - Agents can reach reputation-engine (http://code-server-reputation-engine:9050)
  - Alert-relay connects to alertmanager (http://code-server-alertmanager:9093)

- [ ] **Data Persistence**: Volumes mounted correctly on both hosts
  - Command: `docker inspect code-server-postgres | grep -A5 Mounts`
  - Verify: 13 volumes present on primary, 13 on replica

- [ ] **Observability Stack**: Metrics and logs flowing
  - Prometheus targets: `curl http://localhost:9090/api/v1/targets | grep "\"health\""`
  - Loki logs ingesting: Check Grafana datasources health

- [ ] **Alert Relay**: Configured and operational
  - Check container: `docker ps | grep alert-relay`
  - Verify env vars: `docker inspect code-server-alert-relay | grep -E "SLACK_WEBHOOK|SMTP_HOST|PAGERDUTY"`

---

## Rollback Plan (If Needed)

- [ ] **Destroy Infrastructure** (full rollback)
  - Command: `terraform destroy -target=module.stack_primary -target=module.stack_replica`
  - Warning: This will stop all 82 containers

- [ ] **Selective Rollback** (specific container)
  - Command: `terraform destroy -target=docker_container.alert_relay`
  - Use for isolated fixes

---

## Sign-Off

- [ ] **Primary Host Deployment**: ✓ Complete (Date: ___)
- [ ] **Replica Host Deployment**: ✓ Complete (Date: ___)
- [ ] **All Validations Passed**: ✓ Complete (Date: ___)
- [ ] **Production Ready**: ✓ Approved (Date: ___)

---

## Additional Notes

**Governance**: 
- All containers remain prefixed with `code-server-*`
- No shared resources modified (isolated namespace)
- Terraform is authoritative source for IaC

**Documentation**:
- Code review findings: [IaC Code Review Report](../CODE_REVIEW_INFRASTRUCTURE_VALIDATION.md)
- Remediation commit: 9668d9a4
- Previous fixes: Secrets removed, alert-relay added, healthchecks improved, SSH hardened

**Contact**: Infrastructure team for any blockers or questions
