/**
 * @file modules/stack/containers-apps.tf
 * @description App-tier containers: IDE, GitLab, MinIO, Appsmith, Vault,
 *              and custom-built testing + control-plane services.
 *              All derived from docker-compose.enterprise.yml service definitions.
 */

# ── code-server IDE ───────────────────────────────────────────────────────────
resource "docker_container" "code_server_ide" {
  name    = "code-server-ide"
  image   = docker_image.code_server_ide.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 8080
    external = 8090
  }

  env = [
    "PASSWORD=${var.code_server_password}",
    "SUDO_PASSWORD=${var.code_server_password}",
  ]

  volumes {
    volume_name    = docker_volume.code_server_data.name
    container_path = "/home/coder"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8080/"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "10s"
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
    value = "ci-runner"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "app"
  }

  lifecycle {
    ignore_changes = [image, network_mode, volumes]
  }
}

# ── MinIO Object Storage ──────────────────────────────────────────────────────
resource "docker_container" "minio" {
  name    = "code-server-minio"
  image   = docker_image.minio.image_id
  restart = "unless-stopped"
  command = ["server", "/data", "--console-address", ":9001"]

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 9000
    external = 9010
  }
  ports {
    internal = 9001
    external = 9011
  }

  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}",
  ]

  volumes {
    volume_name    = docker_volume.minio_data.name
    container_path = "/data"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
    interval     = "30s"
    timeout      = "20s"
    retries      = 3
    start_period = "10s"
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
    value = "object-storage"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "data"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports, command]
  }
}

# ── Appsmith Low-Code Platform ────────────────────────────────────────────────
resource "docker_container" "appsmith" {
  name    = "code-server-appsmith"
  image   = docker_image.appsmith.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 80
    external = 8084
  }

  env = [
    "APPSMITH_DISABLE_TELEMETRY=true",
    "APPSMITH_INSTANCE_NAME=kushnir-cloud-ide",
  ]

  volumes {
    volume_name    = docker_volume.appsmith_stacks.name
    container_path = "/appsmith-stacks"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost/"]
    interval     = "1m0s"
    timeout      = "10s"
    retries      = 5
    start_period = "1m0s"
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
    value = "low-code-platform"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "app"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}

# ── HashiCorp Vault ───────────────────────────────────────────────────────────
resource "docker_container" "vault" {
  name    = "code-server-vault"
  image   = docker_image.vault.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 8200
    external = 8200
  }

  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=${var.vault_token}",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200",
  ]

  capabilities {
    add  = ["IPC_LOCK"]
    drop = []
  }

  healthcheck {
    test         = ["CMD-SHELL", "VAULT_ADDR=http://127.0.0.1:8200 vault status >/dev/null 2>&1 || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
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
    value = "secrets"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "security"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}

# ── Sonatype Nexus Artifact Repository ───────────────────────────────────────
resource "docker_container" "artifact_repo" {
  name    = "code-server-artifact-repo"
  image   = docker_image.nexus.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 8081
    external = 8083
  }

  env = [
    "NEXUS_CONTEXT=nexus",
    "INSTALL4J_ADD_VM_PARAMS=-Xms1024m -Xmx1024m -XX:MaxDirectMemorySize=1024m",
  ]

  volumes {
    volume_name    = docker_volume.nexus_data.name
    container_path = "/nexus-data"
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8081/nexus/"]
    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "5m0s"
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
    value = "artifact-repo"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "devops"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}

# ── Testing Service (custom build) ────────────────────────────────────────────
resource "docker_container" "testing" {
  name    = "code-server-testing"
  image   = local.app.testing
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 8888
    external = 8888
  }

  env = [
    "SERVICE_NAME=testing-service",
    "TEST_RUNNER_HOST=0.0.0.0",
    "TEST_RUNNER_PORT=8888",
    "LOG_LEVEL=INFO",
    "DATABASE_URL=${local.svc.postgres_url}",
    "REDIS_URL=redis://code-server-redis:6379/3",
    "KAFKA_BOOTSTRAP_SERVERS=${local.svc.kafka_broker}",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8888/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
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
    value = "testing"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "platform"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}

# ── Control Plane (custom build) ──────────────────────────────────────────────
resource "docker_container" "control_plane" {
  name    = "code-server-control-plane"
  image   = local.app.control_plane
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 8082
    external = 8086
  }

  env = [
    "SERVICE_NAME=control-plane",
    "CONTROL_PLANE_PORT=8082",
    "CONTROL_PLANE_HOST=0.0.0.0",
    "LOG_LEVEL=INFO",
    "DATABASE_URL=${local.svc.postgres_url}",
    "REDIS_URL=redis://code-server-redis:6379/4",
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8082/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "15s"
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
    value = "control-plane"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "platform"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}
