"""
Agent Farm FastAPI Application
Main entry point — all routes wired here.

Endpoints:
  POST /run_task            — Submit a task (blocking)
  GET  /stream_task         — SSE streaming execution
  GET  /status/{thread_id}  — Poll task status
  GET  /threads             — List all threads
  POST /resume/{thread_id}  — HITL approve/reject
  DELETE /thread/{thread_id}— Delete thread
  GET  /agents              — Agent catalog
  GET  /models              — Available Ollama models
  GET  /health              — Aggregate health check
  GET  /graph               — LangGraph structure
  GET  /pending_approvals   — Outstanding HITL requests
  POST /rag/index           — Trigger RAG indexing
  GET  /rag/search          — Semantic search
  GET  /metrics             — Prometheus metrics
"""
from __future__ import annotations

import asyncio
import json
import logging
import uuid
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import httpx
import structlog
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from starlette.responses import Response

from agent_farm import AgentState, Plan, get_graph
from auth.rbac import get_current_user, require_executor_privilege
from config import get_settings
from models import (
    AgentInfo,
    HealthResponse,
    MessageOut,
    ModelInfo,
    PendingApproval,
    RagIndexRequest,
    ResumeTaskRequest,
    RunTaskRequest,
    RunTaskResponse,
    TaskStatus,
)

logger = structlog.get_logger(__name__)
settings = get_settings()
limiter = Limiter(key_func=get_remote_address)

# ── Prometheus metrics ────────────────────────────────────────────────────────
TASK_COUNTER = Counter("agent_tasks_total", "Total tasks submitted", ["status"])
TASK_LATENCY = Histogram("agent_task_duration_seconds", "Task execution latency")
HITL_COUNTER = Counter("agent_hitl_events_total", "HITL approval events", ["decision"])

# In-memory HITL store (replace with Redis for HA)
_pending_approvals: dict[str, dict] = {}


# ── Lifespan ──────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Agent Farm API starting", ollama=settings.ollama_base_url)
    yield
    logger.info("Agent Farm API shutting down")


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Agent Farm API",
    version="1.0.0",
    description="LangGraph multi-agent orchestration for code-server enterprise",
    lifespan=lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _msgs_to_out(messages: list) -> list[MessageOut]:
    out = []
    for m in messages:
        if isinstance(m, HumanMessage):
            out.append(MessageOut(role="human", content=str(m.content)))
        elif isinstance(m, AIMessage):
            tc = [dict(t) if hasattr(t, "__iter__") else t for t in (m.tool_calls or [])]
            out.append(MessageOut(role="ai", content=str(m.content), tool_calls=tc or None))
        elif isinstance(m, SystemMessage):
            out.append(MessageOut(role="system", content=str(m.content)))
    return out


async def _run_graph_blocking(thread_id: str, initial_state: AgentState) -> AgentState | None:
    config = {"configurable": {"thread_id": thread_id}}
    graph = get_graph()
    final = None
    async for chunk in graph.astream(initial_state, config=config, stream_mode="values"):
        final = chunk
    return final


# ── Task Endpoints ────────────────────────────────────────────────────────────

@app.post("/run_task", response_model=RunTaskResponse, tags=["tasks"])
@limiter.limit("30/minute")
async def run_task(
    request: Request,
    body: RunTaskRequest,
    user: dict = Depends(get_current_user),
) -> RunTaskResponse:
    """Submit a task to the agent farm (blocking until completion or HITL)."""
    thread_id = body.thread_id
    initial: AgentState = {
        "messages": [HumanMessage(content=body.task)],
        "task": body.task,
        "plan": None,
        "iteration_count": 0,
        "parallel_results": {},
        "rag_context": [],
        "hitl_pending": None,
        "next_agent": "",
        "thread_id": thread_id,
        "user_role": user.get("role", "mcp-readonly"),
    }

    with TASK_LATENCY.time():
        try:
            final = await _run_graph_blocking(thread_id, initial)
            TASK_COUNTER.labels(status="completed").inc()
        except Exception as exc:
            TASK_COUNTER.labels(status="failed").inc()
            logger.exception("Task failed", thread_id=thread_id, error=str(exc))
            raise HTTPException(status_code=500, detail=str(exc))

    messages = _msgs_to_out((final or {}).get("messages", []))
    last = messages[-1].content if messages else ""
    return RunTaskResponse(thread_id=thread_id, status="completed", result=last, messages=messages)


@app.get("/stream_task", tags=["tasks"])
@limiter.limit("20/minute")
async def stream_task(
    request: Request,
    task: str = Query(..., max_length=4096),
    thread_id: str = Query(default_factory=lambda: str(uuid.uuid4())),
    user: dict = Depends(get_current_user),
) -> StreamingResponse:
    """Execute a task with Server-Sent Events streaming."""

    async def _gen() -> AsyncGenerator[str, None]:
        initial: AgentState = {
            "messages": [HumanMessage(content=task)],
            "task": task,
            "plan": None,
            "iteration_count": 0,
            "parallel_results": {},
            "rag_context": [],
            "hitl_pending": None,
            "next_agent": "",
            "thread_id": thread_id,
            "user_role": user.get("role", "mcp-readonly"),
        }
        config = {"configurable": {"thread_id": thread_id}}
        try:
            async for chunk in get_graph().astream(initial, config=config, stream_mode="updates"):
                payload = json.dumps({"event": "update", "data": str(chunk)[:2000]})
                yield f"data: {payload}\n\n"
                await asyncio.sleep(0)
            yield f"data: {json.dumps({'event': 'done', 'thread_id': thread_id})}\n\n"
        except Exception as exc:
            yield f"data: {json.dumps({'event': 'error', 'message': str(exc)})}\n\n"

    return StreamingResponse(_gen(), media_type="text/event-stream")


@app.get("/status/{thread_id}", response_model=TaskStatus, tags=["tasks"])
async def get_status(
    thread_id: str,
    user: dict = Depends(get_current_user),
) -> TaskStatus:
    """Poll the current status of a task thread."""
    config = {"configurable": {"thread_id": thread_id}}
    state_snap = get_graph().get_state(config)
    if not state_snap or not state_snap.values:
        raise HTTPException(status_code=404, detail="Thread not found")
    vals = state_snap.values
    msgs = _msgs_to_out(vals.get("messages", []))
    hitl = vals.get("hitl_pending")
    status = "waiting_approval" if hitl else (
        "completed" if vals.get("next_agent") in ("finish", None, "") else "running"
    )
    return TaskStatus(
        thread_id=thread_id,
        status=status,
        messages=msgs,
        plan=vals.get("plan", {}).model_dump() if vals.get("plan") else None,
        iteration_count=vals.get("iteration_count", 0),
        parallel_results=vals.get("parallel_results"),
        hitl_pending=hitl.model_dump() if hitl else None,
    )


@app.get("/threads", tags=["tasks"])
async def list_threads(user: dict = Depends(get_current_user)) -> dict:
    """List all known thread IDs from the checkpointer."""
    try:
        threads = [t.config["configurable"]["thread_id"] for t in get_graph().checkpointer.list()]
        return {"threads": threads}
    except Exception:
        return {"threads": []}


@app.delete("/thread/{thread_id}", tags=["tasks"])
async def delete_thread(
    thread_id: str,
    user: dict = Depends(require_executor_privilege),
) -> dict:
    """Delete a thread. Requires executor role."""
    try:
        get_graph().checkpointer.delete({"configurable": {"thread_id": thread_id}})
        return {"deleted": thread_id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── HITL Endpoints ────────────────────────────────────────────────────────────

@app.get("/pending_approvals", response_model=list[PendingApproval], tags=["hitl"])
async def pending_approvals(user: dict = Depends(require_executor_privilege)) -> list[PendingApproval]:
    """List outstanding HITL approval requests."""
    return [PendingApproval(**v) for v in _pending_approvals.values()]


@app.post("/resume/{thread_id}", tags=["hitl"])
async def resume_task(
    thread_id: str,
    body: ResumeTaskRequest,
    user: dict = Depends(require_executor_privilege),
) -> dict:
    """Approve or reject a pending HITL interrupt and resume execution."""
    from langgraph.types import Command
    decision = "approved" if body.approved else "rejected"
    HITL_COUNTER.labels(decision=decision).inc()
    logger.info("HITL decision", thread_id=thread_id, decision=decision, user=user.get("sub"))
    config = {"configurable": {"thread_id": thread_id}}
    try:
        final = None
        async for chunk in get_graph().astream(
            Command(resume={"approved": body.approved, "reason": body.reason}),
            config=config,
            stream_mode="values",
        ):
            final = chunk
        _pending_approvals.pop(thread_id, None)
        last = final["messages"][-1].content if final and final.get("messages") else ""
        return {"thread_id": thread_id, "status": "resumed", "result": last}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ── Info Endpoints ────────────────────────────────────────────────────────────

@app.get("/agents", response_model=list[AgentInfo], tags=["info"])
async def list_agents() -> list[AgentInfo]:
    return [
        AgentInfo(name="supervisor", description="Routes tasks to specialist agents", model=settings.ollama_default_model, capabilities=["routing", "orchestration"]),
        AgentInfo(name="planner", description="Decomposes tasks into steps with RAG context", model=settings.ollama_fast_model, capabilities=["planning", "rag"]),
        AgentInfo(name="coder", description="Writes production-grade code", model=settings.ollama_default_model, capabilities=["code_generation", "file_io", "search"]),
        AgentInfo(name="tester", description="Runs test suites and reports failures", model=settings.ollama_fast_model, capabilities=["test_execution", "terminal"]),
        AgentInfo(name="reviewer", description="FAANG-level code review", model=settings.ollama_default_model, capabilities=["code_review", "security_audit"]),
        AgentInfo(name="executor", description="Applies approved changes (HITL gated)", model=settings.ollama_default_model, capabilities=["terminal", "file_io", "system"]),
    ]


@app.get("/models", response_model=list[ModelInfo], tags=["info"])
async def list_models() -> list[ModelInfo]:
    try:
        async with httpx.AsyncClient() as client:
            r = await client.get(f"{settings.ollama_base_url}/api/tags", timeout=5.0)
            if r.status_code == 200:
                return [ModelInfo(name=m["name"]) for m in r.json().get("models", [])]
    except Exception:
        pass
    return [ModelInfo(name=settings.ollama_default_model), ModelInfo(name=settings.ollama_fast_model)]


@app.get("/health", response_model=HealthResponse, tags=["info"])
async def health() -> HealthResponse:
    """Aggregate health across all dependent services."""
    checks: dict[str, str] = {}
    async with httpx.AsyncClient() as client:
        for name, url in [
            ("ollama", f"{settings.ollama_base_url}/api/tags"),
            ("chroma", f"http://{settings.chroma_host}:{settings.chroma_port}/api/v1/heartbeat"),
            ("keycloak", settings.keycloak_realm_url),
        ]:
            try:
                r = await client.get(url, timeout=3.0)
                checks[name] = "healthy" if r.status_code == 200 else f"http_{r.status_code}"
            except Exception:
                checks[name] = "unreachable"

    all_healthy = all(v == "healthy" for v in checks.values())
    none_healthy = all(v != "healthy" for v in checks.values())
    overall = "healthy" if all_healthy else ("unhealthy" if none_healthy else "degraded")
    return HealthResponse(status=overall, components=checks)


@app.get("/graph", tags=["info"])
async def graph_structure(user: dict = Depends(get_current_user)) -> dict:
    """Return the LangGraph structure (nodes and edges)."""
    g = get_graph()
    return {
        "nodes": list(g.nodes.keys()),
        "edges": [{"from": e[0], "to": e[1]} for e in g.edges],
    }


# ── RAG Endpoints ─────────────────────────────────────────────────────────────

@app.post("/rag/index", tags=["rag"])
async def rag_index(body: RagIndexRequest, user: dict = Depends(require_executor_privilege)) -> dict:
    """Trigger RAG indexing of a codebase path."""
    async with httpx.AsyncClient() as client:
        try:
            r = await client.post(
                f"http://{settings.chroma_host}:{settings.chroma_port}/index",
                json=body.model_dump(), timeout=10.0,
            )
            return r.json()
        except Exception as exc:
            raise HTTPException(status_code=503, detail=f"Embeddings service unavailable: {exc}")


@app.get("/rag/search", tags=["rag"])
async def rag_search(
    q: str = Query(..., max_length=512),
    k: int = Query(5, ge=1, le=20),
    user: dict = Depends(get_current_user),
) -> dict:
    """Semantic search over the indexed codebase."""
    async with httpx.AsyncClient() as client:
        try:
            r = await client.get(
                f"http://{settings.chroma_host}:{settings.chroma_port}/search",
                params={"q": q, "k": k}, timeout=5.0,
            )
            return r.json()
        except Exception as exc:
            raise HTTPException(status_code=503, detail=f"Search unavailable: {exc}")


# ── Metrics ───────────────────────────────────────────────────────────────────

@app.get("/metrics", tags=["observability"])
async def metrics() -> Response:
    """Prometheus metrics."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
