# Phase 8-B: Falco Runtime Security (#359)
# Runtime threat detection, behavioral monitoring, security anomaly detection
# Immutable versions: Falco 0.36.0, Falco Rules 0.36.0, Falco Sidekick 0.30.0

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

variable "falco_version" {
  description = "Falco runtime security version (immutable)"
  type        = string
  default     = "0.36.0"
}

variable "falco_rules_version" {
  description = "Falco rules version (immutable)"
  type        = string
  default     = "0.36.0"
}

variable "falco_sidekick_version" {
  description = "Falco Sidekick output dispatcher (immutable)"
  type        = string
  default     = "0.30.0"
}

# ============================================================================
# Falco Runtime Security Configuration
# ============================================================================

resource "local_file" "setup_falco" {
  filename = "${path.module}/../scripts/setup-falco-runtime-security.sh"
  content = templatefile("${path.module}/../templates/setup-falco-runtime-security.sh.tpl", {
    falco_version           = var.falco_version
    falco_sidekick_version  = var.falco_sidekick_version
  })
}

resource "local_file" "falco_config" {
  filename = "${path.module}/../config/falco/falco-config.yaml"
  content = templatefile("${path.module}/../templates/falco-config.yaml.tpl", {
    log_level = "INFO"
  })
}

resource "local_file" "falco_custom_rules" {
  filename = "${path.module}/../config/falco/rules.local.yaml"
  content = file("${path.module}/../templates/falco-custom-rules.yaml")
}

resource "local_file" "falco_sidekick_config" {
  filename = "${path.module}/../config/falco/falco-sidekick.yaml"
  content = templatefile("${path.module}/../templates/falco-sidekick-config.yaml.tpl", {
    syslog_host     = "192.168.168.31"
    webhook_url     = "http://localhost:5000/alerts"
    s3_bucket       = "falco-audit-trail"
  })
}

resource "local_file" "falco_rules_documentation" {
  filename = "${path.module}/../docs/falco-rules.md"
  content = file("${path.module}/../templates/falco-rules-documentation.md")
}

resource "local_file" "cicd_falco_deploy" {
  filename = "${path.module}/../.github/workflows/deploy-falco.yml"
  content = templatefile("${path.module}/../templates/deploy-falco.yml.tpl", {
    falco_version = var.falco_version
  })
}

output "falco_runtime_security_config" {
  value = {
    runtime_security_engine = {
      tool            = "Falco"
      version         = var.falco_version
      rules_version   = var.falco_rules_version
      dispatcher      = "Falco Sidekick ${var.falco_sidekick_version}"
    }
    threat_detection_rules = {
      malware_detection = {
        count = 8
        examples = [
          "Unauthorized process execution",
          "Cryptominer detection (xmrig, cpuminer, mkxminer)",
          "Known malware signatures",
          "Botnet C&C communication",
          "Ransomware file patterns",
          "Trojan/backdoor detection",
          "Rootkit installation attempts",
          "Shellcode execution detection"
        ]
        severity = "CRITICAL"
        action = "ALERT + BLOCK"
      }
      privilege_escalation = {
        count = 10
        examples = [
          "Unauthorized capability grants",
          "setuid binary abuse",
          "sudo command abuse",
          "Kernel exploit attempts",
          "SUID bit manipulation",
          "File permission bypass attempts",
          "Group membership escalation",
          "Token impersonation",
          "UAC bypass attempts",
          "seLinux policy violations"
        ]
        severity = "HIGH"
        action = "ALERT"
      }
      suspicious_behavior = {
        count = 15
        examples = [
          "Unusual process spawning",
          "Excessive failed logins",
          "Suspicious file modifications",
          "Abnormal network connections",
          "Container escape attempts",
          "Privilege mode changes",
          "Mount operations abuse",
          "IPC mechanism abuse",
          "Socket creation anomalies",
          "System call pattern deviations",
          "Resource limit violations",
          "Orphaned process detection",
          "Memory corruption attempts",
          "Stack overflow patterns",
          "Buffer overflow signatures"
        ]
        severity = "MEDIUM"
        action = "ALERT"
      }
      compliance_violations = {
        count = 12
        examples = [
          "Unauthorized file access",
          "Policy violation detection",
          "Audit log tampering",
          "Configuration changes",
          "Privilege abuse",
          "Data access violations",
          "Encryption bypass attempts",
          "SSL/TLS abuse",
          "Policy enforcement failure",
          "Compliance control violation",
          "Audit trail gaps",
          "Unauthorized tool execution"
        ]
        severity = "HIGH"
        action = "ALERT + LOG"
      }
      cryptomining = {
        count = 5
        examples = [
          "xmrig process detection",
          "Monero pool connection",
          "stratum protocol abuse",
          "GPU exploitation",
          "CPU exhaustion patterns"
        ]
        severity = "CRITICAL"
        action = "ALERT + BLOCK"
      }
    }
    output_integrations = {
      syslog = {
        enabled = true
        host    = "192.168.168.31"
        port    = 514
        protocol = "UDP"
        facility = "LOG_LOCAL0"
      }
      http_webhook = {
        enabled = true
        url     = "http://localhost:5000/alerts"
        timeout = "5s"
        retry   = true
      }
      s3_export = {
        enabled = true
        bucket  = "falco-audit-trail"
        prefix  = "alerts/"
        retention = "7 years"
      }
      prometheus = {
        enabled = true
        metrics = [
          "falco_alerts_total",
          "falco_rule_load_time",
          "falco_events_processed",
          "falco_events_dropped"
        ]
      }
    }
    slo_targets = {
      rule_evaluation     = "< 1ms per event"
      alert_generation   = "< 5s after event"
      log_export         = "< 30s per batch"
      webhook_delivery   = "< 2s per event"
      false_positive_rate = "< 5%"
      detection_latency  = "< 100ms p99"
    }
    performance_impact = {
      cpu_overhead    = "2-5% per host"
      memory_overhead = "50-100 MB"
      latency_impact  = "< 1ms per syscall"
      network_used    = "< 100 Kbps for logging"
    }
  }
}
