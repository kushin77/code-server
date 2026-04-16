---
# P2 #418: Terraform Module Refactoring — Implementation Plan
## Convert Flat 37-File Structure → Composable Modules with Primary/Replica Support

---

## 📋 EXECUTION PLAN

### Phase 1: Module Structure Setup (Current)
- [x] Create modules/ directory hierarchy
- [x] Create module subdirectories: core, data, monitoring, networking, security, dns, failover
- [ ] Create module templates (variables.tf, main.tf, outputs.tf)
- [ ] Document file mapping

### Phase 2: File Consolidation (This Session)
- [ ] Move core service files to `modules/core/`
- [ ] Move database files to `modules/data/`
- [ ] Move observability files to `modules/monitoring/`
- [ ] Move gateway/proxy files to `modules/networking/`
- [ ] Move security/hardening files to `modules/security/`
- [ ] Move Cloudflare/DNS files to `modules/dns/`
- [ ] Move replication/backup files to `modules/failover/`

### Phase 3: Root Module Composition (This Session)
- [ ] Create new root main.tf with module blocks
- [ ] Remove/move variable-only files (compute.tf, network.tf, database.tf, monitoring.tf, dns.tf)
- [ ] Add primary/replica differentiation logic
- [ ] Add terraform-docs configuration

### Phase 4: Testing & Validation (Next Session)
- [ ] Run `terraform plan -var-file=production.tfvars`
- [ ] Run `terraform plan -var-file=replica.tfvars`
- [ ] Validate each module independently
- [ ] Test full stack composition

---

## 🗂️ MODULE STRUCTURE & FILE MAPPING

### modules/core/ — Docker Services (code-server, Caddy, OAuth2-proxy)
**Purpose**: Core application services  
**Files to Include**:
- New: main.tf (docker-compose management, service configuration)
- New: variables.tf (service ports, versions, resources)
- New: outputs.tf (service endpoints, health checks)
**Source Files** (to consolidate):
- (None directly; Terraform doesn't manage Docker services — use docker-compose)
- Or: Create docker_image, docker_container resources for Terraform-managed deployment

**Decision**: Docker services currently managed via docker-compose.yml (IaC-compliant). Keep as-is. Module template created for future native Terraform deployment if needed.

---

### modules/data/ — PostgreSQL, Redis, PgBouncer
**Purpose**: Data tier (databases, caching, connection pooling)  
**Files to Include**:
- New: main.tf (PostgreSQL provisioning, replication setup)
- New: replication.tf (Primary/replica failover logic)
- New: variables.tf (DB names, users, replication params)
- New: outputs.tf (connection strings, replica endpoints)
**Source Files** (to consolidate):
- `database.tf` → Merge into variables.tf (currently only has variable definitions)
- `phase-9d-disaster-recovery.tf` → Extract replication-specific logic → replication.tf
- New content: PostgreSQL Terraform provisioning (currently via docker-compose/scripts)

---

### modules/monitoring/ — Prometheus, Grafana, AlertManager, Jaeger, Loki
**Purpose**: Observability stack  
**Files to Include**:
- New: main.tf (monitoring service provisioning)
- New: dashboards.tf (Grafana dashboards, data sources)
- New: alert-rules.tf (Prometheus recording/alerting rules) ← **Single source of truth**
- New: variables.tf (retention, targets, SLOs)
- New: outputs.tf (dashboard URLs, Prometheus endpoints)
**Source Files** (to consolidate):
- `monitoring.tf` → Merge into variables.tf
- `phase-9b-prometheus-slo.tf` → alert-rules.tf
- `phase-9b-loki-logs.tf` → main.tf
- `phase-9b-jaeger-tracing.tf` → main.tf
- Alert rules currently in `config/prometheus/` → Should be generated from alert-rules.tf

---

### modules/networking/ — Caddy, Kong, CoreDNS, Network Policies
**Purpose**: Ingress, routing, network isolation  
**Files to Include**:
- New: main.tf (network policy provisioning, CoreDNS setup)
- New: caddy.tf (Caddy reverse proxy configuration)
- New: kong.tf (Kong API Gateway configuration)
- New: variables.tf (ports, routing rules, network CIDR)
- New: outputs.tf (gateway endpoints, network details)
**Source Files** (to consolidate):
- `network.tf` → Merge into variables.tf
- `cloudflare.tf` → Move logic to dns module (DNS-focused)
- `phase-9c-kong-gateway.tf` → kong.tf
- `phase-9c-kong-routing.tf` → kong.tf (merge with above)
- New: Caddy provisioning rules

---

### modules/security/ — Falco, OPA, Vault, OS Hardening, Egress Filtering
**Purpose**: Runtime security, policy, secrets, OS hardening  
**Files to Include**:
- New: main.tf (security service provisioning)
- New: falco.tf (Falco runtime security rules, deployment)
- New: vault.tf (HashiCorp Vault setup, secret rotation)
- New: opa.tf (Open Policy Agent policies, enforcement)
- New: variables.tf (security policies, key rotation intervals, audit levels)
- New: outputs.tf (Vault endpoints, policy endpoints)
**Source Files** (to consolidate):
- `phase-8-cis-hardening.tf` → main.tf (CIS benchmark implementation)
- `phase-8-container-hardening.tf` → main.tf (container security)
- `phase-8-falco.tf` → falco.tf
- `phase-8b-falco-runtime-security.tf` → falco.tf (merge)
- `phase-8-opa-policies.tf` → opa.tf
- `phase-8-os-hardening.tf` → main.tf
- `phase-8-vault-production.tf` → vault.tf
- `phase-8-vault-secrets-rotation.tf` → vault.tf (merge)
- `phase-8-egress-filtering.tf` → main.tf
- `phase-9-egress-filtering.tf` → main.tf (merge)
- `phase-8-supply-chain-security.tf` → supply-chain.tf
- `phase-8b-supply-chain-security.tf` → supply-chain.tf (merge)
- `phase-8-secrets-management.tf` → vault.tf (merge)

---

### modules/dns/ — Cloudflare Tunnel, Cloudflare WAF, DNS Failover
**Purpose**: Domain, DNS, edge security  
**Files to Include**:
- New: main.tf (DNS configuration, failover setup)
- New: cloudflare.tf (Cloudflare tunnel, WAF rules)
- New: variables.tf (domain, DNS providers, tunnel config)
- New: outputs.tf (DNS records, tunnel endpoints)
**Source Files** (to consolidate):
- `dns.tf` → Merge into variables.tf
- `cloudflare.tf` → cloudflare.tf
- `godaddy-dns.tf` → main.tf (secondary DNS provider logic)
- New: DNS failover (GoDaddy, Cloudflare automatic failover)

---

### modules/failover/ — Replication, Disaster Recovery, Backups
**Purpose**: High availability, disaster recovery, backup automation  
**Files to Include**:
- New: main.tf (failover infrastructure provisioning)
- New: replication.tf (PostgreSQL replication, Patroni, Redis Sentinel)
- New: backup.tf (Backup scheduling, retention, restore procedures)
- New: variables.tf (replication lag limits, RTO, RPO, backup retention)
- New: outputs.tf (replica endpoints, backup locations)
**Source Files** (to consolidate):
- `phase-9d-backup.tf` → backup.tf
- `phase-9d-disaster-recovery.tf` → replication.tf + main.tf
- New: Patroni/HA Proxy setup (currently in docker-compose)
- New: Redis Sentinel configuration (currently in docker-compose)
- New: Backup automation Terraform (currently shell scripts)

---

## 🚀 ROOT MODULE COMPOSITION

### New: terraform/main.tf (Root Module)
```hcl
# Compose all child modules

module "core" {
  source = "./modules/core"
  
  host_ip       = var.host_ip
  domain        = var.domain
  code_server_port = var.code_server_port
}

module "data" {
  source = "./modules/data"
  
  is_primary       = var.is_primary
  replica_host_ip  = var.replica_host_ip
  postgres_version = var.postgres_version
  postgres_memory  = var.postgres_memory
}

module "monitoring" {
  source = "./modules/monitoring"
  
  prometheus_retention = var.prometheus_retention
  grafana_port = var.grafana_port
  slo_availability_target = var.slo_availability_target
}

module "networking" {
  source = "./modules/networking"
  
  domain          = var.domain
  kong_port       = var.kong_port
  caddy_tls_email = var.caddy_tls_email
}

module "security" {
  source = "./modules/security"
  
  falco_enabled    = var.falco_enabled
  vault_enabled    = var.vault_enabled
  opa_enabled      = var.opa_enabled
  cis_hardening    = var.cis_hardening
}

module "dns" {
  source = "./modules/dns"
  
  domain              = var.domain
  cloudflare_api_token = var.cloudflare_api_token
  godaddy_api_key     = var.godaddy_api_key
}

module "failover" {
  source = "./modules/failover"
  
  is_primary       = var.is_primary
  replica_host_ip  = var.replica_host_ip
  backup_retention_days = var.backup_retention_days
}

output "core_services" {
  value = module.core.service_endpoints
}

output "data_endpoints" {
  value = module.data.database_endpoints
}

output "monitoring_dashboards" {
  value = module.monitoring.dashboard_urls
}

output "networking_endpoints" {
  value = module.networking.gateway_endpoints
}
```

### Updated: terraform/variables.tf (Root Variables)
```hcl
# Global input variables referenced by root main.tf

variable "host_ip" {
  description = "Primary host IP (192.168.168.31)"
  type        = string
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.host_ip))
    error_message = "Must be a valid IP address."
  }
}

variable "is_primary" {
  description = "Is this the primary host (true) or replica (false)?"
  type        = bool
  default     = false
}

variable "replica_host_ip" {
  description = "Replica host IP (192.168.168.42)"
  type        = string
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.replica_host_ip))
    error_message = "Must be a valid IP address."
  }
}

variable "domain" {
  description = "Primary domain (ide.kushnir.cloud)"
  type        = string
  validation {
    condition     = can(regex("^([a-z0-9]+(-[a-z0-9]+)*\\.)+[a-z]{2,}$", var.domain))
    error_message = "Must be a valid domain name."
  }
}

# ... more variables for each module
```

### Updated: terraform/production.tfvars (Primary Host)
```hcl
# production.tfvars — Primary host (192.168.168.31)

host_ip         = "192.168.168.31"
is_primary      = true
replica_host_ip = "192.168.168.42"
domain          = "ide.kushnir.cloud"

# Data tier
postgres_version = "15.6-alpine"
postgres_memory  = "2g"

# Networking
kong_port = 8000

# Monitoring
prometheus_retention = "30d"
grafana_port         = 3000
slo_availability_target = 99.99

# DNS
cloudflare_api_token = "..."  # From GSM

# Failover
backup_retention_days = 30
```

### New: terraform/replica.tfvars (Replica Host)
```hcl
# replica.tfvars — Replica host (192.168.168.42)

host_ip         = "192.168.168.42"
is_primary      = false
primary_host_ip = "192.168.168.31"  # Replicate FROM primary
domain          = "ide.kushnir.cloud"

# ... rest similar to production.tfvars
```

---

## 📦 FILE MIGRATION MAPPING

### DELETE (Variable-only files with zero resources):
- [ ] `compute.tf` → Move variables to modules/**/variables.tf
- [ ] `network.tf` → Move variables to modules/**/variables.tf  
- [ ] `database.tf` → Move variables to modules/data/variables.tf
- [ ] `monitoring.tf` → Move variables to modules/monitoring/variables.tf
- [ ] `dns.tf` → Move variables to modules/dns/variables.tf
- [ ] `compliance-validation.tf` → Either implement resources or delete

### MOVE TO modules/core/:
- (None directly; core is Docker-managed)

### MOVE TO modules/data/:
- (None to move; PostgreSQL provisioning not currently in Terraform)

### MOVE TO modules/monitoring/:
- [ ] `phase-9b-prometheus-slo.tf` → alert-rules.tf
- [ ] `phase-9b-loki-logs.tf` → main.tf
- [ ] `phase-9b-jaeger-tracing.tf` → main.tf

### MOVE TO modules/networking/:
- [ ] `phase-9c-kong-gateway.tf` → kong.tf
- [ ] `phase-9c-kong-routing.tf` → kong.tf (merge)

### MOVE TO modules/security/:
- [ ] `phase-8-*.tf` (8 files) → Respective files (falco.tf, vault.tf, opa.tf, etc)
- [ ] `phase-8b-*.tf` (3 files) → Merge with corresponding phase-8 files
- [ ] `phase-9-egress-filtering.tf` → main.tf

### MOVE TO modules/dns/:
- [ ] `cloudflare.tf` → cloudflare.tf
- [ ] `godaddy-dns.tf` → main.tf

### MOVE TO modules/failover/:
- [ ] `phase-9d-backup.tf` → backup.tf
- [ ] `phase-9d-disaster-recovery.tf` → replication.tf + main.tf

### KEEP AT ROOT:
- [x] `main.tf` → REPLACE with new root composition
- [x] `variables.tf` → KEEP as global variables
- [x] `locals.tf` → KEEP (used across modules)
- [ ] `users.tf` → MOVE to modules/security/ or delete
- [ ] `backend-s3.tf` → KEEP at root (backend config)
- [ ] `backend-config.hcl` → KEEP at root
- [x] `production.tfvars` → KEEP (primary host)
- [x] `staging.tfvars` → KEEP or rename to replica.tfvars
- [x] `README.md` → UPDATE with module documentation
- [x] `README-DEPLOYMENT.md` → KEEP (deployment guide)

---

## 🔍 VARIABLE DEFINITION LOCATIONS

### Root (terraform/variables.tf):
- `host_ip`, `is_primary`, `replica_host_ip`, `domain`
- `deploy_env`, `region`, `acme_email`

### modules/core/variables.tf:
- `code_server_port`, `code_server_memory`, `code_server_version`
- `caddy_port_http`, `caddy_port_https`, `caddy_version`
- `oauth_provider`, `oauth_callback_url`

### modules/data/variables.tf:
- `postgres_version`, `postgres_memory`, `postgres_user`
- `redis_version`, `redis_memory`, `replication_lag_limit_ms`
- `pgbouncer_max_connections`, `pgbouncer_pool_mode`

### modules/monitoring/variables.tf:
- `prometheus_retention`, `prometheus_scrape_interval`
- `grafana_port`, `grafana_memory`
- `slo_availability_target`, `slo_p99_latency_target`
- `alert_notification_channels` (Slack, PagerDuty, email)

### modules/networking/variables.tf:
- `kong_port`, `kong_rate_limit_minute`, `kong_admin_listen`
- `caddy_tls_email`, `caddy_auto_https`, `caddy_trusted_proxies`
- `coredns_port`, `network_policy_rules`

### modules/security/variables.tf:
- `falco_enabled`, `falco_rulesfile_url`
- `vault_enabled`, `vault_version`, `vault_unseal_keys`
- `opa_enabled`, `cis_hardening`, `selinux_mode`
- `rbac_enabled`, `audit_logging_enabled`

### modules/dns/variables.tf:
- `domain`, `cloudflare_api_token`, `cloudflare_zone_id`
- `godaddy_api_key`, `godaddy_api_secret`
- `dns_ttl`, `dns_failover_enabled`

### modules/failover/variables.tf:
- `is_primary`, `primary_host_ip`, `replica_host_ip`
- `backup_retention_days`, `backup_schedule_cron`
- `rto_seconds`, `rpo_seconds` (service level targets)
- `pgbouncer_connect_timeout`, `pgbouncer_idle_in_transaction_session_timeout`

---

## ⚡ IMPLEMENTATION SEQUENCE (This Session)

1. **Create module variable templates** (5 min)
2. **Consolidate Phase 8-9 files into modules** (45 min)
3. **Create root main.tf composition** (15 min)
4. **Update production.tfvars + create replica.tfvars** (10 min)
5. **Add terraform-docs configuration** (10 min)
6. **Test terraform plan** (10 min)
7. **Document in README** (10 min)
8. **Commit to GitHub** (5 min)

**Total Time**: ~110 minutes (1h 50min)  
**Not Started**: Actual resource implementation (terraform apply) — tested in next session

---

## ✅ ACCEPTANCE CRITERIA

- [ ] `terraform/` restructured into `modules/` hierarchy
- [ ] Root module (`main.tf`) composes child modules via `module` blocks
- [ ] Each module can be `plan`'d independently
- [ ] Zero duplicate resource definitions across modules
- [ ] `terraform plan -var-file=production.tfvars` succeeds
- [ ] `terraform plan -var-file=replica.tfvars` succeeds
- [ ] Variable-only files (`compute.tf`, `network.tf`, etc) deleted or consolidated
- [ ] `compliance-validation.tf` either has real resources or is deleted
- [ ] `terraform-docs` generates module documentation
- [ ] CI plan runs on PR for all changed modules

---

## 📚 REFERENCE DOCUMENTATION

- Terraform Modules Best Practices: https://developer.hashicorp.com/terraform/language/modules/develop
- terraform-docs: https://terraform-docs.io/
- Variable Validation: https://developer.hashicorp.com/terraform/language/values/variables#validation-rules

---

**Status**: PLAN DOCUMENTED  
**Ready for**: Execution in next phase  
**Effort**: ~2 hours (consolidation + testing)  
**Next Steps**: Start file consolidation and module creation
