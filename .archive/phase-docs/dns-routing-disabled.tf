# ════════════════════════════════════════════════════════════════════════════
# Phase 18-20: DNS Routing & Load Balancing (IaC)
# Production DNS configuration with Cloudflare for all services
# Immutable: All changes via Terraform only; no manual DNS edits
# ════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES (Override via terraform.tfvars or environment)
# ─────────────────────────────────────────────────────────────────────────────

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for ide.kushnir.cloud"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "root_domain" {
  description = "Root domain"
  type        = string
  default     = "ide.kushnir.cloud"
}

variable "primary_ip" {
  description = "Primary infrastructure IP (192.168.168.31)"
  type        = string
  default     = "192.168.168.31"
}

variable "secondary_ip" {
  description = "Secondary infrastructure IP (failover)"
  type        = string
  default     = "192.168.168.32"
}

variable "phase_18_services" {
  description = "Phase-18 services with DNS names"
  type        = map(string)
  default = {
    # Core IDE Access
    "ide"         = "Code-Server IDE (8080 -> 443)"
    "api"         = "Code-Server API (8080 -> 443)"
    
    # Compliance & Audit (Phase 18)
    "loki"        = "Loki Audit Logs (3100)"
    "grafana"     = "Grafana Compliance Dashboard (3000)"
    "prometheus"  = "Prometheus Metrics (9090)"
    
    # Security (Phase 18)
    "vault"       = "HashiCorp Vault (8200)"
    "consul"      = "Consul Service Registry (8500)"
    
    # Database (Phase 16+17)
    "db"          = "PostgreSQL Primary (5432)"
    "db-replica"  = "PostgreSQL Replica (5433)"
    "pgbouncer"   = "PgBouncer Connection Pool (6432)"
    
    # Load Balancers (Phase 16)
    "lb1"         = "Load Balancer 1 (8404)"
    "lb2"         = "Load Balancer 2 (8405)"
    
    # Security Proxy
    "git-proxy"   = "Git SSH Proxy (2222)"
    "ssh-proxy"   = "SSH Proxy (2221)"
  }
}

variable "enable_load_balancing" {
  description = "Enable Cloudflare load balancing for HA"
  type        = bool
  default     = true
}

variable "ttl_seconds" {
  description = "DNS TTL in seconds (300 = 5 min for failover)"
  type        = number
  default     = 300
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default = {
    Phase       = "18-20"
    Component   = "DNS-Routing"
    Environment = "production"
    ManagedBy   = "terraform"
    Immutable   = "true"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PROVIDER
# ─────────────────────────────────────────────────────────────────────────────

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ─────────────────────────────────────────────────────────────────────────────
# ROOT DOMAIN RECORDS (ide.kushnir.cloud)
# ─────────────────────────────────────────────────────────────────────────────

# Primary A record pointing to primary IP
resource "cloudflare_record" "root_primary" {
  zone_id = var.cloudflare_zone_id
  name    = var.root_domain
  type    = "A"
  value   = var.primary_ip
  ttl     = var.ttl_seconds
  
  comment = "Phase 18-20: Primary infrastructure endpoint"
  tags    = ["phase-18-20", "dns", "primary"]
}

# Secondary A record (failover)
resource "cloudflare_record" "root_secondary" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "A"
  value   = var.secondary_ip
  ttl     = var.ttl_seconds
  priority = 10
  
  comment = "Phase 18-20: Secondary failover endpoint"
  tags    = ["phase-18-20", "dns", "failover"]
}

# ─────────────────────────────────────────────────────────────────────────────
# SERVICE SUBDOMAINS (CNAME -> root)
# ─────────────────────────────────────────────────────────────────────────────

# IDE subdomain
resource "cloudflare_record" "ide" {
  zone_id = var.cloudflare_zone_id
  name    = "ide"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18-20: Code-Server IDE (proxied via Cloudflare)"
  tags    = ["phase-18-20", "ide", "proxied"]
}

# API subdomain
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18-20: Code-Server API"
  tags    = ["phase-18-20", "api", "proxied"]
}

# ─────────────────────────────────────────────────────────────────────────────
# COMPLIANCE & AUDIT SUBDOMAINS (Phase 18)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "loki" {
  zone_id = var.cloudflare_zone_id
  name    = "loki"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: Loki Audit Log Aggregation (SOC2)"
  tags    = ["phase-18", "compliance", "audit"]
}

resource "cloudflare_record" "grafana" {
  zone_id = var.cloudflare_zone_id
  name    = "grafana"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: Grafana Compliance Dashboard (SOC2 Type II)"
  tags    = ["phase-18", "compliance", "monitoring"]
}

resource "cloudflare_record" "prometheus" {
  zone_id = var.cloudflare_zone_id
  name    = "prometheus"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: Prometheus Metrics & Monitoring"
  tags    = ["phase-18", "monitoring", "metrics"]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY SUBDOMAINS (Phase 18)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "vault" {
  zone_id = var.cloudflare_zone_id
  name    = "vault"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: HashiCorp Vault - Secrets Management"
  tags    = ["phase-18", "security", "secrets"]
}

resource "cloudflare_record" "consul" {
  zone_id = var.cloudflare_zone_id
  name    = "consul"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: Consul - Service Registry & Discovery"
  tags    = ["phase-18", "security", "registry"]
}

# ─────────────────────────────────────────────────────────────────────────────
# VAULT MULTI-NODE SUBDOMAINS (Phase 18)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "vault_node" {
  count   = 3
  zone_id = var.cloudflare_zone_id
  name    = "vault-${count.index}"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 18: Vault Node ${count.index} - HA cluster"
  tags    = ["phase-18", "vault-cluster", "node-${count.index}"]
}

# ─────────────────────────────────────────────────────────────────────────────
# DATABASE SUBDOMAINS (Phase 16+17)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "db" {
  zone_id = var.cloudflare_zone_id
  name    = "db"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = false  # Database requires direct connection
  
  comment = "Phase 16: PostgreSQL Primary (HA mirror)"
  tags    = ["phase-16", "database", "primary"]
}

resource "cloudflare_record" "db_replica" {
  zone_id = var.cloudflare_zone_id
  name    = "db-replica"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = false
  
  comment = "Phase 16: PostgreSQL Read Replica"
  tags    = ["phase-16", "database", "replica"]
}

resource "cloudflare_record" "pgbouncer" {
  zone_id = var.cloudflare_zone_id
  name    = "pgbouncer"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = false
  
  comment = "Phase 16: PgBouncer Connection Pool"
  tags    = ["phase-16", "database", "connection-pool"]
}

# ─────────────────────────────────────────────────────────────────────────────
# LOAD BALANCER SUBDOMAINS (Phase 16)
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "lb1" {
  zone_id = var.cloudflare_zone_id
  name    = "lb1"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 16: Load Balancer 1 (Keepalived HA)"
  tags    = ["phase-16", "load-balancer", "lb1"]
}

resource "cloudflare_record" "lb2" {
  zone_id = var.cloudflare_zone_id
  name    = "lb2"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = true
  
  comment = "Phase 16: Load Balancer 2 (Keepalived HA)"
  tags    = ["phase-16", "load-balancer", "lb2"]
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY PROXIES
# ─────────────────────────────────────────────────────────────────────────────

resource "cloudflare_record" "git_proxy" {
  zone_id = var.cloudflare_zone_id
  name    = "git-proxy"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = false
  
  comment = "Git SSH Proxy (port 2222)"
  tags    = ["security", "git-proxy"]
}

resource "cloudflare_record" "ssh_proxy" {
  zone_id = var.cloudflare_zone_id
  name    = "ssh-proxy"
  type    = "CNAME"
  value   = var.root_domain
  ttl     = var.ttl_seconds
  proxied = false
  
  comment = "SSH Proxy (port 2221)"
  tags    = ["security", "ssh-proxy"]
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "root_domain" {
  description = "Root domain for all services"
  value       = var.root_domain
}

output "dns_records_created" {
  description = "Total DNS records created"
  value       = 16 + 3  // Service records + vault nodes
}

output "service_urls" {
  description = "Access URLs for Phase 18-20 services"
  value = {
    "IDE"         = "https://ide.kushnir.cloud"
    "API"         = "https://api.kushnir.cloud"
    "Loki"        = "https://loki.kushnir.cloud"
    "Grafana"     = "https://grafana.kushnir.cloud"
    "Prometheus"  = "https://prometheus.kushnir.cloud"
    "Vault"       = "https://vault.kushnir.cloud"
    "Consul"      = "https://consul.kushnir.cloud"
    "LB1"         = "https://lb1.kushnir.cloud"
    "LB2"         = "https://lb2.kushnir.cloud"
  }
}

output "ttl_seconds" {
  description = "DNS record TTL (for quick failover)"
  value       = var.ttl_seconds
}

output "immutability_note" {
  description = "IaC immutability enforcement"
  value       = "All DNS records are managed via Terraform. Manual edits will be overwritten on next apply. Changes must go through version control."
}
