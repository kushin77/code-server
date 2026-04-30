/**
 * @file modules/stack/images.tf
 * @description docker_image resources — pulls all pre-built images to this host.
 *              terraform plan shows which images need to be pulled/updated.
 *              keep_locally = true so images persist if containers are destroyed.
 */

# ── Shared base ───────────────────────────────────────────────────────────────
resource "docker_image" "alpine" {
  name         = local.img.alpine
  keep_locally = true
}

# ── Infrastructure ────────────────────────────────────────────────────────────
resource "docker_image" "caddy" {
  name         = local.img.caddy
  keep_locally = true
}

resource "docker_image" "keepalived" {
  name         = local.img.keepalived
  keep_locally = true
}

resource "docker_image" "opa" {
  name         = local.img.opa
  keep_locally = true
}

resource "docker_image" "oauth2_proxy" {
  name         = local.img.oauth2_proxy
  keep_locally = true
}

# ── Observability ─────────────────────────────────────────────────────────────
resource "docker_image" "prometheus" {
  name         = local.img.prometheus
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = local.img.grafana
  keep_locally = true
}

resource "docker_image" "loki" {
  name         = local.img.loki
  keep_locally = true
}

resource "docker_image" "alertmanager" {
  name         = local.img.alertmanager
  keep_locally = true
}

resource "docker_image" "otel_collector" {
  name         = local.img.otel_collector
  keep_locally = true
}

resource "docker_image" "tempo" {
  name         = local.img.tempo
  keep_locally = true
}

# ── Data layer ────────────────────────────────────────────────────────────────
resource "docker_image" "postgres" {
  name         = local.img.postgres
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = local.img.redis
  keep_locally = true
}

resource "docker_image" "redpanda" {
  name         = local.img.redpanda
  keep_locally = true
}

resource "docker_image" "redpanda_console" {
  name         = local.img.redpanda_console
  keep_locally = true
}

resource "docker_image" "qdrant" {
  name         = local.img.qdrant
  keep_locally = true
}

# ── AI ────────────────────────────────────────────────────────────────────────
resource "docker_image" "ollama" {
  name         = local.img.ollama
  keep_locally = true
}

# ── App-tier services ─────────────────────────────────────────────────────────
resource "docker_image" "code_server_ide" {
  name         = local.img.code_server_ide
  keep_locally = true
}

resource "docker_image" "gitlab" {
  name         = local.img.gitlab
  keep_locally = true
}

resource "docker_image" "gitlab_runner" {
  name         = local.img.gitlab_runner
  keep_locally = true
}

resource "docker_image" "minio" {
  name         = local.img.minio
  keep_locally = true
}

resource "docker_image" "appsmith" {
  name         = local.img.appsmith
  keep_locally = true
}

resource "docker_image" "vault" {
  name         = local.img.vault
  keep_locally = true
}

resource "docker_image" "nexus" {
  name         = local.img.nexus
  keep_locally = true
}

# ── Custom app images ─────────────────────────────────────────────────────────
# Custom app images are built directly on each host from source (apps/ tree).
# No docker_image resources needed — containers reference local name:tag directly.
# Build is handled by: ssh <host> "cd ~/code-server-enterprise && docker compose build <svc>"
