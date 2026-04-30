/**
 * @file modules/stack/containers-platform.tf
 * @description Platform services: paperclip, execution-scheduler, env-provisioner,
 *              activity-feed, edge-agent.
 */

# ── Paperclip (Governance Plane) ──────────────────────────────────────────────
resource "docker_container" "paperclip" {
  name    = "code-server-paperclip"
  image   = local.app.paperclip
  user    = "1002:1002"
  restart = "unless-stopped"

  depends_on = [
    docker_container.postgres,
    docker_container.opa,
    docker_container.reputation_engine,
  ]

  ports {
    internal = 8007
    external = 8007
  }

  env = [
    "OPA_URL=${local.svc.opa_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
    "DATABASE_URL=${local.svc.postgres_url}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/paperclip"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8010/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  networks_advanced {
    name = docker_network.database.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  lifecycle {
    ignore_changes = [network_mode, mounts]
  }

}

# ── Execution Scheduler ───────────────────────────────────────────────────────
resource "docker_container" "execution_scheduler" {
  name    = "code-server-execution-scheduler"
  image   = local.app.execution_scheduler
  user    = "1003:1003"
  restart = "unless-stopped"

  depends_on = [
    docker_container.postgres,
    docker_container.redpanda,
  ]

  env = [
    "KAFKA_BROKER=${local.svc.kafka_broker}",
    "DATABASE_URL=${local.svc.postgres_url}",
    "SCHEDULER_API_KEY=${var.scheduler_api_key}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/execution-scheduler"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8080/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  networks_advanced {
    name = docker_network.database.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  lifecycle {
    ignore_changes = [network_mode, mounts]
  }

}

# ── Environment Provisioner (Control Plane) ───────────────────────────────────
resource "docker_container" "env_provisioner" {
  name    = "code-server-env-provisioner"
  image   = local.app.env_provisioner
  user    = "1002:1002"
  restart = "unless-stopped"

  ports {
    internal = 8000
    external = 8000
  }

  env = [
    "LOG_LEVEL=INFO",
    "REPO_ROOT=/app",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/env-provisioner"
    type   = "bind"
  }

  mounts {
    target    = "/app/config"
    source    = "${local.repo}/config"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/app/artifacts"
    source = "${local.repo}/artifacts"
    type   = "bind"
  }

  mounts {
    target    = "/app/docker-compose.yml"
    source    = "${local.repo}/docker-compose.yml"
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8050/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.ingress.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  lifecycle {
    ignore_changes = [network_mode, mounts]
  }

}

# ── Activity Feed ─────────────────────────────────────────────────────────────
resource "docker_container" "activity_feed" {
  name    = "code-server-activity-feed"
  image   = local.app.activity_feed
  user    = "1001:1001"
  restart = "unless-stopped"

  depends_on = [docker_container.redpanda]

  ports {
    internal = 8004
    external = 8004
  }

  env = [
    "KAFKA_BROKER=${local.svc.kafka_broker}",
    "LOG_LEVEL=INFO",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

}

# ── Edge Agent ────────────────────────────────────────────────────────────────
resource "docker_container" "edge_agent" {
  name    = "code-server-edge-agent"
  image   = local.app.edge_agent
  restart = "unless-stopped"

  depends_on = [
    docker_container.redis,
    docker_container.redpanda,
  ]

  ports {
    internal = 8002
    external = 8002
  }

  env = [
    "AGENT_ID=${local.edge_agent_id}",
    "REDIS_URL=redis://code-server-redis:6379/1",
    "KAFKA_BOOTSTRAP_SERVERS=${local.svc.kafka_broker}",
    "REPLICATION_TOPIC=edge.replication.events",
    "LOG_LEVEL=INFO",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8060/health"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "15s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file
  lifecycle {
    ignore_changes = [network_mode, mounts]
  }

}
