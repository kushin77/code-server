# External Integrations Map - Code Server Platform

**Generated**: April 29, 2026  
**Scope**: Complete platform external integration audit  
**Document Purpose**: Single source of truth for all external service dependencies, versions, error handling, fallback mechanisms, and testing coverage

---

## 📋 Executive Summary

The platform has **40+ external integrations** across 8 major categories. Current testing coverage is **minimal** for integration points, with several **brittle connections** and **undocumented dependencies** identified.

### Quick Stats
- **Total Services**: 40+
- **Critical Path Integrations**: 12
- **Integration Tests**: ~2-3 (minimal)
- **Documented Dependencies**: ~60%
- **Fallback Mechanisms**: ~30% coverage
- **Error Handling**: Mixed (requests-based have try/catch; async httpx has partial handling)

---

## 1. AUTHENTICATION & IDENTITY INTEGRATIONS

### 1.1 OAuth2-Proxy
| Property | Details |
|----------|---------|
| **Service** | OAuth2-Proxy (reverse proxy auth layer) |
| **Version** | v7.5.1 (pinned in docker-compose.prod.yml) |
| **Image** | `quay.io/oauth2-proxy/oauth2-proxy:v7.5.1@sha256:e797b3934eb8d7cb2756b67e59be2ef29c18c2b45da763f540ece66d843cec85` |
| **Container** | `code-server-oauth2-proxy` (port 4180) |
| **Provider Support** | Generic OIDC, Google, GitHub, custom |
| **Config** | `/config/oauth2-proxy/oauth2-proxy.cfg` (mounted RO) |

**Dependencies**:
- Caddy (reverse proxy integration)
- Auth domain configuration
- OAuth2 Client ID/Secret (env vars: `OAUTH2_CLIENT_ID`, `OAUTH2_CLIENT_SECRET`)
- Cookie secret (`OAUTH2_COOKIE_SECRET`)

**Error Handling**:
- ❌ No health endpoint monitoring documented
- ❌ Cookie secret mismatch can cause auth loops
- ⚠️ Config file permission issues noted in PHASE10_11_DEPLOYMENT_COMPLETE.md

**Fallback Mechanisms**:
- ❌ No fallback documented
- Manual config override possible but not automated

**Testing Coverage**:
- ❌ No integration tests found
- Manual testing only

---

### 1.2 OAuth2 Client Integration (Execution Scheduler + Agents)
| Property | Details |
|----------|---------|
| **Service** | OAuth2 token endpoint (auth-server) |
| **Location** | `apps/execution-scheduler/auth.py` + `apps/agent-runtime/oidc_client.py` |
| **HTTP Client** | `httpx.AsyncClient` (async) |
| **Auth Flow** | Client credentials → token → API calls |

**Implementation**:
```python
# execution-scheduler/auth.py (line 87-90)
async with httpx.AsyncClient(timeout=10.0) as client:
    response = await client.post(OIDC_ISSUER + "/token", data={...})

# agent-runtime/oidc_client.py (lines 49-51, 94-96)
async with httpx.AsyncClient() as client:
    # token endpoint call
    # introspect call
```

**Error Handling**:
- ⚠️ Timeout set to 10s (execution-scheduler)
- ⚠️ httpx.HTTPError caught but logging is minimal
- ❌ No retry logic
- ❌ No exponential backoff

**Fallback Mechanisms**:
- ❌ None documented

**Testing Coverage**:
- ❌ No unit tests for token flows
- ❌ No integration tests

---

## 2. DATABASE INTEGRATIONS

### 2.1 PostgreSQL (Primary)
| Property | Details |
|----------|---------|
| **Service** | PostgreSQL 15-alpine |
| **Image** | `postgres:15-alpine` |
| **Container** | `code-server-postgres` (port 5432) |
| **Host** | `code-server-postgres` (internal), `192.168.168.31` (primary) |
| **Connection String** | `postgresql://postgres:${DB_PASSWORD}@code-server-postgres:5432/code_server` |
| **Libraries** | `psycopg2-binary==2.9.9`, `asyncpg==0.29.0` |

**Connection Pools**:
- SQLAlchemy ORM pool size not configured (uses default)
- Auth-server: `sqlalchemy==2.0.23`
- Control-plane: `sqlalchemy==2.0.25`
- Reputation-engine: `sqlalchemy==2.0.25`

**Replication**:
- Primary-replica setup (hot standby)
- Streaming replication configured
- Replica host: `192.168.168.42`

**Error Handling**:
- ⚠️ SQLAlchemy connection pool errors not explicitly caught in apps
- ⚠️ Replica failover not automated

**Fallback Mechanisms**:
- ❌ Automatic failover: NOT implemented
- Manual connection string override via env var required

**Testing Coverage**:
- ❌ No connection pool tests
- ❌ No replica failover tests
- ❌ No connection timeout tests

---

### 2.2 PostgreSQL Replica (Standby)
| Property | Details |
|----------|---------|
| **Host** | `192.168.168.42` |
| **Status** | Hot standby (read-only in production) |
| **Replication** | Streaming replication from primary |

**Monitoring**:
- Prometheus metric: `pg_replication_lag_seconds` (configured)
- Grafana dashboard shows replication status

**Issues Identified**:
- ❌ Lag threshold alert not configured
- ❌ Manual steps required to promote replica
- ⚠️ Connection pooling doesn't distribute read queries

---

### 2.3 Redis (Primary)
| Property | Details |
|----------|---------|
| **Service** | Redis 7-alpine |
| **Image** | `redis:7-alpine` |
| **Container** | `code-server-redis` (port 6379) |
| **Host** | `code-server-redis` (internal), `192.168.168.31` (primary) |
| **Connection** | `redis://code-server-redis:6379/0` |
| **Libraries** | `redis==5.0.1`, `hiredis==2.2.3` |
| **DB Slots** | 0-5 (multi-app isolation) |

**Sentinel Configuration**:
- Primary sentinel: `code-server-redis-sentinel-primary:26379`
- Backup sentinels: `code-server-redis-sentinel-1`, `code-server-redis-sentinel-arbiter`
- Failover configured

**Error Handling**:
- ⚠️ Redis connection errors noted in PHASE10_11 (NOAUTH errors)
- ❌ No automatic reconnect with exponential backoff
- ❌ Connection pool exhaustion alerts missing

**Fallback Mechanisms**:
- Sentinel provides failover to replica (`192.168.168.42`)
- ⚠️ Client-side failover not implemented in python redis lib configs

**Testing Coverage**:
- ❌ No failover tests
- ❌ No connection pool saturation tests
- ❌ No Sentinel health tests

---

### 2.4 Redis Replica (Standby)
| Property | Details |
|----------|---------|
| **Host** | `192.168.168.42` |
| **Status** | Replica (replication of primary) |

**Monitoring**:
- Redis exporter at `code-server-redis-exporter:9121`
- Prometheus scrapes replication info

---

### 2.5 Redis Sentinel Cluster
| Property | Details |
|----------|---------|
| **Nodes** | 3-node cluster (odd number) |
| **Port** | 26379 |
| **Role** | HA coordinator for Redis failover |

**Containers**:
- `code-server-redis-sentinel-primary`
- `code-server-redis-sentinel-1`
- `code-server-redis-sentinel-arbiter`

**Error Handling**:
- ❌ Sentinel network partitions not tested
- ❌ Split-brain scenarios not handled

---

## 3. MESSAGE QUEUE INTEGRATIONS

### 3.1 Redpanda (Kafka-Compatible)
| Property | Details |
|----------|---------|
| **Service** | Redpanda (Kafka drop-in replacement) |
| **Image** | `redpandadata/redpanda:latest` |
| **Container** | `code-server-redpanda` (ports 9092, 9644, 29092) |
| **Broker URL** | `code-server-redpanda:9092` |
| **Console** | Redpanda console at port 8081 |
| **Admin URL** | `code-server-redpanda-console` |

**Libraries**:
- `kafka-python==2.0.2` (control-plane)
- `confluent-kafka==2.3.0` (reputation-engine)

**Publishers**:
- Execution scheduler (`apps/execution-scheduler/events.py`)
- Reputation engine (`apps/reputation_engine/event_processor.py`)
- Event-bus (`apps/event-bus/src/producer.py`)

**Consumers**:
- Reputation engine event processor
- Event-bus consumer
- Paperclip policy events

**Topics** (Configured):
- `code-server.scheduler.events` (task scheduling)
- `code-server.agent.events` (agent execution)
- `code-server.reputation.*` (reputation scoring)
- `code-server.policy.*` (policy enforcement)
- `agent.killswitch` (emergency stop)

**Error Handling**:
- ⚠️ KafkaError caught in reputation-engine line 127
- ⚠️ Connection errors logged but not retried
- ❌ No circuit breaker pattern
- ❌ No dead-letter topic configured

**Fallback Mechanisms**:
- ❌ No event persistence (in-memory only)
- ❌ No local queue fallback
- Events dropped if Kafka unavailable

**Testing Coverage**:
- ❌ No integration tests with real Kafka
- ❌ No producer/consumer failure tests
- ❌ No partition rebalance tests

---

### 3.2 Redpanda Console
| Property | Details |
|----------|---------|
| **Service** | Redpanda web UI |
| **Port** | 8081 |
| **Purpose** | Topic browser, monitoring, management |

**Issues**:
- ⚠️ No auth protection documented
- ⚠️ Accessible from internal network only (design)

---

## 4. VECTOR DATABASE & EMBEDDINGS

### 4.1 Qdrant (Vector DB)
| Property | Details |
|----------|---------|
| **Service** | Qdrant vector database |
| **Container** | `code-server-qdrant` |
| **Port** | 6333 (REST API) |
| **API Key** | `${QDRANT_API_KEY}` (env var) |
| **Health** | REST API endpoint at `/health` |

**Connection Points**:
- Memory engine (`apps/memory-engine/main.py` line 138 - placeholder)
- Multimodal-ai (embeddings)

**Error Handling**:
- ⚠️ No dedicated Qdrant client in production code (commented out)
- ❌ No error handling for API failures

**Testing Coverage**:
- ✅ Unit test mock in `test_memory_engine.py` (but tests mocked, not integration)
- ❌ No integration tests with running Qdrant

---

## 5. EXTERNAL AI/LLM INTEGRATIONS

### 5.1 Ollama (On-Premise LLM)
| Property | Details |
|----------|---------|
| **Service** | Ollama (local LLM inference) |
| **Container** | `code-server-ollama` |
| **Port** | 11434 |
| **Models** | Loaded on startup |
| **Timeout** | Various (vision: 300s, LLM: 120s) |

**Client Integration**:
- Multimodal-ai: `httpx.AsyncClient(timeout=300.0)` (line 123)
- Diagrams: `httpx.AsyncClient(timeout=120.0)` (line 138)

**Error Handling**:
```python
# apps/multimodal-ai/image_analysis.py:128
except httpx.HTTPStatusError as e:
    logger.error(f"Vision API error: {e}")
    # Returns fallback/error response
```

**Fallback Mechanisms**:
- ⚠️ Returns placeholder response on timeout
- ❌ No retry logic
- ❌ No fallback to alternative provider

**Testing Coverage**:
- ❌ No mock Ollama tests
- ❌ No timeout handling tests

---

### 5.2 OpenAI API (Placeholder)
| Property | Details |
|----------|---------|
| **Service** | OpenAI API (LLM completions) |
| **Status** | EMPTY - `OPENAI_API_KEY=` in containers-ai.tf |
| **Client** | Would use httpx or openai-python library |

**Issues**:
- ❌ OPENAI_API_KEY is empty (line 89, containers-ai.tf)
- ❌ No fallback to Ollama documented
- ❌ Cost implications not documented

---

## 6. STORAGE INTEGRATIONS

### 6.1 MinIO (S3-Compatible Object Storage)
| Property | Details |
|----------|---------|
| **Service** | MinIO |
| **Image** | `minio/minio:latest` |
| **Container** | `code-server-minio` |
| **S3 API Port** | 9010 |
| **Console Port** | 9011 |
| **Credentials** | Root user/pass (env vars) |
| **Purpose** | Artifact storage, build artifacts, logs |

**Usage Points**:
- Control-plane mentions minio (line 52, main.py)
- NAS backup strategy includes S3 compatibility

**Error Handling**:
- ❌ No S3 client integration code found
- ❌ Connection errors not documented

**Testing Coverage**:
- ⚠️ Provisioner tests mention minio (image sha256) but no API tests

---

### 6.2 NAS (Network Attached Storage)
| Property | Details |
|----------|---------|
| **Host** | `192.168.168.33` |
| **Mount Path** | `/mnt/nas` |
| **Purpose** | Database backups, persistent logs, artifacts |
| **Subdirs** | `/export/code-server/*`, `/export/postgres/*`, `/export/loki/*` |

**Mounted By**:
- PostgreSQL (backup mount)
- Loki (log storage)
- Various volume mounts

**Error Handling**:
- ❌ No NFS connection timeout handling
- ❌ No fallback mount points

**Fallback Mechanisms**:
- ❌ None documented
- Manual intervention required if NAS offline

**Testing Coverage**:
- ❌ No NAS connectivity tests

---

### 6.3 GitLab Registry (Docker Image Registry)
| Property | Details |
|----------|---------|
| **Service** | GitLab Container Registry |
| **Instance** | `gitlab.kushnir.cloud` |
| **Port** | 5005 (registry) |
| **Purpose** | Custom service images |

**Configuration**:
- `GITLAB_REGISTRY_ENABLED=true` (in gitlab omnibus config)
- Registry database: PostgreSQL `gitlabdb`

---

## 7. POLICY & SECURITY INTEGRATIONS

### 7.1 OPA (Open Policy Agent)
| Property | Details |
|----------|---------|
| **Service** | OPA policy engine |
| **Container** | `code-server-opa` |
| **Port** | 8181 |
| **Endpoint** | `http://localhost:8181` |
| **Bundles** | Policy definitions (location TBD) |

**Integration Points**:
- Paperclip: `apps/paperclip/opa_integration.py`
- Auth decisions
- Access control

**API Calls** (Paperclip):
```python
# Line 49-71: POST /v1/data/policy/decision
# Line 86-97: GET /v1/data/policy/{policy_id}
# Line 117-130: POST /v1/compile
# Line 137-142: GET /policies/health
```

**Error Handling**:
- ⚠️ `requests.RequestException` caught (lines 71, 97, 130, 142)
- ❌ No retry logic
- ❌ No circuit breaker

**Fallback Mechanisms**:
- ❌ Default to "allow" if OPA down? (not documented)
- ❌ No policy caching

**Testing Coverage**:
- ❌ No integration tests

---

### 7.2 Vault (HashiCorp Secrets Management) [Enterprise]
| Property | Details |
|----------|---------|
| **Service** | HashiCorp Vault |
| **Version** | 1.13.0 |
| **Container** | `code-server-vault` |
| **Port** | 8200 |
| **Dev Mode** | Token: `${VAULT_TOKEN:-devtoken}` |
| **Listener** | `0.0.0.0:8200` |
| **Health Check** | `vault status` |

**Status**:
- Deployed but no application integration code found
- Used for secret management (database passwords, API keys)

**Error Handling**:
- ⚠️ Health check configured (docker-compose.enterprise.yml:214)

**Testing Coverage**:
- ❌ No integration tests

---

## 8. MONITORING & OBSERVABILITY INTEGRATIONS

### 8.1 Prometheus (Metrics Collection)
| Property | Details |
|----------|---------|
| **Service** | Prometheus v2.50.0 |
| **Image** | `prom/prometheus:latest` |
| **Container** | `code-server-prometheus` |
| **Port** | 9090 |
| **Scrape Interval** | Default 15s |
| **Retention** | 15d (default) |

**Scrape Targets**:
- postgres_exporter:9187
- redis-exporter:9121
- Redpanda metrics
- OPA metrics
- Ollama metrics
- Each service: `/metrics` endpoint

**Alerts** (Configured):
- PrometheusDown (1m)
- GrafanaDown (1m)
- LokiDown (1m)
- PostgreSQL connection pool exhaustion
- Redis key evictions
- Custom agent alerts

**Error Handling**:
- ⚠️ Scrape timeout: 10s (default)
- ❌ Failed scrapes logged but alert threshold not documented

**Testing Coverage**:
- ❌ No scrape endpoint tests
- ❌ No alert rule validation tests

---

### 8.2 Grafana (Visualization & Dashboards)
| Property | Details |
|----------|---------|
| **Service** | Grafana v10.2.0 |
| **Image** | `grafana/grafana:latest` |
| **Container** | `code-server-grafana` |
| **Port** | 3000 |
| **Default Auth** | admin/password123 (insecure) |

**Datasources**:
- Prometheus (metrics)
- Loki (logs)
- Tempo (traces)

**Dashboards** (4 configured):
- Infrastructure overview
- Application performance
- Database replication
- Event streaming

**Error Handling**:
- ⚠️ Health check configured but slow start (40s)

**Testing Coverage**:
- ❌ No datasource connectivity tests
- ❌ No dashboard rendering tests

---

### 8.3 Loki (Log Aggregation)
| Property | Details |
|----------|---------|
| **Service** | Loki v2.9.1 |
| **Image** | `grafana/loki:latest` |
| **Container** | `code-server-loki` |
| **Port** | 3100 |
| **Retention** | 31 days |
| **Storage** | NAS mount (/export/loki) |

**Log Sources**:
- Promtail (containerized logs)
- Application stdout/stderr
- Syslog (optional)

**Status**:
- ⏳ Config mounting issues noted (PHASE10_11)

**Error Handling**:
- ⚠️ No backpressure handling configured
- ❌ Disk space alerts missing

**Testing Coverage**:
- ❌ No log ingestion tests
- ❌ No retention policy tests

---

### 8.4 Tempo (Distributed Tracing)
| Property | Details |
|----------|---------|
| **Service** | Tempo v2.4.1 |
| **Image** | `grafana/tempo:latest` |
| **Container** | `code-server-tempo` |
| **Port** | 3200 |
| **Storage** | NAS mount (similar to Loki) |

**OTEL Collector**:
- Receives traces from applications
- Forwards to Tempo

**Status**:
- ⏳ Config mounting issues noted (PHASE10_11)

**Error Handling**:
- ❌ Trace storage failures not handled

**Testing Coverage**:
- ❌ No trace ingestion tests

---

### 8.5 AlertManager (Alert Routing)
| Property | Details |
|----------|---------|
| **Service** | AlertManager |
| **Container** | `code-server-alertmanager` |
| **Port** | 9093 |
| **Routes** | Configured via alertmanager.yml |

**Notification Channels**:
- ❌ Not documented (likely email/webhook only)
- ❌ Severity-based routing not documented

---

### 8.6 Exporters

#### PostgreSQL Exporter
- **Port**: 9187
- **Metrics**: Connection pool, replication lag, slow queries

#### Redis Exporter
- **Port**: 9121
- **Metrics**: Memory usage, evictions, replication

---

## 9. INFRASTRUCTURE & CLOUD INTEGRATIONS

### 9.1 Google Cloud Platform (GCP)
| Property | Details |
|----------|---------|
| **Service** | GCP Secret Manager + gcloud CLI |
| **Project** | `purebliss-ghl` |
| **SDK Version** | 565.0.0 (verified) |
| **Usage** | GitHub token storage + deployment automation |

**Integration Points**:
- GitHub issue sync (`setup-github-gcp-integration.sh`)
- Secret retrieval for CI/CD

**Error Handling**:
- ⚠️ Token expiration not handled
- ❌ GSM quota errors not retried

**Fallback Mechanisms**:
- Manual token entry fallback documented

**Testing Coverage**:
- ⚠️ Manual testing only
- ❌ No automated token rotation tests

---

### 9.2 GitHub (Source Control + Auth)
| Property | Details |
|----------|---------|
| **Service** | GitHub.com API + OAuth |
| **PAT Storage** | GCP Secret Manager |
| **Usage** | Issue sync, CI/CD runner, code hosting |
| **CLI** | GitHub CLI (installed via setup scripts) |

**API Integration**:
- Issue data sync
- PR creation
- Workflow status

**Error Handling**:
- ⚠️ Rate limits (60 req/hr unauthenticated, 5000/hr authenticated)
- ⚠️ Token revocation handling missing

**Fallback Mechanisms**:
- ❌ No fallback if GitHub down

**Testing Coverage**:
- ❌ No GitHub API integration tests

---

## 10. REVERSE PROXY & LOAD BALANCING

### 10.1 Caddy (Reverse Proxy & HTTPS)
| Property | Details |
|----------|---------|
| **Service** | Caddy web server |
| **Container** | `code-server-caddy` |
| **Port** | 80, 443 |
| **Config** | `./Caddyfile` |
| **TLS** | Auto (Let's Encrypt) or manual |

**Backend Routes**:
- IDE: `:8090`
- API: `:8080`
- Auth: `:4180` (OAuth2-proxy)
- GitLab: `:8101`
- MinIO: `:9010`, `:9011`
- Prometheus: `:9090`
- Grafana: `:3000`

**Error Handling**:
- ⚠️ TLS cert renewal not documented
- ❌ Backend failure fallback not documented

**Fallback Mechanisms**:
- ❌ No fallback upstream

---

## 11. DEPENDENCY INJECTION & INTEGRATION PATTERNS

### 11.1 Authentication Flow
```
OAuth2-Proxy (4180)
  ↓
Auth Server (OIDC issuer)
  ↓
Apps validate via OIDC_ISSUER env var
  ↓
Token introspection (httpx call)
```

**Status**: ⚠️ OIDC_ISSUER defined but flows untested

---

### 11.2 Event Pipeline
```
Task/Action Generated
  ↓
Event-bus producer (Kafka publish)
  ↓
Redpanda broker (persistence 24h)
  ↓
Multiple consumers (reputation, agents, etc.)
```

**Status**: ❌ No persistence if Kafka down, ⚠️ no DLQ

---

### 11.3 Policy Enforcement
```
API Request
  ↓
Paperclip (policy middleware)
  ↓
OPA policy evaluation
  ↓
Decision cached (TTL?)
```

**Status**: ❌ Caching not documented, ❌ OPA down = allow or deny?

---

## 🔴 CRITICAL ISSUES IDENTIFIED

### Issue 1: No Automatic Failover for PostgreSQL
- **Severity**: CRITICAL
- **Impact**: Data loss if primary fails
- **Current**: Manual steps required to promote replica
- **Fix Required**: Implement pg_basebackup + automatic failover script
- **Test Required**: Failover simulation every 30 days

### Issue 2: Event Loss on Kafka Outage
- **Severity**: CRITICAL
- **Impact**: Lost task assignments, reputation updates, policy decisions
- **Current**: Events dropped if broker unavailable
- **Fix Required**: Implement local queue with retry
- **Test Required**: Kafka unavailability scenario

### Issue 3: No Distributed Transaction Coordination
- **Severity**: HIGH
- **Impact**: Cross-service consistency issues
- **Current**: Each service owns transactions, no 2PC
- **Fix Required**: Event sourcing or saga pattern implementation
- **Test Required**: Split-brain scenarios

### Issue 4: Auth Bypass if OPA Down
- **Severity**: HIGH
- **Impact**: Uncontrolled API access
- **Current**: OPA failure mode not documented
- **Fix Required**: Explicit fail-secure policy
- **Test Required**: OPA unavailability scenario

### Issue 5: Redis Sentinel Not Validated
- **Severity**: HIGH
- **Impact**: Failover to stale replica possible
- **Current**: No health check of sentinel quorum
- **Fix Required**: Sentinel quorum monitoring
- **Test Required**: Sentinel split-brain scenario

### Issue 6: OAuth2-Proxy Config Issues
- **Severity**: MEDIUM
- **Impact**: Authentication failures
- **Current**: Config file permission issues noted
- **Fix Required**: Validate permissions during startup
- **Test Required**: Config validation tests

### Issue 7: OPENAI_API_KEY Empty
- **Severity**: MEDIUM
- **Impact**: AI features unavailable
- **Current**: Key is empty string, no fallback to Ollama
- **Fix Required**: Add env var validation, implement fallback
- **Test Required**: Fallback behavior tests

### Issue 8: No Connection Pooling Limits
- **Severity**: MEDIUM
- **Impact**: Connection exhaustion under load
- **Current**: Default connection pool sizes (unlimited?)
- **Fix Required**: Configure max_connections per app
- **Test Required**: Connection pool saturation tests

### Issue 9: NAS Single Point of Failure
- **Severity**: MEDIUM
- **Impact**: Loss of backups/logs if NAS offline
- **Current**: No NAS redundancy documented
- **Fix Required**: NAS RAID + replicated backups
- **Test Required**: NAS failover scenario

### Issue 10: Vault Not Integrated
- **Severity**: MEDIUM
- **Impact**: Secrets in env vars (lower security)
- **Current**: Vault deployed but not used by apps
- **Fix Required**: App-level Vault integration
- **Test Required**: Secret rotation tests

---

## 🟡 UNDOCUMENTED DEPENDENCIES

| Dependency | Status | Location | Risk |
|-----------|--------|----------|------|
| Ollama timeout behavior | ❌ Undocumented | multimodal-ai | Timeout > 5min could hang |
| Kafka partition rebalance | ❌ Undocumented | reputation-engine | Consumer lag during rebalance |
| Redis Sentinel quorum | ❌ Undocumented | docker-compose.prod.yml | Split-brain possible |
| OPA policy cache TTL | ❌ Undocumented | paperclip | Stale policy decisions |
| Loki disk space limits | ❌ Undocumented | docker-compose.observability.yml | Disk full = log loss |
| NAS failover strategy | ❌ Undocumented | PHASE-06-PLANNING | Data loss if NAS offline |
| Grafana datasource auth | ❌ Undocumented | docker-compose.observability.yml | Unauthenticated access |
| QDRANT_API_KEY scope | ❌ Undocumented | containers-data.tf | API key permissions? |

---

## 🟢 MISSING INTEGRATION TESTS

### High Priority
1. **PostgreSQL Replication Failover**
   - Setup: Primary + standby
   - Test: Kill primary, verify standby promotes
   - Frequency: Weekly

2. **Redis Sentinel Failover**
   - Setup: Primary + replica + 3 sentinels
   - Test: Kill primary, verify failover to replica
   - Frequency: Weekly

3. **Kafka Producer/Consumer Failure**
   - Setup: Publisher + consumer + broker
   - Test: Kill broker, verify event loss, restart broker, verify recovery
   - Frequency: Monthly

4. **OAuth2-Proxy Auth Flow**
   - Setup: Proxy + auth-server + test client
   - Test: Login flow, token refresh, invalidation
   - Frequency: Every deploy

5. **OPA Policy Enforcement**
   - Setup: OPA + paperclip + test policies
   - Test: Policy allow/deny, cache behavior
   - Frequency: Every deploy

### Medium Priority
6. Cross-service transaction consistency (event sourcing)
7. NAS connectivity + recovery
8. Ollama timeout handling
9. Vault secret rotation
10. Grafana datasource failover

---

## 📊 INTEGRATION MATRIX

```
Service                 Health Check    Error Logging   Retry Logic    Circuit Breaker   DLQ/Fallback
─────────────────────────────────────────────────────────────────────────────────────────────────────
PostgreSQL              ✅              ⚠️  Partial      ❌             ❌               ❌
Redis                   ✅              ⚠️  Partial      ❌             ❌               ❌
Redpanda/Kafka          ⚠️  Manual       ⚠️  Partial      ❌             ❌               ❌
OAuth2-Proxy            ⚠️  Config       ❌              ❌             ❌               ❌
OPA                     ❌              ⚠️  Requests     ❌             ❌               ❌ (deny)
Ollama/LLM              ⚠️  Timeout      ⚠️  Log only     ❌             ❌               ✅ (Fallback)
Qdrant                  ❌              ❌              ❌             ❌               ❌
MinIO                   ❌              ❌              ❌             ❌               ❌
NAS                     ❌              ❌              ❌             ❌               ❌
Prometheus              ✅              ⚠️  Scrape fail  ❌             ❌               ❌
Grafana                 ✅              ⚠️  Log only     ❌             ❌               ❌
Loki                    ❌              ⚠️  Log only     ❌             ❌               ❌
Tempo                   ❌              ❌              ❌             ❌               ❌
Vault                   ✅              ⚠️  Health only  ❌             ❌               ❌
Caddy                   ⚠️  HTTP status  ⚠️  Log only     ❌             ⚠️  (502 retry)   ❌
GitHub API              ❌              ❌              ❌             ❌               ❌
GCP Secret Manager      ❌              ❌              ❌             ❌               ❌
GitLab                  ⚠️  HTTP status  ⚠️  Log only     ❌             ❌               ❌

Legend: ✅=Good  ⚠️=Partial  ❌=Missing
```

---

## 🔧 RECOMMENDED NEXT STEPS

### Phase 1 (Immediate - Week 1)
1. Add integration test for PostgreSQL failover
2. Add integration test for Redis Sentinel failover
3. Document OPA failure mode (explicit policy)
4. Add circuit breaker pattern to Kafka integration
5. Validate OAuth2-Proxy startup (config permissions)

### Phase 2 (Short-term - Week 2-3)
6. Implement event retry queue for Kafka
7. Add Vault integration to apps (auth-server first)
8. Implement distributed tracing end-to-end
9. Add connection pool limits to all apps
10. Create NAS redundancy (RAID + backup replication)

### Phase 3 (Medium-term - Month 1-2)
11. Implement automatic PostgreSQL failover
12. Implement automatic Redis failover validation
13. Add comprehensive integration test suite (CI/CD integration)
14. Implement chaos engineering scenarios
15. Document all integration failure modes

---

## 📝 VERSION MATRIX

| Component | Version | Image Digest | EOL | Status |
|-----------|---------|------|-----|--------|
| PostgreSQL | 15 | SHA256(...) | 2025-10 | ✅ Active |
| Redis | 7 | SHA256(...) | 2024-12 | ⚠️ Approach EOL |
| Redpanda | Latest | TAG (mutable) | Rolling | ⚠️ Use pinned version |
| Prometheus | 2.50.0 | Latest | Latest | ✅ Active |
| Grafana | 10.2.0 | Latest | Latest | ✅ Active |
| Loki | 2.9.1 | Latest | 2024-Q2 | ⚠️ Update to 2.10+ |
| Tempo | 2.4.1 | Latest | 2024-Q2 | ⚠️ Update to 2.5+ |
| Vault | 1.13.0 | Official | 2024-06 | ✅ Active |
| OAuth2-Proxy | 7.5.1 | SHA256(...) | 2024-Q2 | ✅ Active |
| Caddy | Latest | TAG (mutable) | Rolling | ⚠️ Use pinned version |
| Ollama | Latest | TAG (mutable) | Rolling | ⚠️ Use pinned version |

---

## 🔐 Security Considerations

### Authentication
- ⚠️ Default Grafana credentials (admin/password123) must be changed
- ⚠️ OAuth2 cookie secret generation: TBD if cryptographically secure
- ❌ API key rotation not automated

### Authorization
- ⚠️ OPA policies not version controlled (location TBD)
- ❌ RBAC scopes not documented

### Data Protection
- ⚠️ PostgreSQL replication not encrypted
- ⚠️ Redis (no TLS) - internal network only assumed
- ⚠️ NAS mount no encryption at rest

---

## 📞 ESCALATION MATRIX

| Issue | Severity | On-Call | Response Time |
|-------|----------|---------|---|
| PostgreSQL down | CRITICAL | DBA | 15 min |
| Redis down | CRITICAL | Platform | 15 min |
| Kafka down | CRITICAL | Platform | 30 min |
| OPA down | HIGH | Security | 5 min |
| OAuth2 auth failure | HIGH | Platform | 10 min |
| Grafana down | MEDIUM | Observability | 1 hour |
| NAS down | MEDIUM | Infrastructure | 2 hours |
| Ollama down | LOW | AI | 4 hours |

---

**Document Status**: COMPLETE  
**Last Updated**: April 29, 2026, 3:00 PM UTC  
**Next Review**: May 6, 2026  
**Owner**: Platform Engineering  
**Review Frequency**: Weekly
