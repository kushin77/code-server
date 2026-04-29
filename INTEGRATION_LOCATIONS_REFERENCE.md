# Integration Points - Code Location Reference

**Purpose**: Pinpoint every external integration usage in codebase  
**Updated**: April 29, 2026

---

## 1. AUTHENTICATION INTEGRATIONS

### OAuth2-Proxy Configuration
- **Docker Image**: `quay.io/oauth2-proxy/oauth2-proxy:v7.5.1`
- **Config File**: [./config/oauth2-proxy/oauth2-proxy.cfg](./config/oauth2-proxy/oauth2-proxy.cfg)
- **Docker Compose**:
  - [docker-compose.prod.yml](docker-compose.prod.yml) (lines 43-63)
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) - may reference
- **Terraform**:
  - [terraform/modules/identity/main.tf](terraform/modules/identity/main.tf)
  - [terraform/modules/identity/variables.tf](terraform/modules/identity/variables.tf)
  - [terraform/environments/private/modules/stack/containers-infrastructure.tf](terraform/environments/private/modules/stack/containers-infrastructure.tf) (lines 68-110)
- **Environment Variables**: 
  - `OAUTH2_PROXY_CLIENT_ID`
  - `OAUTH2_PROXY_CLIENT_SECRET`
  - `OAUTH2_COOKIE_SECRET`

### OAuth2 Token Client
- **File**: [apps/execution-scheduler/auth.py](apps/execution-scheduler/auth.py) (lines 80-100)
  - Function: `get_oauth_token()`
  - Library: `httpx.AsyncClient`
  - Timeout: 10.0s
  - Error Handling: Catches `httpx.HTTPStatusError`
  
- **File**: [apps/agent-runtime/oidc_client.py](apps/agent-runtime/oidc_client.py)
  - Class: `OIDCClient`
  - Methods:
    - `get_token()` (lines 40-75)
    - `introspect_token()` (lines 85-110)
  - Library: `httpx.AsyncClient`

### GitHub OAuth Integration
- **File**: [setup-github-gcp-integration.sh](setup-github-gcp-integration.sh)
- **File**: [configure-github-ubuntu.sh](configure-github-ubuntu.sh)
- **GCP Secret Manager**:
  - Project: `purebliss-ghl`
  - Command: `gcloud secrets versions access latest --secret=github-token`
- **Flow**: GCP GSM → GitHub CLI → Issue Sync

---

## 2. DATABASE INTEGRATIONS

### PostgreSQL Client
- **Libraries**:
  - `psycopg2-binary==2.9.9` (sync)
  - `asyncpg==0.29.0` (async)
  
- **Connection String**:
  ```
  postgresql://postgres:${DB_PASSWORD}@code-server-postgres:5432/code_server
  ```

- **Apps Using**:
  1. **Auth Server**: [apps/auth-server/requirements.txt](apps/auth-server/requirements.txt)
     - [apps/auth-server/src/user_models.py](apps/auth-server/src/user_models.py) - SQLAlchemy ORM
  
  2. **Control Plane**: [apps/control-plane/requirements.txt](apps/control-plane/requirements.txt)
     - [apps/control-plane/main.py](apps/control-plane/main.py) (line 20-30 likely)
  
  3. **Reputation Engine**: [apps/reputation_engine/requirements.txt](apps/reputation_engine/requirements.txt)
     - [apps/reputation_engine/main.py](apps/reputation_engine/main.py)
     - [apps/reputation_engine/event_processor.py](apps/reputation_engine/event_processor.py)

- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) - PostgreSQL service definition
  - [docker-compose.yml](docker-compose.yml)
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Terraform**:
  - [terraform/modules/database/rds.tf](terraform/modules/database/rds.tf) - AWS RDS config
  - [terraform/environments/private/modules/stack/containers-data.tf](terraform/environments/private/modules/stack/containers-data.tf) (lines 10-45)

### PostgreSQL Replication
- **Primary Host**: `code-server-postgres` (port 5432)
- **Replica Host**: `192.168.168.42:5432`
- **Streaming Replication**: Configured in postgresql.conf
- **Monitoring**:
  - Prometheus metric: `pg_replication_lag_seconds`
  - Exporter: `code-server-postgres-exporter:9187`
  - Dashboard: Grafana (4th dashboard)

### Redis Client
- **Library**: `redis==5.0.1`
- **Connection String**: `redis://code-server-redis:6379/{db_slot}`
- **DB Slots**:
  - 0: Cache (default)
  - 1: Sessions
  - 2: GitLab
  - 3-5: Reserved

- **Apps Using**:
  1. **Auth Server**: Cache sessions, tokens
  2. **Control Plane**: Cache execution state
  3. **Execution Scheduler**: Task queue
  4. **Edge Agent**: State machine storage
  5. **Event Bus**: Event buffering

- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) - Redis + Sentinel services
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Terraform**:
  - [terraform/modules/database/redis.tf](terraform/modules/database/redis.tf)
  - [terraform/environments/private/modules/stack/containers-data.tf](terraform/environments/private/modules/stack/containers-data.tf) (lines 70-120)

### Redis Sentinel
- **Nodes**:
  - `code-server-redis-sentinel-primary:26379`
  - `code-server-redis-sentinel-1:26379`
  - `code-server-redis-sentinel-arbiter:26379`

- **Python Integration**: 
  ```python
  from redis.sentinel import Sentinel
  sentinel = Sentinel([("host", 26379)])
  master = sentinel.master_for("mymaster")
  ```

---

## 3. MESSAGE QUEUE INTEGRATIONS

### Redpanda/Kafka Configuration
- **Docker Image**: `redpandadata/redpanda:latest`
- **Ports**:
  - 9092: Kafka API
  - 9644: Admin API
  - 29092: Internal broker port

- **Docker Compose**:
  - [docker-compose.redpanda.yml](docker-compose.redpanda.yml)
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml)
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-data.tf](terraform/environments/private/modules/stack/containers-data.tf) (lines 121-210)

### Kafka Producer Integrations

#### 1. Execution Scheduler
- **File**: [apps/execution-scheduler/events.py](apps/execution-scheduler/events.py)
- **Class**: `KafkaEventPublisher`
- **Library**: `kafka-python==2.0.2`
- **Topics**:
  - `code-server.scheduler.events` (line 24)
  - Configurable via `KAFKA_BROKER` env var (default: `redpanda:9092`)

- **Configuration**:
  ```python
  KafkaProducer(
      bootstrap_servers=broker_url,
      value_serializer=lambda v: json.dumps(v).encode('utf-8'),
      retries=3,
      max_in_flight_requests_per_connection=1,
      acks="all"
  )
  ```

- **Usage in Main App**: [apps/execution-scheduler/main.py](apps/execution-scheduler/main.py)
  - Line 82: Publish event to Kafka scheduler topic
  - Line 289: Publish cancellation

#### 2. Event-Bus Producer
- **File**: [apps/event-bus/src/producer.py](apps/event-bus/src/producer.py)
- **Library**: `confluent_kafka==2.3.0`
- **Class**: `BaseEventProducer`
- **Topic Pattern**: Configurable (example: `code-server.events`)
- **Broker**: Configurable via constructor argument

#### 3. Reputation Engine
- **File**: [apps/reputation_engine/main.py](apps/reputation_engine/main.py)
- **Line 37**: `KAFKA_BOOTSTRAP_SERVERS = config.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")`

### Kafka Consumer Integrations

#### 1. Reputation Engine Event Processor
- **File**: [apps/reputation_engine/event_processor.py](apps/reputation_engine/event_processor.py)
- **Class**: `ReputationEventProcessor`
- **Library**: `confluent_kafka==2.3.0`
- **Consumer Group**: `reputation-engine-group`
- **Bootstrap Servers**: `KAFKA_BOOTSTRAP_SERVERS` env var

- **Connection** (lines 64-75):
  ```python
  self.consumer = Consumer({
      'bootstrap.servers': self.bootstrap_servers,
      'group.id': self.group_id,
      'auto.offset.reset': 'earliest'
  })
  ```

- **Topics Subscribed**: Configurable (default: `code-server.*`)
- **Error Handling**: Lines 123, 127 (KafkaError checking)

#### 2. Event-Bus Consumer
- **File**: [apps/event-bus/src/consumer.py](apps/event-bus/src/consumer.py)
- **Class**: `BaseEventConsumer`
- **Library**: `confluent_kafka==2.3.0`

### Redpanda Console (UI)
- **Port**: 8081
- **Purpose**: Topic browser, consumer lag monitoring
- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) (service: redpanda-console)

---

## 4. POLICY ENGINE (OPA)

### OPA Integration
- **Docker Image**: `openpolicyagent/opa:latest`
- **Port**: 8181
- **Endpoint**: `http://code-server-opa:8181`

- **Integration File**: [apps/paperclip/opa_integration.py](apps/paperclip/opa_integration.py)
- **Library**: `requests==2.31.0`

- **API Endpoints Used**:
  - POST `/v1/data/policy/decision` (line 49)
  - GET `/v1/data/policy/{policy_id}` (line 86)
  - POST `/v1/compile` (line 117)
  - GET `/policies/health` (line 137)

- **Functions**:
  - `check_policy_decision()` - Policy evaluation
  - `get_policy()` - Retrieve policy definition
  - `compile_policy()` - Validate policy Rego syntax
  - `health_check()` - Health status

- **Error Handling**:
  - `requests.RequestException` caught but no retry logic (lines 71, 97, 130, 142)

- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml)
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-infrastructure.tf](terraform/environments/private/modules/stack/containers-infrastructure.tf) (lines 9-50)

---

## 5. VECTOR DATABASE (QDRANT)

### Qdrant Configuration
- **Docker Image**: `qdrant/qdrant:latest`
- **Port**: 6333 (REST API)
- **API Key**: `${QDRANT_API_KEY}` (env var)

- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml)
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-data.tf](terraform/environments/private/modules/stack/containers-data.tf) (lines 268-290)
  - Environment var: `QDRANT_API_KEY=${var.qdrant_api_key}` (line 284)

### Qdrant Usage (Minimal - Not Fully Integrated)
- **File**: [apps/memory-engine/main.py](apps/memory-engine/main.py)
  - Line 138: Comment "Would insert into Qdrant here"
  - Status: PLACEHOLDER - not implemented

- **Tests**: [apps/memory-engine/test_memory_engine.py](apps/memory-engine/test_memory_engine.py)
  - Line 203: `@patch('qdrant_client.QdrantClient')`
  - Line 206: Mocked QdrantClient test
  - No real integration tests

---

## 6. LLM INTEGRATIONS

### Ollama (On-Premise LLM)
- **Docker Image**: `ollama/ollama:latest`
- **Port**: 11434
- **Endpoint**: `http://code-server-ollama:11434`

- **Integrations**:
  1. **Multimodal-AI Image Analysis**
     - File: [apps/multimodal-ai/image_analysis.py](apps/multimodal-ai/image_analysis.py)
     - Library: `httpx==0.25.2`
     - Timeout: 300s (line 123)
     - Error handling: Line 128 (HTTPStatusError)
     - Endpoint: `/api/vision` (inferred)

  2. **Multimodal-AI Diagrams**
     - File: [apps/multimodal-ai/diagrams.py](apps/multimodal-ai/diagrams.py)
     - Timeout: 120s (line 138)
     - Error handling: Line 142

  3. **Multimodal-AI Voice**
     - File: [apps/multimodal-ai/voice.py](apps/multimodal-ai/voice.py)
     - Line 147: Import httpx
     - Line 163: AsyncClient timeout 15.0s

- **Docker Compose**:
  - [docker-compose.ai.yml](docker-compose.ai.yml)

- **Requirements**: [apps/multimodal-ai/requirements.txt](apps/multimodal-ai/requirements.txt)

### OpenAI API (Empty - Not Configured)
- **Status**: EMPTY - `OPENAI_API_KEY=` (placeholder)
- **Location**: [terraform/environments/private/modules/stack/containers-ai.tf](terraform/environments/private/modules/stack/containers-ai.tf) (line 89)
- **Issue**: No fallback to Ollama documented

---

## 7. STORAGE INTEGRATIONS

### MinIO (S3-Compatible Storage)
- **Docker Image**: `minio/minio:latest`
- **Ports**: 9010 (S3 API), 9011 (Console)

- **Configuration**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) - minio service
  - Credentials: `${MINIO_ROOT_USER}`, `${MINIO_ROOT_PASSWORD}`

- **Minimal Usage**:
  - [apps/control-plane/main.py](apps/control-plane/main.py) (line 52)
  - Status: MENTIONED but not integrated

### NAS (Network Attached Storage)
- **Host**: `192.168.168.33`
- **Mount Path**: `/mnt/nas`
- **Mounts**:
  - PostgreSQL backups: `/export/postgres/*`
  - Loki logs: `/export/loki/*`
  - Prometheus data: `/export/prometheus/*` (optional)

- **Docker Compose Volume Mounts**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml)
  - [docker-compose.prod.yml](docker-compose.prod.yml)

- **Environment Variables**: [.env.infrastructure](.env.infrastructure)
  - `NAS_HOST=192.168.168.33`
  - `NAS_MOUNT_PATH=/mnt/nas`

### GitLab Container Registry
- **URL**: `gitlab.kushnir.cloud:5005`
- **Purpose**: Custom service images
- **Integration**: [docker-compose.enterprise.yml](docker-compose.enterprise.yml)
  - GitLab service (lines 38-80)
  - Registry enabled via GITLAB_OMNIBUS_CONFIG

---

## 8. MONITORING & OBSERVABILITY INTEGRATIONS

### Prometheus
- **Docker Image**: `prom/prometheus:latest`
- **Port**: 9090
- **Config File**: [config/prometheus/prometheus.yml](config/prometheus/prometheus.yml)

- **Scrape Targets**:
  - `code-server-postgres-exporter:9187`
  - `code-server-redis-exporter:9121`
  - Redpanda metrics
  - OPA metrics
  - Service endpoints: `/metrics`

- **Alerts**: Configured in prometheus.yml
  - PrometheusDown, GrafanaDown, LokiDown
  - PostgreSQL connection pool exhaustion
  - Redis key evictions

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-observability.tf](terraform/environments/private/modules/stack/containers-observability.tf) (lines 9-70)

- **Docker Compose**:
  - [docker-compose.observability.yml](docker-compose.observability.yml)

### Grafana
- **Docker Image**: `grafana/grafana:latest`
- **Port**: 3000
- **Default Creds**: admin/password123 (INSECURE - change in production)

- **Datasources**:
  - Prometheus (metrics)
  - Loki (logs)
  - Tempo (traces)

- **Docker Compose**:
  - [docker-compose.observability.yml](docker-compose.observability.yml)

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-observability.tf](terraform/environments/private/modules/stack/containers-observability.tf) (lines 72-135)

### Loki (Log Aggregation)
- **Docker Image**: `grafana/loki:latest`
- **Port**: 3100
- **Config File**: [config/loki/loki-config.yml](config/loki/loki-config.yml)
- **Storage**: `/mnt/nas/loki`
- **Retention**: 31 days

- **Log Sources**:
  - Promtail (container logs)
  - Syslog (optional)

- **Docker Compose**:
  - [docker-compose.observability.yml](docker-compose.observability.yml)

- **Status Issues**:
  - Config mounting issues noted in PHASE10_11_DEPLOYMENT_COMPLETE.md

### Tempo (Distributed Tracing)
- **Docker Image**: `grafana/tempo:latest`
- **Port**: 3200
- **Storage**: `/mnt/nas/tempo`

- **OTEL Collector**: Separate container
  - Port: 4317 (gRPC), 4318 (HTTP)

- **Docker Compose**:
  - [docker-compose.observability.yml](docker-compose.observability.yml)

### Exporters
- **PostgreSQL Exporter**: [docker-compose.prod.yml](docker-compose.prod.yml)
  - Port: 9187
  - Metrics: Query latency, replication lag

- **Redis Exporter**: [docker-compose.prod.yml](docker-compose.prod.yml)
  - Port: 9121
  - Metrics: Memory, evictions, replication

---

## 9. INFRASTRUCTURE & CLOUD INTEGRATIONS

### GCP Integration
- **Project**: `purebliss-ghl`
- **SDK**: Google Cloud CLI v565.0.0

- **Setup Scripts**:
  - [setup-github-gcp-integration.sh](setup-github-gcp-integration.sh)
  - [setup-github-gcp-quick.sh](setup-github-gcp-quick.sh)

- **Services Used**:
  - Secret Manager (GitHub token storage)
  - Cloud Run (optional)
  - Artifact Registry (optional)

### GitHub Integration
- **CLI Tool**: GitHub CLI (installed via setup scripts)
- **Usage**: 
  - Issue sync
  - PR creation
  - Workflow status

- **Token Storage**: GCP Secret Manager
- **Retrieval**: `gcloud secrets versions access latest --secret=github-token`

---

## 10. REVERSE PROXY & LOAD BALANCING

### Caddy
- **Docker Image**: `caddy:latest`
- **Ports**: 80, 443
- **Config File**: [./Caddyfile](./Caddyfile)

- **Backend Routes**:
  - IDE (8090)
  - API (8080)
  - Auth/OAuth (4180)
  - GitLab (8101)
  - MinIO (9010, 9011)
  - Prometheus (9090)
  - Grafana (3000)

- **Docker Compose**:
  - [docker-compose.prod.yml](docker-compose.prod.yml)
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml)

- **Terraform**:
  - [terraform/environments/private/modules/stack/containers-infrastructure.tf](terraform/environments/private/modules/stack/containers-infrastructure.tf)

---

## 11. VAULT (SECRETS MANAGEMENT)

### Vault Configuration
- **Docker Image**: `hashicorp/vault:1.13.0`
- **Port**: 8200
- **Dev Mode**: Enabled (token: `${VAULT_TOKEN:-devtoken}`)

- **Docker Compose**:
  - [docker-compose.enterprise.yml](docker-compose.enterprise.yml) (lines 198-220)

- **Health Check**:
  ```bash
  VAULT_ADDR=http://127.0.0.1:8200 vault status
  ```

- **Status**: Deployed but NOT integrated with apps yet
  - Environment variables use env vars instead of Vault

---

## DEPENDENCY GRAPH

```
External Service            → Used By                          → Library
─────────────────────────────────────────────────────────────────────────────
PostgreSQL                 → Auth, Control-Plane,              psycopg2, sqlalchemy
                             Reputation, etc.

Redis                      → Cache layer (all apps)            redis==5.0.1

Redpanda/Kafka             → Execution-scheduler,              kafka-python,
                             Reputation-engine                 confluent-kafka

OPA                        → Paperclip (policy)                requests==2.31.0

Ollama                     → Multimodal-AI (LLM)               httpx==0.25.2

Qdrant                     → Memory-engine (embeddings)        qdrant_client
                             [PLACEHOLDER]

MinIO                      → Control-plane (storage)           boto3 (not yet)
                             [MINIMAL]

Prometheus                 → Grafana, Alert evaluation         Native scrape

Grafana                    → UI dashboards                     React frontend

Loki                       → Log storage                       Promtail forwarder

Tempo                      → Trace storage                     OTEL Collector

Caddy                      → TLS termination,                  Native
                             reverse proxy

GitHub                     → Issue sync, CI/CD                 GitHub CLI,
                                                               requests

GCP                        → Token storage,                    gcloud CLI
                             deployment

Vault                      → Secret management                 hcl/rest API
                             [PLANNED]
```

---

## 📍 QUICK LOOKUP TABLE

| Integration | File | Line | Library | Status |
|-------------|------|------|---------|--------|
| PostgreSQL Primary | terraform/.../containers-data.tf | 10 | psycopg2 | ✅ Active |
| PostgreSQL Replica | docker-compose.prod.yml | ~50 | psycopg2 | ✅ Active |
| Redis Sentinel | docker-compose.enterprise.yml | 198+ | redis-py | ✅ Active |
| Kafka Producer | apps/execution-scheduler/events.py | 11 | kafka-python | ✅ Active |
| Kafka Consumer | apps/reputation_engine/event_processor.py | 14 | confluent-kafka | ✅ Active |
| OAuth2-Proxy | terraform/.../containers-infrastructure.tf | 68 | N/A | ✅ Deployed |
| OAuth2 Token | apps/execution-scheduler/auth.py | 87 | httpx | ✅ Active |
| OPA | apps/paperclip/opa_integration.py | 49 | requests | ✅ Active |
| Ollama | apps/multimodal-ai/image_analysis.py | 123 | httpx | ✅ Active |
| Qdrant | apps/memory-engine/main.py | 138 | qdrant_client | ⏳ Placeholder |
| MinIO | apps/control-plane/main.py | 52 | boto3 | ⏳ Planned |
| Prometheus | terraform/.../containers-observability.tf | 9 | N/A | ✅ Deployed |
| Grafana | terraform/.../containers-observability.tf | 72 | N/A | ✅ Deployed |
| Loki | terraform/.../containers-observability.tf | 136 | N/A | ✅ Deployed |
| Tempo | terraform/.../containers-observability.tf | 304 | N/A | ✅ Deployed |
| Caddy | terraform/.../containers-infrastructure.tf | 110+ | N/A | ✅ Deployed |
| Vault | docker-compose.enterprise.yml | 200 | N/A | ✅ Deployed |
| GitHub | setup-github-gcp-integration.sh | 1 | GitHub CLI | ⏳ Setup phase |
| GCP | setup-github-gcp-integration.sh | 1 | gcloud | ✅ Active |

---

**Document Status**: COMPLETE  
**Last Updated**: April 29, 2026  
**Maintainer**: Platform Engineering
