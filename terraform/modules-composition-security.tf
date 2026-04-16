# Terraform Module: Security Stack (Falco Runtime Security, OPA Policy Engine, Vault Secrets, OS Hardening)
# Module Version: 1.0.0 | Last Updated: 2026-04-22

module "security" {
  source = "./modules/security"

  # General configuration
  environment     = var.environment
  deployment_host = var.deployment_host
  domain          = var.domain
  namespace       = "security"

  # Falco Runtime Security Configuration
  falco_enabled   = true
  falco_image     = "falcosecurity/falco:${var.falco_version}"
  falco_log_level = var.log_level
  falco_memory    = "512Mi"
  falco_cpu       = "250m"

  # Falco rules and policies
  falco_rules_enabled = true
  falco_rules_file    = "${path.module}/../config/falco/falco-rules.yaml"

  # Falco suspicious activity detection
  falco_detections = {
    unauthorized_container_execution = {
      enabled = true
      severity = "WARNING"
    }
    privilege_escalation = {
      enabled = true
      severity = "CRITICAL"
    }
    data_exfiltration = {
      enabled = true
      severity = "CRITICAL"
    }
    cryptomining = {
      enabled = true
      severity = "CRITICAL"
    }
    reverse_shell = {
      enabled = true
      severity = "CRITICAL"
    }
  }

  # Falco alerting
  falco_alerts = {
    enabled     = true
    sink_type   = "http"
    sink_url    = "http://localhost:${var.loki_port}/loki/api/v1/push"
    batch_size  = 10
    timeout_ms  = 5000
  }

  # OPA Policy Engine Configuration
  opa_enabled     = true
  opa_image       = "openpolicyagent/opa:${var.opa_version}"
  opa_port        = var.opa_port
  opa_log_level   = var.log_level
  opa_memory      = "512Mi"
  opa_cpu         = "250m"

  # OPA Rego policies
  opa_policies = {
    # RBAC enforcement
    rbac = {
      path = "data.rbac"
      rules_file = "${path.module}/../config/opa/rbac.rego"
    }

    # Pod security policy
    pod_security = {
      path = "data.kubernetes.admission"
      rules_file = "${path.module}/../config/opa/pod-security.rego"
    }

    # Network policy
    network_policy = {
      path = "data.network"
      rules_file = "${path.module}/../config/opa/network-policy.rego"
    }

    # Data protection
    data_protection = {
      path = "data.data_protection"
      rules_file = "${path.module}/../config/opa/data-protection.rego"
    }

    # Compliance (PCI DSS, HIPAA, SOC2)
    compliance = {
      path = "data.compliance"
      rules_file = "${path.module}/../config/opa/compliance.rego"
    }
  }

  # OPA decision logging
  opa_decision_logging = {
    enabled = true
    console = true
    remote_url = "http://localhost:${var.loki_port}/loki/api/v1/push"
  }

  # Vault Secrets Management Configuration
  vault_enabled       = true
  vault_image         = "vault:${var.vault_version}"
  vault_port          = var.vault_port
  vault_unseal_key    = var.vault_unseal_key  # Retrieved from GCP Secret Manager
  vault_root_token    = var.vault_root_token
  vault_memory        = "512Mi"
  vault_cpu           = "250m"

  # Vault storage backend
  vault_storage = {
    type = "postgresql"
    config = {
      connection_url = "postgresql://${var.vault_db_user}:${var.vault_db_password}@${var.postgres_host}:${var.postgres_port}/vault"
      table          = "vault_kv_store"
      max_parallel   = 128
    }
  }

  # Vault auth methods
  vault_auth_methods = {
    github = {
      enabled = true
      config = {
        organization = "kushin77"
        base_url     = "https://github.com/api/v3"
      }
    }
    oidc = {
      enabled = true
      config = {
        oidc_discovery_url = "https://accounts.google.com"
        oidc_client_id     = var.vault_oidc_client_id
        oidc_client_secret = var.vault_oidc_client_secret
      }
    }
    kubernetes = {
      enabled = true
      config = {
        kubernetes_host = var.k8s_api_url
        kubernetes_ca_cert = var.k8s_ca_cert
      }
    }
  }

  # Vault secret engines
  vault_secret_engines = {
    database = {
      enabled = true
      type    = "database"
      path    = "database"
    }
    kv = {
      enabled = true
      type    = "kv"
      version = 2
      path    = "secret"
    }
    pki = {
      enabled = true
      type    = "pki"
      path    = "pki"
      max_lease_ttl = "87600h"  # 10 years for CA
    }
  }

  # Vault policies
  vault_policies = {
    admin = {
      rules = file("${path.module}/../config/vault/admin-policy.hcl")
    }
    developer = {
      rules = file("${path.module}/../config/vault/developer-policy.hcl")
    }
    application = {
      rules = file("${path.module}/../config/vault/application-policy.hcl")
    }
  }

  # OS Hardening Configuration
  os_hardening = {
    enabled = true

    # Kernel hardening
    kernel_parameters = {
      "kernel.unprivileged_userns_clone" = 0
      "net.ipv4.ip_forward"              = 0
      "net.ipv6.conf.all.forwarding"     = 0
      "kernel.kptr_restrict"             = 2
      "kernel.dmesg_restrict"            = 1
      "kernel.yama.ptrace_scope"         = 2
      "net.ipv4.tcp_rfc1337"             = 1
    }

    # AppArmor/SELinux enforcement
    mandatory_access_control = {
      enabled = true
      type    = "apparmor"  # Or: selinux
      profiles_dir = "${path.module}/../config/apparmor"
    }

    # System audit logging
    auditd = {
      enabled = true
      rules_file = "${path.module}/../config/auditd/audit-rules.conf"
      log_format = "json"
      log_sink   = "http://localhost:${var.loki_port}/loki/api/v1/push"
    }

    # Automatic security updates
    unattended_upgrades = {
      enabled     = true
      auto_reboot = true
      auto_reboot_time = "03:00"
    }

    # Firewall configuration
    firewall = {
      enabled = true
      type    = "iptables"  # Or: nftables, ufw
      default_policy = "DROP"
      allowed_ports = [
        { port = 22, protocol = "tcp", source = "10.0.0.0/8" },
        { port = 80, protocol = "tcp", source = "0.0.0.0/0" },
        { port = 443, protocol = "tcp", source = "0.0.0.0/0" },
      ]
    }

    # File integrity monitoring
    file_integrity_monitoring = {
      enabled = true
      tool    = "aide"  # Or: tripwire, samhain
      check_interval = "daily"
      alert_on_change = true
    }

    # Password policy
    password_policy = {
      min_length       = 16
      complexity       = true
      history_count    = 5
      max_days         = 90
      warn_days        = 14
      min_digits       = 1
      min_uppercase    = 1
      min_lowercase    = 1
      min_special_char = 1
    }

    # SSH hardening
    ssh_hardening = {
      enabled           = true
      permit_root_login = false
      password_auth     = false
      key_auth          = true
      port              = 22
      ciphers           = ["chacha20-poly1305@openssh.com", "aes128-gcm@openssh.com", "aes256-gcm@openssh.com"]
      kex_algorithms    = ["curve25519-sha256", "curve25519-sha256@libssh.org"]
    }
  }

  # Secrets rotation
  secrets_rotation = {
    enabled       = true
    rotation_days = 90
    services      = ["postgres", "redis", "kong", "code-server"]
  }

  # Resource limits
  resource_limits = {
    memory = "2Gi"
    cpu    = "1000m"
  }

  # High availability
  replicas = {
    vault = 3  # HA Vault cluster with Raft backend
  }

  # Backup and disaster recovery
  backup = {
    enabled           = true
    frequency         = "daily"
    retention_days    = 30
    backup_destination = "s3://code-server-backups/vault"
  }

  # Logging and monitoring
  logging = {
    level       = var.log_level
    format      = "json"
    audit_enabled = true
    audit_sink  = "http://localhost:${var.loki_port}/loki/api/v1/push"
  }

  # Tags
  tags = merge(var.tags, {
    Module  = "security"
    Purpose = "Falco Runtime Security, OPA Policies, Vault Secrets, OS Hardening"
  })
}

# Output Vault configuration
output "vault_endpoints" {
  value = {
    api_url = "http://localhost:${module.security.vault_port}"
    unseal_required = module.security.vault_unseal_required
  }
}

# Output OPA endpoints
output "opa_endpoints" {
  value = {
    api_url = "http://localhost:${module.security.opa_port}"
  }
}

# Output Falco status
output "falco_status" {
  value = {
    enabled = module.security.falco_enabled
    rules_loaded = module.security.falco_rules_count
  }
}

# Output security posture
output "security_posture" {
  value = {
    kernel_hardening = module.security.kernel_hardening_status
    os_compliance    = module.security.os_compliance_status
    policy_violations = module.security.policy_violations
  }
}
