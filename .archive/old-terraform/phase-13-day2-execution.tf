# Phase 13 Day 2: Orchestration & Execution (IaC Configuration)
# ─────────────────────────────────────────────────────────────────────────────
# Terraform configuration for Phase 13 Day 2 load testing
# 
# This file defines the complete Phase 13 Day 2 execution as infrastructure code,
# ensuring reproducibility, idempotence, and immutability across deployments.
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
# NOTE: Terraform configuration consolidated in main.tf for idempotency

# ─────────────────────────────────────────────────────────────────────────────
# Phase 13 Day 2: Configuration Variables (IaC)
# ─────────────────────────────────────────────────────────────────────────────

variable "phase_13_config" {
  description = "Phase 13 Day 2 load testing configuration"
  type = object({
    target_host                 = string
    target_user                 = string
    deployment_directory        = string
    load_test_duration_seconds  = number
    concurrent_generators       = number
    monitoring_interval_seconds = number
    metrics_interval_seconds    = number
    request_timeout_seconds     = number
    docker_network              = string
    code_server_container       = string
    caddy_container             = string
    ssh_proxy_container         = string
  })

  default = {
    target_host                 = "192.168.168.31"
    target_user                 = "akushnir"
    deployment_directory        = "/tmp/code-server-phase13"
    load_test_duration_seconds  = 86400      # 24 hours
    concurrent_generators       = 5
    monitoring_interval_seconds = 30         # Every 30 seconds
    metrics_interval_seconds    = 300        # Every 5 minutes
    request_timeout_seconds     = 5
    docker_network              = "phase13-net"
    code_server_container       = "code-server-31"
    caddy_container             = "caddy-31"
    ssh_proxy_container         = "ssh-proxy-31"
  }
}

variable "slo_targets" {
  description = "SLO targets for Phase 13 Day 2"
  type = object({
    p99_latency_ms  = number
    error_rate_pct  = number
    availability_pct = number
    min_throughput_rps = number
  })

  default = {
    p99_latency_ms     = 100   # milliseconds
    error_rate_pct     = 0.1   # percentage
    availability_pct   = 99.9  # percentage
    min_throughput_rps = 50    # requests per second
  }
}

variable "execution_tags" {
  description = "Execution metadata tags"
  type = object({
    phase              = string
    day                = string
    execution_date     = string
    team               = string
    cost_center        = string
    environment        = string
  })

  default = {
    phase              = "phase-13"
    day                = "day-2"
    execution_date     = "2026-04-13"
    team               = "infrastructure"
    cost_center        = "code-server"
    environment        = "production"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Local Execution Configuration (IaC representation)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  execution_metadata = {
    phase                   = var.execution_tags.phase
    day                     = var.execution_tags.day
    execution_datetime      = "${var.execution_tags.execution_date}T180000Z"
    expected_completion     = "2026-04-14T170000Z"
    duration_hours          = var.phase_13_config.load_test_duration_seconds / 3600
    monitoring_enabled      = true
    metrics_collection_enabled = true
    load_generation_enabled = true
  }

  deployment_checklist = {
    monitoring_deployed        = "scripts/phase-13-day2-monitoring.sh"
    metrics_collection_deployed = "scripts/phase-13-day2-metrics-collection.sh"
    orchestrator_deployed       = "scripts/phase-13-day2-orchestrator.sh"
  }

  slo_validation_targets = {
    p99_latency_ms       = var.slo_targets.p99_latency_ms
    error_rate_threshold = var.slo_targets.error_rate_pct
    availability_target  = var.slo_targets.availability_pct
    throughput_min       = var.slo_targets.min_throughput_rps
  }

  infrastructure_requirements = {
    min_memory_gb            = 16
    min_disk_gb              = 50
    required_containers      = 3
    required_networks        = 1
    health_check_interval_sec = var.phase_13_config.monitoring_interval_seconds
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 13 Day 2: Execution Plan (IaC)
# ─────────────────────────────────────────────────────────────────────────────

resource "local_file" "phase_13_day2_execution_plan" {
  filename = "${path.module}/.terraform/phase-13-day2-execution-plan.json"

  content = jsonencode({
    metadata = local.execution_metadata
    configuration = {
      target_host                = var.phase_13_config.target_host
      deployed_directory         = var.phase_13_config.deployment_directory
      load_test_config = {
        duration_seconds       = var.phase_13_config.load_test_duration_seconds
        concurrent_generators  = var.phase_13_config.concurrent_generators
        request_timeout_sec    = var.phase_13_config.request_timeout_seconds
      }
      monitoring_config = {
        enabled              = true
        health_check_interval_sec = var.phase_13_config.monitoring_interval_seconds
        required_containers  = [
          var.phase_13_config.code_server_container,
          var.phase_13_config.caddy_container,
          var.phase_13_config.ssh_proxy_container
        ]
      }
      metrics_config = {
        enabled            = true
        collection_interval_sec = var.phase_13_config.metrics_interval_seconds
        captures = [
          "memory_utilization",
          "cpu_utilization",
          "container_stats",
          "response_times",
          "error_rates",
          "throughput"
        ]
      }
    }
    slo_targets = local.slo_validation_targets
    deployment_checklist = local.deployment_checklist
    expected_results = {
      format               = "JSON"
      contains_metrics     = true
      contains_health_data = true
      completion_timestamp = "2026-04-14T170000Z"
    }
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs (IaC Results)
# ─────────────────────────────────────────────────────────────────────────────

output "phase_13_day2_config" {
  description = "Phase 13 Day 2 execution configuration"
  value = {
    target_infrastructure = var.phase_13_config.target_host
    execution_start       = local.execution_metadata.execution_datetime
    expected_completion   = local.execution_metadata.expected_completion
    duration_hours        = local.execution_metadata.duration_hours
    slo_targets           = local.slo_validation_targets
    deployment_status     = "ACTIVE"
  }
}

output "execution_artifacts" {
  description = "Phase 13 Day 2 execution artifacts"
  value       = local.deployment_checklist
}

output "monitoring_status" {
  description = "Real-time monitoring configuration"
  value = {
    health_checks_interval_sec = var.phase_13_config.monitoring_interval_seconds
    metrics_collection_interval_sec = var.phase_13_config.metrics_interval_seconds
    required_containers = [
      var.phase_13_config.code_server_container,
      var.phase_13_config.caddy_container,
      var.phase_13_config.ssh_proxy_container
    ]
  }
}

output "load_test_configuration" {
  description = "Load test execution parameters"
  value = {
    duration_seconds       = var.phase_13_config.load_test_duration_seconds
    concurrent_generators  = var.phase_13_config.concurrent_generators
    request_timeout_sec    = var.phase_13_config.request_timeout_seconds
    target_url             = "http://${var.phase_13_config.target_host}/"
  }
}
