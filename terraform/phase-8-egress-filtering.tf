# terraform/phase-8-egress-filtering.tf
# ========================================
# Docker Container Egress Filtering (Issue #350)
# DOCKER-USER iptables chain: allow internal/DNS/HTTPS, block all else
# Configuration: iptables: true, userland-proxy: false

# ─── Local variables ──────────────────────────────────────────────────────

locals {
  egress_script = "${path.module}/../scripts/configure-egress-filtering.sh"
  
  # Egress allow list
  allowed_services = {
    dns    = { protocol = "UDP/TCP", port = 53, destination = "public-resolvers" }
    https  = { protocol = "TCP", port = 443, destination = "any" }
    ntp    = { protocol = "UDP", port = 123, destination = "time-servers" }
    http   = { protocol = "TCP", port = 80, destination = "ubuntu-mirrors" }
    internal = { protocol = "all", destination = "192.168.168.0/24" }
  }
}

# ─── Deploy egress filtering to primary host ──────────────────────────────

resource "null_resource" "egress_filtering" {
  count = var.enable_egress_filtering ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Deploying container egress filtering...'",
      "bash ${local.egress_script}"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "10m"
    }
  }

  depends_on = [
    # Ensure Docker is running
  ]

  triggers = {
    script_hash = filemd5(local.egress_script)
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Verify egress filtering deployment ────────────────────────────────────

resource "null_resource" "verify_egress_filtering" {
  count = var.enable_egress_filtering ? 1 : 0

  provisioner "remote-exec" {
    inline = [
      "echo 'Verifying egress filtering...'",
      "echo 'Docker daemon config:' && cat /etc/docker/daemon.json | grep -E 'iptables|userland-proxy'",
      "echo 'DOCKER-USER chain:' && iptables -t filter -L DOCKER-USER -n | head -10",
      "echo 'Egress filtering verification complete'"
    ]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      host        = var.primary_host
      private_key = file(var.ssh_key_path)
      timeout     = "5m"
    }
  }

  depends_on = [null_resource.egress_filtering]
}

# ─── Variables ────────────────────────────────────────────────────────────

variable "enable_egress_filtering" {
  description = "Deploy Docker container egress filtering (#350)"
  type        = bool
  default     = true
}

variable "internal_subnet" {
  description = "Internal network CIDR for allow-listing"
  type        = string
  default     = "192.168.168.0/24"
}

variable "allow_http_mirrors" {
  description = "Allow HTTP to Ubuntu package mirrors"
  type        = bool
  default     = true
}

variable "primary_host" {
  description = "Primary host IP or FQDN"
  type        = string
  default     = "primary.prod.internal"
}

variable "ssh_user" {
  description = "SSH user for deployment"
  type        = string
  default     = "akushnir"
}

variable "ssh_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_rsa"
  sensitive   = true
}

# ─── Outputs ──────────────────────────────────────────────────────────────

output "egress_filtering_status" {
  description = "Egress filtering deployment status"
  value = var.enable_egress_filtering ? {
    deployed          = true
    allowed_services  = local.allowed_services
    internal_subnet   = var.internal_subnet
    default_policy    = "DENY (explicit allow required)"
  } : {
    deployed = false
  }
}

output "docker_daemon_config" {
  description = "Docker daemon iptables configuration"
  value = var.enable_egress_filtering ? {
    iptables        = true
    userland_proxy  = false
    log_driver      = "json-file"
    storage_driver  = "overlay2"
  } : {}
}

output "allowed_services_summary" {
  description = "Services allowed in egress filter allow-list"
  value       = local.allowed_services
}
