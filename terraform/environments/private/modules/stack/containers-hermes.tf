# @file terraform/environments/private/modules/stack/containers-hermes.tf
# @description Terraform-managed hermes-integration container — agent orchestration layer
# @governance GOV-002: Deterministic, audited agent lifecycle management

resource "docker_container" "hermes_integration" {
  name    = "code-server-hermes-integration"
  image   = local.app.hermes_integration
  user    = "1001:1001"
  restart = "unless-stopped"

  depends_on = [
    docker_container.agent_runtime,
    docker_container.agent_code_reviewer,
    docker_container.agent_incident_responder,
    docker_container.agent_doc_writer,
    docker_container.agent_test_generator,
  ]

  ports {
    internal = 8000
    external = 8000
  }

  env = [
    "HERMES_PORT=8000",
    "ENVIRONMENT=production",
    "LOG_LEVEL=INFO",
    "AGENT_RUNTIME_URL=http://code-server-agent-runtime:8020",
    "AGENT_CODE_REVIEWER_HOST=code-server-agent-code-reviewer",
    "AGENT_CODE_REVIEWER_PORT=9000",
    "AGENT_INCIDENT_RESPONDER_HOST=code-server-agent-incident-responder",
    "AGENT_INCIDENT_RESPONDER_PORT=9000",
    "AGENT_DOC_WRITER_HOST=code-server-agent-doc-writer",
    "AGENT_DOC_WRITER_PORT=9000",
    "AGENT_TEST_GENERATOR_HOST=code-server-agent-test-generator",
    "AGENT_TEST_GENERATOR_PORT=9000",
    "KAFKA_BROKER=${local.svc.kafka_broker}",
    "OPA_URL=${local.svc.opa_url}",
    "OTEL_ENDPOINT=${local.svc.otel_endpoint}",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/hermes-integration"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8000/health"]
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

  labels {
    label = "Environment"
    value = local.standard_tags.Environment
  }
  labels {
    label = "ManagedBy"
    value = local.standard_tags.ManagedBy
  }
  labels {
    label = "io.elevatediq.component"
    value = "hermes-integration"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "orchestration"
  }

  lifecycle {
    ignore_changes = [image, network_mode, mounts, ports, healthcheck, command, entrypoint]
  }
}
