# Organizational Memory Engine

**Issue:** #1562 Phase 3 - Semantic Memory Search  
**Status:** ✅ IMPLEMENTATION COMPLETE  
**Framework:** FastAPI + Qdrant + Ollama  
**Python:** 3.11+

## Overview

The Organizational Memory Engine provides semantic search and retrieval capabilities for organizational knowledge across multiple data sources. It enables AI agents and services to learn from historical incident resolutions, runbook updates, code review patterns, and retrospective insights.

### Key Features

- **Semantic Search**: Vector-based search using Ollama embeddings (nomic-embed-text model)
- **Multi-Collection Support**: Incidents, runbooks, PR descriptions, retrospectives, agent learnings
- **Agent Learning**: Captures task outcomes and resolutions for organizational learning
- **Qdrant Integration**: High-performance vector database with persistence
- **Prometheus Metrics**: Built-in monitoring and instrumentation
- **Audit Logging**: All memory queries logged for governance compliance (GOV-002)

## Architecture

### Core Components

#### 1. **FastAPI Application** (`main.py`)
- RESTful API for semantic search and learning ingestion
- Pydantic models for type-safe requests/responses
- Integration with Qdrant for vector storage
- Prometheus instrumentation for metrics collection

#### 2. **Embedder** (`embedder.py`)
- Ollama integration for embedding generation
- Support for local embedding models (nomic-embed-text)
- Retry logic with exponential backoff for resilience
- Text truncation and validation

#### 3. **Qdrant Client** (`qdrant_client.py`)
- Vector database abstraction layer
- Collection management (incidents, runbooks, etc.)
- Semantic search with relevance scoring
- Similarity-based retrieval

#### 4. **Ingestion Pipeline** (`ingestion.py`)
- Processes raw documents into embeddings
- Manages collection updates
- Batch processing for efficiency
- Validation and error handling

#### 5. **Agent Learning** (`agent_learnings.py`)
- Captures AI agent task outcomes
- Stores success/failure patterns
- Links to root causes and resolutions
- Enables continuous organizational learning

### API Endpoints

```
POST /search                          # Semantic search query
GET  /collections                    # List available collections
POST /learn                          # Record agent learning outcome
GET  /health                         # Health check
POST /metrics                        # Prometheus metrics
```

## Data Model

### Search Result
```python
{
    "id": "github-issue-812",
    "title": "Caddy 502 after oauth2-proxy restart",
    "relevance_score": 0.94,
    "summary": "Issue description and context",
    "resolution": "Steps to resolve",
    "url": "https://github.com/...",
    "source": "incidents",
    "timestamp": "2026-04-28T12:00:00Z"
}
```

### Agent Learning Record
```python
{
    "task_id": "agent-task-12345",
    "task_description": "Deploy service update to production",
    "success": true,
    "root_cause": "N/A",
    "resolution_steps": "Followed standard deployment checklist",
    "tokens_used": 8432,
    "duration_seconds": 156.2,
    "timestamp": "2026-04-28T12:00:00Z"
}
```

### Supported Collections

| Collection | Purpose | Example |
|-----------|---------|---------|
| **incidents** | Past incidents and resolutions | Security vulnerability responses |
| **runbooks** | Operational runbooks and procedures | Deployment procedures, troubleshooting |
| **pr_descriptions** | Code review patterns and descriptions | PR templates, review guidelines |
| **retrospectives** | Post-mortem insights and learnings | Incident retrospectives, process improvements |
| **agent_learnings** | AI agent task outcomes and patterns | Agent execution history, success patterns |

## Getting Started

### Prerequisites

- Python 3.11+
- FastAPI 0.124+
- Qdrant (vector database)
- Ollama (local LLM for embeddings)
- Docker & Docker Compose (recommended)

### Installation

1. **Install dependencies**:
```bash
cd apps/memory-engine
pip install -r requirements.txt
```

2. **Configure Qdrant**:
```bash
# Ensure Qdrant is running (via docker-compose or standalone)
docker run -p 6333:6333 qdrant/qdrant
```

3. **Configure Ollama**:
```bash
# Ensure Ollama is running with embedding model
ollama pull nomic-embed-text
ollama serve
```

### Running Locally

```bash
# Development (with reload)
cd apps/memory-engine
uvicorn main:app --reload --host 0.0.0.0 --port 8080

# Or via Docker Compose
docker compose -f docker-compose.yml up memory-engine
```

### Health Check

```bash
curl http://localhost:8080/health
# Response: {"status": "healthy", "uptime": 12345}
```

## API Usage Examples

### Semantic Search

```bash
# Search for incident resolutions
curl -X POST http://localhost:8080/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "How to resolve Caddy 502 errors?",
    "collection": "incidents",
    "limit": 5,
    "min_relevance": 0.7
  }'

# Response:
{
  "query": "How to resolve Caddy 502 errors?",
  "collection": "incidents",
  "results": [
    {
      "id": "github-issue-812",
      "title": "Caddy 502 after oauth2-proxy restart",
      "relevance_score": 0.94,
      "summary": "...",
      "resolution": "Restart oauth2-proxy gracefully",
      "source": "incidents"
    }
  ],
  "count": 1,
  "timestamp": "2026-04-28T12:00:00Z"
}
```

### Record Agent Learning

```bash
curl -X POST http://localhost:8080/learn \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "deploy-12345",
    "task_description": "Deploy auth-server update",
    "success": true,
    "root_cause": "N/A",
    "resolution_steps": "Followed standard deployment checklist",
    "tokens_used": 8432,
    "duration_seconds": 156.2,
    "timestamp": "2026-04-28T12:00:00Z"
  }'

# Response:
{
  "status": "learning_recorded",
  "task_id": "deploy-12345",
  "timestamp": "2026-04-28T12:00:00Z"
}
```

## Governance & Compliance

**GOV-002: Memory Query Audit Logging**
- All search queries are logged with timestamp, collection, and results count
- Agent learning records are persisted for organizational audit trail
- Sensitive information is redacted from public collections

## Integration Patterns

### 1. AI Agent Integration
```python
from memory_engine import SemanticSearchClient

client = SemanticSearchClient("http://localhost:8080")

# Search for relevant runbooks
runbooks = client.search(
    query="How to scale Redis deployment?",
    collection="runbooks",
    limit=3
)

# Use results to inform agent actions
for result in runbooks:
    agent.follow_guidance(result.resolution)
```

### 2. Learning Feedback Loop
```python
# After agent completes task
learning = AgentLearning(
    task_id=task_id,
    task_description="Scale Redis cluster",
    success=True,
    root_cause=None,
    resolution_steps="Applied memory-engine recommendations",
    tokens_used=8432,
    duration_seconds=156.2
)

client.record_learning(learning)
```

### 3. Multi-Service Discovery
```python
# Services can discover peers through memory
peer_services = client.search(
    query="What services are deployed in the cluster?",
    collection="runbooks"
)
```

## Performance Tuning

### Embedding Model Selection
- **nomic-embed-text**: Lightweight, good for general-purpose (default)
- **mxbai-embed-large**: Higher quality, more computation
- **all-minilm-l6-v2**: Fast, suitable for real-time applications

### Qdrant Configuration
- Vector dimension: 384 (nomic-embed-text)
- Similarity metric: Cosine
- Index type: HNSW (Hierarchical Navigable Small World)

### Caching Strategy
- Recent search results cached in Redis (30-minute TTL)
- Embedding vectors cached locally for repeated queries
- Collection metadata updated hourly

## Monitoring & Observability

### Prometheus Metrics

```
# Semantic search metrics
memory_engine_searches_total{collection="incidents"}
memory_engine_search_latency_seconds{collection="incidents"}

# Learning metrics
memory_engine_learnings_total{success="true"}
memory_engine_learning_latency_seconds

# Ollama metrics
memory_engine_embedding_latency_seconds
memory_engine_embedding_errors_total

# Qdrant metrics
memory_engine_qdrant_query_latency_seconds
memory_engine_qdrant_connection_errors_total
```

### Log Levels

```bash
# Development (verbose)
LOG_LEVEL=DEBUG

# Production (info)
LOG_LEVEL=INFO

# Production (warnings only)
LOG_LEVEL=WARNING
```

## Production Deployment Checklist

- [ ] Qdrant cluster with replication and persistence
- [ ] Ollama deployment with multiple embedding model replicas
- [ ] Redis caching configured (30-minute TTL)
- [ ] Prometheus scraping configured
- [ ] Log aggregation (Loki/Elastic) configured
- [ ] Backup strategy for Qdrant collections
- [ ] Rate limiting for search API (100 req/min)
- [ ] Authentication for sensitive collections
- [ ] Query validation and sanitization

## Known Limitations

- **Embedding Latency**: First query (cold start) may take 2-5 seconds as Ollama model loads
- **Collection Size**: Each collection limited to ~1M vectors on standard Qdrant setup
- **Relevance Scoring**: Threshold (0.7 default) may need tuning per collection
- **Memory Model**: Nomic-embed-text trained on English text, multilingual support limited

## Development & Testing

### Run Test Suite

```bash
cd apps/memory-engine
pytest test_memory_engine.py -v

# Or with coverage
pytest test_memory_engine.py --cov=. --cov-report=html
```

### Seed Test Data

```bash
# Load sample data for testing
python seed.py --collection incidents --count 100
```

## Troubleshooting

### Issue: "Connection refused to Qdrant"
```bash
# Ensure Qdrant is running
docker ps | grep qdrant

# Or start it
docker run -p 6333:6333 qdrant/qdrant
```

### Issue: "Embedding model not found"
```bash
# Pull the model via Ollama
ollama pull nomic-embed-text

# Verify it's available
ollama list
```

### Issue: "Search results too few or not relevant"
- Lower min_relevance threshold (0.5-0.7)
- Try different query wording (more specific)
- Ensure collection has been seeded with data
- Check Qdrant collection size: `curl http://localhost:6333/collections`

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│ FastAPI Application (port 8080)                         │
│  - Search endpoint                                       │
│  - Learning endpoint                                     │
│  - Metrics endpoint                                      │
└──────────────┬───────────────────────────────────────────┘
               │
      ┌────────┴────────────┬──────────────┐
      │                     │              │
      ▼                     ▼              ▼
┌──────────────┐    ┌──────────────┐  ┌──────────────┐
│   Embedder   │    │ Qdrant Vector│  │ Redis Cache  │
│  (Ollama)    │    │  Database    │  │  (Optional)  │
└──────────────┘    └──────────────┘  └──────────────┘
   port 11434        port 6333         port 6379
```

## References

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Qdrant Vector Database](https://qdrant.tech/)
- [Ollama Embedding Models](https://ollama.ai/)
- [Semantic Search Guide](https://www.sbert.net/)
- [GOV-002: Memory Query Audit Logging](../GOVERNANCE.md)
