from datetime import datetime, timezone
from io import BytesIO

from PIL import Image

from baseline_backend.config import Settings
from baseline_backend.food import FoodAnalyzer
from baseline_backend.models import FoodObservationRecord
from baseline_backend.schemas import FoodVisionItem, FoodVisionResult
from baseline_backend.usda import NutrientMatch


class FakeVision:
    def analyze_food(self, image_bytes: bytes, media_type: str = "image/jpeg") -> FoodVisionResult:
        return FoodVisionResult(
            contains_food=True,
            confidence=0.9,
            items=[
                FoodVisionItem(
                    name="rice cooked",
                    estimated_grams=200,
                    grams_low=160,
                    grams_high=240,
                    label_confidence=0.9,
                    portion_confidence=0.7,
                    estimated_kcal_per_100g=130,
                )
            ],
        )


class FakeUSDA:
    def search_energy(self, query: str) -> NutrientMatch:
        return NutrientMatch(fdc_id=123, description="Rice, cooked", kcal_per_100g=130)


def jpeg() -> bytes:
    output = BytesIO()
    Image.new("RGB", (64, 64), (230, 220, 190)).save(output, format="JPEG")
    return output.getvalue()


def test_food_analysis_persists_range_but_never_image_bytes(db) -> None:
    settings = Settings(api_token="x" * 32, food_dedupe_seconds=120)
    analyzer = FoodAnalyzer(settings, FakeVision(), FakeUSDA())
    now = datetime.now(timezone.utc)

    first = analyzer.analyze(db, user_id="user-1", image_bytes=jpeg(), captured_at=now)
    second = analyzer.analyze(db, user_id="user-1", image_bytes=jpeg(), captured_at=now)

    assert first.stored
    assert first.calories_low < first.calories_high
    assert first.items[0].nutrient_source == "usda"
    assert not second.stored
    assert second.duplicate_of == first.observation_id
    row = db.get(FoodObservationRecord, str(first.observation_id))
    assert row is not None
    assert "image" not in row.__table__.columns


def test_dismissed_duplicate_is_suppressed_as_not_food(db) -> None:
    settings = Settings(api_token="x" * 32, food_dedupe_seconds=120)
    analyzer = FoodAnalyzer(settings, FakeVision(), FakeUSDA())
    now = datetime.now(timezone.utc)

    first = analyzer.analyze(db, user_id="user-1", image_bytes=jpeg(), captured_at=now)
    row = db.get(FoodObservationRecord, str(first.observation_id))
    assert row is not None
    row.dismissed = True
    db.commit()

    repeated = analyzer.analyze(db, user_id="user-1", image_bytes=jpeg(), captured_at=now)
    assert repeated.contains_food is False
    assert repeated.stored is False
    assert repeated.duplicate_of == first.observation_id
