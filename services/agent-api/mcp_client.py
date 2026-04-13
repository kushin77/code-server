"""
MCP client wrapper — bridges LangGraph agents to FastMCP servers
(computer-use-mcp, backstage MCP) via langchain-mcp-adapters.
"""
from __future__ import annotations

from functools import lru_cache
from typing import Any

from langchain_mcp_adapters.client import MultiServerMCPClient

from config import get_settings

settings = get_settings()


@lru_cache(maxsize=1)
def get_mcp_client() -> MultiServerMCPClient:
    """Return a shared MultiServerMCPClient instance (lazy, cached)."""
    return MultiServerMCPClient(
        servers={
            "computer_use": {
                "url": f"{settings.computer_use_mcp_url}/sse",
                "transport": "sse",
            },
            "backstage": {
                "url": f"{settings.backstage_mcp_url}/mcp/sse",
                "transport": "sse",
            },
        }
    )


async def get_tools(server: str | None = None) -> list[Any]:
    """
    Return LangChain-compatible tools from the specified MCP server.
    If server is None, returns tools from all servers.
    """
    client = get_mcp_client()
    if server:
        return await client.get_tools(server_name=server)
    return await client.get_tools()
