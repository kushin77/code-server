"""
Agent Runtime Application Factory

Creates a FastAPI application with modular blueprint registration,
health checks, and integrated logging.

Usage:
    from app import create_app
    app = create_app()
    
    # Run with:
    #   uvicorn app:create_app --factory --host 0.0.0.0 --port 8020
    #   gunicorn -w 4 -k uvicorn.workers.UvicornWorker app:create_app
"""

from fastapi import FastAPI, APIRouter
from fastapi.middleware.cors import CORSMiddleware

from config import DEBUG, ENVIRONMENT, validate_config
from log import get_logger, log_event

log = get_logger(__name__)


def create_app() -> FastAPI:
    """
    Application factory — idempotent, returns a configured FastAPI app.
    
    Validates configuration, initializes logging, and registers blueprints.
    """
    # ── Validate configuration ────────────────────────────────────────────────
    validate_config()
    
    # ── Create app ────────────────────────────────────────────────────────────
    app = FastAPI(
        title="Agent Runtime",
        description="Sandboxed agent execution with approval gating and OIDC",
        version="1.0",
        debug=DEBUG,
    )
    
    # ── CORS configuration ────────────────────────────────────────────────────
    CORS_ORIGINS = ["*"] if DEBUG else ["http://localhost:3000", "http://localhost:8080"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # ── Startup event ────────────────────────────────────────────────────────
    @app.on_event("startup")
    async def startup_event():
        log_event(
            log,
            "agent_runtime_startup",
            environment=ENVIRONMENT,
            debug=DEBUG,
        )
    
    # ── Shutdown event ───────────────────────────────────────────────────────
    @app.on_event("shutdown")
    async def shutdown_event():
        log_event(log, "agent_runtime_shutdown")
    
    # ── Register blueprints / routers ────────────────────────────────────────
    # Health checks
    from health import router as health_router
    app.include_router(health_router, prefix="/health", tags=["health"])
    
    # Agent execution (to be imported once refactored)
    # from execution import router as execution_router
    # app.include_router(execution_router, prefix="/api/agents", tags=["execution"])
    
    log_event(log, "agent_runtime_app_created")
    return app
