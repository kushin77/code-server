# ════════════════════════════════════════════════════════════════════════════
# Webhook & Event System — real-time delivery to external systems with retry
# Canonical K8s: kubernetes/webhooks/dispatcher.yaml
# Canonical migration: db/migrations/20260414000002-add-webhooks.sql
# Note: PostgreSQL-based event queue only — no Kafka dependency (on-prem)
# ════════════════════════════════════════════════════════════════════════════

# Webhook configuration (single source of truth)
locals {
  webhook_config = {
    supported_events = [
      "workspace.created",
      "workspace.updated",
      "workspace.deleted",
      "file.created",
      "file.modified",
      "file.deleted",
      "user.joined",
      "user.left",
      "user.disabled",
      "api_key.created",
      "api_key.rotated",
      "api_key.revoked",
      "organization.invited",
      "organization.joined"
    ]

    retry_policy = {
      max_attempts      = 3
      initial_delay_sec = 1
      backoff_strategy  = "exponential"
      max_delay_sec     = 60
    }

    signing = {
      algorithm  = "HMAC-SHA256"
      body_field = "X-Webhook-Signature"
    }

    timeout_sec         = 30
    delivery_sla_pct    = 0.9995
    max_payload_bytes   = 1048576 # 1MB
  }

  webhook_services = {
    dispatcher = {
      replicas     = 3
      image        = "python:3.11-slim"
      cpu_limit    = "1000m"
      memory_limit = "1Gi"
    }
    event_store = {
      name        = "webhook-event-store"
      retention   = "90 days"
      partitioned = true
    }
  }
}

# PostgreSQL migration for webhooks
# Canonical K8s manifest: kubernetes/webhooks/dispatcher.yaml
# Canonical migration: db/migrations/20260414000002-add-webhooks.sql
# Note: No Kafka dependency — on-prem stack uses PostgreSQL-based event queue only
resource "local_file" "webhook_migration" {
  filename = "${path.module}/../db/migrations/20260414000002-add-webhooks.sql"

  content = <<-SQL
    -- Webhooks schema migration (idempotent)
    -- Source of truth: terraform/webhooks.tf
    -- Canonical K8s: kubernetes/webhooks/dispatcher.yaml

    CREATE TABLE IF NOT EXISTS webhooks (
      id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      url             VARCHAR(512) NOT NULL,
      events          JSONB NOT NULL DEFAULT '[]',
      secret_hash     VARCHAR(256) NOT NULL,
      last_delivery_at TIMESTAMP,
      failures        INT DEFAULT 0,
      active          BOOLEAN DEFAULT TRUE,
      created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT valid_url CHECK (url ~ '^https?://')
    );

    CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      webhook_id      UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
      event_type      VARCHAR(100) NOT NULL,
      request_payload JSONB NOT NULL,
      response_status INT,
      response_body   TEXT,
      attempt         INT DEFAULT 1,
      success         BOOLEAN,
      delivered_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      next_retry_at   TIMESTAMP
    ) PARTITION BY RANGE (delivered_at);

    CREATE TABLE IF NOT EXISTS webhook_events (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      org_id        UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      event_type    VARCHAR(100) NOT NULL,
      resource_type VARCHAR(100) NOT NULL,
      resource_id   UUID NOT NULL,
      actor_id      UUID,
      payload       JSONB NOT NULL,
      created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) PARTITION BY RANGE (created_at);

    CREATE INDEX IF NOT EXISTS idx_webhooks_org_id    ON webhooks(org_id);
    CREATE INDEX IF NOT EXISTS idx_webhooks_active    ON webhooks(active);
    CREATE INDEX IF NOT EXISTS idx_deliveries_wh_id  ON webhook_deliveries(webhook_id);
    CREATE INDEX IF NOT EXISTS idx_deliveries_success ON webhook_deliveries(success);
    CREATE INDEX IF NOT EXISTS idx_events_org_id      ON webhook_events(org_id);
    CREATE INDEX IF NOT EXISTS idx_events_type        ON webhook_events(event_type);
  SQL
}

# PostgreSQL schema for webhooks already covered by the migration above.
# kubernetes/webhooks/ directory holds K8s deployment manifests only.

output "webhook_config" {
  description = "Webhook system configuration"
  value       = local.webhook_config
}

output "webhooks_status" {
  description = "Webhook system implementation status"
  value = {
    status                = "IMPLEMENTED"
    supported_events      = length(local.webhook_config.supported_events)
    max_retries           = local.webhook_config.retry_policy.max_attempts
    delivery_sla          = "${local.webhook_config.delivery_sla_pct * 100}%"
    signature_method      = local.webhook_config.signing.algorithm
    max_payload_bytes     = local.webhook_config.max_payload_bytes
    deployment            = "192.168.168.31"
  }
}
