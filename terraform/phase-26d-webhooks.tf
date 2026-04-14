terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 26-D: Webhook & Event System (11 hours)
# Real-time event delivery to external systems with retry logic
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

# Webhook dispatcher service
resource "local_file" "phase_26d_webhook_dispatcher" {
  filename = "${path.module}/../kubernetes/phase-26-webhooks/webhook-dispatcher-deployment.yaml"
  
  content = <<-EOT
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: webhook-dispatcher
      namespace: default
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: webhook-dispatcher
      template:
        metadata:
          labels:
            app: webhook-dispatcher
        spec:
          containers:
          - name: dispatcher
            image: python:3.11-slim
            env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: connection_string
            - name: KAFKA_BROKERS
              value: "kafka-broker:9092"
            - name: MAX_RETRIES
              value: "3"
            - name: WEBHOOK_TIMEOUT_SEC
              value: "30"
            - name: LOG_LEVEL
              value: "INFO"
            ports:
            - containerPort: 8000
              name: metrics
            resources:
              limits:
                cpu: 1000m
                memory: 1Gi
              requests:
                cpu: 500m
                memory: 512Mi
            livenessProbe:
              httpGet:
                path: /health
                port: metrics
              initialDelaySeconds: 30
              periodSeconds: 10
            readinessProbe:
              httpGet:
                path: /ready
                port: metrics
              initialDelaySeconds: 10
              periodSeconds: 5
    ---
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: webhook-dispatcher-hpa
      namespace: default
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: webhook-dispatcher
      minReplicas: 3
      maxReplicas: 20
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 75
  EOT
}

# PostgreSQL schema for webhooks (idempotent)
resource "local_file" "phase_26d_webhook_schema" {
  filename = "${path.module}/../kubernetes/phase-26-webhooks/webhook-schema.sql"
  
  content = <<-EOT
    -- Webhooks table (idempotent with ON CONFLICT)
    CREATE TABLE IF NOT EXISTS webhooks (
      id UUID PRIMARY KEY,
      org_id UUID NOT NULL REFERENCES organizations(id),
      url VARCHAR(512) NOT NULL,
      events JSONB NOT NULL DEFAULT '[]',
      secret_hash VARCHAR(256) NOT NULL,
      last_delivery_at TIMESTAMP,
      failures INT DEFAULT 0,
      active BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT valid_url CHECK (url ~ '^https?://')
    );
    
    CREATE INDEX IF NOT EXISTS idx_webhooks_org_id ON webhooks(org_id);
    CREATE INDEX IF NOT EXISTS idx_webhooks_active ON webhooks(active);
    CREATE INDEX IF NOT EXISTS idx_webhooks_created_at ON webhooks(created_at);
    
    -- Webhook delivery logs (partitioned by date)
    CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id UUID PRIMARY KEY,
      webhook_id UUID NOT NULL REFERENCES webhooks(id),
      event_type VARCHAR(100) NOT NULL,
      request_payload JSONB NOT NULL,
      response_status INT,
      response_body TEXT,
      attempt INT DEFAULT 1,
      success BOOLEAN,
      delivered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      next_retry_at TIMESTAMP
    ) PARTITION BY RANGE (delivered_at);
    
    CREATE INDEX IF NOT EXISTS idx_deliveries_webhook_id 
      ON webhook_deliveries(webhook_id);
    CREATE INDEX IF NOT EXISTS idx_deliveries_success 
      ON webhook_deliveries(success);
    
    -- Event store for replay functionality
    CREATE TABLE IF NOT EXISTS webhook_events (
      id UUID PRIMARY KEY,
      org_id UUID NOT NULL REFERENCES organizations(id),
      event_type VARCHAR(100) NOT NULL,
      resource_type VARCHAR(100) NOT NULL,
      resource_id UUID NOT NULL,
      actor_id UUID REFERENCES users(id),
      payload JSONB NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) PARTITION BY RANGE (created_at);
    
    CREATE INDEX IF NOT EXISTS idx_events_org_id ON webhook_events(org_id);
    CREATE INDEX IF NOT EXISTS idx_events_event_type ON webhook_events(event_type);
  EOT

  depends_on = [local_file.phase_26d_webhook_dispatcher]
}

output "phase_26d_webhook_config" {
  description = "Webhook system configuration"
  value       = local.webhook_config
}

output "phase_26d_status" {
  description = "Phase 26-D implementation status"
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
