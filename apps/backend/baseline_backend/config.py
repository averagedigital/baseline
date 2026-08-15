from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "sqlite:///./baseline.db"
    api_token: str = Field(default="dev-only-change-me", min_length=12)
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    openai_text_model: str = "gpt-5"
    openai_vision_model: str = "gpt-5"
    usda_api_key: str = "DEMO_KEY"
    request_timeout_seconds: float = 45.0
    food_dedupe_seconds: int = 120
    food_hash_hamming_threshold: int = 6
    auto_create_schema: bool = True


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
