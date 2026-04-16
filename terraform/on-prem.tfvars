# On-Premises Terraform Configuration
# P2 #418 Phase 4: Validation environment

################################
# KEEPALIVED (Optional - disabled for Phase 4)
################################
enable_keepalived = false

################################
# CLOUDFLARE & DNS
################################
cloudflare_api_token    = "fake-token-for-testing"
cloudflare_account_id   = "fake-account-id"
cloudflare_zone_id      = "fake-zone-id"
godaddy_api_key         = "fake-godaddy-key"
godaddy_api_secret      = "fake-godaddy-secret"

apex_domain             = "kushnir.cloud"
tunnel_name             = "code-server-on-prem"
primary_ip              = "192.168.168.31"
secondary_ip            = "192.168.168.42"

################################
# MONITORING
################################
monitoring_namespace         = "monitoring"
prometheus_version           = "v2.48.0"
prometheus_storage_size      = "50Gi"
prometheus_retention_days    = 30
prometheus_scrape_interval   = 15

grafana_version              = "10.2.3"
grafana_admin_password       = "test-password-change-in-production"
grafana_storage_size         = "10Gi"

alertmanager_version         = "v0.26.0"

slo_error_budget_percentage  = 0.1

################################
# NETWORKING
################################
networking_namespace         = "networking"
kong_version                 = "3.4.0"
kong_database_password       = "test-password-change-in-production"
kong_storage_size            = "20Gi"

coredns_version              = "1.10.1"
coredns_config               = "."

################################
# SECURITY
################################
security_namespace           = "security"
falco_version                = "0.36.0"
opa_version                  = "0.55.0"
vault_version                = "1.15.0"
vault_storage_size           = "10Gi"
vault_unseal_keys            = 5
vault_key_threshold          = 3

os_hardening_level           = "standard"
selinux_enabled              = true
auditd_enabled               = true

################################
# FAILOVER / HA
################################
failover_namespace           = "failover"
patroni_version              = "3.0.0"
postgres_version             = "15.3"
postgres_storage_size        = "100Gi"
etcd_version                 = "3.5.9"

backup_retention_days        = 30
backup_schedule              = "0 2 * * *"
rpo_seconds                  = 300
rto_seconds                  = 60

################################
# KUBERNETES / DOCKER
################################
kubernetes_config_path       = "~/.kube/config"
deployment_environment       = "staging"  # Testing in staging
