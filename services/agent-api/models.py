"""
Agent Farm Pydantic models — request/response schemas for the API.
"""
from __future__ import annotations
from typing import Any
from uuid import uuid4
from pydantic import BaseModel, Field

class RunTaskRequest(BaseModel):
    task: str = Field(..., description="Natural language task description", max_length=4096)
    thread_id: str = Field(default_factory=lambda: str(uuid4()), description="Unique thread identifier")

class MessageOut(BaseModel):
    role: str
    content: str
    tool_calls: list[dict] | None = None

class RunTaskResponse(BaseModel):
    thread_id: str
    status: str
    result: str
    messages: list[MessageOut]

class TaskStatus(BaseModel):
    thread_id: str
    status: str
    messages: list[MessageOut]
    plan: dict | None = None
    iteration_count: int = 0
    parallel_results: dict[str, Any] | None = None
    hitl_pending: dict | None = None

class ResumeTaskRequest(BaseModel):
    approved: bool = Field(..., description="Whether to approve the pending action")
    reason: str = Field("", description="Optional justification for the decision", max_length=1024)

class PendingApproval(BaseModel):
    thread_id: str
    description: str
    tool_name: str
    tool_args: dict[str, Any]

class AgentInfo(BaseModel):
    name: str
    description: str
    model: str
    capabilities: list[str]

class ModelInfo(BaseModel):
    name: str
    size: str | None = None
    modified_at: str | None = None

class HealthResponse(BaseModel):
    status: str
    components: dict[str, str]

class RagIndexRequest(BaseModel):
    path: str = Field(..., description="Filesystem path (inside container) to index")
    collection: str = Field("codebase", description="ChromaDB collection name")
    glob_pattern: str = Field("**/*.{py,ts,js,go,tf,yaml,yml,md}", description="Glob filter")
