from baseline_backend.grounding import verify_grounding


def test_grounding_rejects_unknown_reference_and_unreferenced_number() -> None:
    result = verify_grounding(
        "Сделано 8 подходов.\nНагрузка выросла [ev:unknown]",
        evidence_ids={"known"},
        food_ids=set(),
        model_ids={"personalization-v1"},
    )
    assert not result.valid
    assert len(result.issues) == 2


def test_grounding_accepts_allowed_references() -> None:
    result = verify_grounding(
        "Сделано 8 подходов [ev:known]\nОценка 7.2 [model:personalization-v1]",
        evidence_ids={"known"},
        food_ids=set(),
        model_ids={"personalization-v1"},
    )
    assert result.valid
