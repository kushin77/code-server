# P2 #418: TERRAFORM MODULE REFACTORING — PHASE 2-5 EXECUTION GUIDE

**Status**: 🟡 **IN PROGRESS - PHASE 2 EXECUTION**  
**Date**: April 17, 2026  
**Branch**: phase-7-deployment  
**Objective**: Complete modularization from flat 37-file structure → 7 composable modules

---

## Executive Summary

**P2 #418** refactors Terraform from flat file organization to composable modules for:
- ✅ Improved maintainability (separation of concerns)
- ✅ Primary/replica deployment support
- ✅ Independent module testing
- ✅ Production-ready IaC

### Current Status

| Phase | Objective | Status | Effort |
|-------|-----------|--------|--------|
| **1** | Module structure setup | ✅ Complete | 1h |
| **2** | File consolidation into modules | 🟡 In Progress | 2-3h |
| **3** | Root module composition | ⏳ Planned | 1h |
| **4** | Validation (terraform plan) | ⏳ Planned | 30m |
| **5** | Testing & closure | ⏳ Planned | 1h |

---

## What Are The 7 Modules?

### 1. **modules/core/** — Docker Services (code-server, Caddy, OAuth2-proxy)
**Purpose**: Core application services  
**Critical For**: Code serving, reverse proxy, authentication  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- docker-compose.yml (code-server, caddy, oauth2-proxy services)
- Caddyfile (reverse proxy configuration)
- config/_base-config.env (service configuration)

**Phase 2 Tasks**:
1. [x] Create modules/core/variables.tf (service versions, ports, memory)
2. [x] Create modules/core/main.tf (service configuration)
3. [x] Create modules/core/outputs.tf (service endpoints)
4. [ ] Populate with actual service definitions
5. [ ] Add docker-compose integration

**Module Variables** (18 total):
- code_server_port (default: 8080)
- code_server_version (default: 4.115.0)
- code_server_memory (default: 1Gi)
- caddy_http_port (default: 80)
- caddy_https_port (default: 443)
- caddy_admin_port (default: 2019)
- caddy_auto_https (default: "on")
- caddy_tls_email (required for production)
- oauth2_proxy_version (default: 7.5.1)
- oauth2_proxy_port (default: 4180)
- oauth2_proxy_google_client_id (sensitive)
- oauth2_proxy_google_client_secret (sensitive)
- oauth2_proxy_session_secret (sensitive)
- oauth2_proxy_redis_connection_string (default: redis:6379)
- oauth2_proxy_rate_limit_per_second (default: 10)
- oauth2_proxy_memory (default: 256Mi)
- oauth2_proxy_cpu (default: 100m)
- domain (default: ide.kushnir.cloud)

**Module Outputs**:
- code_server_endpoint (http://localhost:8080)
- caddy_endpoint (https://...)
- oauth2_proxy_endpoint (port 4180)
- health_check_commands

---

### 2. **modules/data/** — PostgreSQL, Redis, PgBouncer
**Purpose**: Data tier (databases, caching, connection pooling)  
**Critical For**: Data persistence, caching, connection management  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- docker-compose.yml (postgres, redis, pgbouncer services)
- db/migrations/*.sql (database schemas)
- phase-5-replication.tf (replication configuration)
- phase-5b-failover.tf (failover logic)

**Phase 2 Tasks**:
1. [x] Create modules/data/variables.tf (DB config)
2. [x] Create modules/data/main.tf (PostgreSQL, Redis, PgBouncer setup)
3. [x] Create modules/data/outputs.tf (connection strings)
4. [ ] Populate with actual database definitions
5. [ ] Add replication logic (Patroni for HA)
6. [ ] Add Redis Sentinel for cache HA

**Module Variables** (31 total):
- postgres_version (default: 15)
- postgres_database (default: code_server_db)
- postgres_user (default: pguser)
- postgres_password (sensitive, required)
- postgres_port (default: 5432)
- postgres_memory (default: 2Gi)
- postgres_cpu (default: 500m)
- postgres_max_connections (default: 100)
- postgres_backup_schedule (default: "0 2 * * *")
- postgres_backup_retention_days (default: 30)
- postgres_replication_enabled (default: true)
- postgres_replication_slot_name (default: replication_slot)
- postgres_wal_keep_segments (default: 64)
- is_primary (default: true, controls replication role)
- primary_host_ip (required for replicas)
- replica_host_ip (required for primary HA setup)
- redis_version (default: 7)
- redis_port (default: 6379)
- redis_memory (default: 512Mi)
- redis_maxmemory (default: 512Mi)
- redis_maxmemory_policy (default: allkeys-lru)
- redis_persistence_enabled (default: true)
- redis_aof_fsync (default: everysec)
- pgbouncer_version (default: 1.18)
- pgbouncer_port (default: 6432)
- pgbouncer_pool_mode (default: transaction)
- pgbouncer_max_client_conn (default: 1000)
- pgbouncer_default_pool_size (default: 25)
- rto_minutes (default: 15, disaster recovery objective)
- rpo_seconds (default: 60, data loss tolerance)
- backup_enabled (default: true)

**Module Outputs**:
- postgres_connection_string
- postgres_replica_host
- redis_connection_string
- pgbouncer_connection_string
- backup_location
- replication_status

---

### 3. **modules/monitoring/** — Prometheus, Grafana, AlertManager, Loki, Jaeger
**Purpose**: Observability stack (metrics, logs, traces, alerts)  
**Critical For**: Visibility, alerting, SLO tracking  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- docker-compose.yml (prometheus, grafana, alertmanager, loki, jaeger)
- config/prometheus/*.yml (Prometheus config, rules)
- config/grafana/dashboards/*.json (dashboards)
- phase-9b-prometheus-slo.tf (SLO configuration)
- phase-9b-loki-logs.tf (log aggregation)
- phase-9b-jaeger-tracing.tf (distributed tracing)

**Phase 2 Tasks**:
1. [x] Create modules/monitoring/variables.tf (observability config)
2. [x] Create modules/monitoring/main.tf (service setup)
3. [x] Create modules/monitoring/outputs.tf (endpoints)
4. [ ] Populate with actual observability configuration
5. [ ] Add SLO tracking rules
6. [ ] Add dashboards and alerts

**Module Variables** (57 total, split into observability categories):
- **Prometheus** (12 vars): version, port, retention, scrape intervals, memory, CPU, etc.
- **Grafana** (8 vars): version, port, admin password, datasources, dashboards, etc.
- **AlertManager** (6 vars): version, port, routes, receivers, templates, etc.
- **Loki** (10 vars): version, port, retention, chunk size, storage, etc.
- **Jaeger** (8 vars): version, port, sampling, retention, storage, etc.
- **SLO** (15 vars): availability target, error budget, alert thresholds, notification channels, etc.

**Module Outputs**:
- prometheus_endpoint (http://localhost:9090)
- grafana_endpoint (http://localhost:3000)
- alertmanager_endpoint (http://localhost:9093)
- loki_endpoint (http://localhost:3100)
- jaeger_endpoint (http://localhost:16686)
- slo_status (availability metrics)
- dashboard_links

---

### 4. **modules/security/** — Falco, OPA, Vault, OS Hardening
**Purpose**: Runtime security, policy enforcement, secrets management  
**Critical For**: Threat detection, policy compliance, secret rotation  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- phase-8-falco.tf (runtime security)
- phase-8-opa-policies.tf (policy enforcement)
- phase-8-vault-production.tf (Vault setup)
- phase-8-cis-hardening.tf (CIS benchmarks)
- phase-8-container-hardening.tf (container security)

**Phase 2 Tasks**:
1. [x] Create modules/security/variables.tf (security config)
2. [x] Create modules/security/main.tf (security services)
3. [x] Create modules/security/outputs.tf (endpoints)
4. [ ] Populate with Falco rules
5. [ ] Populate with OPA policies
6. [ ] Populate with Vault configuration
7. [ ] Add hardening baseline

**Module Variables** (23 total):
- falco_version (default: 0.36.0)
- falco_rules_version (default: 0.36.0)
- falco_sidekick_version (default: 0.30.0)
- falco_log_level (default: info)
- falco_output_stdout (default: true)
- opa_version (default: 0.61.0)
- conftest_version (default: 0.50.0)
- opa_log_level (default: info)
- opa_policy_storage_path (default: /etc/opa/policies)
- vault_version (default: 1.15.0)
- vault_port (default: 8200)
- vault_tls_enabled (default: true)
- vault_seal_type (default: shamir, cloud-kms for production)
- vault_audit_logging_enabled (default: true)
- vault_audit_log_path (default: /var/log/vault/audit.log)
- vault_rbac_enabled (default: true)
- vault_policy_files_path (default: /etc/vault/policies)
- apparmor_enabled (default: true)
- seccomp_enabled (default: true)
- selinux_enabled (default: false)
- cis_benchmark_enabled (default: true)
- encryption_at_rest_enabled (default: true)
- secret_rotation_interval_days (default: 90)

**Module Outputs**:
- falco_alerts_endpoint
- opa_policy_endpoint
- vault_api_endpoint
- vault_ui_endpoint
- security_policy_status

---

### 5. **modules/networking/** — Caddy, Kong, CoreDNS
**Purpose**: Ingress, API gateway, network policies  
**Critical For**: Service routing, API management, DNS resolution  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- docker-compose.yml (kong, coredns)
- config/kong/db.yml (Kong configuration)
- phase-9c-kong-gateway.tf (Kong setup)
- Caddyfile (reverse proxy)

**Phase 2 Tasks**:
1. [x] Create modules/networking/variables.tf (network config)
2. [x] Create modules/networking/main.tf (gateway setup)
3. [x] Create modules/networking/outputs.tf (endpoints)
4. [ ] Populate with Kong configuration
5. [ ] Populate with CoreDNS rules
6. [ ] Add load balancing rules

**Module Variables** (28 total):
- kong_version (default: 3.4.0)
- kong_admin_api_port (default: 8001)
- kong_proxy_port (default: 8000)
- kong_proxy_ssl_port (default: 8443)
- kong_postgres_version (default: 15)
- kong_database_host (default: postgres)
- kong_log_level (default: notice)
- kong_rate_limit_per_minute (default: 60)
- coredns_version (default: 1.10.0)
- coredns_port (default: 53)
- coredns_zones_path (default: /etc/coredns)
- coredns_log_level (default: info)
- caddy_port (default: 80)
- caddy_tls_port (default: 443)
- caddy_email (required for Let's Encrypt)
- load_balancer_algorithm (default: least_conn)
- load_balancer_enabled (default: true)
- network_policy_enabled (default: true)
- network_policy_default_deny (default: true)
- health_check_interval (default: 10s)
- health_check_timeout (default: 5s)
- health_check_unhealthy_threshold (default: 3)
- health_check_healthy_threshold (default: 2)
- max_connections (default: 10000)
- connection_timeout (default: 30s)
- read_timeout (default: 60s)
- write_timeout (default: 60s)
- idle_timeout (default: 90s)

**Module Outputs**:
- kong_admin_endpoint
- kong_proxy_endpoint
- coredns_endpoint
- caddy_endpoint
- load_balancer_status

---

### 6. **modules/dns/** — Cloudflare Tunnel, GoDaddy Failover
**Purpose**: Domain management, edge security, DNS failover  
**Critical For**: Public DNS, edge protection, HA  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- cloudflare.tf (tunnel configuration)
- godaddy-dns.tf (secondary DNS provider)
- phase-5-dns-failover.tf (failover logic)

**Phase 2 Tasks**:
1. [x] Create modules/dns/variables.tf (DNS config)
2. [x] Create modules/dns/main.tf (Cloudflare + GoDaddy)
3. [x] Create modules/dns/outputs.tf (DNS records)
4. [ ] Populate with Cloudflare tunnel config
5. [ ] Populate with GoDaddy failover rules
6. [ ] Add health check for failover

**Module Variables** (20 total):
- domain (required, e.g., kushnir.cloud)
- cloudflare_zone_id (required)
- cloudflare_api_token (sensitive, required)
- cloudflare_tunnel_name (default: prod-tunnel)
- cloudflare_tunnel_secret (sensitive, required)
- cloudflare_waf_enabled (default: true)
- cloudflare_rate_limit_enabled (default: true)
- cloudflare_rate_limit_threshold (default: 100)
- cloudflare_ddos_protection_level (default: high)
- godaddy_api_key (required for failover)
- godaddy_api_secret (sensitive, required)
- godaddy_ttl (default: 600)
- failover_enabled (default: true)
- failover_check_interval (default: 30s)
- failover_unhealthy_threshold (default: 3)
- primary_dns_provider (default: cloudflare)
- secondary_dns_provider (default: godaddy)
- acme_provider (default: letsencrypt)
- dnssec_enabled (default: true)
- dns_record_ttl (default: 300)

**Module Outputs**:
- cloudflare_tunnel_cname
- cloudflare_tunnel_token
- godaddy_dns_records
- failover_status
- domain_nameservers

---

### 7. **modules/failover/** — Patroni Replication, Backup, Disaster Recovery
**Purpose**: High availability, disaster recovery, backup automation  
**Critical For**: Data protection, RTO/RPO compliance, failover automation  
**Status**: ✅ Template created | 🟡 Content to be added  
**Files to Reference**:
- phase-5-replication.tf (PostgreSQL replication)
- phase-9d-disaster-recovery.tf (DR setup)
- phase-9d-backup.tf (backup automation)
- scripts/backup-*.sh (backup scripts)

**Phase 2 Tasks**:
1. [x] Create modules/failover/variables.tf (HA/DR config)
2. [x] Create modules/failover/main.tf (Patroni, Redis Sentinel, backups)
3. [x] Create modules/failover/outputs.tf (replica endpoints)
4. [ ] Populate with Patroni configuration
5. [ ] Populate with backup automation
6. [ ] Populate with DR procedures

**Module Variables** (27 total):
- is_primary (default: true)
- primary_host_ip (required)
- replica_host_ip (required)
- patroni_version (default: 3.0.0)
- patroni_cluster_name (default: code-server-cluster)
- patroni_dcs_type (default: etcd)
- patroni_replication_lag_limit_mb (default: 100)
- patroni_replication_timeout_seconds (default: 300)
- patroni_failover_timeout_seconds (default: 30)
- patroni_synchronous_replication (default: true)
- patroni_synchronous_commit (default: remote_apply)
- redis_sentinel_enabled (default: true)
- redis_sentinel_port (default: 26379)
- redis_sentinel_quorum (default: 2)
- redis_sentinel_down_after_milliseconds (default: 30000)
- redis_sentinel_parallel_syncs (default: 1)
- backup_enabled (default: true)
- backup_strategy (default: pgbackrest)
- backup_encryption_enabled (default: true)
- backup_compression_enabled (default: true)
- backup_retention_days (default: 30)
- backup_retention_full_backups (default: 7)
- backup_pitr_window_days (default: 7)
- backup_schedule (default: "0 2 * * *")
- backup_parallel_jobs (default: 4)
- rto_minutes (default: 15)
- rpo_seconds (default: 60)

**Module Outputs**:
- primary_endpoint
- replica_endpoint
- patroni_cluster_status
- backup_location
- last_backup_timestamp
- rto_rpo_status

---

## Module Composition Strategy

All 7 modules are **independently deployable** but work together in **root main.tf**:

```hcl
module "core" { source = "./modules/core" ... }
module "data" { source = "./modules/data" ... }
module "monitoring" { source = "./modules/monitoring" ... }
module "networking" { source = "./modules/networking" ... }
module "security" { source = "./modules/security" ... }
module "dns" { source = "./modules/dns" ... }
module "failover" { source = "./modules/failover" ... }
```

---

## Execution Timeline

### Phase 2: File Consolidation (THIS SESSION)
**Effort**: 2-3 hours  
**Deliverables**:
- [x] Verify module directory structure (done)
- [ ] Consolidate core service definitions into modules/core/
- [ ] Consolidate database definitions into modules/data/
- [ ] Consolidate observability configs into modules/monitoring/
- [ ] Consolidate security policies into modules/security/
- [ ] Consolidate networking rules into modules/networking/
- [ ] Consolidate DNS configs into modules/dns/
- [ ] Consolidate replication/backup into modules/failover/

### Phase 3: Root Module Composition
**Effort**: 1 hour  
**Deliverables**:
- Create new root main.tf (module instantiation)
- Update root variables.tf (module-level variables)
- Delete redundant phase-*.tf files (after migration)
- Create terraform-docs configuration

### Phase 4: Validation
**Effort**: 30 minutes  
**Deliverables**:
- terraform validate (syntax check)
- terraform plan -var-file=production.tfvars
- terraform plan -var-file=replica.tfvars
- Module independence validation

### Phase 5: Testing & Closure
**Effort**: 1 hour  
**Deliverables**:
- Document module usage
- Create deployment runbook
- Close P2 #418
- Production readiness checklist

---

## Production Readiness Checklist

### Module Structure
- [x] 7 modules created with directory structure
- [ ] All modules have variables.tf, main.tf, outputs.tf
- [ ] Module documentation complete
- [ ] Module dependencies mapped

### File Consolidation
- [ ] All phase-*.tf files migrated into modules
- [ ] Variable-only files (compute.tf, network.tf, etc.) consolidated
- [ ] Redundant definitions eliminated
- [ ] No duplicate resources across modules

### Root Module
- [ ] Root main.tf created with all 7 modules
- [ ] Root variables.tf imports module variables
- [ ] Primary/replica logic implemented
- [ ] Module outputs accessible at root level

### Validation
- [x] terraform fmt (formatting)
- [ ] terraform validate (syntax)
- [ ] terraform plan (execution plan)
- [ ] terraform-docs (auto-documentation)

### Deployment
- [ ] Tested on primary (192.168.168.31)
- [ ] Tested on replica (192.168.168.42)
- [ ] Rollback procedure documented
- [ ] Monitoring alerts configured

---

## Next Steps

1. **Phase 2** (This Session): Consolidate files into modules
2. **Phase 3**: Create root main.tf with module composition
3. **Phase 4**: Validate terraform (plan + apply dry-run)
4. **Phase 5**: Close P2 #418 after production testing

---

**Status**: 🟡 PHASE 2 IN PROGRESS  
**Target Completion**: End of session  
**Branch**: phase-7-deployment  
**Related Issues**: P2 #418 (Terraform module refactoring)
