from __future__ import annotations

from dataclasses import dataclass

import numpy as np


ACTIONS = ("technique", "load", "recovery", "nutrition", "consistency")
FEATURE_DIMENSION = 8


@dataclass(frozen=True)
class PersonalizationPrediction:
    predicted_difficulty: float | None
    confidence: float
    suggested_action: str
    samples: int


class OnlinePersonalizer:
    """Per-user online learning that never changes measured evidence.

    RLS-like ridge updates calibrate expected session difficulty from explicit RPE.
    Disjoint LinUCB ranks coaching categories from explicit useful/not-useful feedback.
    """

    def __init__(self, *, alpha: float = 0.35, ridge: float = 2.0) -> None:
        self.alpha = alpha
        self.ridge = ridge

    def initial_state(self) -> dict:
        identity = (np.eye(FEATURE_DIMENSION) * self.ridge).tolist()
        zeros = np.zeros(FEATURE_DIMENSION).tolist()
        return {
            "version": "personalization-v1",
            "difficulty": {"A": identity, "b": zeros, "samples": 0},
            "bandit": {
                "samples": 0,
                "actions": {
                    action: {"A": identity, "b": zeros, "samples": 0}
                    for action in ACTIONS
                },
            },
        }

    def predict(self, state: dict | None, features: list[float]) -> PersonalizationPrediction:
        state = state or self.initial_state()
        x = self._vector(features)
        difficulty = state["difficulty"]
        samples = int(difficulty.get("samples", 0))
        predicted: float | None = None
        if samples >= 3:
            theta = self._theta(difficulty)
            predicted = float(np.clip(theta @ x, 1.0, 10.0))
        confidence = min(samples / 20.0, 1.0)

        scores: dict[str, float] = {}
        for action in ACTIONS:
            arm = state["bandit"]["actions"][action]
            A = np.asarray(arm["A"], dtype=float)
            A_inv = np.linalg.inv(A)
            theta = A_inv @ np.asarray(arm["b"], dtype=float)
            exploration = self.alpha * float(np.sqrt(max(x @ A_inv @ x, 0.0)))
            scores[action] = float(theta @ x + exploration)
        suggested = max(ACTIONS, key=lambda action: (scores[action], -ACTIONS.index(action)))
        return PersonalizationPrediction(predicted, confidence, suggested, samples)

    def update_difficulty(self, state: dict | None, features: list[float], rpe: float) -> dict:
        state = self._copy_state(state)
        x = self._vector(features)
        block = state["difficulty"]
        A = np.asarray(block["A"], dtype=float) + np.outer(x, x)
        b = np.asarray(block["b"], dtype=float) + np.clip(rpe, 1.0, 10.0) * x
        block["A"] = A.tolist()
        block["b"] = b.tolist()
        block["samples"] = int(block.get("samples", 0)) + 1
        return state

    def update_reward(self, state: dict | None, features: list[float], action: str, reward: float) -> dict:
        if action not in ACTIONS:
            raise ValueError(f"unsupported action: {action}")
        state = self._copy_state(state)
        x = self._vector(features)
        arm = state["bandit"]["actions"][action]
        A = np.asarray(arm["A"], dtype=float) + np.outer(x, x)
        b = np.asarray(arm["b"], dtype=float) + np.clip(reward, -1.0, 1.0) * x
        arm["A"] = A.tolist()
        arm["b"] = b.tolist()
        arm["samples"] = int(arm.get("samples", 0)) + 1
        state["bandit"]["samples"] = int(state["bandit"].get("samples", 0)) + 1
        return state

    def _copy_state(self, state: dict | None) -> dict:
        source = state or self.initial_state()
        return {
            "version": source.get("version", "personalization-v1"),
            "difficulty": {
                "A": [row[:] for row in source["difficulty"]["A"]],
                "b": source["difficulty"]["b"][:],
                "samples": int(source["difficulty"].get("samples", 0)),
            },
            "bandit": {
                "samples": int(source["bandit"].get("samples", 0)),
                "actions": {
                    action: {
                        "A": [row[:] for row in source["bandit"]["actions"][action]["A"]],
                        "b": source["bandit"]["actions"][action]["b"][:],
                        "samples": int(source["bandit"]["actions"][action].get("samples", 0)),
                    }
                    for action in ACTIONS
                },
            },
        }

    def _theta(self, block: dict) -> np.ndarray:
        A = np.asarray(block["A"], dtype=float)
        b = np.asarray(block["b"], dtype=float)
        return np.linalg.solve(A, b)

    def _vector(self, features: list[float]) -> np.ndarray:
        if len(features) != FEATURE_DIMENSION:
            raise ValueError(f"expected {FEATURE_DIMENSION} features, got {len(features)}")
        x = np.asarray(features, dtype=float)
        x[~np.isfinite(x)] = 0
        return np.clip(x, -3.0, 3.0)


def feature_vector_from_context(context: dict) -> list[float]:
    """Stable normalized features. Index 0 is an intercept."""
    return [
        1.0,
        min(float(context.get("active_minutes", 0)) / 90.0, 2.0),
        min(float(context.get("set_count", 0)) / 30.0, 2.0),
        min(float(context.get("work_rest_ratio", 0)) / 2.0, 2.0),
        min(float(context.get("tracking_coverage", 0)), 1.0),
        min(float(context.get("seven_day_active_minutes", 0)) / 300.0, 2.0),
        min(float(context.get("hours_since_previous_session", 72)) / 72.0, 2.0),
        min(float(context.get("recent_food_kcal_midpoint", 0)) / 1200.0, 2.0),
    ]
