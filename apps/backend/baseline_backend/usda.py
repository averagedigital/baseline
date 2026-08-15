from __future__ import annotations

from dataclasses import dataclass

import httpx

from .config import Settings


@dataclass(frozen=True)
class NutrientMatch:
    fdc_id: int
    description: str
    kcal_per_100g: float


class USDAClient:
    def __init__(self, settings: Settings, client: httpx.Client | None = None) -> None:
        self.settings = settings
        self.client = client or httpx.Client(timeout=settings.request_timeout_seconds)
        self._cache: dict[str, NutrientMatch | None] = {}

    def search_energy(self, query: str) -> NutrientMatch | None:
        key = query.strip().lower()
        if not key:
            return None
        if key in self._cache:
            return self._cache[key]
        response = self.client.post(
            "https://api.nal.usda.gov/fdc/v1/foods/search",
            params={"api_key": self.settings.usda_api_key},
            json={
                "query": query,
                "pageSize": 12,
                "dataType": ["Foundation", "SR Legacy", "Survey (FNDDS)"],
            },
        )
        response.raise_for_status()
        foods = response.json().get("foods", [])
        candidates: list[tuple[int, NutrientMatch]] = []
        priorities = {"Foundation": 3, "Survey (FNDDS)": 2, "SR Legacy": 1}
        for food in foods:
            energy = self._energy(food.get("foodNutrients", []))
            fdc_id = food.get("fdcId")
            if energy is None or not isinstance(fdc_id, int):
                continue
            match = NutrientMatch(
                fdc_id=fdc_id,
                description=str(food.get("description", query)),
                kcal_per_100g=energy,
            )
            candidates.append((priorities.get(str(food.get("dataType")), 0), match))
        value = max(candidates, key=lambda item: item[0])[1] if candidates else None
        self._cache[key] = value
        return value

    @staticmethod
    def _energy(nutrients: list[dict]) -> float | None:
        for nutrient in nutrients:
            name = str(nutrient.get("nutrientName", nutrient.get("name", ""))).lower()
            unit = str(nutrient.get("unitName", "")).upper()
            value = nutrient.get("value", nutrient.get("amount"))
            if name == "energy" and unit == "KCAL" and isinstance(value, (int, float)):
                return float(value)
        return None
