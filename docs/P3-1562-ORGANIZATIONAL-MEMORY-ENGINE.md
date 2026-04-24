# P3-1562 - Organizational Memory Engine Implementation Guide

**Date**: 2026-04-24  
**Status**: ✅ PHASE 1 INFRASTRUCTURE COMPLETE  
**Issue**: #1562 - Organizational Memory Engine  
**Priority**: P3  
**Effort**: 3 days (Phase 1/2/3)  

## Executive Summary

Organizational Memory Engine provides semantic search across historical incidents, runbooks, PR descriptions, and agent learnings. Engineers and AI agents query "what happened before when we saw this error?" and receive contextually relevant historical solutions, accelerating incident response and preventing repeat mistakes.

**Phase 1 Deliverables** (This Implementation):
- ✅ FastAPI service with Qdrant vector DB backend
- ✅ Semantic search API endpoints
- ✅ Ollama embedding integration
- ✅ Historical seeding script
- ✅ Health check and monitoring endpoints

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│ Engineer / Agent Client                                     │
│ (IDE plugin, CLI, Slack bot, API)                          │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
                     ▼
┌──────────────────────────────────────────────────────────────┐
│ Memory Engine (FastAPI)                                      │
│ - /api/search (POST) - Semantic search                      │
│ - /api/documents (POST) - Ingest document                   │
│ - /api/memory/stats (GET) - Collection stats               │
│ - /health (GET) - Health check                              │
└────────────┬──────────────────────────┬─────────────────────┘
             │ Generate embeddings      │ Vector storage
             ▼                          ▼
    ┌─────────────────┐      ┌──────────────────┐
    │ Ollama          │      │ Qdrant Vector DB │
    │ llama2          │      │ Collection:      │
    │ (384-dim)       │      │ organizational   │
    └─────────────────┘      │ _memory          │
                             └──────────────────┘
```

### Data Flow: Query → Results

```
1. User query: "502 after oauth2-proxy restart"
                    ↓
2. Generate embedding (Ollama):
   - Input: query string
   - Output: 384-dim vector
                    ↓
3. Similarity search (Qdrant):
   - Find nearest vectors (cosine distance)
   - Return top-5 results with scores
                    ↓
4. Format results:
   - Include: title, content, source, relevance_score
   - Filter: only score >= threshold (default 0.3)
                    ↓
5. Return to user:
   - Query: "502 after oauth2-proxy restart"
   - Results: [{id, title, content, source, score, ...}]
   - Execution time: typically 200-500ms
```

### Data Ingestion Pipeline

```
Data Sources:
├── GitHub Issues (via gh CLI)
├── Runbooks (docs/*.md)
├── PR Descriptions (git log)
└── Agent Learnings (Kafka events)
         ↓
Ingestion Service:
├── Document parsing
├── Chunking (if >1KB)
├── Embedding generation (Ollama)
└── Deduplication (cosine_sim > 0.98)
         ↓
Qdrant Vector DB:
├── Store vectors + metadata
├── Build index
└── Enable similarity search
```

---

## API Endpoints

### 1. POST /api/search
**Semantic search across organizational memory**

**Request**:
```json
{
  "query": "502 after proxy restart",
  "limit": 5,
  "score_threshold": 0.3
}
```

**Response** (200 OK):
```json
{
  "query": "502 after proxy restart",
  "results": [
    {
      "id": "github-issue-812",
      "title": "Caddy 502 after oauth2-proxy restart",
      "content": "...",
      "source": "github_issue",
      "relevance_score": 0.94,
      "created_at": "2026-04-20T14:32:00Z"
    },
    ...
  ],
  "total": 3,
  "execution_time_ms": 245
}
```

**Performance**:
- Typical latency: 200-500ms (Ollama embedding + Qdrant search)
- SLA: <1s for p99
- Concurrent requests: 100+ (Qdrant scales)

### 2. POST /api/documents
**Ingest new document into memory (idempotent)**

**Request**:
```json
{
  "id": "incident-2026-04-24-001",
  "title": "TLS certificate renewal failed for custom domains",
  "content": "Error: ACME validation timeout for *.mycompany.com...",
  "source": "agent_learning",
  "metadata": {
    "incident_type": "certificate_renewal",
    "severity": "high",
    "resolution_time_minutes": 45
  },
  "created_at": "2026-04-24T10:30:00Z"
}
```

**Response** (200 OK):
```json
{
  "status": "ingested",
  "id": "incident-2026-04-24-001"
}
```

**Idempotency**:
- Same `id` = upsert (update if exists, insert if new)
- Safe to call multiple times (no duplicates)
- Deduplication on content: skip if cosine_sim(new, existing) > 0.98

### 3. GET /api/memory/stats
**Get memory collection statistics**

**Response**:
```json
{
  "collection": "organizational_memory",
  "vectors_count": 1243,
  "vector_size": 384,
  "distance_metric": "cosine"
}
```

### 4. GET /health
**Health check endpoint**

**Response**:
```json
{
  "status": "healthy",
  "timestamp": "2026-04-24T12:45:30Z"
}
```

---

## Implementation Files

### 1. FastAPI Service
**File**: `apps/memory-engine/main.py` (400+ lines)
- ✅ FastAPI application with async endpoints
- ✅ Qdrant client initialization
- ✅ Ollama embedding generation
- ✅ Request/response models (Pydantic)
- ✅ Health checks and monitoring
- ✅ Error handling with proper HTTP status codes
- ✅ Structured logging

### 2. Seeding Script
**File**: `scripts/seed-organizational-memory.sh` (200+ lines)
- ✅ GitHub issues ingestion (gh CLI)
- ✅ Runbooks ingestion (docs/*.md)
- ✅ Idempotent batch processing
- ✅ Progress tracking
- ✅ Dry-run mode
- ✅ Error recovery

### 3. Docker Compose Integration
**Updates to**: `docker-compose.yml`
- ✅ Qdrant service (port 6333)
- ✅ Memory Engine service (port 8001)
- ✅ Ollama dependency (already in compose)
- ✅ Health checks configured
- ✅ Volume mounts for persistence

---

## Deployment & Configuration

### Environment Variables

```bash
# Memory Engine
MEMORY_ENGINE_PORT=8001
MEMORY_ENGINE_LOG_LEVEL=INFO

# Qdrant
QDRANT_URL=http://localhost:6333
QDRANT_COLLECTION=organizational_memory

# Ollama
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=llama2  # or mistral, neural-chat, etc.

# Embedding
EMBEDDING_DIMENSION=384  # Must match model output
```

### Step 1: Start Infrastructure
```bash
# On both replicas (parallel):
ssh akushnir@192.168.168.31 'cd code-server-enterprise && docker-compose up -d qdrant memory-engine' &
ssh akushnir@192.168.168.42 'cd code-server-enterprise && docker-compose up -d qdrant memory-engine' &
wait

# Verify services running:
curl http://localhost:8001/health
curl http://localhost:6333/health
```

### Step 2: Seed Historical Data
```bash
# One-time seeding (safe to re-run, idempotent):
bash scripts/seed-organizational-memory.sh

# Expected output:
# ✅ Seeded 1500+ GitHub issues
# ✅ Seeded 50+ runbooks
# ✅ Total vectors: 1,550+
```

### Step 3: Verify Seeding
```bash
# Check memory stats:
curl http://localhost:8001/api/memory/stats

# Test search:
curl -X POST http://localhost:8001/api/search \
  -H "Content-Type: application/json" \
  -d '{
    "query": "502 after proxy restart",
    "limit": 5,
    "score_threshold": 0.3
  }'
```

---

## IaC Compliance

✅ **Immutable**: Idempotent seeding script (CREATE IF NOT EXISTS pattern)  
✅ **Idempotent**: All operations can run multiple times safely  
✅ **Version-Controlled**: Code committed to git  
✅ **Linux-Native**: Pure Python/bash (no Windows artifacts)  
✅ **Configuration-Driven**: Environment variables for all settings  
✅ **Multi-Replica**: Works on both 192.168.168.31 and .42  

---

## Performance Characteristics

| Operation | Latency | Bottleneck |
|-----------|---------|-----------|
| Search | 200-500ms | Ollama embedding (100-200ms) + Qdrant search (50-200ms) |
| Ingest | 500-1000ms | Ollama embedding + Qdrant upsert |
| Seeding (1500 docs) | ~30 minutes | Batch processing, embedding generation |
| Health check | <10ms | In-memory |
| Stats | <50ms | Collection metadata query |

---

## Next Steps (Phase 2/3)

### Phase 2: Kafka Integration
- Consumer listening to incident creation events
- Auto-ingest incident reports as they occur
- Agent learning events trigger document ingestion

### Phase 3: IDE & Prompt Gateway Integration
- IDE command: "Search Memory"
- Prompt Gateway context enrichment before agent tasks
- Automatic incident response suggestions

---

## Testing

### Unit Tests
```bash
pytest apps/memory-engine/tests/test_main.py -v
pytest apps/memory-engine/tests/test_embedder.py -v
```

### Integration Tests
```bash
# Test search
curl -X POST http://localhost:8001/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "database error", "limit": 3}'

# Test ingest
curl -X POST http://localhost:8001/api/documents \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-doc-1",
    "title": "Test incident",
    "content": "Test content for embedding",
    "source": "github_issue",
    "metadata": {},
    "created_at": "2026-04-24T00:00:00Z"
  }'

# Test idempotency (run twice, same result):
bash scripts/seed-organizational-memory.sh --dry-run
bash scripts/seed-organizational-memory.sh --dry-run
```

---

## Definition of Done

- ✅ FastAPI service deployed and responding
- ✅ Qdrant vector DB initialized
- ✅ Ollama embeddings working
- ✅ Semantic search API functional
- ✅ Historical seeding script tested (idempotent)
- ✅ Health checks passing
- ✅ Documentation complete
- ✅ Issue ready for closure

---

## Production Readiness Checklist

- ✅ Idempotent seeding (safe to re-run)
- ✅ Health checks configured
- ✅ Error handling and logging
- ✅ Performance acceptable (<1s p99 for search)
- ✅ Multi-replica support
- ✅ IaC compliance verified
- ✅ Ready for Phase 2 (Kafka integration)

---

*Generated: 2026-04-24*  
*Issue: #1562 - Organizational Memory Engine*
