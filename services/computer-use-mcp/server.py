"""
Computer-Use MCP Server — Playwright-based browser/desktop automation
exposed as FastMCP tools for LangGraph agent-api.
"""
from __future__ import annotations
import base64
from io import BytesIO
from typing import Any
import asyncio
from fastapi import FastAPI
from fastmcp import FastMCP
from playwright.async_api import async_playwright

mcp = FastMCP("computer-use")
app = FastAPI()

_browser_instance = None
_page_instance = None
_lock = asyncio.Lock()

async def _get_page():
    global _browser_instance, _page_instance
    async with _lock:
        if _browser_instance is None:
            pw = await async_playwright().start()
            _browser_instance = await pw.chromium.launch(headless=True, args=["--no-sandbox"])
            context = await _browser_instance.new_context()
            _page_instance = await context.new_page()
    return _page_instance

@mcp.tool()
async def navigate(url: str) -> str:
    """Navigate the browser to a URL."""
    page = await _get_page()
    await page.goto(url, wait_until="domcontentloaded", timeout=30000)
    return f"Navigated to {page.url}"

@mcp.tool()
async def screenshot() -> str:
    """Capture a screenshot of the current page. Returns base64-encoded PNG."""
    page = await _get_page()
    data = await page.screenshot(type="png", full_page=False)
    return base64.b64encode(data).decode("ascii")

@mcp.tool()
async def click(selector: str) -> str:
    """Click an element identified by a CSS selector."""
    page = await _get_page()
    await page.click(selector, timeout=10000)
    return f"Clicked: {selector}"

@mcp.tool()
async def type_text(selector: str, text: str) -> str:
    """Type text into an input field."""
    page = await _get_page()
    await page.fill(selector, text)
    return f"Typed into {selector}"

@mcp.tool()
async def get_page_text() -> str:
    """Extract all visible text from the current page (truncated to 4096 chars)."""
    page = await _get_page()
    text = await page.inner_text("body")
    return text[:4096]

@mcp.tool()
async def evaluate_js(script: str) -> str:
    """Execute JavaScript in the browser context and return the stringified result."""
    page = await _get_page()
    result = await page.evaluate(script)
    return str(result)[:2048]

app.mount("/", mcp.get_asgi_app())

@app.get("/health")
async def health() -> dict:
    return {"status": "healthy", "service": "computer-use-mcp"}
