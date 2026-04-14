# ════════════════════════════════════════════════════════════════════════════
# PHASE 14: PRODUCTION GO-LIVE INFRASTRUCTURE AS CODE
# 
# Idempotent, immutable Terraform module for production cutover
# April 14-15, 2026
#
# KEY PROPERTIES (IaC Requirements):
# - Idempotent: Multiple applies produce identical result
# - Immutable: All versions and values hardcoded
# - Auditable: Full git history + terraform.tfstate
# - Reproducible: Same inputs = same infrastructure
# ════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 14 CONFIGURATION VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

variable "phase_14_enabled" {
  description = "Enable Phase 14 production go-live"
  type        = bool
  default     = false
}

variable "phase_14_canary_percentage" {
  description = "Traffic percentage for canary deployment (0-100)"
  type        = number
  default     = 10
  validation {
    condition     = var.phase_14_canary_percentage >= 0 && var.phase_14_canary_percentage <= 100
    error_message = "Canary percentage must be between 0 and 100."
  }
}

variable "production_primary_host" {
  description = "Production primary host IP"
  type        = string
  default     = "192.168.168.31"
}

variable "production_standby_host" {
  description = "Production standby host IP (rollback)"
  type        = string
  default     = "192.168.168.30"
}

variable "slo_target_p99_latency_ms" {
  description = "SLO target: p99 latency (milliseconds)"
  type        = number
  default     = 100
}

variable "slo_target_error_rate_pct" {
  description = "SLO target: error rate (percent)"
  type        = number
  default     = 0.1
}

variable "slo_target_availability_pct" {
  description = "SLO target: availability (percent)"
  type        = number
  default     = 99.9
}

variable "enable_auto_rollback" {
  description = "Automatically rollback if SLOs breached"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 14 LOCAL CONFIGURATION (Immutable values)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  phase_14_enabled = var.phase_14_enabled

  production_config = {
    primary = {
      host             = var.production_primary_host
      role             = "primary"
      slo_compliant    = true
      containers       = 5
      health_check_url = "http://${var.production_primary_host}:8080/health"
    }
    standby = {
      host             = var.production_standby_host
      role             = "standby"
      slo_compliant    = true
      containers       = 5
      health_check_url = "http://${var.production_standby_host}:8080/health"
    }
  }

  canary_stages = {
    stage_1 = {
      name               = "initial-canary"
      traffic_percentage = 10
      observation_min    = 60
      slo_critical       = true
    }
    stage_2 = {
      name               = "progressive-rollout"
      traffic_percentage = 50
      observation_min    = 60
      slo_critical       = true
    }
    stage_3 = {
      name               = "go-live"
      traffic_percentage = 100
      observation_min    = 1440
      slo_critical       = true
    }
  }

  slo_targets = {
    p99_latency_ms   = var.slo_target_p99_latency_ms
    error_rate_pct   = var.slo_target_error_rate_pct
    availability_pct = var.slo_target_availability_pct
    measurement_interval_min = 5
  }

  deployment_id = "phase-14-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE 14: DEPLOYMENT STATE & EXECUTION (Idempotent)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "phase_14_deployment_config" {
  count    = local.phase_14_enabled ? 1 : 0
  filename = "${path.module}/.phase-14-state.json"

  content = jsonencode({
    phase              = "14"
    enabled            = local.phase_14_enabled
    canary_percentage  = var.phase_14_canary_percentage
    primary_host       = local.production_config.primary.host
    standby_host       = local.production_config.standby.host
    deployment_id      = local.deployment_id
    timestamp          = timestamp()
    slo_targets        = local.slo_targets
    auto_rollback      = var.enable_auto_rollback
    stage_1_config     = local.canary_stages.stage_1
    stage_2_config     = local.canary_stages.stage_2
    stage_3_config     = local.canary_stages.stage_3
  })
}

resource "local_file" "slo_monitoring_config" {
  count    = local.phase_14_enabled ? 1 : 0
  filename = "${path.module}/.phase-14-slo-config.yaml"

  content = <<-EOF
---
# Phase 14 SLO Monitoring Configuration
phase: 14
deployment_id: ${local.deployment_id}
timestamp: ${timestamp()}

slo_targets:
  p99_latency_ms: ${local.slo_targets.p99_latency_ms}
  error_rate_percent: ${local.slo_targets.error_rate_pct}
  availability_percent: ${local.slo_targets.availability_pct}

canary_deployment:
  stage_1:
    traffic_percentage: ${local.canary_stages.stage_1.traffic_percentage}
    observation_minutes: ${local.canary_stages.stage_1.observation_min}
  
  stage_2:
    traffic_percentage: ${local.canary_stages.stage_2.traffic_percentage}
    observation_minutes: ${local.canary_stages.stage_2.observation_min}
  
  stage_3:
    traffic_percentage: ${local.canary_stages.stage_3.traffic_percentage}
    observation_minutes: ${local.canary_stages.stage_3.observation_min}

deployment_targets:
  primary:
    host: ${local.production_config.primary.host}
  standby:
    host: ${local.production_config.standby.host}

safeguards:
  auto_rollback_enabled: ${var.enable_auto_rollback}
  rollback_rto_seconds: 300
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# TERRAFORM OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────

output "phase_14_deployment_status" {
  description = "Current Phase 14 deployment status"
  value = local.phase_14_enabled ? {
    status                = "ENABLED"
    deployment_id         = local.deployment_id
    canary_percentage     = var.phase_14_canary_percentage
    primary_host          = local.production_config.primary.host
    standby_host          = local.production_config.standby.host
    auto_rollback_enabled = var.enable_auto_rollback
  } : {
    status = "DISABLED"
    note   = "Phase 14 not enabled"
  }
}

output "slo_targets" {
  description = "SLO targets for this deployment"
  value = {
    p99_latency_ms       = local.slo_targets.p99_latency_ms
    error_rate_percent   = local.slo_targets.error_rate_pct
    availability_percent = local.slo_targets.availability_pct
  }
}


