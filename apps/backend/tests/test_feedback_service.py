from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest

from baseline_backend.models import EvidenceRecord, FeedbackRecord, PersonalizationRecord
from baseline_backend.repository import create_recommendation_exposure
from baseline_backend.schemas import FeedbackRequest
from baseline_backend.services import PersonalizationService


def add_session(db, *, evidence_id, user_id, observed_to, active_seconds, sets=7) -> None:
    db.add(
        EvidenceRecord(
            id=str(evidence_id),
            user_id=user_id,
            kind="activity.session.v1",
            module_id="org.baseline.activity",
            observed_from=observed_to - timedelta(hours=1),
            observed_to=observed_to,
            epistemic_role="computed",
            content_digest=f"sha256:{evidence_id}",
            payload={
                "trackingCoverage": 0.9,
                "activeTime": active_seconds,
                "restTime": 900,
                "setCount": sets,
            },
        )
    )


def test_session_rpe_uses_the_linked_session_not_newer_client_or_server_state(db) -> None:
    now = datetime.now(timezone.utc)
    source_id = uuid4()
    newer_id = uuid4()
    add_session(
        db,
        evidence_id=source_id,
        user_id="user-1",
        observed_to=now - timedelta(hours=4),
        active_seconds=600,
        sets=3,
    )
    add_session(
        db,
        evidence_id=newer_id,
        user_id="user-1",
        observed_to=now,
        active_seconds=5400,
        sets=20,
    )
    db.commit()

    response = PersonalizationService().feedback(
        db,
        "user-1",
        FeedbackRequest(
            event_type="session_rpe",
            target_value=8,
            source_evidence_id=source_id,
            note="Присед 100 кг на 5",
            context={"active_minutes": 999999},
        ),
    )

    assert response.stored is True
    state = db.get(PersonalizationRecord, "user-1")
    assert state is not None
    assert state.state["difficulty"]["samples"] == 1

    reports = [row for row in db.query(EvidenceRecord).all() if row.kind == "user.narrative.v1"]
    assert len(reports) == 1
    assert reports[0].payload["claims"] == [{"kind": "rpe", "value": "8"}]
    assert reports[0].payload["sessionEvidenceID"] == str(source_id)

    feedback = db.query(FeedbackRecord).one()
    assert feedback.context["client_metadata"]["active_minutes"] == 999999
    # The trained feature is the linked session's canonical 10 active minutes, not
    # the newer session and not the client-provided value.
    assert feedback.context["feature_vector"][1] == pytest.approx(10 / 90)


def test_recommendation_reward_uses_single_use_server_exposure(db) -> None:
    features = [1.0, 0.2, 0.1, 0.2, 0.9, 0.3, 0.5, 0.0]
    exposure = create_recommendation_exposure(
        db,
        "user-1",
        thread_id=str(uuid4()),
        action="recovery",
        context_digest="sha256:context",
        feature_vector=features,
    )
    service = PersonalizationService()

    response = service.feedback(
        db,
        "user-1",
        FeedbackRequest(
            event_type="recommendation_reward",
            reward=1,
            feedback_context_id=UUID(exposure.id),
            action="load",  # Must be ignored; the exposure is authoritative.
            context={"active_minutes": 999999},
        ),
    )

    assert response.stored is True
    state = db.get(PersonalizationRecord, "user-1")
    assert state is not None
    assert state.state["bandit"]["actions"]["recovery"]["samples"] == 1
    assert state.state["bandit"]["actions"]["load"]["samples"] == 0
    feedback = db.query(FeedbackRecord).one()
    assert feedback.action == "recovery"
    assert feedback.context["feature_vector"] == features

    with pytest.raises(ValueError, match="already submitted"):
        service.feedback(
            db,
            "user-1",
            FeedbackRequest(
                event_type="recommendation_reward",
                reward=1,
                feedback_context_id=UUID(exposure.id),
            ),
        )
