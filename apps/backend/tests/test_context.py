from datetime import datetime, timedelta, timezone
from uuid import uuid4

from baseline_backend.context import ContextBuilder
from baseline_backend.models import EvidenceRecord, FoodObservationRecord


def test_context_contains_payload_values_and_grounding_ids(db) -> None:
    now = datetime.now(timezone.utc)
    evidence_id = str(uuid4())
    food_id = str(uuid4())
    db.add(
        EvidenceRecord(
            id=evidence_id,
            user_id="user-1",
            kind="activity.session.v1",
            module_id="org.baseline.activity",
            observed_from=now - timedelta(hours=1),
            observed_to=now,
            epistemic_role="computed",
            content_digest="sha256:test",
            payload={
                "trackingCoverage": 0.92,
                "activeTime": 1800,
                "restTime": 1200,
                "setCount": 8,
            },
        )
    )
    db.add(
        FoodObservationRecord(
            id=food_id,
            user_id="user-1",
            captured_at=now - timedelta(hours=2),
            image_hash="0" * 16,
            confidence=0.8,
            calories_low=420,
            calories_high=610,
            items=[{"name": "rice"}],
        )
    )
    db.commit()

    context = ContextBuilder().build(db, "user-1", now=now)

    assert "Active time: 30.0 min" in context.markdown
    assert "Detected sets: 8" in context.markdown
    assert f"[ev:{evidence_id}]" in context.markdown
    assert f"[food:{food_id}]" in context.markdown
    assert evidence_id in context.evidence_ids
    assert food_id in context.food_ids
