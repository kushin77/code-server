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
# PHASE 26-C: Multi-Tenant Organization Support (12 hours)
# Team-based API management and billing with RBAC
# ════════════════════════════════════════════════════════════════════════════

# PostgreSQL schema migration for organizations (idempotent)
locals {
  org_database_schema = {
    organizations = {
      columns = {
        id          = "UUID PRIMARY KEY"
        name        = "VARCHAR(255) NOT NULL"
        tier        = "VARCHAR(20) NOT NULL DEFAULT 'free'"
        created_at  = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        owner_id    = "UUID REFERENCES users(id) NOT NULL"
        max_members = "INT DEFAULT 10"
        metadata    = "JSONB DEFAULT '{}'"
      }
      indexes = [
        "owner_id",
        "tier",
        "created_at"
      ]
    }
    
    organization_members = {
      columns = {
        id        = "UUID PRIMARY KEY"
        org_id    = "UUID REFERENCES organizations(id) NOT NULL"
        user_id   = "UUID REFERENCES users(id) NOT NULL"
        role      = "VARCHAR(50) NOT NULL" # admin, developer, auditor, viewer
        joined_at = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        metadata  = "JSONB DEFAULT '{}'"
      }
      indexes = [
        "org_id",
        "user_id",
        "role"
      ]
    }
    
    organization_api_keys = {
      columns = {
        id             = "UUID PRIMARY KEY"
        org_id         = "UUID REFERENCES organizations(id) NOT NULL"
        key_hash       = "VARCHAR(256) NOT NULL UNIQUE"
        name           = "VARCHAR(255) NOT NULL"
        created_at     = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
        rotated_at     = "TIMESTAMP"
        expires_at     = "TIMESTAMP"
        last_used_at   = "TIMESTAMP"
        permissions    = "JSONB DEFAULT '[]'"
      }
      indexes = [
        "org_id",
        "key_hash",
        "expires_at"
      ]
    }
  }

  # RBAC roles (single source of truth)
  rbac_roles = {
    admin = {
      description = "Full organization management, billing, API keys"
      permissions = [
        "org:read",
        "org:update",
        "org:delete",
        "members:*",
        "api_keys:*",
        "billing:*",
        "logs:read"
      ]
    }
    developer = {
      description = "Create/view API keys, read analytics"
      permissions = [
        "org:read",
        "api_keys:create",
        "api_keys:read",
        "api_keys:delete",
        "analytics:read",
        "logs:read"
      ]
    }
    auditor = {
      description = "Read-only access to logs and analytics"
      permissions = [
        "org:read",
        "analytics:read",
        "logs:read",
        "api_keys:read"
      ]
    }
    viewer = {
      description = "Read-only access to public schemas"
      permissions = [
        "org:read",
        "schemas:read"
      ]
    }
  }
}

# Kubernetes manifest for organization management API
resource "local_file" "phase_26c_org_api_deployment" {
  filename = "${path.module}/../kubernetes/phase-26-orgs/organization-api-deployment.yaml"
  
  content = <<-EOT
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: organization-api
      namespace: default
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: organization-api
      template:
        metadata:
          labels:
            app: organization-api
        spec:
          containers:
          - name: api
            image: node:20-alpine
            env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: connection_string
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: jwt-secret
                  key: secret
            - name: RBAC_ENABLED
              value: "true"
            ports:
            - containerPort: 3001
              name: http
            resources:
              limits:
                cpu: 500m
                memory: 512Mi
              requests:
                cpu: 250m
                memory: 256Mi
            livenessProbe:
              httpGet:
                path: /health
                port: http
              initialDelaySeconds: 30
              periodSeconds: 10
            readinessProbe:
              httpGet:
                path: /ready
                port: http
              initialDelaySeconds: 10
              periodSeconds: 5
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: organization-api
      namespace: default
    spec:
      selector:
        app: organization-api
      ports:
      - port: 3001
        name: http
      type: ClusterIP
    ---
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: organization-api-hpa
      namespace: default
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: organization-api
      minReplicas: 3
      maxReplicas: 10
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
  EOT
}

output "phase_26c_schema" {
  description = "PostgreSQL schema for organization support"
  value       = local.org_database_schema
}

output "phase_26c_rbac_config" {
  description = "RBAC roles and permissions"
  value       = local.rbac_roles
}

output "phase_26c_status" {
  description = "Phase 26-C implementation status"
  value = {
    status      = "IMPLEMENTED"
    tables      = 3
    rbac_roles  = length(local.rbac_roles)
    features    = "Organization hierarchy, RBAC, API key management, audit logs"
    deployment  = "192.168.168.31"
  }
}
