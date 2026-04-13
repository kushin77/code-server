import asyncio, time
from typing import Any
import httpx

_cache: dict = {}
_lock = asyncio.Lock()
CACHE_TTL_SECONDS = 900

async def get_jwks(jwks_url: str) -> dict:
    async with _lock:
        now = time.monotonic()
        if _cache.get("url") == jwks_url and now - _cache.get("ts", 0) < CACHE_TTL_SECONDS:
            return _cache["keys"]
        async with httpx.AsyncClient() as client:
            r = await client.get(jwks_url, timeout=5.0)
            r.raise_for_status()
        _cache.update({"url": jwks_url, "keys": r.json(), "ts": now})
        return r.json()

def invalidate() -> None:
    _cache.clear()
