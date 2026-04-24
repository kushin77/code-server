#!/usr/bin/env bash
# @file        apps/memory-engine/main.py
# @module      memory/engine
# @description Organizational Memory Engine FastAPI service with Qdrant vector DB backend
# @owner       engineering/memory
# @status      production-ready
#
# Provides semantic search API for historical incidents, runbooks, PR descriptions,
# and agent learnings. Uses Ollama for embeddings, Qdrant for vector storage.

import os
import sys
import logging
from typing import List, Optional
from datetime import datetime

import fastapi
from fastapi import FastAPI, HTTPException
import pydantic
import requests
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

# ════════════════════════════════════════════════════════════════════════════
# Configuration
# ════════════════════════════════════════════════════════════════════════════

QDRANT_URL = os.getenv('QDRANT_URL', 'http://localhost:6333')
QDRANT_COLLECTION = os.getenv('QDRANT_COLLECTION', 'organizational_memory')
OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://localhost:11434')
OLLAMA_MODEL = os.getenv('OLLAMA_MODEL', 'llama2')

EMBEDDING_DIMENSION = int(os.getenv('EMBEDDING_DIMENSION', '384'))
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')

# ════════════════════════════════════════════════════════════════════════════
# Logging
# ════════════════════════════════════════════════════════════════════════════

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ════════════════════════════════════════════════════════════════════════════
# FastAPI App
# ════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title='ElevatedIQ Memory Engine',
    version='1.0.0',
    description='Organizational Memory Engine with semantic search'
)

# ════════════════════════════════════════════════════════════════════════════
# Pydantic Models
# ════════════════════════════════════════════════════════════════════════════

class SearchRequest(pydantic.BaseModel):
    query: str
    limit: int = 5
    score_threshold: float = 0.3


class SearchResult(pydantic.BaseModel):
    id: str
    title: str
    content: str
    source: str  # 'github_issue', 'runbook', 'pr_description', 'agent_learning'
    relevance_score: float
    created_at: str
    updated_at: Optional[str] = None


class SearchResponse(pydantic.BaseModel):
    query: str
    results: List[SearchResult]
    total: int
    execution_time_ms: float


class MemoryDocument(pydantic.BaseModel):
    id: str
    title: str
    content: str
    source: str
    metadata: dict
    created_at: str
    updated_at: Optional[str] = None


# ════════════════════════════════════════════════════════════════════════════
# Qdrant Client
# ════════════════════════════════════════════════════════════════════════════

def get_qdrant_client():
    """Get or create Qdrant client"""
    return QdrantClient(QDRANT_URL)


def ensure_collection_exists():
    """Ensure Qdrant collection exists (idempotent)"""
    client = get_qdrant_client()
    
    try:
        client.get_collection(QDRANT_COLLECTION)
        logger.info(f'✅ Collection "{QDRANT_COLLECTION}" already exists')
    except Exception:
        logger.info(f'Creating collection "{QDRANT_COLLECTION}"...')
        client.create_collection(
            collection_name=QDRANT_COLLECTION,
            vectors_config=VectorParams(
                size=EMBEDDING_DIMENSION,
                distance=Distance.COSINE
            )
        )
        logger.info(f'✅ Collection "{QDRANT_COLLECTION}" created')


# ════════════════════════════════════════════════════════════════════════════
# Embedding Generation
# ════════════════════════════════════════════════════════════════════════════

def generate_embedding(text: str) -> List[float]:
    """Generate embedding vector from Ollama"""
    try:
        response = requests.post(
            f'{OLLAMA_URL}/api/embeddings',
            json={
                'model': OLLAMA_MODEL,
                'prompt': text
            },
            timeout=30
        )
        response.raise_for_status()
        return response.json()['embedding']
    except Exception as e:
        logger.error(f'Failed to generate embedding: {e}')
        raise HTTPException(status_code=503, detail='Embedding service unavailable')


# ════════════════════════════════════════════════════════════════════════════
# Routes
# ════════════════════════════════════════════════════════════════════════════

@app.on_event('startup')
def startup_event():
    """Initialize on startup"""
    logger.info('Memory Engine starting...')
    ensure_collection_exists()
    logger.info('✅ Memory Engine ready')


@app.get('/health')
def health_check():
    """Health check endpoint"""
    return {'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()}


@app.post('/api/search', response_model=SearchResponse)
def semantic_search(request: SearchRequest):
    """
    Semantic search across organizational memory
    
    Example query: "502 after proxy restart"
    Returns: Related incidents, runbooks, and solutions
    """
    import time
    start_time = time.time()
    
    try:
        # Generate embedding for query
        logger.debug(f'Generating embedding for query: {request.query}')
        query_embedding = generate_embedding(request.query)
        
        # Search in Qdrant
        client = get_qdrant_client()
        search_results = client.search(
            collection_name=QDRANT_COLLECTION,
            query_vector=query_embedding,
            limit=request.limit,
            score_threshold=request.score_threshold
        )
        
        # Format results
        results = []
        for point in search_results:
            results.append(SearchResult(
                id=point.payload['id'],
                title=point.payload['title'],
                content=point.payload['content'],
                source=point.payload['source'],
                relevance_score=point.score,
                created_at=point.payload['created_at'],
                updated_at=point.payload.get('updated_at')
            ))
        
        execution_time = (time.time() - start_time) * 1000
        
        logger.info(f'Search completed: query="{request.query}", results={len(results)}, time={execution_time:.1f}ms')
        
        return SearchResponse(
            query=request.query,
            results=results,
            total=len(results),
            execution_time_ms=execution_time
        )
        
    except Exception as e:
        logger.error(f'Search failed: {e}')
        raise HTTPException(status_code=500, detail=str(e))


@app.post('/api/documents')
def ingest_document(doc: MemoryDocument):
    """
    Ingest a new document into memory (idempotent)
    
    Called by:
    - GitHub webhook on new issue/PR/comment
    - Kafka event consumer on incident creation
    - Agent learnings pipeline after task completion
    """
    try:
        # Generate embedding
        content_to_embed = f"{doc.title}\n\n{doc.content}"
        embedding = generate_embedding(content_to_embed)
        
        # Create point for Qdrant
        point = PointStruct(
            id=hash(doc.id) % (2**31),  # Convert string ID to integer
            vector=embedding,
            payload={
                'id': doc.id,
                'title': doc.title,
                'content': doc.content,
                'source': doc.source,
                'metadata': doc.metadata,
                'created_at': doc.created_at,
                'updated_at': doc.updated_at or datetime.utcnow().isoformat()
            }
        )
        
        # Upsert to Qdrant (idempotent)
        client = get_qdrant_client()
        client.upsert(
            collection_name=QDRANT_COLLECTION,
            points=[point]
        )
        
        logger.info(f'✅ Document ingested: {doc.id} ({doc.source})')
        
        return {'status': 'ingested', 'id': doc.id}
        
    except Exception as e:
        logger.error(f'Failed to ingest document: {e}')
        raise HTTPException(status_code=500, detail=str(e))


@app.get('/api/memory/stats')
def memory_stats():
    """Get memory collection statistics"""
    try:
        client = get_qdrant_client()
        collection = client.get_collection(QDRANT_COLLECTION)
        
        return {
            'collection': QDRANT_COLLECTION,
            'vectors_count': collection.points_count,
            'vector_size': EMBEDDING_DIMENSION,
            'distance_metric': 'cosine'
        }
    except Exception as e:
        logger.error(f'Failed to get stats: {e}')
        raise HTTPException(status_code=500, detail=str(e))


# ════════════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    import uvicorn
    
    port = int(os.getenv('MEMORY_ENGINE_PORT', '8001'))
    
    logger.info(f'Starting Memory Engine on port {port}')
    logger.info(f'Qdrant: {QDRANT_URL}')
    logger.info(f'Ollama: {OLLAMA_URL} ({OLLAMA_MODEL})')
    
    uvicorn.run(
        app,
        host='0.0.0.0',
        port=port,
        log_level=LOG_LEVEL.lower()
    )
