/**
 * @file modules/stack/containers-data.tf
 * @description Data layer containers: postgres, redis, redpanda, redpanda-console, qdrant.
 *              These are the stateful backbone — started before all application services.
 */

# ── PostgreSQL ────────────────────────────────────────────────────────────────
resource "docker_container" "postgres" {
  name    = "code-server-postgres"
  image   = docker_image.postgres.image_id
  user    = "999:999"
  restart = "unless-stopped"

  depends_on = [docker_container.postgres_init]

  env = [
    "POSTGRES_DB=${var.db_name}",
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "POSTGRES_INITDB_ARGS=--encoding=UTF8",
  ]

  # Only bind the host port on primary — replica host port 5432 is occupied
  # by other cluster workloads. Replica postgres remains accessible via docker
  # network to all code-server services on that host.
  dynamic "ports" {
    for_each = var.host_role == "primary" ? [5432] : []
    content {
      internal = ports.value
      external = ports.value
    }
  }

  mounts {
    target = "/var/lib/postgresql/data"
    source = docker_volume.postgres_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.db_user}"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "10s"
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
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "database"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "data"
  }
}

# ── Redis ─────────────────────────────────────────────────────────────────────
resource "docker_container" "redis" {
  name    = "code-server-redis"
  image   = docker_image.redis.image_id
  user    = "999:999"
  restart = "unless-stopped"

  depends_on = [docker_container.redis_init]

  command = var.redis_password != "" ? ["redis-server", "--appendonly", "yes", "--requirepass", var.redis_password] : ["redis-server", "--appendonly", "yes"]

  ports {
    internal = 6379
    external = 6379
  }

  mounts {
    target = "/data"
    source = docker_volume.redis_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD", "redis-cli", "--raw", "incr", "ping"]
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

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "cache"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "data"
  }
}

# ── Redpanda (Kafka-compatible event bus) ────────────────────────────────────
resource "docker_container" "redpanda" {
  name    = "code-server-redpanda"
  image   = docker_image.redpanda.image_id
  user    = "101:101"
  restart = "unless-stopped"

  depends_on = [docker_container.redpanda_init]

  command = [
    "redpanda", "start",
    "--kafka-addr=PLAINTEXT://0.0.0.0:29092,OUTSIDE://0.0.0.0:9092",
    "--advertise-kafka-addr=PLAINTEXT://redpanda:29092,OUTSIDE://redpanda:9092",
    "--pandaproxy-addr=0.0.0.0:8082",
    "--advertise-pandaproxy-addr=redpanda:8082",
    "--schema-registry-addr=0.0.0.0:8081",
    "--rpc-addr=0.0.0.0:33145",
    "--advertise-rpc-addr=redpanda:33145",
  ]

  ports {
    internal = 9092
    external = 9092
  }
  ports {
    internal = 29092
    external = 29092
  }
  ports {
    internal = 8082
    external = 8082
  }
  ports {
    internal = 8081
    external = 8081
  }
  ports {
    internal = 33145
    external = 33145
  }

  env = [
    "REDPANDA_BROKERS=redpanda:9092",
    "TZ=UTC",
  ]

  mounts {
    target = "/var/lib/redpanda/data"
    source = docker_volume.redpanda_data.name
    type   = "volume"
  }

  mounts {
    target    = "/redpanda-src"
    source    = local.repo
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD-SHELL", "curl -fsS http://localhost:9644/v1/status/ready"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "30s"
  }

  networks_advanced {
    name    = docker_network.services.id
    aliases = ["redpanda"]
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file_large

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "event-bus"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }
}

# ── Redpanda Console (Kafka UI) ───────────────────────────────────────────────
resource "docker_container" "redpanda_console" {
  name    = "code-server-redpanda-console"
  image   = docker_image.redpanda_console.image_id
  user    = "101:101"
  restart = "unless-stopped"

  depends_on = [docker_container.redpanda]

  ports {
    internal = 8080
    external = 8003
  }

  env = [
    "KAFKA_BROKERS=redpanda:9092",
    "KAFKA_SCHEMAREGISTRY_ENABLED=true",
    "KAFKA_SCHEMAREGISTRY_URLS=http://redpanda:8081",
    "CONSOLE_CONFIG_FILEPATH=/etc/redpanda/redpanda-console-config.yaml",
    "SERVER_LISTENPORT=8080",
  ]

  mounts {
    target    = "/redpanda-console-src"
    source    = local.repo
    type      = "bind"
    read_only = true
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8080/overview"]
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

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "event-bus-ui"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "infrastructure"
  }
}

# ── Qdrant (Vector Database) ──────────────────────────────────────────────────
resource "docker_container" "qdrant" {
  name    = "code-server-qdrant"
  image   = docker_image.qdrant.image_id
  user    = "1000:1000"
  restart = "unless-stopped"

  depends_on = [docker_container.qdrant_init]

  ports {
    internal = 6333
    external = 6333
  }
  ports {
    internal = 6334
    external = 6334
  }

  env = [
    "QDRANT_API_KEY=${var.qdrant_api_key}",
    "QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage",
    "QDRANT__STORAGE__SNAPSHOTS_PATH=/qdrant/storage/snapshots",
    "QDRANT__STORAGE__WAL_PATH=/qdrant/storage/wal",
  ]

  mounts {
    target    = "/qdrant/config/local_config.yaml"
    source    = "${local.repo}/config/qdrant-config.yaml"
    type      = "bind"
    read_only = true
  }

  mounts {
    target = "/qdrant/storage"
    source = docker_volume.qdrant_data.name
    type   = "volume"
  }

  healthcheck {
    test         = ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/6333' || exit 1"]
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

  lifecycle {
    ignore_changes = [image, network_mode, mounts]
  }

  labels {
    label = "io.elevatediq.component"
    value = "vector-db"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "data"
  }
}
