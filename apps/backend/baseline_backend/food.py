from __future__ import annotations

from datetime import datetime
from io import BytesIO
from uuid import UUID, uuid4

from PIL import Image
from sqlalchemy.orm import Session

from .config import Settings
from .models import FoodObservationRecord
from .openai_client import OpenAIResponsesClient
from .repository import recent_food_for_dedupe
from .schemas import FoodAnalysisResponse, FoodItemResult
from .usda import USDAClient


class FoodAnalyzer:
    def __init__(self, settings: Settings, vision: OpenAIResponsesClient, usda: USDAClient) -> None:
        self.settings = settings
        self.vision = vision
        self.usda = usda

    def analyze(
        self,
        db: Session,
        *,
        user_id: str,
        image_bytes: bytes,
        captured_at: datetime,
        media_type: str = "image/jpeg",
    ) -> FoodAnalysisResponse:
        image_hash = difference_hash(image_bytes)
        for recent in recent_food_for_dedupe(
            db,
            user_id,
            captured_at,
            self.settings.food_dedupe_seconds,
        ):
            if hamming_distance(image_hash, recent.image_hash) <= self.settings.food_hash_hamming_threshold:
                if recent.dismissed:
                    return FoodAnalysisResponse(
                        contains_food=False,
                        stored=False,
                        duplicate_of=UUID(recent.id),
                        observation_id=UUID(recent.id),
                        confidence=0,
                    )
                return FoodAnalysisResponse(
                    contains_food=True,
                    stored=False,
                    duplicate_of=UUID(recent.id),
                    observation_id=UUID(recent.id),
                    confidence=recent.confidence,
                    calories_low=recent.calories_low,
                    calories_high=recent.calories_high,
                    items=[FoodItemResult.model_validate(item) for item in recent.items],
                )

        vision = self.vision.analyze_food(image_bytes, media_type=media_type)
        if not vision.contains_food or vision.confidence < 0.55 or not vision.items:
            return FoodAnalysisResponse(
                contains_food=False,
                stored=False,
                confidence=vision.confidence,
            )

        results: list[FoodItemResult] = []
        for item in vision.items:
            nutrient = self.usda.search_energy(item.name)
            if nutrient:
                kcal_per_100g = nutrient.kcal_per_100g
                fdc_id = nutrient.fdc_id
                source = "usda"
            else:
                kcal_per_100g = item.estimated_kcal_per_100g
                fdc_id = None
                source = "model_fallback"

            confidence = min(item.label_confidence, item.portion_confidence)
            uncertainty = min(max(0.20 + (1 - confidence) * 0.45, 0.20), 0.65)
            nominal_low = kcal_per_100g * min(item.grams_low, item.estimated_grams) / 100
            nominal_high = kcal_per_100g * max(item.grams_high, item.estimated_grams) / 100
            calories_low = max(0, nominal_low * (1 - uncertainty))
            calories_high = max(calories_low, nominal_high * (1 + uncertainty))
            results.append(
                FoodItemResult(
                    name=item.name,
                    estimated_grams=item.estimated_grams,
                    grams_low=min(item.grams_low, item.estimated_grams),
                    grams_high=max(item.grams_high, item.estimated_grams),
                    label_confidence=item.label_confidence,
                    portion_confidence=item.portion_confidence,
                    fdc_id=fdc_id,
                    kcal_per_100g=kcal_per_100g,
                    nutrient_source=source,
                    calories_low=round(calories_low, 1),
                    calories_high=round(calories_high, 1),
                )
            )

        observation_id = uuid4()
        total_low = round(sum(item.calories_low for item in results), 1)
        total_high = round(sum(item.calories_high for item in results), 1)
        db.add(
            FoodObservationRecord(
                id=str(observation_id),
                user_id=user_id,
                captured_at=captured_at,
                image_hash=image_hash,
                confidence=vision.confidence,
                calories_low=total_low,
                calories_high=total_high,
                items=[item.model_dump(mode="json") for item in results],
            )
        )
        db.commit()
        return FoodAnalysisResponse(
            contains_food=True,
            stored=True,
            observation_id=observation_id,
            confidence=vision.confidence,
            calories_low=total_low,
            calories_high=total_high,
            items=results,
        )


def difference_hash(image_bytes: bytes) -> str:
    with Image.open(BytesIO(image_bytes)) as image:
        grayscale = image.convert("L").resize((9, 8))
        pixels = list(grayscale.getdata())
    bits = 0
    for row in range(8):
        for column in range(8):
            left = pixels[row * 9 + column]
            right = pixels[row * 9 + column + 1]
            bits = (bits << 1) | int(left > right)
    return f"{bits:016x}"


def hamming_distance(left: str, right: str) -> int:
    return (int(left, 16) ^ int(right, 16)).bit_count()
