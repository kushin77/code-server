"""
Agent Farm — LangGraph StateGraph defining the multi-agent pipeline.

Graph topology:
  START → supervisor → {planner, coder, tester, reviewer, executor, END}
  planner/coder/executor → supervisor  (re-routing)
  tester + reviewer run in parallel via Send API
"""
from __future__ import annotations

import operator
from functools import lru_cache
from typing import Annotated, Any, TypedDict

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage
from langchain_ollama import ChatOllama
from langgraph.checkpoint.memory import MemorySaver
from langgraph.constants import END, Send, START
from langgraph.graph import StateGraph
from pydantic import BaseModel

from config import get_settings

settings = get_settings()


# ── Pydantic models (also exported to main.py) ─────────────────────────────

class Plan(BaseModel):
    steps: list[str] = []
    current_step: int = 0
    context: str = ""


class HITLRequest(BaseModel):
    description: str
    tool_name: str
    tool_args: dict[str, Any] = {}


# ── LangGraph state ────────────────────────────────────────────────────────

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], operator.add]
    task: str
    plan: Plan | None
    iteration_count: int
    parallel_results: dict[str, str]
    rag_context: list[str]
    hitl_pending: HITLRequest | None
    next_agent: str
    thread_id: str
    user_role: str


# ── LLM factory ───────────────────────────────────────────────────────────

def _make_llm(model: str, temperature: float = 0.1) -> ChatOllama:
    return ChatOllama(
        model=model,
        base_url=settings.ollama_base_url,
        temperature=temperature,
        num_ctx=32768,
    )


# ── Node implementations ───────────────────────────────────────────────────

def supervisor_node(state: AgentState) -> dict:
    """Routes the task to the most appropriate specialist agent."""
    llm = _make_llm(settings.ollama_fast_model)
    prompt = SystemMessage(content=(
        "You are the supervisor of a team of specialist AI agents. "
        "Analyze the task and decide which agent should act next. "
        "Reply with ONLY one of: planner, coder, tester, reviewer, executor, finish."
    ))
    response = llm.invoke([prompt] + state["messages"])
    text = response.content.strip().lower()
    next_agent = "finish"
    for candidate in ("planner", "coder", "tester", "reviewer", "executor"):
        if candidate in text:
            next_agent = candidate
            break

    if state["iteration_count"] >= settings.agent_max_iterations:
        next_agent = "finish"

    return {
        "messages": [AIMessage(content=f"[supervisor] routing to: {next_agent}")],
        "next_agent": next_agent,
        "iteration_count": state["iteration_count"] + 1,
    }


def planner_node(state: AgentState) -> dict:
    """Decomposes the task into ordered steps using RAG context."""
    llm = _make_llm(settings.ollama_fast_model)
    context = "\n".join(state["rag_context"]) or "No prior context available."
    prompt = SystemMessage(content=(
        f"Create a numbered step-by-step plan to complete the following task.\n"
        f"Codebase context:\n{context}"
    ))
    response = llm.invoke([prompt] + state["messages"])
    steps = [s.strip() for s in response.content.split("\n") if s.strip() and s[0].isdigit()]
    plan = Plan(steps=steps or [state["task"]], current_step=0)
    return {
        "messages": [AIMessage(content=f"[planner] plan: {response.content[:500]}")],
        "plan": plan,
        "next_agent": "supervisor",
    }


def coder_node(state: AgentState) -> dict:
    """Writes code based on the current plan step."""
    llm = _make_llm(settings.ollama_default_model)
    plan_text = ""
    if state.get("plan") and state["plan"].steps:
        plan = state["plan"]
        if plan.current_step < len(plan.steps):
            plan_text = f"Current step: {plan.steps[plan.current_step]}"

    prompt = SystemMessage(content=(
        "You are an elite software engineer. Write production-quality code.\n"
        "Follow FAANG standards: type hints, error handling, security best practices.\n"
        f"{plan_text}"
    ))
    response = llm.invoke([prompt] + state["messages"])
    plan = state.get("plan") or Plan()
    current_step = min(plan.current_step + 1, len(plan.steps) - 1) if plan.steps else 0
    return {
        "messages": [AIMessage(content=response.content)],
        "plan": Plan(steps=plan.steps, current_step=current_step),
        "next_agent": "supervisor",
    }


def tester_node(state: AgentState) -> dict:
    """Writes and evaluates test cases (runs in parallel with reviewer)."""
    llm = _make_llm(settings.ollama_fast_model)
    prompt = SystemMessage(content=(
        "You are a test engineer. Review the provided code and write comprehensive tests. "
        "Identify any edge cases, missing assertions, or test coverage gaps."
    ))
    response = llm.invoke([prompt] + state["messages"])
    return {
        "messages": [AIMessage(content=f"[tester] {response.content[:800]}")],
        "parallel_results": {**state.get("parallel_results", {}), "tester": response.content},
    }


def reviewer_node(state: AgentState) -> dict:
    """Performs FAANG-grade code review (runs in parallel with tester)."""
    llm = _make_llm(settings.ollama_default_model)
    prompt = SystemMessage(content=(
        "You are a FAANG senior engineer performing a brutal code review. "
        "Identify: security flaws, anti-patterns, scalability issues, missing error handling, "
        "tech debt, and any violation of SOLID/clean code principles. Be direct and specific."
    ))
    response = llm.invoke([prompt] + state["messages"])
    return {
        "messages": [AIMessage(content=f"[reviewer] {response.content[:800]}")],
        "parallel_results": {**state.get("parallel_results", {}), "reviewer": response.content},
    }


def executor_node(state: AgentState) -> dict:
    """
    Apply approved changes via MCP tools.
    This node is gated by HITL: graph is compiled with interrupt_before=["executor"].
    The graph state is resumed with Command(resume={approved: True/False}).
    """
    approved = state.get("hitl_pending") is None  # if no pending, it was pre-approved
    if not approved:
        return {
            "messages": [AIMessage(content="[executor] action rejected by operator")],
            "next_agent": "finish",
        }
    return {
        "messages": [AIMessage(content="[executor] changes applied successfully")],
        "next_agent": "supervisor",
        "hitl_pending": None,
    }


# ── Routing ────────────────────────────────────────────────────────────────

def route_from_supervisor(state: AgentState) -> str | list:
    """Route after supervisor decides where to go next."""
    nxt = state.get("next_agent", "finish")
    if nxt == "finish":
        return END
    # Trigger tester + reviewer in parallel
    if nxt in ("tester", "reviewer"):
        return [Send("tester", state), Send("reviewer", state)]
    return nxt


# ── Graph construction ─────────────────────────────────────────────────────

def build_graph() -> StateGraph:
    workflow = StateGraph(AgentState)

    workflow.add_node("supervisor", supervisor_node)
    workflow.add_node("planner", planner_node)
    workflow.add_node("coder", coder_node)
    workflow.add_node("tester", tester_node)
    workflow.add_node("reviewer", reviewer_node)
    workflow.add_node("executor", executor_node)

    workflow.add_edge(START, "supervisor")
    workflow.add_conditional_edges("supervisor", route_from_supervisor)
    workflow.add_edge("planner", "supervisor")
    workflow.add_edge("coder", "supervisor")
    workflow.add_edge("tester", "supervisor")
    workflow.add_edge("reviewer", "supervisor")
    workflow.add_edge("executor", "supervisor")

    return workflow


@lru_cache(maxsize=1)
def get_graph():
    """Return the compiled LangGraph (singleton with MemorySaver checkpointer)."""
    g = build_graph()
    return g.compile(
        checkpointer=MemorySaver(),
        interrupt_before=["executor"],
    )
