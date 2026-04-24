#!/usr/bin/env python3
# @file        apps/preview-environments/main.py
# @module      session-management/preview-envs
# @description FastAPI service for managing ephemeral preview environments
#
# Handles creation and lifecycle of preview environments for:
# - Code reviews and testing
# - Demo environments
# - Temporary access to session state
# - Automatic cleanup and resource management

import asyncio
import os
import uuid
import shutil
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel, Field
import docker
import psycopg2
import psycopg2.extras
from prometheus_client import Counter, Histogram, generate_latest

# ============================================================================
# CONFIGURATION
# ============================================================================

DOCKER_BASE_URL = os.getenv("DOCKER_BASE_URL", "unix://var/run/docker.sock")
NAS_MOUNT_PATH = os.getenv("NAS_MOUNT_PATH", "/nas")
PREVIEW_STORAGE_PATH = os.getenv("PREVIEW_STORAGE_PATH", f"{NAS_MOUNT_PATH}/persistent/preview-envs")
SESSION_STORAGE_PATH = os.getenv("SESSION_STORAGE_PATH", f"{NAS_MOUNT_PATH}/persistent/sessions")
PREVIEW_TTL = int(os.getenv("PREVIEW_ENVIRONMENT_TTL", "7200"))  # 2 hours
MAX_CONCURRENT_PREVIEWS = int(os.getenv("MAX_CONCURRENT_PREVIEWS", "10"))

# ============================================================================
# METRICS
# ============================================================================

previews_created = Counter('preview_environments_created_total', 'Total preview environments created')
previews_active = Counter('preview_environments_active', 'Currently active preview environments')
previews_cleaned = Counter('preview_environments_cleaned_total', 'Total preview environments cleaned up')
storage_used = Histogram('preview_storage_used_bytes', 'Storage used by preview environments')

# ============================================================================
# MODELS
# ============================================================================

class PreviewRequest(BaseModel):
    source_session_id: str = Field(..., description="ID of source session to clone")
    reviewer_email: str = Field(..., description="Email of the reviewer/tester")
    review_context: str = Field(..., description="Context (PR number, commit hash, etc.)")
    ttl_seconds: int = Field(7200, description="Time to live in seconds")
    include_data: bool = Field(True, description="Include session data in preview")
    read_only: bool = Field(True, description="Make preview read-only")

class PreviewEnvironment(BaseModel):
    preview_id: str
    source_session_id: str
    reviewer_email: str
    review_context: str
    created_at: datetime
    expires_at: datetime
    status: str  # creating, active, expired, cleaning, cleaned
    access_url: str
    container_id: Optional[str]
    storage_path: str
    read_only: bool

class PreviewStatus(BaseModel):
    preview_id: str
    status: str
    access_url: Optional[str]
    time_remaining: int
    storage_used_mb: float

# ============================================================================
# PREVIEW ENVIRONMENT MANAGER
# ============================================================================

class PreviewEnvironmentManager:
    def __init__(self):
        self.docker_client = docker.from_env()
        self.storage_base = Path(PREVIEW_STORAGE_PATH)
        self.session_storage_base = Path(SESSION_STORAGE_PATH)
        self.storage_base.mkdir(parents=True, exist_ok=True)

    async def create_preview(self, request: PreviewRequest, created_by: str) -> PreviewEnvironment:
        """Create a new preview environment by cloning a session"""
        # Check concurrent preview limits
        active_count = await self._count_active_previews()
        if active_count >= MAX_CONCURRENT_PREVIEWS:
            raise HTTPException(429, f"Maximum concurrent previews ({MAX_CONCURRENT_PREVIEWS}) reached")

        # Verify source session exists
        source_path = self.session_storage_base / request.source_session_id
        if not source_path.exists():
            raise HTTPException(404, f"Source session {request.source_session_id} not found")

        preview_id = str(uuid.uuid4())
        now = datetime.utcnow()
        expires_at = now + timedelta(seconds=min(request.ttl_seconds, PREVIEW_TTL))

        preview = PreviewEnvironment(
            preview_id=preview_id,
            source_session_id=request.source_session_id,
            reviewer_email=request.reviewer_email,
            review_context=request.review_context,
            created_at=now,
            expires_at=expires_at,
            status="creating",
            access_url=f"https://preview-{preview_id}.kushnir.cloud",
            container_id=None,
            storage_path=str(self.storage_base / preview_id),
            read_only=request.read_only
        )

        # Store in database
        self._save_preview_to_db(preview, created_by)

        # Start async creation
        asyncio.create_task(self._create_preview_async(preview, request))

        previews_created.inc()
        previews_active.inc()

        return preview

    async def get_preview(self, preview_id: str) -> Optional[PreviewEnvironment]:
        """Get preview environment details"""
        with self._get_db_connection() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT * FROM preview_environments WHERE preview_id = %s", (preview_id,))
                row = cur.fetchone()
                if row:
                    return PreviewEnvironment(**row)
        return None

    async def get_preview_status(self, preview_id: str) -> Optional[PreviewStatus]:
        """Get detailed status of a preview environment"""
        preview = await self.get_preview(preview_id)
        if not preview:
            return None

        time_remaining = max(0, int((preview.expires_at - datetime.utcnow()).total_seconds()))
        storage_used = self._calculate_storage_used(preview.preview_id)

        return PreviewStatus(
            preview_id=preview.preview_id,
            status=preview.status,
            access_url=preview.access_url if preview.status == "active" else None,
            time_remaining=time_remaining,
            storage_used_mb=storage_used
        )

    async def cleanup_expired_previews(self):
        """Clean up expired preview environments"""
        now = datetime.utcnow()
        with self._get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT preview_id, container_id, storage_path
                    FROM preview_environments
                    WHERE expires_at < %s AND status IN ('active', 'creating')
                """, (now,))

                expired_previews = cur.fetchall()

                for preview_id, container_id, storage_path in expired_previews:
                    await self._cleanup_preview(preview_id, container_id, storage_path)

                    cur.execute("""
                        UPDATE preview_environments
                        SET status = 'expired'
                        WHERE preview_id = %s
                    """, (preview_id,))

                conn.commit()

        if expired_previews:
            previews_cleaned.inc(len(expired_previews))
            previews_active.dec(len(expired_previews))

    async def _create_preview_async(self, preview: PreviewEnvironment, request: PreviewRequest):
        """Asynchronously create the preview environment"""
        try:
            # Copy session data
            await self._copy_session_data(preview, request)

            # Create Docker container
            container_id = await self._create_preview_container(preview, request)

            # Update preview status
            with self._get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE preview_environments
                        SET status = 'active', container_id = %s
                        WHERE preview_id = %s
                    """, (container_id, preview.preview_id))
                    conn.commit()

        except Exception as e:
            print(f"Failed to create preview {preview.preview_id}: {e}")
            with self._get_db_connection() as conn:
                with conn.cursor() as cur:
                    cur.execute("""
                        UPDATE preview_environments
                        SET status = 'failed'
                        WHERE preview_id = %s
                    """, (preview.preview_id,))
                    conn.commit()

    async def _copy_session_data(self, preview: PreviewEnvironment, request: PreviewRequest):
        """Copy session data to preview storage"""
        source_path = self.session_storage_base / preview.source_session_id
        preview_path = Path(preview.storage_path)

        if request.include_data:
            # Copy session data
            shutil.copytree(source_path, preview_path, dirs_exist_ok=True)
        else:
            # Create minimal structure
            preview_path.mkdir(parents=True, exist_ok=True)
            (preview_path / "workspace").mkdir(exist_ok=True)

        # Set permissions
        os.system(f"chmod -R 755 {preview.storage_path}")

    async def _create_preview_container(self, preview: PreviewEnvironment, request: PreviewRequest) -> str:
        """Create Docker container for the preview environment"""
        container_name = f"preview-{preview.preview_id}"

        # Mount preview storage
        volumes = {
            preview.storage_path: {
                'bind': '/home/coder/project',
                'mode': 'rw' if not preview.read_only else 'ro'
            }
        }

        # Create container
        container = self.docker_client.containers.run(
            "codercom/code-server:latest",
            name=container_name,
            volumes=volumes,
            environment={
                "PASSWORD": "preview-access",  # Temporary password
                "PREVIEW_MODE": "true",
                "READ_ONLY": str(preview.read_only).lower()
            },
            ports={'8080/tcp': None},  # Auto-assign port
            detach=True,
            remove=True  # Auto-remove when stopped
        )

        return container.id

    async def _cleanup_preview(self, preview_id: str, container_id: Optional[str], storage_path: str):
        """Clean up a preview environment"""
        try:
            # Stop and remove container
            if container_id:
                try:
                    container = self.docker_client.containers.get(container_id)
                    container.stop(timeout=10)
                    container.remove()
                except docker.errors.NotFound:
                    pass  # Container already removed

            # Remove storage
            if os.path.exists(storage_path):
                shutil.rmtree(storage_path)

        except Exception as e:
            print(f"Error cleaning up preview {preview_id}: {e}")

    def _count_active_previews(self) -> int:
        """Count currently active preview environments"""
        with self._get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT COUNT(*) FROM preview_environments
                    WHERE status IN ('creating', 'active')
                """)
                return cur.fetchone()[0]

    def _calculate_storage_used(self, preview_id: str) -> float:
        """Calculate storage used by preview in MB"""
        preview_path = self.storage_base / preview_id
        if not preview_path.exists():
            return 0.0

        total_size = 0
        for dirpath, dirnames, filenames in os.walk(preview_path):
            for filename in filenames:
                filepath = os.path.join(dirpath, filename)
                try:
                    total_size += os.path.getsize(filepath)
                except OSError:
                    pass

        return total_size / (1024 * 1024)  # Convert to MB

    def _save_preview_to_db(self, preview: PreviewEnvironment, created_by: str):
        """Save preview to database"""
        with self._get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    INSERT INTO preview_environments
                    (preview_id, source_session_id, reviewer_email, review_context,
                     created_at, expires_at, status, access_url, container_id,
                     storage_path, read_only, created_by)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    preview.preview_id, preview.source_session_id, preview.reviewer_email,
                    preview.review_context, preview.created_at, preview.expires_at,
                    preview.status, preview.access_url, preview.container_id,
                    preview.storage_path, preview.read_only, created_by
                ))
                conn.commit()

    def _get_db_connection(self):
        """Get database connection"""
        # In real implementation, use proper connection pooling
        return psycopg2.connect(os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/code_server"))

# ============================================================================
# FASTAPI APPLICATION
# ============================================================================

app = FastAPI(title="Preview Environments Service", version="1.0.0")

preview_manager = PreviewEnvironmentManager()

@app.on_event("startup")
async def startup_event():
    # Start background cleanup task
    asyncio.create_task(background_cleanup())

async def background_cleanup():
    """Background task to clean up expired previews"""
    while True:
        try:
            await preview_manager.cleanup_expired_previews()
            await asyncio.sleep(300)  # Run every 5 minutes
        except Exception as e:
            print(f"Background cleanup error: {e}")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "preview-environments"}

@app.post("/previews", response_model=PreviewEnvironment)
async def create_preview(request: PreviewRequest, background_tasks: BackgroundTasks):
    """Create a new preview environment"""
    created_by = "system"  # In real implementation, get from JWT
    return await preview_manager.create_preview(request, created_by)

@app.get("/previews/{preview_id}", response_model=PreviewEnvironment)
async def get_preview(preview_id: str):
    """Get preview environment details"""
    preview = await preview_manager.get_preview(preview_id)
    if not preview:
        raise HTTPException(404, "Preview environment not found")
    return preview

@app.get("/previews/{preview_id}/status", response_model=PreviewStatus)
async def get_preview_status(preview_id: str):
    """Get detailed status of a preview environment"""
    status = await preview_manager.get_preview_status(preview_id)
    if not status:
        raise HTTPException(404, "Preview environment not found")
    return status

@app.delete("/previews/{preview_id}")
async def cleanup_preview(preview_id: str):
    """Manually cleanup a preview environment"""
    preview = await preview_manager.get_preview(preview_id)
    if not preview:
        raise HTTPException(404, "Preview environment not found")

    await preview_manager._cleanup_preview(
        preview.preview_id,
        preview.container_id,
        preview.storage_path
    )

    with preview_manager._get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE preview_environments
                SET status = 'manually_cleaned'
                WHERE preview_id = %s
            """, (preview_id,))
            conn.commit()

    return {"status": "cleaned"}

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8004)