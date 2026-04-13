# Phase 14: Production Go-Live Execution Framework (IaC)
# ─────────────────────────────────────────────────────────────────────────────
# Terraform configuration for Phase 14 production go-live coordination
#
# This file defines the complete Phase 14 execution parameters as infrastructure code,
# ensuring consistent, reproducible, immutable deployments.
#
# Phases:
#   14.1: DNS Cutover & Traffic Routing
#   14.2: Production Monitoring Activation
#   14.3: Blue-Green Deployment Validation
#   14.4: Traffic Migration & Canary Testing
#   14.5: Rollback Procedures & SLO Verification

terraform {
  required_version = ">= 1.0"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14: Configuration Variables (IaC)
# ─────────────────────────────────────────────────────────────────────────────

variable "phase_14_config" {
  description = "Phase 14 production go-live configuration"
  type = object({
    environment             = string
    deployment_date         = string
    deployment_shift        = string    # UTC time window
    production_host         = string
    production_port_http    = number
    production_port_https   = number
    primary_domain          = string
    cdn_domain              = string
    monitoring_enabled      = bool
    health_check_interval   = number
    rollback_enabled        = bool
    canary_traffic_percent  = number
  })

  default = {
    environment             = "production"
    deployment_date         = "2026-04-14"
    deployment_shift        = "08:00-10:00 UTC"
    production_host         = "192.168.168.31"
    production_port_http    = 80
    production_port_https   = 443
    primary_domain          = "ide.kushnir.cloud"
    cdn_domain              = "cdn.kushnir.cloud"
    monitoring_enabled      = true
    health_check_interval   = 30
    rollback_enabled        = true
    canary_traffic_percent  = 10
  }
}

variable "phase_14_slo_targets" {
  description = "Production SLO targets for Phase 14"
  type = object({
    p99_latency_ms      = number
    error_rate_pct      = number
    availability_pct    = number
    min_throughput_rps  = number
  })

  default = {
    p99_latency_ms      = 100       # milliseconds
    error_rate_pct      = 0.1       # percentage
    availability_pct    = 99.95     # production target
    min_throughput_rps  = 500       # for production scale
  }
}

variable "phase_14_deployment_schedule" {
  description = "Phase 14 deployment schedule and actions"
  type = object({
    pre_flight_duration_min  = number
    cutover_duration_min     = number
    post_launch_duration_min = number
    rollback_decision_min    = number
  })

  default = {
    pre_flight_duration_min  = 30    # Health checks, verification
    cutover_duration_min     = 90    # DNS + routing + canary
    post_launch_duration_min = 60    # Monitoring, early issues
    rollback_decision_min    = 120   # Final decision window
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Local Configuration & Computed Values
# ─────────────────────────────────────────────────────────────────────────────

locals {
  phase_14_metadata = {
    phase                   = "phase-14"
    phase_name              = "Production Go-Live"
    phase_description       = "DNA cutover, traffic routing, production monitoring"
    deployment_date         = var.phase_14_config.deployment_date
    deployment_window       = var.phase_14_config.deployment_shift
    expected_go_live_time   = "08:30 UTC"
    expected_stable_time    = "11:30 UTC (3 hours post-launch)"
  }

  phase_14_stages = {
    stage_1 = {
      name        = "Pre-Flight Checks (30 minutes)"
      duration_min = var.phase_14_deployment_schedule.pre_flight_duration_min
      activities = [
        "Health endpoint verification",
        "SSL/TLS certificate validation",
        "Database connectivity test",
        "Cache layer verification",
        "DNS resolution test",
        "Monitoring dashboards check",
        "Alert thresholds verification",
        "Team readiness confirmation"
      ]
    }
    stage_2 = {
      name        = "DNS Cutover & Routing (90 minutes)"
      duration_min = var.phase_14_deployment_schedule.cutover_duration_min
      activities = [
        "Update DNS A/AAAA records (ide.kushnir.cloud -> .31)",
        "Verify DNS propagation globally",
        "Update CDN origin records",
        "Configure Caddy routing rules",
        "Start canary traffic routing (10%)",
        "Monitor error rates during cutover",
        "Watch latency metrics closely"
      ]
    }
    stage_3 = {
      name        = "Post-Launch Monitoring (60 minutes)"
      duration_min = var.phase_14_deployment_schedule.post_launch_duration_min
      activities = [
        "Monitor p99 latency trend",
        "Verify error rate <0.1%",
        "Check memory/CPU utilization",
        "Monitor disk space usage",
        "Verify all 3 containers healthy",
        "Canary traffic health assessment",
        "User session validation",
        "Early incident detection"
      ]
    }
    stage_4 = {
      name        = "Go/No-Go Decision (120 minutes)"
      duration_min = var.phase_14_deployment_schedule.rollback_decision_min
      activities = [
        "Assess all SLO metrics",
        "Review incident log",
        "Verify business continuity",
        "Team sign-off collection",
        "Decision: Proceed to 100% or Rollback",
        "Execute decision actions"
      ]
    }
  }

  phase_14_slo_validation = {
    p99_latency = {
      target           = var.phase_14_slo_targets.p99_latency_ms
      phase_13_baseline = 42
      alert_threshold  = 150          # 1.5x phase 13 baseline
    }
    error_rate = {
      target          = var.phase_14_slo_targets.error_rate_pct
      alert_threshold = 0.5           # 5x target
    }
    availability = {
      target          = var.phase_14_slo_targets.availability_pct
      alert_threshold = 99.95         # Match target
    }
    throughput = {
      target = var.phase_14_slo_targets.min_throughput_rps
      phase_13_baseline = 150
    }
  }

  phase_14_rollback_triggers = {
    trigger_1 = "Single error rate exceeds 1.0% (10x target)"
    trigger_2 = "p99 latency exceeds 300ms for >2 consecutive minutes"
    trigger_3 = "Container crash or restart detected"
    trigger_4 = "Disk space drops below 10% available"
    trigger_5 = "Team decision at any checkpoint"
    trigger_6 = "Database connectivity loss"
  }

  phase_14_success_criteria = {
    metric_1 = "p99 latency <100ms maintained for 120+ minutes"
    metric_2 = "Error rate <0.1% maintained for 120+ minutes"
    metric_3 = "Availability >99.9% for entire go-live window"
    metric_4 = "Zero unplanned container restarts"
    metric_5 = "All critical endpoints responding HTTP 200"
    metric_6 = "Memory usage <80% sustained"
    metric_7 = "Disk space >20% available"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 14 Execution Plan (IaC Representation)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "phase_14_execution_plan" {
  filename = "${path.module}/.terraform/phase-14-go-live-plan.json"

  content = jsonencode({
    metadata = local.phase_14_metadata
    schedule = {
      pre_flight        = local.phase_14_stages.stage_1
      dns_cutover       = local.phase_14_stages.stage_2
      post_launch       = local.phase_14_stages.stage_3
      go_no_go_decision = local.phase_14_stages.stage_4
    }
    infrastructure = {
      production_host  = var.phase_14_config.production_host
      http_port        = var.phase_14_config.production_port_http
      https_port       = var.phase_14_config.production_port_https
      primary_domain   = var.phase_14_config.primary_domain
      cdn_domain       = var.phase_14_config.cdn_domain
      monitoring       = var.phase_14_config.monitoring_enabled
      canary_traffic   = var.phase_14_config.canary_traffic_percent
    }
    slo_validation = local.phase_14_slo_validation
    rollback_triggers = local.phase_14_rollback_triggers
    success_criteria = local.phase_14_success_criteria
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs (Phase 14 Configuration Summary)
# ─────────────────────────────────────────────────────────────────────────────

output "phase_14_deployment_info" {
  description = "Phase 14 go-live deployment information"
  value = {
    phase           = local.phase_14_metadata.phase
    environment     = var.phase_14_config.environment
    deployment_date = local.phase_14_metadata.deployment_date
    deployment_window = local.phase_14_metadata.deployment_window
    expected_go_live = local.phase_14_metadata.expected_go_live_time
    expected_stable  = local.phase_14_metadata.expected_stable_time
    primary_domain   = var.phase_14_config.primary_domain
  }
}

output "phase_14_execution_timeline" {
  description = "Phase 14 detailed execution timeline"
  value = {
    stage_1 = local.phase_14_stages.stage_1.name
    stage_2 = local.phase_14_stages.stage_2.name
    stage_3 = local.phase_14_stages.stage_3.name
    stage_4 = local.phase_14_stages.stage_4.name
    total_duration_min = (
      var.phase_14_deployment_schedule.pre_flight_duration_min +
      var.phase_14_deployment_schedule.cutover_duration_min +
      var.phase_14_deployment_schedule.post_launch_duration_min +
      var.phase_14_deployment_schedule.rollback_decision_min
    )
  }
}

output "phase_14_slo_targets" {
  description = "Production SLO targets for Phase 14"
  value       = var.phase_14_slo_targets
}

output "phase_14_success_criteria" {
  description = "Phase 14 success criteria for go-live"
  value       = local.phase_14_success_criteria
}
