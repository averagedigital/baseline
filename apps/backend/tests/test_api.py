from fastapi.testclient import TestClient

from baseline_backend.config import Settings
from baseline_backend.main import create_app


def test_app_factory_uses_supplied_database_and_auth(tmp_path) -> None:
    settings = Settings(
        database_url=f"sqlite:///{tmp_path / 'api.db'}",
        api_token="x" * 32,
        openai_api_key="",
        usda_api_key="DEMO_KEY",
    )

    with TestClient(create_app(settings)) as client:
        assert client.get("/healthz").json() == {"status": "ok"}
        assert client.get("/v1/home").status_code == 401
        response = client.get(
            "/v1/home",
            headers={
                "Authorization": f"Bearer {settings.api_token}",
                "X-Baseline-User-ID": "user-1",
            },
        )
        assert response.status_code == 200
        assert response.json()["latest_session"] is None
