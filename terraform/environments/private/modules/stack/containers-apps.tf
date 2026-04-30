/**
 * @file modules/stack/containers-apps.tf
 * @description App-tier containers: IDE, GitLab, MinIO, Appsmith, Vault, Nexus,
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
    label = "io.elevatediq.component"
    value = "ide"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "app"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports]
  }
}

# ── GitLab CE ─────────────────────────────────────────────────────────────────
resource "docker_container" "gitlab" {
  name    = "code-server-gitlab"
  image   = docker_image.gitlab.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  ports {
    internal = 80
    external = 8101
  }
  ports {
    internal = 443
    external = 8444
  }
  ports {
    internal = 22
    external = 2223
  }

  env = [
    "GITLAB_OMNIBUS_CONFIG=external_url 'http://gitlab.kushnir.cloud'; gitlab_rails['gitlab_shell_ssh_port'] = 2222; gitlab_rails['db_adapter'] = 'postgresql'; gitlab_rails['db_host'] = 'code-server-postgres'; gitlab_rails['db_username'] = '${var.db_user}'; gitlab_rails['db_password'] = '${var.db_password}'; gitlab_rails['db_database'] = 'gitlabdb'; nginx['redirect_http_to_https'] = false; puma['worker_processes'] = 0;",
    "GITLAB_SKIP_UNMIGRATED_DATA_CHECK=true",
  ]

  volumes {
    volume_name    = docker_volume.gitlab_config.name
    container_path = "/etc/gitlab"
  }
  volumes {
    volume_name    = docker_volume.gitlab_logs.name
    container_path = "/var/log/gitlab"
  }
  volumes {
    volume_name    = docker_volume.gitlab_data.name
    container_path = "/var/opt/gitlab"
  }

  healthcheck {
    test         = ["CMD-SHELL", "for attempt in 1 2 3 4 5; do curl -fsS http://localhost/help >/dev/null && exit 0; sleep 2; done; exit 1"]
    interval     = "1m0s"
    timeout      = "10s"
    retries      = 3
    start_period = "2m0s"
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

  labels {
    label = "io.elevatediq.component"
    value = "source-control"
  }
  labels {
    label = "io.elevatediq.tier"
    value = "app"
  }

  lifecycle {
    ignore_changes = [image, network_mode, ports, env]
  }
}

# ── GitLab Runner ─────────────────────────────────────────────────────────────
resource "docker_container" "gitlab_runner" {
  name    = "code-server-gitlab-runner"
  image   = docker_image.gitlab_runner.image_id
  restart = "unless-stopped"

  networks_advanced {
    name = docker_network.services.id
  }

  env = [
    "CI_SERVER_URL=http://code-server-gitlab:80/",
    "REGISTRATION_TOKEN=${var.gitlab_runner_token}",
    "RUNNER_EXECUTOR=docker",
    "DOCKER_HOST=unix:///var/run/docker.sock",
  ]

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
  volumes {
    volume_name    = docker_volume.gitlab_runner_data.name
    container_path = "/home/gitlab-runner"
  }

  healthcheck {
    test         = ["CMD", "gitlab-runner", "list", "--config", "/etc/gitlab-runner/config.toml"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "40s"
  }

  log_driver = "json-file"
  log_opts   = local.log_json_file

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
