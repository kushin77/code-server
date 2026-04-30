/**
 * @file modules/stack/containers-ai.tf
 * @description AI/ML services: memory-engine, multimodal-ai, reputation-engine, agent-runtime.
 *              All images come from the internal registry (apps built from source).
 */

# ── Memory Engine ─────────────────────────────────────────────────────────────
resource "docker_container" "memory_engine" {
  name    = "code-server-memory-engine"
  image   = local.app.memory_engine
  user    = "1000:1000"
  restart = "unless-stopped"

  depends_on = [
    docker_container.qdrant,
    docker_container.ollama,
  ]

  ports {
    internal = 8001
    external = 8001
  }

  env = [
    "QDRANT_HOST=code-server-qdrant",
    "QDRANT_PORT=6333",
    "QDRANT_API_KEY=${var.qdrant_api_key}",
    "OLLAMA_HOST=${local.svc.ollama_url}",
    "MEMORY_ENGINE_PORT=8001",
    "MEMORY_ENGINE_HOST=0.0.0.0",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/memory-engine"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8001/health"]
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
    label = "io.elevatediq.component"
    value = "memory-engine"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "ai"
  }

  lifecycle {
    ignore_changes = [image, network_mode, mounts, ports, healthcheck, command, entrypoint]
  }
}

# ── Multimodal AI ─────────────────────────────────────────────────────────────
resource "docker_container" "multimodal_ai" {
  name    = "code-server-multimodal-ai"
  image   = local.app.multimodal_ai
  user    = "1000:1000"
  restart = "unless-stopped"

  depends_on = [docker_container.ollama]

  ports {
    internal = 8005
    external = 8005
  }

  env = [
    "VISION_BACKEND=ollama",
    "OLLAMA_BASE_URL=${local.svc.ollama_url}",
    "OLLAMA_VISION_MODEL=llava:13b",
    "OLLAMA_MODEL=llama3:8b",
    "DIAGRAM_LLM_BACKEND=ollama",
    "OPENAI_API_KEY=",
    "WHISPER_MODEL=base",
    "TTS_BACKEND=gtts",
    "LOG_LEVEL=INFO",
  ]

  healthcheck {
    test         = ["CMD-SHELL", "curl -f http://localhost:8040/health || exit 1"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "20s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  labels {
    label = "io.elevatediq.component"
    value = "multimodal-ai"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "ai"
  }

  lifecycle {
    ignore_changes = [image, network_mode, mounts, ports, healthcheck, command, entrypoint]
  }
}

# ── Reputation Engine ─────────────────────────────────────────────────────────
resource "docker_container" "reputation_engine" {
  name    = "code-server-reputation-engine"
  image   = local.app.reputation_engine
  user    = "1001:1001"
  restart = "unless-stopped"

  depends_on = [
    docker_container.postgres,
    docker_container.redpanda,
    docker_container.opa,
  ]

  ports {
    internal = 8002
    external = 8006
    ip       = "0.0.0.0"
    protocol = "tcp"
  }

  env = [
    "DATABASE_URL=${local.svc.postgres_url}",
    "KAFKA_BROKER=${local.svc.kafka_broker}",
    "OPA_URL=${local.svc.opa_url}",
    "LOG_LEVEL=INFO",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/reputation_engine"
    type   = "bind"
    read_only = false
  }

  networks_advanced {
    name = docker_network.services.id
  }

  networks_advanced {
    name = docker_network.database.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  labels {
    label = "io.elevatediq.component"
    value = "reputation-engine"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "ai"
  }

  lifecycle {
    ignore_changes = [image, network_mode, mounts, ports, healthcheck, command, entrypoint]
  }
}

# ── Agent Runtime ─────────────────────────────────────────────────────────────
resource "docker_container" "agent_runtime" {
  name    = "code-server-agent-runtime"
  image   = local.app.agent_runtime
  user    = "1003:1003"
  restart = "unless-stopped"

  depends_on = [
    docker_container.opa,
    docker_container.reputation_engine,
  ]

  ports {
    internal = 9005
    external = 9005
  }

  env = [
    "AGENT_RUNTIME_PORT=9005",
    "AGENT_RUNTIME_HOST=0.0.0.0",
    "LOG_LEVEL=INFO",
    "OPA_URL=${local.svc.opa_url}",
    "REPUTATION_ENGINE_URL=${local.svc.reputation_url}",
  ]

  mounts {
    target = "/app"
    source = "${local.repo}/apps/agent-runtime"
    type   = "bind"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8020/health"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 3
    start_period = "10s"
  }

  networks_advanced {
    name = docker_network.services.id
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  labels {
    label = "io.elevatediq.component"
    value = "agent-runtime"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "ai"
  }

  lifecycle {
    ignore_changes = [image, network_mode, mounts, ports, healthcheck, command, entrypoint]
  }
}
