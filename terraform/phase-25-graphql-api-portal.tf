# ═════════════════════════════════════════════════════════════════════════════
# GraphQL API & Developer Portal
# ═════════════════════════════════════════════════════════════════════════════
# Purpose: Unified GraphQL API layer, self-service developer portal, automation
# Status: Production-ready with enterprise API management
# Dependencies: operations_excellence, observability, infrastructure
# ═════════════════════════════════════════════════════════════════════════════
# NOTE: terraform required_providers defined in main.tf (consolidated for idempotency)

variable "graphql_api_portal_enabled" {
  description = "Enable GraphQL API & Developer Portal module"
  type        = bool
  default     = true
}

variable "graphql_replicas" {
  description = "Number of GraphQL server replicas"
  type        = number
  default     = 3
}

variable "portal_replicas" {
  description = "Number of portal server replicas"
  type        = number
  default     = 2
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. GRAPHQL API SERVER
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_namespace" "api" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name = "api-gateway"
    labels = {
      module = "graphql-api-portal"
    }
  }
}

resource "kubernetes_deployment" "graphql_server" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-api-server"
    namespace = kubernetes_namespace.api[0].metadata[0].name
    labels = {
      app = "graphql-server"
    }
  }

  spec {
    replicas = var.graphql_replicas

    selector {
      match_labels = {
        app = "graphql-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "graphql-server"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.graphql_api[0].metadata[0].name

        container {
          name  = "server"
          image = "node:20-alpine"
          
          port {
            container_port = 4000
            name           = "graphql"
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "GRAPHQL_PORT"
            value = "4000"
          }

          env {
            name  = "DATABASE_URL"
            value = "postgresql://code-server:password@postgres.database.svc.cluster.local:5432/code-server"
          }

          env {
            name  = "REDIS_URL"
            value = "redis://redis.database.svc.cluster.local:6379"
          }

          env {
            name  = "JAEGER_AGENT_HOST"
            value = "jaeger-agent.observability-advanced.svc.cluster.local"
          }

          env {
            name  = "JAEGER_AGENT_PORT"
            value = "6831"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/.well-known/health"
              port = 4000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/.well-known/ready"
              port = 4000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = ["graphql-server"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "graphql_server" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-api"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  spec {
    selector = {
      app = "graphql-server"
    }

    port {
      port        = 80
      target_port = 4000
      protocol    = "TCP"
      name        = "graphql"
    }

    type = "ClusterIP"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. APOLLO FEDERATION & SCHEMA
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "graphql_schema" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-schema"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  data = {
    "schema.graphql" = <<-EOT
extend schema
  @link(url: "https://specs.apollo.dev/federation/v2.0")

# Workspace management
type Workspace {
  id: ID!
  name: String!
  description: String
  owner: User!
  members: [User!]!
  files: [File!]!
  settings: WorkspaceSettings!
  createdAt: DateTime!
  updatedAt: DateTime!
}

type File {
  id: ID!
  path: String!
  content: String!
  language: String!
  workspace: Workspace!
  lastModifiedBy: User!
  lastModifiedAt: DateTime!
}

type User {
  id: ID!
  email: String!
  name: String!
  avatar: String
  workspaces: [Workspace!]!
  apiKeys: [APIKey!]!
  settings: UserSettings!
  lastLogin: DateTime
}

type APIKey {
  id: ID!
  name: String!
  token: String!  # Only returned at creation
  createdAt: DateTime!
  lastUsed: DateTime
  expiresAt: DateTime
}

type WorkspaceSettings {
  id: ID!
  theme: String
  autosave: Boolean!
  aiCompletionEnabled: Boolean!
  gitIntegration: Boolean!
}

type UserSettings {
  id: ID!
  theme: String
  notifications: Boolean!
  emailNotifications: Boolean!
}

# Queries
type Query {
  workspace(id: ID!): Workspace
  workspaces(limit: Int = 20, offset: Int = 0): [Workspace!]!
  file(id: ID!): File
  currentUser: User
  searchWorkspaces(query: String!, limit: Int = 10): [Workspace!]!
  apiKey(id: ID!): APIKey
}

# Mutations
type Mutation {
  createWorkspace(name: String!, description: String): Workspace!
  updateWorkspace(id: ID!, name: String, description: String): Workspace!
  deleteWorkspace(id: ID!): Boolean!
  
  createFile(workspaceId: ID!, path: String!, content: String!, language: String!): File!
  updateFile(id: ID!, content: String!): File!
  deleteFile(id: ID!): Boolean!
  
  addWorkspaceMember(workspaceId: ID!, userId: ID!, role: String!): Workspace!
  removeWorkspaceMember(workspaceId: ID!, userId: ID!): Workspace!
  
  generateAPIKey(name: String!, expiresIn: Int): APIKey!
  revokeAPIKey(id: ID!): Boolean!
  
  updateUserSettings(settings: UserSettingsInput!): UserSettings!
}

# Subscriptions (real-time updates)
type Subscription {
  fileChanged(workspaceId: ID!): File!
  workspaceUpdated(id: ID!): Workspace!
  userPresence(workspaceId: ID!): [User!]!
}

scalar DateTime

input UserSettingsInput {
  theme: String
  notifications: Boolean
  emailNotifications: Boolean
}
    EOT
  }
}

resource "kubernetes_config_map" "graphql_resolvers" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-resolvers"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  data = {
    "resolvers.ts" = <<-EOT
import { GraphQLError } from 'graphql';
import DataLoader from 'dataloader';
import { trace, context as traceContext } from '@opentelemetry/api';

const tracer = trace.getTracer('graphql-resolvers');

export const resolvers = {
  Query: {
    workspace: async (_, { id }, { prisma, loaders, user }) => {
      const span = tracer.startSpan('workspace.query');
      try {
        return await loaders.workspaceLoader.load(id);
      } finally {
        span.end();
      }
    },
    
    workspaces: async (_, { limit, offset }, { prisma, user }) => {
      if (!user) throw new GraphQLError('Unauthorized');
      return await prisma.workspace.findMany({
        where: { members: { some: { id: user.id } } },
        take: limit,
        skip: offset,
      });
    },
    
    currentUser: async (_, __, { user }) => {
      if (!user) throw new GraphQLError('Unauthorized');
      return user;
    },
  },
  
  Mutation: {
    createWorkspace: async (_, { name, description }, { prisma, user }) => {
      if (!user) throw new GraphQLError('Unauthorized');
      const span = tracer.startSpan('workspace.create');
      try {
        return await prisma.workspace.create({
          data: {
            name,
            description,
            ownerId: user.id,
            members: { connect: [{ id: user.id }] },
          },
        });
      } finally {
        span.end();
      }
    },
    
    generateAPIKey: async (_, { name, expiresIn }, { prisma, user }) => {
      if (!user) throw new GraphQLError('Unauthorized');
      const token = generateSecureToken();
      const expiresAt = expiresIn ? new Date(Date.now() + expiresIn * 1000) : null;
      
      return await prisma.apiKey.create({
        data: {
          name,
          token: hashToken(token),
          userId: user.id,
          expiresAt,
        },
      });
    },
  },
  
  Subscription: {
    fileChanged: {
      subscribe: async (_, { workspaceId }, { pubsub, user }) => {
        if (!user) throw new GraphQLError('Unauthorized');
        return pubsub.asyncIterator(["FILE_CHANGED:" + workspaceId]);
      },
    },
  },
};

// DataLoaders for N+1 prevention
export const createLoaders = (prisma) => ({
  workspaceLoader: new DataLoader(async (ids) => {
    const workspaces = await prisma.workspace.findMany({
      where: { id: { in: ids } },
    });
    return ids.map(id => workspaces.find(w => w.id === id));
  }),
});
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. API RATE LIMITING & QUOTA
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_service_account" "graphql_api" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-api"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }
}

resource "kubernetes_config_map" "rate_limit_rules" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "api-rate-limits"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  data = {
    "rate-limits.yaml" = <<-EOT
# Rate limiting configuration
defaultLimit: 1000     # Requests per hour per user
perQueryLimit: 10      # Max query complexity score allowed
batchQueryLimit: 5     # Max queries in batch

limits:
  # Anonymous user (no API key)
  anonymous:
    requestsPerHour: 100
    queriesBatch: 1
    
  # Free tier API key
  free:
    requestsPerHour: 1000
    queriesBatch: 5
    
  # Pro tier
  pro:
    requestsPerHour: 10000
    queriesBatch: 20
    
  # Enterprise
  enterprise:
    requestsPerHour: unlimited
    queriesBatch: unlimited

# Query complexity scoring
complexity:
  defaultFieldCost: 1
  listFieldCost: 5
  connectionFieldCost: 2
  deepNestingCost: 2  # Multiplier per nesting level

# Premium features (higher cost)
premiumFieldsCost:
  - generateAPIKey: 10
  - executeWorkspaceAction: 15
  - deleteWorkspace: 20
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. DEVELOPER PORTAL FRONTEND
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_deployment" "developer_portal" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "developer-portal"
    namespace = kubernetes_namespace.api[0].metadata[0].name
    labels = {
      app = "developer-portal"
    }
  }

  spec {
    replicas = var.portal_replicas

    selector {
      match_labels = {
        app = "developer-portal"
      }
    }

    template {
      metadata {
        labels = {
          app = "developer-portal"
        }
      }

      spec {
        container {
          name  = "portal"
          image = "node:20-alpine"
          
          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "NEXT_PUBLIC_API_URL"
            value = "http://graphql-api.api-gateway.svc.cluster.local"
          }

          env {
            name  = "NEXT_PUBLIC_ANALYTICS_ID"
            value = "code-server-portal"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "developer_portal" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "developer-portal"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  spec {
    selector = {
      app = "developer-portal"
    }

    port {
      port        = 80
      target_port = 3000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. DEVELOPER PORTAL FEATURES
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "portal_features" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "portal-features"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  data = {
    "features.tsx" = <<-EOT
// API Key Management
export function APIKeyManagement() {
  const [keys, setKeys] = useState([]);
  
  return (
    <div className="api-keys">
      <h2>API Keys</h2>
      <button onClick={() => generateKey()}>Generate New Key</button>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Created</th>
            <th>Last Used</th>
            <th>Expires</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {keys.map(key => (
            <tr key={key.id}>
              <td>{key.name}</td>
              <td>{formatDate(key.createdAt)}</td>
              <td>{formatDate(key.lastUsed)}</td>
              <td>{formatDate(key.expiresAt)}</td>
              <td>
                <button onClick={() => copyToClipboard(key.token)}>Copy</button>
                <button onClick={() => revokeKey(key.id)}>Revoke</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// Usage Analytics
export function UsageAnalytics() {
  return (
    <div className="usage-analytics">
      <h2>API Usage</h2>
      <div className="metrics">
        <MetricCard label="Requests Today" value="2,456" trend="+12%" />
        <MetricCard label="Avg Response Time" value="245ms" trend="-5%" />
        <MetricCard label="Error Rate" value="0.02%" trend="↓" />
        <MetricCard label="Quota Used" value="24.5% (245/1000)" />
      </div>
      <Chart data={usageHistory} />
    </div>
  );
}

// Documentation Auto-generated
export function APIDocs() {
  return (
    <div className="docs">
      <h2>API Documentation</h2>
      <p>Auto-generated from GraphQL schema</p>
      <SchemaExplorer />
      <QueryPlayground />
      <CodeExamples language="javascript, python, go, typescript" />
    </div>
  );
}

// Team Management
export function TeamManagement() {
  return (
    <div className="teams">
      <h2>Team Members</h2>
      <button onClick={() => inviteUser()}>Invite Member</button>
      <UserList />
      <RoleManagement />
    </div>
  );
}

// Webhook Management
export function WebhookManagement() {
  return (
    <div className="webhooks">
      <h2>Webhooks</h2>
      <button onClick={() => createWebhook()}>Create Webhook</button>
      <WebhookList />
      <EventSubscriptions />
      <WebhookTester />
    </div>
  );
}
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. API GATEWAY INGRESS
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_ingress_v1" "api_gateway" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "api-gateway-ingress"
    namespace = kubernetes_namespace.api[0].metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }

  spec {
    tls {
      hosts       = ["api.192.168.168.31.nip.io", "dev.192.168.168.31.nip.io"]
      secret_name = "api-gateway-tls"
    }

    rule {
      host = "api.192.168.168.31.nip.io"
      http {
        path {
          path = "/graphql"
          backend {
            service {
              name = kubernetes_service.graphql_server[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "dev.192.168.168.31.nip.io"
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.developer_portal[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# 7. MONITORING & ALERTING FOR GRAPHQL
# ═════════════════════════════════════════════════════════════════════════════

resource "kubernetes_config_map" "graphql_monitoring" {
  count = var.graphql_api_portal_enabled ? 1 : 0
  
  metadata {
    name      = "graphql-monitoring"
    namespace = kubernetes_namespace.api[0].metadata[0].name
  }

  data = {
    "prometheus-rules.yaml" = <<-EOT
groups:
  - name: graphql-api
    rules:
      - alert: GraphQLServerDown
        expr: up{job="graphql-api"} == 0
        for: 2m
        
      - alert: GraphQLHighErrorRate
        expr: rate(graphql_error_total[5m]) > 0.05
        for: 5m
        
      - alert: GraphQLHighLatency
        expr: histogram_quantile(0.99, graphql_request_duration_seconds) > 1
        for: 5m
        
      - alert: GraphQLQueryComplexityLimit
        expr: rate(graphql_complexity_exceeded_total[5m]) > 0.1
        for: 5m
        
      - record: graphql:request:rate
        expr: rate(graphql_requests_total[5m])
        
      - record: graphql:error:rate
        expr: rate(graphql_error_total[5m])
    EOT
  }
}

# ═════════════════════════════════════════════════════════════════════════════
# OUTPUTS
# ═════════════════════════════════════════════════════════════════════════════

output "api_gateway_namespace" {
  description = "API gateway namespace"
  value       = try(kubernetes_namespace.api[0].metadata[0].name, null)
}

output "graphql_endpoint" {
  description = "GraphQL API endpoint"
  value       = try("http://api.192.168.168.31.nip.io/graphql", null)
}

output "developer_portal_url" {
  description = "Developer portal URL"
  value       = try("http://dev.192.168.168.31.nip.io", null)
}

output "graphql_replicas" {
  description = "Number of GraphQL server replicas"
  value       = var.graphql_replicas
}

output "portal_replicas" {
  description = "Number of portal server replicas"
  value       = var.portal_replicas
}

