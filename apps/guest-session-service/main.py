#!/usr/bin/env python3
# @file        apps/guest-session-service/main.py
# @module      session-management/guest-access
# @description FastAPI service for managing guest user sessions with quotas and isolation
#
# Provides external user access to code-server with:
# - Session creation and lifecycle management
# - Quota enforcement (time, resources, storage)
# - Multi-tenant isolation
# - Audit trail and security controls

import asyncio
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
import redis.asyncio as redis
import psycopg2
import psycopg2.extras
from prometheus_client import Counter, Histogram, generate_latest

# ============================================================================
# CONFIGURATION
# ============================================================================

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/code_server")
SESSION_TIMEOUT = int(os.getenv("GUEST_SESSION_TIMEOUT", "3600"))  # 1 hour default
PREVIEW_TTL = int(os.getenv("PREVIEW_ENVIRONMENT_TTL", "7200"))  # 2 hours default

# ============================================================================
# METRICS
# ============================================================================

guest_sessions_created = Counter('guest_sessions_created_total', 'Total guest sessions created')
guest_sessions_active = Counter('guest_sessions_active', 'Currently active guest sessions')
preview_envs_created = Counter('preview_environments_created_total', 'Total preview environments created')
quota_violations = Counter('quota_violations_total', 'Total quota violations detected')

# ============================================================================
# MODELS
# ============================================================================

class GuestSessionRequest(BaseModel):
    guest_email: str = Field(..., description="Email of the guest user")
    purpose: str = Field(..., description="Purpose of the session (review, demo, etc.)")
    requested_duration: int = Field(3600, description="Requested session duration in seconds")
    resource_limits: Dict[str, int] = Field(default_factory=dict, description="Resource limits (cpu, memory, etc.)")

class GuestSession(BaseModel):
    session_id: str
    guest_email: str
    purpose: str
    created_at: datetime
    expires_at: datetime
    status: str  # active, expired, terminated
    resource_usage: Dict[str, float]
    audit_log: List[Dict]

class PreviewEnvironmentRequest(BaseModel):
    source_session_id: str = Field(..., description="ID of the source session to copy")
    reviewer_email: str = Field(..., description="Email of the reviewer")
    review_context: str = Field(..., description="Context for the review (PR number, etc.)")
    ttl_seconds: int = Field(7200, description="Time to live in seconds")

class PreviewEnvironment(BaseModel):
    preview_id: str
    source_session_id: str
    reviewer_email: str
    review_context: str
    created_at: datetime
    expires_at: datetime
    status: str  # active, expired, cleaned_up
    access_url: str

# ============================================================================
# DATABASE HELPERS
# ============================================================================

def get_db_connection():
    return psycopg2.connect(DATABASE_URL)

def init_database():
    """Initialize database tables for guest sessions and preview environments"""
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            # Guest sessions table
            cur.execute("""
                CREATE TABLE IF NOT EXISTS guest_sessions (
                    session_id VARCHAR(36) PRIMARY KEY,
                    guest_email VARCHAR(255) NOT NULL,
                    purpose TEXT,
                    created_at TIMESTAMP NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'active',
                    resource_limits JSONB DEFAULT '{}',
                    resource_usage JSONB DEFAULT '{}',
                    audit_log JSONB DEFAULT '[]',
                    created_by VARCHAR(255)
                );

                CREATE INDEX IF NOT EXISTS idx_guest_sessions_email ON guest_sessions(guest_email);
                CREATE INDEX IF NOT EXISTS idx_guest_sessions_status ON guest_sessions(status);
                CREATE INDEX IF NOT EXISTS idx_guest_sessions_expires ON guest_sessions(expires_at);
            """)

            # Preview environments table
            cur.execute("""
                CREATE TABLE IF NOT EXISTS preview_environments (
                    preview_id VARCHAR(36) PRIMARY KEY,
                    source_session_id VARCHAR(36) NOT NULL,
                    reviewer_email VARCHAR(255) NOT NULL,
                    review_context TEXT,
                    created_at TIMESTAMP NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    status VARCHAR(20) NOT NULL DEFAULT 'active',
                    access_url TEXT,
                    created_by VARCHAR(255)
                );

                CREATE INDEX IF NOT EXISTS idx_preview_envs_reviewer ON preview_environments(reviewer_email);
                CREATE INDEX IF NOT EXISTS idx_preview_envs_status ON preview_environments(status);
                CREATE INDEX IF NOT EXISTS idx_preview_envs_expires ON preview_environments(expires_at);
            """)

            conn.commit()

# ============================================================================
# GUEST SESSION SERVICE
# ============================================================================

class GuestSessionManager:
    def __init__(self):
        self.redis = redis.from_url(REDIS_URL)

    async def create_guest_session(self, request: GuestSessionRequest, created_by: str) -> GuestSession:
        """Create a new guest session with quotas and isolation"""
        session_id = str(uuid.uuid4())
        now = datetime.utcnow()
        expires_at = now + timedelta(seconds=min(request.requested_duration, SESSION_TIMEOUT))

        # Check quota limits
        await self._check_guest_quotas(request.guest_email)

        session = GuestSession(
            session_id=session_id,
            guest_email=request.guest_email,
            purpose=request.purpose,
            created_at=now,
            expires_at=expires_at,
            status="active",
            resource_usage={},
            audit_log=[{
                "timestamp": now.isoformat(),
                "action": "created",
                "actor": created_by,
                "details": f"Session created for {request.purpose}"
            }]
        )

        # Store in database
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO guest_sessions
                    (session_id, guest_email, purpose, created_at, expires_at, status,
                     resource_limits, resource_usage, audit_log, created_by)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    session.session_id, session.guest_email, session.purpose,
                    session.created_at, session.expires_at, session.status,
                    request.resource_limits, session.resource_usage,
                    session.audit_log, created_by
                ))
                conn.commit()

        # Cache in Redis for fast access
        await self.redis.setex(
            f"guest_session:{session_id}",
            SESSION_TIMEOUT,
            session.json()
        )

        guest_sessions_created.inc()
        guest_sessions_active.inc()

        return session

    async def get_guest_session(self, session_id: str) -> Optional[GuestSession]:
        """Get guest session by ID"""
        # Try Redis first
        cached = await self.redis.get(f"guest_session:{session_id}")
        if cached:
            return GuestSession.parse_raw(cached)

        # Fall back to database
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT * FROM guest_sessions WHERE session_id = %s", (session_id,))
                row = cur.fetchone()
                if row:
                    return GuestSession(**row)
        return None

    async def terminate_guest_session(self, session_id: str, terminated_by: str):
        """Terminate a guest session"""
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE guest_sessions
                    SET status = 'terminated',
                        audit_log = audit_log || %s
                    WHERE session_id = %s
                """, ([{
                    "timestamp": datetime.utcnow().isoformat(),
                    "action": "terminated",
                    "actor": terminated_by,
                    "details": "Session terminated by admin"
                }], session_id))
                conn.commit()

        # Remove from Redis
        await self.redis.delete(f"guest_session:{session_id}")
        guest_sessions_active.dec()

    async def _check_guest_quotas(self, guest_email: str):
        """Check if guest is within quota limits"""
        # Count active sessions for this guest
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) FROM guest_sessions
                    WHERE guest_email = %s AND status = 'active'
                """, (guest_email,))
                active_count = cur.fetchone()[0]

                if active_count >= 3:  # Max 3 concurrent sessions per guest
                    quota_violations.inc()
                    raise HTTPException(429, "Guest quota exceeded: too many active sessions")

# ============================================================================
# PREVIEW ENVIRONMENT MANAGER
# ============================================================================

class PreviewEnvironmentManager:
    def __init__(self):
        self.redis = redis.from_url(REDIS_URL)

    async def create_preview_environment(self, request: PreviewEnvironmentRequest, created_by: str) -> PreviewEnvironment:
        """Create a preview environment by copying an existing session"""
        preview_id = str(uuid.uuid4())
        now = datetime.utcnow()
        expires_at = now + timedelta(seconds=min(request.ttl_seconds, PREVIEW_TTL))

        # Verify source session exists and is accessible
        source_session = await self._get_source_session(request.source_session_id)
        if not source_session:
            raise HTTPException(404, "Source session not found")

        preview = PreviewEnvironment(
            preview_id=preview_id,
            source_session_id=request.source_session_id,
            reviewer_email=request.reviewer_email,
            review_context=request.review_context,
            created_at=now,
            expires_at=expires_at,
            status="active",
            access_url=f"https://preview-{preview_id}.kushnir.cloud"
        )

        # Store in database
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO preview_environments
                    (preview_id, source_session_id, reviewer_email, review_context,
                     created_at, expires_at, status, access_url, created_by)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    preview.preview_id, preview.source_session_id, preview.reviewer_email,
                    preview.review_context, preview.created_at, preview.expires_at,
                    preview.status, preview.access_url, created_by
                ))
                conn.commit()

        # Schedule cleanup
        asyncio.create_task(self._schedule_cleanup(preview_id, expires_at))

        preview_envs_created.inc()
        return preview

    async def get_preview_environment(self, preview_id: str) -> Optional[PreviewEnvironment]:
        """Get preview environment by ID"""
        with get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT * FROM preview_environments WHERE preview_id = %s", (preview_id,))
                row = cur.fetchone()
                if row:
                    return PreviewEnvironment(**row)
        return None

    async def cleanup_expired_previews(self):
        """Clean up expired preview environments"""
        now = datetime.utcnow()
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE preview_environments
                    SET status = 'expired'
                    WHERE expires_at < %s AND status = 'active'
                """, (now,))
                expired_count = cur.rowcount
                conn.commit()

        if expired_count > 0:
            print(f"Cleaned up {expired_count} expired preview environments")

    async def _get_source_session(self, session_id: str) -> Optional[Dict]:
        """Get source session details (mock implementation)"""
        # In real implementation, this would call session-broker API
        return {"id": session_id, "exists": True}

    async def _schedule_cleanup(self, preview_id: str, expires_at: datetime):
        """Schedule cleanup of preview environment"""
        delay = (expires_at - datetime.utcnow()).total_seconds()
        if delay > 0:
            await asyncio.sleep(delay)
            await self._cleanup_preview(preview_id)

    async def _cleanup_preview(self, preview_id: str):
        """Clean up a preview environment"""
        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    UPDATE preview_environments
                    SET status = 'cleaned_up'
                    WHERE preview_id = %s
                """, (preview_id,))
                conn.commit()

# ============================================================================
# FASTAPI APPLICATION
# ============================================================================

app = FastAPI(title="Guest Session Service", version="1.0.0")
security = HTTPBearer()

guest_manager = GuestSessionManager()
preview_manager = PreviewEnvironmentManager()

@app.on_event("startup")
async def startup_event():
    init_database()
    # Start background cleanup task
    asyncio.create_task(background_cleanup())

async def background_cleanup():
    """Background task to clean up expired resources"""
    while True:
        try:
            await preview_manager.cleanup_expired_previews()
            await asyncio.sleep(300)  # Run every 5 minutes
        except Exception as e:
            print(f"Background cleanup error: {e}")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "guest-session-service"}

@app.post("/guest-sessions", response_model=GuestSession)
async def create_guest_session(
    request: GuestSessionRequest,
    background_tasks: BackgroundTasks,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    """Create a new guest session"""
    # In real implementation, validate JWT token from credentials
    created_by = "system"  # Mock implementation

    session = await guest_manager.create_guest_session(request, created_by)

    # Schedule expiration check
    background_tasks.add_task(schedule_session_expiry, session.session_id, session.expires_at)

    return session

@app.get("/guest-sessions/{session_id}", response_model=GuestSession)
async def get_guest_session(session_id: str):
    """Get guest session details"""
    session = await guest_manager.get_guest_session(session_id)
    if not session:
        raise HTTPException(404, "Guest session not found")
    return session

@app.delete("/guest-sessions/{session_id}")
async def terminate_guest_session(
    session_id: str,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    """Terminate a guest session"""
    terminated_by = "system"  # Mock implementation
    await guest_manager.terminate_guest_session(session_id, terminated_by)
    return {"status": "terminated"}

@app.post("/preview-environments", response_model=PreviewEnvironment)
async def create_preview_environment(
    request: PreviewEnvironmentRequest,
    credentials: HTTPAuthorizationCredentials = Depends(security)
):
    """Create a preview environment"""
    created_by = "system"  # Mock implementation
    return await preview_manager.create_preview_environment(request, created_by)

@app.get("/preview-environments/{preview_id}", response_model=PreviewEnvironment)
async def get_preview_environment(preview_id: str):
    """Get preview environment details"""
    preview = await preview_manager.get_preview_environment(preview_id)
    if not preview:
        raise HTTPException(404, "Preview environment not found")
    return preview

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

async def schedule_session_expiry(session_id: str, expires_at: datetime):
    """Schedule automatic session expiry"""
    delay = (expires_at - datetime.utcnow()).total_seconds()
    if delay > 0:
        await asyncio.sleep(delay)
        await guest_manager.terminate_guest_session(session_id, "auto-expiry")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003)