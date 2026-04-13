from __future__ import annotations
from typing import Any
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from auth.introspection import is_token_active
from auth.jwt_validator import validate_token
from config import get_settings

settings = get_settings()
_http_bearer = HTTPBearer(auto_error=False)

ROLE_LEVELS: dict[str, int] = {
    "mcp-admin": 40, "mcp-executor": 30, "mcp-coder": 20, "mcp-readonly": 10,
}
HIGH_RISK_TOOLS = frozenset({
    "bash", "terminal", "write_file", "delete_file", "apply_patch", "deploy",
    "terraform_apply", "kubectl_apply", "docker_run",
})

def _extract_role(payload: dict) -> str:
    realm_roles = (
        payload.get("realm_access", {}).get("roles", [])
        + payload.get("resource_access", {}).get(settings.jwt_audience, {}).get("roles", [])
    )
    best = "mcp-readonly"
    for role in realm_roles:
        if role in ROLE_LEVELS and ROLE_LEVELS[role] > ROLE_LEVELS.get(best, 0):
            best = role
    return best

async def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_http_bearer),
) -> dict:
    if settings.dev_mode:
        return {"sub": "dev-user", "email": "dev@localhost", "role": "mcp-admin"}
    if not creds:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Bearer token", headers={"WWW-Authenticate": "Bearer"})
    from jose import JWTError
    try:
        payload = await validate_token(creds.credentials)
    except JWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {exc}", headers={"WWW-Authenticate": "Bearer"})
    payload["role"] = _extract_role(payload)
    return payload

async def require_executor_privilege(
    user: dict = Depends(get_current_user),
    creds: HTTPAuthorizationCredentials | None = Depends(_http_bearer),
) -> dict:
    if settings.dev_mode:
        return user
    if ROLE_LEVELS.get(user.get("role", ""), 0) < ROLE_LEVELS["mcp-executor"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Role '{user.get('role')}' insufficient. Requires mcp-executor or above.")
    if creds and not await is_token_active(creds.credentials):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token no longer active (introspection check failed)")
    return user
