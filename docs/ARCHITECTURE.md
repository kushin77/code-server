# System Architecture Overview

**Version**: 2.0  
**Last Updated**: April 24, 2026  
**Status**: Production  

## Executive Summary

The Paperclip system is a distributed, cloud-native platform providing enterprise IDE services, AI collaboration capabilities, and infrastructure lifecycle management. The architecture follows Domain-Driven Design (DDD) principles with clear separation between frontend, backend, infrastructure, and operational concerns.

## Architecture Principles

### Core Principles

1. **IaC-First**: All infrastructure is code; configuration is environment-driven
2. **Immutability**: Deployments are immutable; changes create new versions
3. **Idempotency**: Operations are idempotent and safe to re-run
4. **Auditability**: All changes are logged and traceable via Git
5. **Resilience**: High availability with automatic failover
6. **Security-by-Default**: Zero-trust principles, secrets management via GSM

### Design Patterns

- **Hexagonal Architecture**: Clear separation of concerns with domain at center
- **Event-Driven**: Services communicate via event streams (Kafka/Redpanda)
- **CQRS**: Separate read and write models where beneficial
- **Eventual Consistency**: Distributed transaction handling via sagas

## System Components

### Frontend Layer

#### VS Code Team Hub Extension
- **Purpose**: Unified IDE interface with collaboration capabilities
- **Technology**: TypeScript, VS Code SDK, React (for webviews)
- **Location**: `apps/extensions/team-hub/`
- **Key Features**:
  - Real-time collaboration (cursor tracking, presence awareness)
  - Integrated terminal with DLP scanning
  - Copilot integration for autonomous task execution
  - GitHub/GitLab integration

#### Code Server
- **Purpose**: Browser-based VS Code environment
- **Technology**: Node.js, TypeScript
- **Location**: Containerized (Docker)
- **Features**:
  - Persistent session storage via GSM
  - Multi-user support with role-based access
  - GPU acceleration for AI workloads

#### Portal Application
- **Purpose**: Administrative dashboard and user management
- **Technology**: React, TypeScript
- **Location**: `apps/frontend/portal/`
- **Features**:
  - User provisioning and lifecycle management
  - Team management and permissions
  - Resource monitoring dashboards

### Backend Layer

#### API Gateway (Port 3100)
- **Purpose**: Central entry point for all API requests
- **Technology**: Node.js, Express
- **Location**: `apps/api/`
- **Responsibilities**:
  - Request routing and load balancing
  - Authentication/Authorization (OAuth2, JWT)
  - Rate limiting and DDoS protection
  - Request logging and tracing

#### Core Services

##### Activity Feed Service
- **Purpose**: Track all user activities and audit logs
- **Location**: `apps/activity-feed/`
- **Data Store**: PostgreSQL, materialized views

##### Session Management
- **Purpose**: Manage IDE session lifecycle
- **Location**: `apps/session-broker/`
- **Features**:
  - Session persistence across reconnections
  - Automatic cleanup of stale sessions
  - Session replay capabilities

##### Knowledge Graph Service
- **Purpose**: Build and maintain semantic knowledge base
- **Location**: `apps/knowledge-graph/`
- **Storage**: PostgreSQL with graph extensions

##### Memory Engine
- **Purpose**: Persistent memory for AI models
- **Location**: `apps/memory-engine/`
- **Storage**: Redis (hot), PostgreSQL (cold)

##### Multimodal AI Service
- **Purpose**: Process text, images, code with AI models
- **Location**: `apps/multimodal-ai/`
- **Models**: Ollama, Claude, GPT-4 (configurable)

### Infrastructure Layer

#### Container Orchestration
- **Platform**: Docker Compose (development), Kubernetes (future)
- **Registry**: Private (self-hosted or ECR)
- **Images**: Multi-stage builds with minimal layers

#### Data Tier

##### PostgreSQL Database
- **Port**: 5432
- **Features**:
  - Replication (Patroni) for HA
  - WAL archiving for disaster recovery
  - Full-text search indexes
  - JSON/JSONB support for flexible schemas

##### Redis Cache
- **Port**: 6379
- **Configuration**: Sentinel for HA
- **Use Cases**:
  - Session caching
  - Rate limit tracking
  - Real-time collaboration state

##### Vector Database (Qdrant)
- **Port**: 6333
- **Purpose**: Semantic search for documentation and code
- **Integration**: Used by Knowledge Graph service

##### Search Engine (Elasticsearch/OpenSearch)
- **Port**: 9200
- **Purpose**: Full-text search across codebase
- **Indexes**: Code files, issues, documentation

#### Message Queue

##### Kafka/Redpanda
- **Port**: 9093
- **Topics**:
  - `user-activities` - Activity feed events
  - `deployment-events` - Infrastructure changes
  - `ai-tasks` - AI processing jobs
- **Retention**: 7 days (configurable)

#### Observability Stack

##### Prometheus
- **Port**: 9090
- **Targets**: All services, infrastructure components
- **Retention**: 15 days

##### Grafana
- **Port**: 3000
- **Dashboards**:
  - System health overview
  - Service-specific metrics
  - SLA compliance tracking

##### Jaeger Distributed Tracing
- **Port**: 16686
- **Purpose**: Trace requests across services
- **Sampling**: Adaptive (1% to 100%)

##### Loki Log Aggregation
- **Port**: 3100
- **Purpose**: Centralized log collection
- **Labels**: service, level, environment

#### Security & Access

##### Caddy Reverse Proxy
- **Port**: 80/443
- **Features**:
  - Automatic HTTPS (Let's Encrypt)
  - Request authentication
  - Security headers

##### OAuth2-Proxy
- **Port**: 4181
- **Purpose**: OAuth2/OIDC authentication layer
- **Providers**: GitHub, Google, custom OIDC

##### OPA (Open Policy Agent)
- **Port**: 8181
- **Purpose**: Policy enforcement for access control
- **Policies**: GAV (Git/API/Vault) integration

##### HashiCorp Vault
- **Port**: 8200
- **Purpose**: Secrets management
- **Backends**: GSM integration, Kubernetes auth

## Deployment Topology

### Multi-Replica Architecture

```
┌─────────────────────────────────────┐
│      Cloudflare DNS/Load Balancing  │
└────────────────────┬────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
    ┌───▼────────┐          ┌────▼────────┐
    │ Replica 1  │          │ Replica 2   │
    │ 192.168... │          │ 192.168...  │
    └───┬────────┘          └────┬────────┘
        │                         │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────┐
        │   Shared Storage (NAS)  │
        │    192.168.168.56       │
        └────────────────────────┘
```

### High Availability Strategy

- **Active-Active**: Both replicas serve traffic simultaneously
- **Health Checks**: Automatic failover on health check failure
- **Data Sync**: PostgreSQL streaming replication, Redis Sentinel
- **Session Affinity**: Sticky sessions with fallback to any replica

## Network Architecture

### External Access
- **HTTPS**: Cloudflare → Caddy (443)
- **Public DNS**: kushnir.cloud (apex), ide.kushnir.cloud (subdomain)

### Internal Network
- **Private VPN**: 192.168.168.0/24
- **Service Discovery**: DNS-based (Docker networks)
- **Inter-Service Communication**: Direct TCP/gRPC

## Data Flow

### User Request Flow

```
1. Browser HTTPS Request → Cloudflare
2. Cloudflare Routes → Replica Load Balancer (health-based)
3. Caddy TLS Termination → OAuth2-Proxy
4. OAuth2-Proxy Auth Check → OPA Policy Evaluation
5. Authorized Request → API Gateway
6. API Gateway Routes → Backend Service(s)
7. Service Queries → PostgreSQL/Redis/Vector DB
8. Response → API Gateway → OAuth2-Proxy → Caddy → Cloudflare → Browser
```

### Asynchronous Processing

```
User Action → Activity Feed Service → Kafka Topic
                                    → Subscriber Service 1
                                    → Subscriber Service 2
                                    → ... (event-driven cascade)
```

## Governance & Compliance

### Infrastructure as Code (IaC)
- **Version Control**: All infrastructure code in Git
- **Validation**: `terraform validate`, Docker Compose config validation
- **Immutability**: Tagged releases correspond to deployed infrastructure

### Security Posture
- **Secrets Management**: All credentials in Vault/GSM, never in code
- **Network Policies**: Zero-trust model, explicit allow rules
- **Audit Logging**: All API calls logged with user context
- **Compliance**: GDPR-compliant data handling

### Monitoring & Alerting
- **Metrics**: Prometheus scrapes all services every 30s
- **Alerts**: AlertManager routes to PagerDuty/Slack
- **SLA Tracking**: Automated SLA compliance reporting
- **Health Checks**: Every service exposes /health endpoint

## Disaster Recovery

### Backup Strategy
- **Database**: Continuous WAL archiving to S3-compatible storage
- **Application State**: Snapshot-based backups every 24 hours
- **RTO**: 15 minutes (warm standby ready)
- **RPO**: 1 hour (acceptable data loss window)

### Recovery Procedures
- **Infrastructure**: Terraform apply to rebuild from IaC
- **Data**: WAL recovery + snapshot restoration
- **Orchestration**: GitOps CD automatically syncs desired state

## Scaling Strategy

### Horizontal Scaling
- **Stateless Services**: Add replicas via Docker Compose replicas field
- **Database**: Partition large tables, add read replicas
- **Cache**: Redis Cluster mode for sharding

### Performance Optimization
- **CDN**: Cloudflare caches static assets
- **Database Query Optimization**: Query plans reviewed, indexes tuned
- **Caching Layers**: Multi-level caching (browser → CDN → Redis → DB)

## Technology Stack Summary

| Layer | Component | Technology | Purpose |
|-------|-----------|-----------|---------|
| Frontend | IDE | VS Code + TypeScript | Code editing interface |
| Frontend | Dashboard | React | Administrative UI |
| API | Gateway | Express.js | Request routing |
| Services | Multiple | Node.js | Microservices |
| Database | Primary | PostgreSQL | Relational data |
| Database | Search | Elasticsearch | Full-text search |
| Database | Vector | Qdrant | Semantic search |
| Cache | Session | Redis | Hot data cache |
| Queue | Events | Kafka/Redpanda | Event streaming |
| Observability | Metrics | Prometheus | Performance data |
| Observability | Visualization | Grafana | Dashboards |
| Observability | Tracing | Jaeger | Request tracing |
| Observability | Logs | Loki | Log aggregation |
| Infrastructure | Container | Docker | Containerization |
| Infrastructure | Orchestration | Docker Compose | Multi-host |
| Infrastructure | Code | Terraform | IaC |
| Security | Auth | OAuth2-Proxy | Authentication |
| Security | Policy | OPA | Authorization |
| Security | Secrets | Vault | Secret storage |
| Reverse Proxy | HTTP | Caddy | TLS + routing |

## Future Architecture Roadmap

### Phase 1: Kubernetes Migration
- Transition from Docker Compose to Kubernetes
- Helm charts for service deployment
- Service mesh (Istio) for observability

### Phase 2: Global Distribution
- Multi-region deployment
- Edge computing for reduced latency
- Global load balancing

### Phase 3: Advanced AI Integration
- Real-time code generation pipeline
- Multi-modal AI processing at scale
- Distributed model serving

## Design Decision Records (ADRs)

- **ADR-001**: Container-based deployment over VMs
- **ADR-002**: Unified identity via OAuth2-Proxy
- **ADR-003**: Dual-portal strategy (IDE + Admin)
- **ADR-004**: Event-driven architecture for scalability

## Related Documentation

- [Deployment Runbook](../operations/DEPLOYMENT-RUNBOOK.md)
- [Security Guide](../security/SECURITY-GUIDE.md)
- [API Reference](../api/API-REFERENCE.md)
- [Test Plan](../testing/TEST-PLAN.md)
