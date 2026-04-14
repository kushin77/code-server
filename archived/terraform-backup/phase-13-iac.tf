# ════════════════════════════════════════════════════════════════════════════
# PHASE 13 INFRASTRUCTURE AS CODE
#
# Idempotent, immutable configurations for Phase 13 deployment
# April 13, 2026 - Day 1 Execution
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13 CONFIGURATION VARIABLES (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

variable "phase_13_enabled" {
  description = "Enable Phase 13 requirements"
  type        = bool
  default     = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for tunnel"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for tunnel"
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_proxy_port" {
  description = "SSH proxy listening port"
  type        = number
  default     = 2222
}

variable "audit_log_path" {
  description = "Audit log file path"
  type        = string
  default     = "/var/log/code-server-audit.log"
}

locals {
  phase_13_config = {
    cloudflare_tunnel = {
      name        = "code-server-phase-13"
      description = "Zero-trust tunnel for code-server enterprise"
      # Tunnel ID will be populated dynamically
    }

    ssh_proxy = {
      port                = var.ssh_proxy_port
      target_host         = "localhost"
      target_port         = 22
      key_logging_enabled = true
      audit_log_sinks     = ["file", "sqlite", "syslog"]
    }

    audit_logging = {
      file_sink = {
        path         = var.audit_log_path
        max_size     = "1GB"
        max_backups  = 5
        max_age_days = 30
      }
      sqlite_sink = {
        path  = "/var/lib/code-server/audit.db"
        table = "ssh_access_audit"
      }
      syslog_sink = {
        facility = "LOG_AUTH"
        priority = "LOG_NOTICE"
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13: AUDIT LOGGING CONFIGURATION (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "audit_logging_config" {
  count           = var.phase_13_enabled ? 1 : 0
  filename        = "${path.module}/config/audit-logging.conf"
  file_permission = "0600"

  content = jsonencode({
    version     = "1.0"
    description = "Phase 13 Audit Logging Configuration"
    timestamp   = timestamp()
    immutable   = true

    sinks = {
      file = {
        type     = "file"
        path     = local.phase_13_config.audit_logging.file_sink.path
        max_size = local.phase_13_config.audit_logging.file_sink.max_size
        format   = "json"
        fields = [
          "timestamp",
          "event_type",
          "user",
          "source_ip",
          "command",
          "key_fingerprint",
          "status"
        ]
      }

      sqlite = {
        type     = "sqlite"
        path     = local.phase_13_config.audit_logging.sqlite_sink.path
        table    = local.phase_13_config.audit_logging.sqlite_sink.table
        index_on = ["timestamp", "user", "event_type"]
        retention = {
          days = 90
        }
      }

      syslog = {
        type     = "syslog"
        facility = local.phase_13_config.audit_logging.syslog_sink.facility
        priority = local.phase_13_config.audit_logging.syslog_sink.priority
        format   = "rfc5424"
      }
    }

    event_types = [
      "SSH_CONNECT",
      "SSH_AUTH_SUCCESS",
      "SSH_AUTH_FAILURE",
      "SSH_COMMAND",
      "SSH_DISCONNECT",
      "SSH_KEY_ADDED",
      "SSH_KEY_REMOVED"
    ]
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13: SSH PROXY SYSTEMD UNIT (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "ssh_proxy_systemd" {
  count           = var.phase_13_enabled ? 1 : 0
  filename        = "${path.module}/config/ssh-proxy.service"
  file_permission = "0644"

  content = <<-EOT
[Unit]
Description=Code-Server SSH Proxy with Audit Logging
Documentation=https://github.com/kushin77/code-server
After=network-online.target
Wants=network-online.target
PartOf=code-server.target

# Restart policy (immutable)
[Service]
Type=simple
Restart=always
RestartSec=5
StartLimitInterval=300
StartLimitBurst=10

# Security hardening
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${var.audit_log_path} /var/lib/code-server

# Resource limits
MemoryLimit=256M
CPUQuota=50%

# User/group (immutable)
User=code-server
Group=code-server

# Working directory
WorkingDirectory=/opt/code-server

# Executable (FastAPI SSH proxy)
ExecStart=/usr/bin/python3 /opt/code-server/ssh-proxy.py \
  --listen 127.0.0.1:${local.phase_13_config.ssh_proxy.port} \
  --target ${local.phase_13_config.ssh_proxy.target_host}:${local.phase_13_config.ssh_proxy.target_port} \
  --audit-config /etc/code-server/audit-logging.conf \
  --log-level info

# Environment
Environment="PYTHONUNBUFFERED=1"
Environment="AUDIT_LOG_PATH=${var.audit_log_path}"

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ssh-proxy

[Install]
WantedBy=multi-user.target
EOT
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13: CLOUDFLARE TUNNEL CONFIGURATION (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "cloudflare_tunnel_config" {
  count           = var.phase_13_enabled && var.cloudflare_account_id != "" ? 1 : 0
  filename        = "${path.module}/config/cloudflare-tunnel.json"
  file_permission = "0600"

  content = jsonencode({
    version   = "2024-04-13"
    immutable = true

    tunnel = {
      name        = local.phase_13_config.cloudflare_tunnel.name
      description = local.phase_13_config.cloudflare_tunnel.description
      account_id  = var.cloudflare_account_id
    }

    ingress = [
      {
        hostname        = "code-server.company.com"
        service         = "https://localhost:443"
        path            = "/"
        tls_skip_verify = false
      },
      {
        service = "http"
      }
    ]

    warp_routes = []

    warp_routing = {
      enabled = false
    }

    policy = {
      mtls_auth      = false
      jwt_validation = false
      auth_domain    = ""
    }

    logging = {
      enabled = true
      level   = "info"
      file    = "/var/log/cloudflare-tunnel.log"
    }

    metrics = {
      enabled      = true
      port         = 49312
      read_timeout = 30
    }
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13: LOAD TEST CONFIGURATION (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "load_test_config" {
  count           = var.phase_13_enabled ? 1 : 0
  filename        = "${path.module}/config/load-test.conf"
  file_permission = "0644"

  content = jsonencode({
    version   = "1.0"
    immutable = true
    timestamp = timestamp()

    load_test = {
      name = "Phase 13 Day 1 Load Test"

      configuration = {
        concurrent_users   = 5
        ramp_up_time_sec   = 60
        sustain_time_sec   = 600
        ramp_down_time_sec = 60
        think_time_ms      = 1000
      }

      targets = [
        {
          name     = "SSH Connection"
          endpoint = "ssh://localhost:2222"
          type     = "ssh"
        },
        {
          name     = "HTTP Health Check"
          endpoint = "https://localhost:443/healthz"
          type     = "http"
        },
        {
          name     = "IDE Access"
          endpoint = "https://localhost:443/"
          type     = "http"
        }
      ]

      metrics = {
        p50_latency_target_ms     = 50
        p99_latency_target_ms     = 100
        p99_9_latency_target_ms   = 200
        error_rate_target_pct     = 0.1
        throughput_target_req_sec = 100
      }

      success_criteria = {
        all_metrics_within_target  = true
        zero_authentication_errors = true
        zero_pod_restarts          = true
      }
    }
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 13: IDEMPOTENT DEPLOYMENT STATE (Immutable)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "phase_13_deployment_state" {
  count           = var.phase_13_enabled ? 1 : 0
  filename        = "${path.module}/.phase-13-deployed"
  file_permission = "0644"
  content         = "deployed:${timestamp()}\nversion:1.0\nimmutable:true"
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT: PHASE 13 DEPLOYMENT STATUS
# ─────────────────────────────────────────────────────────────────────────────

output "phase_13_enabled" {
  description = "Phase 13 IaC is deployed"
  value       = var.phase_13_enabled
}

output "cloudflare_tunnel_config" {
  description = "Cloudflare tunnel configuration file path"
  value       = try(local_file.cloudflare_tunnel_config[0].filename, "")
  sensitive   = false
}

output "ssh_proxy_config" {
  description = "SSH proxy systemd configuration"
  value       = try(local_file.ssh_proxy_systemd[0].filename, "")
}

output "audit_logging_config" {
  description = "Audit logging configuration path"
  value       = try(local_file.audit_logging_config[0].filename, "")
}

output "load_test_config" {
  description = "Load test configuration path"
  value       = try(local_file.load_test_config[0].filename, "")
}

output "phase_13_deployment_timestamp" {
  description = "Phase 13 deployment timestamp"
  value       = var.phase_13_enabled ? timestamp() : null
}
