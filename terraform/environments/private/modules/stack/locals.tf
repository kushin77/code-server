/**
 * @file modules/stack/locals.tf
 * @description Computed locals — image tags, port map, env var map, repo-relative paths.
 *              All container env blocks reference these locals so changes flow from one place.
 */

locals {
  # ── Repo path on the remote host ────────────────────────────────────────────
  repo = var.remote_repo_path

  # ── Role-specific values ─────────────────────────────────────────────────────
  edge_agent_id = var.edge_agent_id != "" ? var.edge_agent_id : "edge-agent-${var.host_role}"

  # ── Pre-built image references (pinned digests from docker-compose.yml) ──────
  img = {
    alpine         = "alpine:3.20@sha256:c64c687cbea9300178b30c95835354e34c4e4febc4badfe27102879de0483b5e"
    caddy          = "caddy:2.7.4@sha256:505de4e957da923672a8c79f16581e9b717a2479a8d5ddb909ab2d1b351f2ba4"
    keepalived     = "keepalived:2.2.7"  # Must match docker-compose.yml:340
    opa            = "openpolicyagent/opa:0.58.0@sha256:63186b7f0d95e51cf4c7ee38cae6fd2cf9168020abd09d48104bd87c99f863fe"
    oauth2_proxy   = "quay.io/oauth2-proxy/oauth2-proxy:v7.5.1@sha256:e797b3934eb8d7cb2756b67e59be2ef29c18c2b45da763f540ece66d843cec85"
    prometheus     = "prom/prometheus:v2.48.0@sha256:b440bc0e8aa5bab44a782952c09516b6a50f9d7b2325c1ffafac7bc833298e2e"
    grafana        = "grafana/grafana:10.2.0@sha256:1ee0c54286b8ca09a3dd1419ff8653e7780a148a006ac088544203bb0affe550"
    loki           = "grafana/loki:2.9.4@sha256:f379a20ce9dd815884ed6446aad8819b81a8ba4d36b548ca14be8cecbc6cbca0"
    alertmanager   = "prom/alertmanager:v0.27.0@sha256:e13b6ed5cb929eeaee733479dce55e10eb3bc2e9c4586c705a4e8da41e5eacf5"
    qdrant         = "qdrant/qdrant:v1.7.0@sha256:ff1639878418c0572f50a7e1314874e399537eb97e6d2f42d6b987a07a2c4c4f"
    postgres       = "postgres:16-alpine@sha256:4e6e670bb069649261c9c18031f0aded7bb249a5b6664ddec29c013a89310d50"
    redis          = "redis:7-alpine@sha256:7aec734b2bb298a1d769fd8729f13b8514a41bf90fcdd1f38ec52267fbaa8ee6"
    redpanda       = "docker.redpanda.com/redpandadata/redpanda:v26.1.6@sha256:e5b6aaecf38861d199b0d26d635b83da26dd6e6acf0684cd8b92f16b4f4b8733"
    redpanda_console = "docker.redpanda.com/redpandadata/console:v3.7.1@sha256:d5ec9a54339db74d8efa61b18576185903694bee1deb4c029befa492e41ac78f"
    ollama         = "ollama/ollama:0.1.16@sha256:3a3ec7ea8e006aea63ce13b7027069687ed34cc85bbd7bbebf1f565db587511a"
    otel_collector = "otel/opentelemetry-collector-contrib:0.96.0@sha256:ef20ffeb9ae06d75f94bd031cde7713a1d1bcad20e5ebc0f7dc6c2ee52b8ae4a"
    tempo          = "grafana/tempo:2.4.1@sha256:cf1ed1d5cc671c80d389f7c59cfa491a9e5b99d28a42fccb9d6cbbef0da378e4"

    # ── App-tier services ────────────────────────────────────────────────────
    code_server_ide = "codercom/code-server:4.19.0"
    gitlab          = "gitlab/gitlab-ce:15.11.11-ce.0"
    gitlab_runner   = "gitlab/gitlab-runner:latest"
    minio           = "minio/minio:latest"
    appsmith        = "appsmith/appsmith-ce:latest"
    vault           = "hashicorp/vault:1.13.0"
    nexus           = "sonatype/nexus3:3.68.1"
  }

  # ── Custom-built app image references (locally built on host) ────────────────
  # Images are built directly on each host from apps/ source tree.
  # Registry is not required — containers reference local image name:tag.
  app = {
    memory_engine        = "code-server-memory-engine:${var.app_image_tag}"
    multimodal_ai        = "code-server-multimodal-ai:${var.app_image_tag}"
    reputation_engine    = "code-server-reputation-engine:${var.app_image_tag}"
    agent_runtime        = "code-server-agent-runtime:${var.app_image_tag}"
    activity_feed        = "code-server-activity-feed:${var.app_image_tag}"
    paperclip            = "code-server-paperclip:${var.app_image_tag}"
    execution_scheduler  = "code-server-execution-scheduler:${var.app_image_tag}"
    env_provisioner      = "code-server-env-provisioner:${var.app_image_tag}"
    edge_agent           = "code-server-edge-agent:${var.app_image_tag}"
    testing              = "code-server-enterprise-testing:${var.app_image_tag}"
    control_plane        = "code-server-control-plane:${var.app_image_tag}"
  }

  # ── Standard logging config ───────────────────────────────────────────────────
  log_json_file = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  log_json_file_large = {
    "max-size" = "20m"
    "max-file" = "5"
  }

  # ── Service endpoint map (used in container env vars) ────────────────────────
  svc = {
    postgres_url          = "postgresql://${var.db_user}:${urlencode(var.db_password)}@code-server-postgres:5432/${var.db_name}"
    kafka_broker          = "code-server-redpanda:9092"
    opa_url               = "http://code-server-opa:8181"
    ollama_url            = "http://code-server-ollama:11434"
    qdrant_host           = "code-server-qdrant"
    reputation_url        = "http://code-server-reputation-engine:8002"
    paperclip_url         = "http://code-server-paperclip:8007"
    scheduler_url         = "http://code-server-execution-scheduler:8001"
    otel_endpoint         = "http://code-server-otel-collector:4317"
  }
}
