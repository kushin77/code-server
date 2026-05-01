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

import asyncio

from fastapi import FastAPI, APIRouter
from fastapi.middleware.cors import CORSMiddleware

from config import DEBUG, ENVIRONMENT, validate_config
from log import get_logger, log_event
from hermes_registration import hermes_client
from hermes_tracing import setup_tracing, instrument_app

log = get_logger(__name__)


def create_app() -> FastAPI:
    """
    Application factory — idempotent, returns a configured FastAPI app.
    
    Validates configuration, initializes logging, and registers blueprints.
    """
    # ── Validate configuration ────────────────────────────────────────────────
    validate_config()

    # ── Initialise distributed tracing (Hermes + Tempo) ──────────────────────
    setup_tracing(service_name="agent-runtime")

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
        # Initial dependency probe (non-blocking)
        from health import check_dependencies
        asyncio.create_task(check_dependencies())
        # Register with Hermes orchestrator (non-blocking — failure is tolerated)
        await hermes_client.register()

    # ── Shutdown event ───────────────────────────────────────────────────────
    @app.on_event("shutdown")
    async def shutdown_event():
        await hermes_client.deregister()
        log_event(log, "agent_runtime_shutdown")
    
    # ── Register blueprints / routers ────────────────────────────────────────
    # Health checks
    from health import router as health_router
    app.include_router(health_router, prefix="/health", tags=["health"])

    # Agent execution (to be imported once refactored)
    # from execution import router as execution_router
    # app.include_router(execution_router, prefix="/api/agents", tags=["execution"])

    # ── Apply OTEL FastAPI instrumentation after routers are mounted ──────────
    instrument_app(app)

    log_event(log, "agent_runtime_app_created")
    return app
