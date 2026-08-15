from collections.abc import Generator
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .config import Settings, get_settings
from .db import Base, make_engine, make_session_factory
from .food import FoodAnalyzer
from .openai_client import OpenAIResponsesClient
from .repository import append_feedback, dismiss_food, store_evidence
from .schemas import (
    ChatRequest,
    ChatResponse,
    EvidenceUpload,
    EvidenceUploadResponse,
    FeedbackRequest,
    FeedbackResponse,
    FoodAnalysisResponse,
    FoodDismissResponse,
    HomeResponse,
)
from .security import make_user_dependency
from .services import CoachService, HomeService, PersonalizationService
from .usda import USDAClient


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    app_engine = make_engine(settings.database_url)
    session_factory = make_session_factory(app_engine)
    require_user = make_user_dependency(settings)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if settings.auto_create_schema:
            Base.metadata.create_all(app_engine)
        yield
        app_engine.dispose()

    def get_db() -> Generator[Session, None, None]:
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app = FastAPI(title="Baseline Backend", version="0.2.0", lifespan=lifespan)
    responses = OpenAIResponsesClient(settings)
    app.state.food_analyzer = FoodAnalyzer(settings, responses, USDAClient(settings))
    app.state.coach_service = CoachService(responses)
    app.state.personalization_service = PersonalizationService()
    app.state.home_service = HomeService()

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/v1/evidence", response_model=EvidenceUploadResponse)
    def evidence(
        payload: EvidenceUpload,
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
    ) -> EvidenceUploadResponse:
        return EvidenceUploadResponse(id=payload.id, stored=store_evidence(db, user_id, payload))

    @app.post("/v1/food/analyze", response_model=FoodAnalysisResponse)
    async def analyze_food(
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
        image: Annotated[UploadFile, File()],
        captured_at: Annotated[datetime, Form()],
    ) -> FoodAnalysisResponse:
        if image.content_type not in {"image/jpeg", "image/png", "image/heic", "image/heif"}:
            raise HTTPException(status_code=415, detail="unsupported image type")
        body = await image.read()
        if not body or len(body) > 8 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="image must be between 1 byte and 8 MB")
        try:
            return app.state.food_analyzer.analyze(
                db,
                user_id=user_id,
                image_bytes=body,
                captured_at=captured_at,
                media_type=image.content_type or "image/jpeg",
            )
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error

    @app.post("/v1/food/{observation_id}/dismiss", response_model=FoodDismissResponse)
    def dismiss_food_observation(
        observation_id: UUID,
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
    ) -> FoodDismissResponse:
        if not dismiss_food(db, user_id, observation_id):
            raise HTTPException(status_code=404, detail="food observation not found")
        append_feedback(
            db,
            user_id,
            event_type="food_correction",
            action=None,
            reward=None,
            target_value=None,
            context={"food_observation_id": str(observation_id), "correction": "not_food"},
        )
        return FoodDismissResponse(dismissed=True)

    @app.post("/v1/chat", response_model=ChatResponse)
    def chat(
        payload: ChatRequest,
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
    ) -> ChatResponse:
        try:
            return app.state.coach_service.answer(db, user_id, payload)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except RuntimeError as error:
            raise HTTPException(status_code=502, detail=str(error)) from error

    @app.post("/v1/feedback", response_model=FeedbackResponse)
    def feedback(
        payload: FeedbackRequest,
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
    ) -> FeedbackResponse:
        try:
            return app.state.personalization_service.feedback(db, user_id, payload)
        except LookupError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error

    @app.get("/v1/home", response_model=HomeResponse)
    def home(
        user_id: Annotated[str, Depends(require_user)],
        db: Annotated[Session, Depends(get_db)],
    ) -> HomeResponse:
        return app.state.home_service.home(db, user_id)

    return app


app = create_app()
