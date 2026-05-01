/**
 * @file modules/stack/containers-agents.tf
 * @description AI Agent containers: code-reviewer, incident-responder, doc-writer, test-generator.
 *              All agents share the agent-runtime image with different AGENT_TYPE env vars.
 */

# ── Agent: Code Reviewer ──────────────────────────────────────────────────────
resource "docker_container" "agent_code_reviewer" {
  name    = "code-server-agent-code-reviewer"
  image   = local.app.agent_runtime
  user    = "1004:1004"
  restart = "unless-stopped"

  depends_on = [
    docker_container.agent_runtime,
    docker_container.reputation_engine,
    docker_container.execution_scheduler,
    docker_container.paperclip,
  ]

  ports {
    internal = 9000
    external = 9001
  }

  env = [
    "AGENT_TYPE=code-reviewer",
    "AGENT_RUNTIME_PORT=9000",
    "AGENT_RUNTIME_HOST=0.0.0.0",
    "ENVIRONMENT=production",
    "PAPERCLIP_URL=${local.svc.paperclip_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
    "SCHEDULER_URL=${local.svc.scheduler_url}",
    "OIDC_ISSUER=https://${var.auth_domain}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/agent-runtime"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9000/health"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }

}

# ── Agent: Incident Responder ─────────────────────────────────────────────────
resource "docker_container" "agent_incident_responder" {
  name    = "code-server-agent-incident-responder"
  image   = local.app.agent_runtime
  user    = "1004:1004"
  restart = "unless-stopped"

  depends_on = [
    docker_container.agent_runtime,
    docker_container.reputation_engine,
    docker_container.execution_scheduler,
    docker_container.paperclip,
  ]

  ports {
    internal = 9000
    external = 9002
  }

  env = [
    "AGENT_TYPE=incident-responder",
    "AGENT_RUNTIME_PORT=9000",
    "AGENT_RUNTIME_HOST=0.0.0.0",
    "ENVIRONMENT=production",
    "PAPERCLIP_URL=${local.svc.paperclip_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
    "SCHEDULER_URL=${local.svc.scheduler_url}",
    "OIDC_ISSUER=https://${var.auth_domain}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/agent-runtime"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9000/health"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }

}

# ── Agent: Doc Writer ─────────────────────────────────────────────────────────
resource "docker_container" "agent_doc_writer" {
  name    = "code-server-agent-doc-writer"
  image   = local.app.agent_runtime
  user    = "1004:1004"
  restart = "unless-stopped"

  depends_on = [
    docker_container.agent_runtime,
    docker_container.reputation_engine,
    docker_container.execution_scheduler,
    docker_container.paperclip,
  ]

  ports {
    internal = 9000
    external = 9003
  }

  env = [
    "AGENT_TYPE=doc-writer",
    "AGENT_RUNTIME_PORT=9000",
    "AGENT_RUNTIME_HOST=0.0.0.0",
    "ENVIRONMENT=production",
    "PAPERCLIP_URL=${local.svc.paperclip_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
    "SCHEDULER_URL=${local.svc.scheduler_url}",
    "OIDC_ISSUER=https://${var.auth_domain}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/agent-runtime"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9000/health"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }

}

# ── Agent: Test Generator ─────────────────────────────────────────────────────
resource "docker_container" "agent_test_generator" {
  name    = "code-server-agent-test-generator"
  image   = local.app.agent_runtime
  user    = "1004:1004"
  restart = "unless-stopped"

  depends_on = [
    docker_container.agent_runtime,
    docker_container.reputation_engine,
    docker_container.execution_scheduler,
    docker_container.paperclip,
  ]

  ports {
    internal = 9000
    external = 9004
  }

  env = [
    "AGENT_TYPE=test-generator",
    "AGENT_RUNTIME_PORT=9000",
    "AGENT_RUNTIME_HOST=0.0.0.0",
    "ENVIRONMENT=production",
    "PAPERCLIP_URL=${local.svc.paperclip_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
    "SCHEDULER_URL=${local.svc.scheduler_url}",
    "OIDC_ISSUER=https://${var.auth_domain}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/agent-runtime"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9000/health"]
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
  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }

}
