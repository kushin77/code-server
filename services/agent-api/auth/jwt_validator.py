from typing import Any
from jose import JWTError, jwt
from auth.jwks import get_jwks, invalidate
from config import get_settings
settings = get_settings()

async def validate_token(token: str) -> dict:
    for attempt in range(2):
        jwks = await get_jwks(settings.jwks_url)
        try:
            return jwt.decode(token, jwks, algorithms=["RS256"],
                              audience=settings.jwt_audience, options={"verify_exp": True})
        except JWTError as exc:
            if attempt == 0 and "key" in str(exc).lower():
                invalidate(); continue
            raise
    raise JWTError("JWT validation failed after JWKS refresh")
