from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class EvidenceUpload(BaseModel):
    id: UUID
    kind: str
    module_id: str
    observed_from: datetime
    observed_to: datetime
    epistemic_role: Literal["observed", "computed", "inferred", "userReported"]
    content_digest: str
    payload: dict


class EvidenceUploadResponse(BaseModel):
    id: UUID
    stored: bool


class FoodVisionItem(BaseModel):
    name: str
    estimated_grams: float = Field(ge=1, le=2500)
    grams_low: float = Field(ge=1, le=2500)
    grams_high: float = Field(ge=1, le=3000)
    label_confidence: float = Field(ge=0, le=1)
    portion_confidence: float = Field(ge=0, le=1)
    estimated_kcal_per_100g: float = Field(ge=0, le=1000)


class FoodVisionResult(BaseModel):
    contains_food: bool
    confidence: float = Field(ge=0, le=1)
    items: list[FoodVisionItem]


class FoodItemResult(BaseModel):
    name: str
    estimated_grams: float
    grams_low: float
    grams_high: float
    label_confidence: float
    portion_confidence: float
    fdc_id: int | None
    kcal_per_100g: float
    nutrient_source: Literal["usda", "model_fallback"]
    calories_low: float
    calories_high: float


class FoodAnalysisResponse(BaseModel):
    contains_food: bool
    stored: bool
    duplicate_of: UUID | None = None
    observation_id: UUID | None = None
    confidence: float
    calories_low: float = 0
    calories_high: float = 0
    items: list[FoodItemResult] = Field(default_factory=list)


class ChatRequest(BaseModel):
    thread_id: UUID | None = None
    message: str = Field(min_length=1, max_length=8000)


class ChatResponse(BaseModel):
    thread_id: UUID
    answer_markdown: str
    recommendation_category: Literal["technique", "load", "recovery", "nutrition", "consistency", "none"]
    evidence_ids: list[UUID]
    food_ids: list[UUID]
    context_digest: str
    feedback_context_id: UUID | None = None


class FeedbackRequest(BaseModel):
    event_type: Literal["session_rpe", "recommendation_reward", "food_correction"]
    action: Literal["technique", "load", "recovery", "nutrition", "consistency"] | None = None
    reward: float | None = Field(default=None, ge=-1, le=1)
    target_value: float | None = Field(default=None, ge=1, le=10)
    source_evidence_id: UUID | None = None
    feedback_context_id: UUID | None = None
    note: str | None = Field(default=None, max_length=1000)
    context: dict = Field(default_factory=dict)


class FeedbackResponse(BaseModel):
    stored: bool
    personalization_samples: int


class FoodDismissResponse(BaseModel):
    dismissed: bool


class HomeResponse(BaseModel):
    latest_session: dict | None
    latest_food: dict | None
    suggested_action: str
    predicted_difficulty: float | None
    prediction_confidence: float
