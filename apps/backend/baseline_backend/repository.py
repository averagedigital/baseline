from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
from uuid import UUID, uuid4

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from .models import (
    ChatMessageRecord,
    ChatThreadRecord,
    EvidenceRecord,
    FeedbackRecord,
    FoodObservationRecord,
    PersonalizationRecord,
    RecommendationExposureRecord,
)
from .schemas import EvidenceUpload


def store_evidence(db: Session, user_id: str, value: EvidenceUpload) -> bool:
    if db.get(EvidenceRecord, str(value.id)) is not None:
        return False
    db.add(
        EvidenceRecord(
            id=str(value.id),
            user_id=user_id,
            kind=value.kind,
            module_id=value.module_id,
            observed_from=value.observed_from,
            observed_to=value.observed_to,
            epistemic_role=value.epistemic_role,
            content_digest=value.content_digest,
            payload=value.payload,
        )
    )
    db.commit()
    return True


def evidence_since(
    db: Session,
    user_id: str,
    since: datetime,
    *,
    until: datetime | None = None,
) -> list[EvidenceRecord]:
    statement = select(EvidenceRecord).where(
        EvidenceRecord.user_id == user_id,
        EvidenceRecord.observed_to >= since,
    )
    if until is not None:
        statement = statement.where(EvidenceRecord.observed_to <= until)
    return list(db.scalars(statement.order_by(EvidenceRecord.observed_to)))


def latest_evidence(db: Session, user_id: str, kind: str) -> EvidenceRecord | None:
    return db.scalar(
        select(EvidenceRecord)
        .where(EvidenceRecord.user_id == user_id, EvidenceRecord.kind == kind)
        .order_by(desc(EvidenceRecord.observed_to))
        .limit(1)
    )


def recent_food(
    db: Session,
    user_id: str,
    *,
    days: int = 7,
    now: datetime | None = None,
) -> list[FoodObservationRecord]:
    now = now or datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    return list(
        db.scalars(
            select(FoodObservationRecord)
            .where(
                FoodObservationRecord.user_id == user_id,
                FoodObservationRecord.captured_at >= since,
                FoodObservationRecord.captured_at <= now,
                FoodObservationRecord.dismissed.is_(False),
            )
            .order_by(FoodObservationRecord.captured_at)
        )
    )


def recent_food_for_dedupe(
    db: Session, user_id: str, captured_at: datetime, seconds: int
) -> list[FoodObservationRecord]:
    since = captured_at - timedelta(seconds=seconds)
    return list(
        db.scalars(
            select(FoodObservationRecord)
            .where(
                FoodObservationRecord.user_id == user_id,
                FoodObservationRecord.captured_at >= since,
                FoodObservationRecord.captured_at <= captured_at,
            )
            .order_by(desc(FoodObservationRecord.captured_at))
        )
    )


def get_or_create_thread(db: Session, user_id: str, thread_id: str | None, title: str) -> ChatThreadRecord:
    if thread_id:
        thread = db.get(ChatThreadRecord, thread_id)
        if thread is None or thread.user_id != user_id:
            raise LookupError("thread not found")
        return thread
    thread = ChatThreadRecord(id=str(uuid4()), user_id=user_id, title=title[:160])
    db.add(thread)
    db.commit()
    db.refresh(thread)
    return thread


def append_message(db: Session, user_id: str, thread: ChatThreadRecord, role: str, text: str) -> None:
    now = datetime.now(timezone.utc)
    db.add(
        ChatMessageRecord(
            id=str(uuid4()),
            thread_id=thread.id,
            user_id=user_id,
            role=role,
            text=text,
            created_at=now,
        )
    )
    thread.updated_at = now
    db.commit()


def thread_messages(db: Session, user_id: str, thread_id: str, limit: int = 20) -> list[ChatMessageRecord]:
    rows = list(
        db.scalars(
            select(ChatMessageRecord)
            .where(ChatMessageRecord.user_id == user_id, ChatMessageRecord.thread_id == thread_id)
            .order_by(desc(ChatMessageRecord.created_at))
            .limit(limit)
        )
    )
    return list(reversed(rows))



def create_recommendation_exposure(
    db: Session,
    user_id: str,
    *,
    thread_id: str,
    action: str,
    context_digest: str,
    feature_vector: list[float],
) -> RecommendationExposureRecord:
    row = RecommendationExposureRecord(
        id=str(uuid4()),
        user_id=user_id,
        thread_id=thread_id,
        action=action,
        context_digest=context_digest,
        feature_vector=feature_vector,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def consume_recommendation_exposure(
    db: Session,
    user_id: str,
    exposure_id: UUID,
    reward: float,
) -> RecommendationExposureRecord:
    row = db.get(RecommendationExposureRecord, str(exposure_id))
    if row is None or row.user_id != user_id:
        raise LookupError("recommendation feedback context not found")
    if row.rewarded:
        raise ValueError("recommendation feedback was already submitted")
    row.rewarded = True
    row.reward = reward
    row.rewarded_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return row

def load_personalization(db: Session, user_id: str) -> PersonalizationRecord | None:
    return db.get(PersonalizationRecord, user_id)


def save_personalization(db: Session, user_id: str, state: dict) -> PersonalizationRecord:
    row = db.get(PersonalizationRecord, user_id)
    if row is None:
        row = PersonalizationRecord(user_id=user_id, state=state)
        db.add(row)
    else:
        row.state = state
    db.commit()
    db.refresh(row)
    return row


def append_feedback(
    db: Session,
    user_id: str,
    *,
    event_type: str,
    action: str | None,
    reward: float | None,
    target_value: float | None,
    context: dict,
) -> None:
    db.add(
        FeedbackRecord(
            id=str(uuid4()),
            user_id=user_id,
            event_type=event_type,
            action=action,
            reward=reward,
            target_value=target_value,
            context=context,
        )
    )
    db.commit()


def store_user_report(
    db: Session,
    user_id: str,
    *,
    source_evidence_id: UUID,
    rpe: float,
    note: str | None,
) -> EvidenceRecord:
    source = db.get(EvidenceRecord, str(source_evidence_id))
    if source is None or source.user_id != user_id or source.kind != "activity.session.v1":
        raise LookupError("source session evidence not found")
    now = datetime.now(timezone.utc)
    clean_note = (note or "").strip()
    text = f"RPE {round(rpe, 1):g}" + (f". {clean_note}" if clean_note else "")
    payload = {
        "text": text,
        "sessionEvidenceID": str(source_evidence_id),
        "claims": [{"kind": "rpe", "value": f"{round(rpe, 1):g}"}],
        "note": clean_note,
    }
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    row = EvidenceRecord(
        id=str(uuid4()),
        user_id=user_id,
        kind="user.narrative.v1",
        module_id="org.baseline.user-narrative",
        observed_from=now,
        observed_to=now,
        epistemic_role="userReported",
        content_digest="sha256:" + hashlib.sha256(encoded).hexdigest(),
        payload=payload,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def dismiss_food(db: Session, user_id: str, observation_id: UUID) -> bool:
    row = db.get(FoodObservationRecord, str(observation_id))
    if row is None or row.user_id != user_id:
        return False
    row.dismissed = True
    db.commit()
    return True
