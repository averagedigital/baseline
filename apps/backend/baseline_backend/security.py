from collections.abc import Callable
from typing import Annotated

from fastapi import Header, HTTPException, status

from .config import Settings


def make_user_dependency(settings: Settings) -> Callable:
    async def require_user(
        authorization: Annotated[str | None, Header()] = None,
        x_baseline_user_id: Annotated[str | None, Header()] = None,
    ) -> str:
        expected = f"Bearer {settings.api_token}"
        if authorization != expected:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid bearer token")
        if not x_baseline_user_id or len(x_baseline_user_id) > 64:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="missing user id")
        return x_baseline_user_id

    return require_user
