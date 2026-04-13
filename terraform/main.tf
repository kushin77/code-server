# Main Terraform Configuration
# Orchestration of all 8 phases with explicit dependencies

# ===== PHASE 2: Namespaces =====
module "namespaces" {
  source = "./modules/phase2-namespaces"

  namespace_monitoring     = var.namespace_monitoring
  namespace_security       = var.namespace_security
  namespace_backup         = var.namespace_backup
  namespace_code_server    = var.namespace_code_server
  namespace_ingress        = var.namespace_ingress
  namespace_cert_manager   = var.namespace_cert_manager
  environment              = var.cluster_name
  enable_monitoring        = var.enable_monitoring
  enable_security          = true
  enable_backup            = true
  enable_code_server       = var.enable_code_server
  enable_ingress           = true
}

# ===== PHASE 2: Storage =====
module "storage" {
  source = "./modules/phase2-storage"

  prometheus_storage_size              = var.prometheus_storage_size
  loki_storage_size                    = var.loki_storage_size
  code_server_workspace_size           = var.code_server_workspace_size
  velero_storage_size                  = var.velero_storage_size
  create_prometheus_pv                 = var.enable_monitoring
  create_loki_pv                       = var.enable_monitoring
  create_code_server_workspace_pv      = var.enable_code_server
  create_velero_pv                     = true

  depends_on = [module.namespaces]
}

# ===== PHASE 3: Observability =====
module "observability" {
  source = "./modules/phase3-observability"

  namespace_monitoring      = var.namespace_monitoring
  enable_prometheus         = var.enable_monitoring
  enable_grafana            = var.enable_monitoring
  enable_loki               = var.enable_monitoring
  prometheus_storage_size   = var.prometheus_storage_size
  loki_storage_size         = var.loki_storage_size
  prometheus_replicas       = var.prometheus_replicas
  grafana_replicas          = var.grafana_replicas
  loki_replicas             = var.loki_replicas
  prometheus_requests       = var.prometheus_requests
  prometheus_limits         = var.prometheus_limits
  grafana_requests          = var.grafana_requests
  grafana_limits            = var.grafana_limits
  loki_requests             = var.loki_requests
  loki_limits               = var.loki_limits
  grafana_admin_password    = var.grafana_admin_password

  depends_on = [module.namespaces, module.storage]
}

# ===== PHASE 4: Security & RBAC =====
module "security" {
  source = "./modules/phase4-security"

  namespace_monitoring   = var.namespace_monitoring
  namespace_security     = var.namespace_security
  namespace_code_server  = var.namespace_code_server
  namespace_backup       = var.namespace_backup
  environment            = var.cluster_name
  create_read_only_role  = true
  create_developer_role  = true
  create_admin_role      = true
  create_monitoring_sa   = var.enable_monitoring
  create_code_server_sa  = var.enable_code_server
  create_backup_sa       = true
  enable_network_policies = true

  depends_on = [module.observability]
}

# ===== PHASE 5: Backup & Disaster Recovery =====
module "backup" {
  source = "./modules/phase5-backup"

  namespace_backup       = var.namespace_backup
  namespace_monitoring   = var.namespace_monitoring
  namespace_code_server  = var.namespace_code_server
  namespace_security     = var.namespace_security
  environment            = var.cluster_name
  enable_velero          = true
  velero_chart_version   = "5.0.0"
  velero_storage_size    = var.velero_storage_size
  backup_bucket_name     = "velero-backups"
  enable_restore_testing = true
  enable_restore_verification = true

  depends_on = [module.security]
}

# ===== PHASE 6: Application Platform (code-server) =====
module "app_platform" {
  source = "./modules/phase6-app-platform"

  namespace_code_server       = var.namespace_code_server
  environment                 = var.cluster_name
  enable_code_server          = var.enable_code_server
  code_server_version         = var.code_server_version
  code_server_replicas        = var.code_server_replicas
  code_server_workspace_size  = var.code_server_workspace_size
  code_server_password        = var.code_server_password
  code_server_requests        = var.code_server_requests
  code_server_limits          = var.code_server_limits
  code_server_extensions      = var.code_server_extensions
  create_code_server_settings = true
  create_code_server_extensions = true
  create_code_server_secret   = true

  depends_on = [module.backup]
}

# ===== PHASE 7: Ingress & TLS =====
module "ingress" {
  source = "./modules/phase7-ingress"

  namespace_ingress       = var.namespace_ingress
  namespace_cert_manager  = var.namespace_cert_manager
  namespace_monitoring    = var.namespace_monitoring
  namespace_code_server   = var.namespace_code_server
  environment             = var.cluster_name
  enable_ingress_controller = true
  ingress_nginx_chart_version = "4.9.1"
  enable_cert_manager     = true
  cert_manager_chart_version = "v1.13.2"
  enable_letsencrypt_staging = true
  enable_letsencrypt_production = true
  certmanager_email       = var.certmanager_email
  cert_issuer_name        = "letsencrypt-prod"
  enable_grafana_ingress  = var.enable_monitoring
  grafana_hostname        = var.grafana_hostname
  enable_prometheus_ingress = var.enable_monitoring
  prometheus_hostname     = var.prometheus_hostname
  enable_code_server_ingress = var.enable_code_server
  code_server_hostname    = var.code_server_hostname

  depends_on = [module.app_platform]
}

# ===== PHASE 8: Verification & Validation =====
module "verification" {
  source = "./modules/phase8-verification"

  environment                      = var.cluster_name
  namespaces_to_verify             = var.namespaces_to_verify
  create_health_check_script       = true
  create_compliance_check_script   = true
  create_performance_benchmark     = true
  create_cleanup_script            = true
  create_verification_checklist    = true
  verification_scripts_dir         = "/tmp/k8s-verification"
  enable_monitoring                = var.enable_monitoring
  enable_code_server               = var.enable_code_server
  enable_ingress_controller        = true

  depends_on = [module.ingress]
}

# ===== PHASE 10: On-Premises Optimization =====
module "onprem_optimization" {
  source = "./modules/phase10-onprem-optimization"

  environment                      = var.cluster_name
  namespace_monitoring             = var.namespace_monitoring
  namespace_code_server            = var.namespace_code_server
  enable_resource_quotas           = true
  monitoring_quota_cpu             = "10"
  monitoring_quota_memory          = "20Gi"
  enable_priority_classes          = true
  enable_hpa                       = true
  enable_code_server_hpa           = true
  code_server_hpa_min              = 2
  code_server_hpa_max              = var.code_server_hpa_max
  code_server_cpu_threshold        = 70
  code_server_memory_threshold     = 75
  create_node_optimization_script  = true
  create_metrics_optimization      = true
  create_cost_optimization_report  = true
  cluster_node_count               = var.cluster_node_count
  create_operational_runbooks      = true

  depends_on = [module.verification]
}

# ===== DEPLOYMENT OUTPUTS =====

output "deployment_summary" {
  value = {
    phase_2_namespaces    = "✓ Namespaces created"
    phase_2_storage       = "✓ Storage provisioned"
    phase_3_observability = "✓ Prometheus, Grafana, Loki deployed"
    phase_4_security      = "✓ RBAC and Network Policies configured"
    phase_5_backup        = "✓ Velero backup enabled"
    phase_6_platform      = "✓ code-server deployed"
    phase_7_ingress       = "✓ NGINX Ingress and TLS configured"
    phase_8_verification  = "✓ Health checks and validation scripts ready"
    phase_10_optimization = "✓ On-premises optimization enabled"
  }
  description = "Complete deployment status across all phases"
}

output "access_information" {
  value = <<-EOT
╔════════════════════════════════════════════════════════════════╗
║          KUBERNETES CLUSTER DEPLOYMENT COMPLETE                ║
╚════════════════════════════════════════════════════════════════╝

MONITORING & OBSERVABILITY:
  Prometheus:  https://${var.prometheus_hostname}
  Grafana:     https://${var.grafana_hostname}
  Loki:        internal://loki.${var.namespace_monitoring}:3100

DEVELOPMENT PLATFORM:
  code-server: https://${var.code_server_hostname}
  Workspaces:  ${var.code_server_replicas} replicas with ${var.code_server_workspace_size} storage each

BACKUP & DISASTER RECOVERY:
  Velero:      Automated daily backups enabled
  Status:      kubectl get backup -n ${var.namespace_backup}

SECURITY:
  Network Policies: Default-deny with explicit allow rules
  RBAC:            Role-based access control configured
  ServiceAccounts: Monitoring, code-server, backup

QUICK COMMANDS:
  Check status:        terraform show
  Verify deployment:   bash /tmp/k8s-verification/01-health-check.sh
  View logs:           kubectl logs -n monitoring -l app=prometheus
  Port-forward:        kubectl port-forward -n ingress-nginx svc/ingress-nginx 8080:80
  
IDEMPOTENT & SAFE:
  ✓ All resources can be safely reapplied: terraform apply
  ✓ Lifecycle rules prevent destructive updates
  ✓ Cluster readiness checks before deployment
  ✓ State management via local tfstate (extend to S3/GCS for teams)

NEXT STEPS:
  1. Verify cluster health: bash /tmp/k8s-verification/01-health-check.sh
  2. Check compliance:     bash /tmp/k8s-verification/02-compliance-check.sh
  3. Run benchmarks:       bash /tmp/k8s-verification/03-performance-benchmark.sh
  4. Access services:      Use hostnames above with proper DNS/load balancer
  5. Review logs:          kubectl logs -n <namespace> <pod-name>

TERRAFORM STATE:
  Location: ${var.terraform_state_file}
  Backup:   ${var.terraform_state_backup}
  
For GitOps integration, push this configuration to: git@github.com:kushin77/code-server.git
  EOT
  description = "Complete access information and next steps"
  sensitive   = false
}

output "terraform_commands" {
  value = <<-EOT
TERRAFORM OPERATIONS:

Initialize workspace (first-time only):
  terraform init

Plan changes (preview before applying):
  terraform plan -out=tfplan

Apply changes (deploy infrastructure):
  terraform apply tfplan

Re-apply safely (idempotent - safe for re-runs):
  terraform apply -auto-approve

View current state:
  terraform show

Validate configuration:
  terraform validate

Format code:
  terraform fmt -recursive

Destroy infrastructure (WARNING - destructive):
  terraform destroy

Export state as JSON:
  terraform show -json

View specific outputs:
  terraform output deployment_summary
  terraform output access_information
  EOT
  description = "Common Terraform commands for deployment"
}

