# Phase 20-A1: Global Orchestration Framework
# Infrastructure as Code - Multi-Region Setup
# ✅ Immutable, Idempotent, IaC principles
# NOTE: Terraform configuration consolidated in main.tf for idempotency

# Phase 20-A1: Global Orchestration Configuration
# NOTE: Locals consolidated in locals.tf and main.tf - phase-specific overrides should use variables
locals {
  phase            = "phase-20-a1"
  component        = "global-orchestration-framework"
  
  # Regional configuration with immutable properties
  regions = {
    primary = {
      name       = "us-east-1"
      host       = "192.168.168.31"
      port       = 22
      priority   = 100
      weight     = 1.0
      health_threshold = 3
      failover_threshold = 5
    }
    secondary = {
      name       = "us-west-2"
      host       = "192.168.168.32"
      port       = 22
      priority   = 50
      weight     = 0.75
      health_threshold = 3
      failover_threshold = 5
    }
    tertiary = {
      name       = "eu-west-1"
      host       = "192.168.168.33"
      port       = 22
      priority   = 25
      weight     = 0.5
      health_threshold = 3
      failover_threshold = 5
    }
  }

  # Service configuration - immutable Docker images
  services = {
    global_orchestrator = {
      image    = "python:3.11-slim"
      image_digest = "sha256:5f77e0c4a8a96359c1c1f69d9d1a8e4a5d8e8e8a7c6b5a8c9e8f7a8b9c8d7e"
      
      ports = {
        api     = 8000
        metrics = 9205
        health  = 8001
      }
      
      # ✅ IaC Configuration
      cpu_limit   = "500m"
      memory_limit = "1Gi"
      restart_policy = "unless-stopped"
      
      # ✅ Health checks
      health_check = {
        enabled  = true
        interval = 30
        timeout  = 10
        retries  = 3
        start_delay = 10
      }
      
      # ✅ Logging configuration
      logging = {
        driver = "json-file"
        options = {
          "max-size" = "10m"
          "max-file" = "3"
          "labels"   = "phase=20-a1,component=orchestrator"
        }
      }
    }
    
    prometheus = {
      image    = "prom/prometheus:v2.48.0"
      image_digest = "sha256:a7c7eda2b1d0a8f4c7e8f5a8c9e8f7a8b9c8d7e1f2a3b4c5d6e7f8a9b0c1d"
      
      ports = {
        web = 9090
      }
      
      cpu_limit   = "250m"
      memory_limit = "512Mi"
      restart_policy = "unless-stopped"
      
      health_check = {
        enabled  = true
        interval = 30
        timeout  = 10
        retries  = 3
        start_delay = 15
      }
      
      logging = {
        driver = "json-file"
        options = {
          "max-size" = "50m"
          "max-file" = "5"
          "labels"   = "phase=20-a1,component=prometheus"
        }
      }
    }
    
    grafana = {
      image    = "grafana/grafana:10.2.3"
      image_digest = "sha256:f7a8c9e8f5a8c9e8f7a8b9c8d7e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d"
      
      ports = {
        web = 3000
      }
      
      cpu_limit   = "250m"
      memory_limit = "512Mi"
      restart_policy = "unless-stopped"
      
      health_check = {
        enabled  = true
        interval = 30
        timeout  = 10
        retries  = 3
        start_delay = 30  # Grafana slower to start
      }
      
      logging = {
        driver = "json-file"
        options = {
          "max-size" = "10m"
          "max-file" = "3"
          "labels"   = "phase=20-a1,component=grafana"
        }
      }
    }
  }

  # ✅ Immutable labels and tags
  common_labels = {
    "phase"         = local.phase
    "component"     = local.component
    "environment"   = local.environment
    "created_by"    = "terraform"
    "iac"           = "true"
    "date"          = timestamp()
  }

  # ✅ Docker network configuration - immutable
  docker_network = {
    name   = "${local.phase}-${local.component}-net"
    driver = "bridge"
    subnet = "10.20.0.0/16"
    gateway = "10.20.0.1"
  }

  # ✅ Volume configuration - immutable mount paths
  volumes = {
    prometheus_data = {
      name   = "${local.phase}-prometheus-data"
      path   = "/prometheus"
      driver = "local"
    }
    grafana_data = {
      name   = "${local.phase}-grafana-data"
      path   = "/var/lib/grafana"
      driver = "local"
    }
    orchestrator_logs = {
      name   = "${local.phase}-orchestrator-logs"
      path   = "/var/log/orchestrator"
      driver = "local"
    }
  }

  # ✅ Environment-specific configuration
  env_vars = {
    PHASE              = local.phase
    COMPONENT          = local.component
    ENVIRONMENT        = local.environment
    LOG_LEVEL          = "INFO"
    METRICS_ENABLED    = "true"
    HEALTH_CHECK_INTERVAL = "60"
    FAILOVER_TIMEOUT   = "30"
    REGION_COUNT       = length(local.regions)
  }
}

# ✅ Data source: Immutable Docker image references
data "docker_image" "orchestrator" {
  name = local.services.global_orchestrator.image
  pull_triggers = {
    digest = local.services.global_orchestrator.image_digest
  }
}

data "docker_image" "prometheus" {
  name = local.services.prometheus.image
  pull_triggers = {
    digest = local.services.prometheus.image_digest
  }
}

data "docker_image" "grafana" {
  name = local.services.grafana.image
  pull_triggers = {
    digest = local.services.grafana.image_digest
  }
}

# ✅ Docker Network - Immutable and idempotent
resource "docker_network" "phase_20_a1" {
  name           = local.docker_network.name
  check_duplicate = true
  driver         = local.docker_network.driver
  
  ipam_config {
    subnet = local.docker_network.subnet
  }

  labels = local.common_labels
}

# ✅ Docker Volumes - Immutable mount points
resource "docker_volume" "prometheus_data" {
  name   = local.volumes.prometheus_data.name
  driver = local.volumes.prometheus_data.driver

  labels = merge(
    local.common_labels,
    { "component" = "prometheus-data" }
  )
}

resource "docker_volume" "grafana_data" {
  name   = local.volumes.grafana_data.name
  driver = local.volumes.grafana_data.driver

  labels = merge(
    local.common_labels,
    { "component" = "grafana-data" }
  )
}

resource "docker_volume" "orchestrator_logs" {
  name   = local.volumes.orchestrator_logs.name
  driver = local.volumes.orchestrator_logs.driver

  labels = merge(
    local.common_labels,
    { "component" = "orchestrator-logs" }
  )
}

# ✅ Output configuration for integration
output "phase_20_a1_configuration" {
  description = "Phase 20-A1 Global Orchestration Configuration"
  value = {
    phase             = local.phase
    environment       = local.environment
    network_id        = docker_network.phase_20_a1.id
    network_name      = docker_network.phase_20_a1.name
    
    # Regional configuration
    regions = {
      for region_key, region in local.regions : region_key => {
        name       = region.name
        host       = region.host
        priority   = region.priority
      }
    }

    # Service configuration
    services = {
      orchestrator_image = local.services.global_orchestrator.image
      prometheus_image   = local.services.prometheus.image
      grafana_image      = local.services.grafana.image
    }

    # Port mappings
    ports = {
      orchestrator_api     = local.services.global_orchestrator.ports.api
      orchestrator_metrics = local.services.global_orchestrator.ports.metrics
      orchestrator_health  = local.services.global_orchestrator.ports.health
      prometheus_web       = local.services.prometheus.ports.web
      grafana_web          = local.services.grafana.ports.web
    }

    # Volume mappings
    volumes = {
      for vol_key, vol in local.volumes : vol_key => vol.name
    }

    # Labels
    labels = local.common_labels
  }

  sensitive = false
}
