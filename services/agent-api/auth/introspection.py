from typing import Any
import httpx
from config import get_settings
settings = get_settings()

async def introspect_token(token: str) -> dict:
    async with httpx.AsyncClient() as client:
        r = await client.post(settings.introspection_url,
            data={"token": token, "token_type_hint": "access_token"},
            auth=(settings.introspection_client_id, settings.introspection_client_secret),
            timeout=5.0)
        r.raise_for_status()
        return r.json()

async def is_token_active(token: str) -> bool:
    result = await introspect_token(token)
    return bool(result.get("active", False))
