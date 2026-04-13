# Embeddings API - Vector generation and semantic code indexing
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import os
from sentence_transformers import SentenceTransformer
import structlog

logger = structlog.get_logger()

app = FastAPI(
    title="Code Embeddings API",
    description="Vector generation and semantic search indexing",
    version="1.0.0"
)

# Configuration
EMBED_MODEL = os.getenv("EMBED_MODEL_NAME", "nomic-ai/nomic-embed-text-v1.5")
embedding_model = None

@app.on_event("startup")
async def startup():
    global embedding_model
    try:
        logger.info(f"Loading embedding model: {EMBED_MODEL}")
        embedding_model = SentenceTransformer(EMBED_MODEL)
    except Exception as e:
        logger.error(f"Startup error: {e}")
        raise

# Models
class CodeSnippet(BaseModel):
    code: str
    file_path: str
    language: Optional[str] = None
    line_start: Optional[int] = None
    line_end: Optional[int] = None

class EmbedRequest(BaseModel):
    snippets: List[CodeSnippet]

class SearchRequest(BaseModel):
    query: str
    top_k: Optional[int] = 5

# Endpoints
@app.get("/health")
async def health():
    return {"status": "ok", "model": EMBED_MODEL}

@app.get("/api/v1/heartbeat")
async def heartbeat():
    return {"status": "alive"}

@app.post("/api/v1/embed")
async def embed_snippets(request: EmbedRequest):
    if not embedding_model:
        raise HTTPException(status_code=503, detail="Service not initialized")
    
    try:
        results = []
        for snippet in request.snippets:
            embedding = embedding_model.encode(snippet.code, convert_to_tensor=False).tolist()
            doc_id = f"{snippet.file_path}:{snippet.line_start or 0}"
            results.append({"id": doc_id, "file_path": snippet.file_path, "status": "indexed"})
            logger.info(f"Indexed {doc_id}")
        
        return {"count": len(results), "results": results}
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/stats")
async def collection_stats():
    return {"embedding_model": EMBED_MODEL, "status": "ready"}
# Embeddings API - Vector generation and semantic code indexing
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import os
import json
from sentence_transformers import SentenceTransformer
import chromadb
from chromadb.config import Settings
import structlog

# ──────────────────────────────────────────────────────────────────────────────

logger = structlog.get_logger()

app = FastAPI(
    title="Code Embeddings API",
    description="Vector generation and semantic search indexing",
    version="1.0.0"
)

# ──────────────────────────────────────────────────────────────────────────────
# Configuration

EMBED_MODEL_NAME = os.getenv("EMBED_MODEL_NAME", "nomic-ai/nomic-embed-text-v1.5")
CHROMA_HOST = os.getenv("CHROMA_HOST", "localhost")
CHROMA_PORT = int(os.getenv("CHROMA_PORT", "8000"))
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "codebase")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "400"))

# ──────────────────────────────────────────────────────────────────────────────
# Initialize Services

embedding_model = None
chroma_client = None
collection = None

@app.on_event("startup")
async def startup():
    """Initialize embedding model and vector database on startup."""
    global embedding_model, chroma_client, collection
    
    try:
        logger.info(f"Loading embedding model: {EMBED_MODEL_NAME}")
        embedding_model = SentenceTransformer(EMBED_MODEL_NAME)
        
        logger.info(f"Connecting to ChromaDB at {CHROMA_HOST}:{CHROMA_PORT}")
        chroma_client = chromadb.HttpClient(host=CHROMA_HOST, port=CHROMA_PORT)
        
        # Get or create collection
        collection = chroma_client.get_or_create_collection(
            name=COLLECTION_NAME,
            metadata={"hnsw:space": "cosine"}
        )
        logger.info(f"Collection '{COLLECTION_NAME}' ready")
        
    except Exception as e:
        logger.error(f"Startup error: {e}", exc_info=True)
        raise

# ──────────────────────────────────────────────────────────────────────────────
# Models

class CodeSnippet(BaseModel):
    """Code snippet with metadata for embedding."""
    code: str
    file_path: str
    language: Optional[str] = None
    line_start: Optional[int] = None
    line_end: Optional[int] = None
    metadata: Optional[dict] = None

class EmbedRequest(BaseModel):
    """Request to embed multiple code snippets."""
    snippets: List[CodeSnippet]

class SearchRequest(BaseModel):
    """Request to search similar code."""
    query: str
    top_k: Optional[int] = 5
    threshold: Optional[float] = 0.5

# ──────────────────────────────────────────────────────────────────────────────
# Endpoints

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "model": EMBED_MODEL_NAME}

@app.get("/api/v1/heartbeat")
async def heartbeat():
    """Heartbeat for docker healthcheck."""
    return {"status": "alive"}

@app.post("/api/v1/embed")
async def embed_snippets(request: EmbedRequest):
    """Embed code snippets and store in vector database."""
    
    if not embedding_model or not collection:
        raise HTTPException(status_code=503, detail="Service not initialized")
    
    try:
        results = []
        
        for snippet in request.snippets:
            # Generate embedding
            embedding = embedding_model.encode(snippet.code, convert_to_tensor=False).tolist()
            
            # Create unique ID
            doc_id = f"{snippet.file_path}:{snippet.line_start or 0}"
            
            # Prepare metadata
            metadata = snippet.metadata or {}
            metadata.update({
                "language": snippet.language or "unknown",
                "line_start": snippet.line_start,
                "line_end": snippet.line_end,
            })
            
            # Add to collection
            collection.add(
                ids=[doc_id],
                embeddings=[embedding],
                documents=[snippet.code],
                metadatas=[metadata]
            )
            
            results.append({
                "id": doc_id,
                "file_path": snippet.file_path,
                "status": "indexed"
            })
            
            logger.info(f"Indexed {doc_id}")
        
        return {"count": len(results), "results": results}
        
    except Exception as e:
        logger.error(f"Embedding error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/search")
async def search_code(request: SearchRequest):
    """Search for semantically similar code."""
    
    if not embedding_model or not collection:
        raise HTTPException(status_code=503, detail="Service not initialized")
    
    try:
        # Generate query embedding
        query_embedding = embedding_model.encode(request.query, convert_to_tensor=False).tolist()
        
        # Search in collection
        results = collection.query(
            query_embeddings=[query_embedding],
            n_results=request.top_k,
            where={"distance": {"$lt": 1 - request.threshold}}  # Simple threshold
        )
        
        # Format response
        matches = []
        if results['documents'] and len(results['documents']) > 0:
            for i, doc in enumerate(results['documents'][0]):
                matches.append({
                    "id": results['ids'][0][i],
                    "code": doc,
                    "metadata": results['metadatas'][0][i],
                    "distance": results['distances'][0][i] if results['distances'] else None
                })
        
        return {
            "query": request.query,
            "top_k": request.top_k,
            "matches": matches
        }
        
    except Exception as e:
        logger.error(f"Search error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/stats")
async def collection_stats():
    """Get collection statistics."""
    
    if not collection:
        raise HTTPException(status_code=503, detail="Service not initialized")
    
    try:
        count = collection.count()
        return {
            "collection": COLLECTION_NAME,
            "document_count": count,
            "embedding_model": EMBED_MODEL_NAME
        }
    except Exception as e:
        logger.error(f"Stats error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

# ──────────────────────────────────────────────────────────────────────────────
# Error handlers

@app.exception_handler(Exception)
async def exception_handler(request, exc):
    """Global exception handler."""
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )
