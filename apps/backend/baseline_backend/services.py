from __future__ import annotations

from uuid import UUID

from sqlalchemy.orm import Session

from .context import ContextBuilder
from .grounding import REFERENCE, verify_grounding
from .openai_client import OpenAIResponsesClient
from .personalization import OnlinePersonalizer
from .repository import (
    append_feedback,
    append_message,
    consume_recommendation_exposure,
    create_recommendation_exposure,
    get_or_create_thread,
    latest_evidence,
    load_personalization,
    recent_food,
    save_personalization,
    store_user_report,
    thread_messages,
)
from .schemas import ChatRequest, ChatResponse, FeedbackRequest, FeedbackResponse, HomeResponse


class CoachService:
    def __init__(self, client: OpenAIResponsesClient, context_builder: ContextBuilder | None = None) -> None:
        self.client = client
        self.context_builder = context_builder or ContextBuilder()

    def answer(self, db: Session, user_id: str, request: ChatRequest) -> ChatResponse:
        thread = get_or_create_thread(db, user_id, str(request.thread_id) if request.thread_id else None, request.message)
        history_rows = thread_messages(db, user_id, thread.id, limit=20)
        history = [{"role": row.role, "content": row.text} for row in history_rows]
        compiled = self.context_builder.build(db, user_id)
        append_message(db, user_id, thread, "user", request.message)

        result = self.client.coach(
            compiled_context=compiled.markdown,
            history=history,
            user_message=request.message,
        )
        grounding = verify_grounding(
            result.answer_markdown,
            evidence_ids=compiled.evidence_ids,
            food_ids=compiled.food_ids,
            model_ids=compiled.model_ids,
        )
        if not grounding.valid:
            result = self.client.coach(
                compiled_context=compiled.markdown,
                history=history,
                user_message=request.message,
                correction="\n".join(grounding.issues),
            )
            grounding = verify_grounding(
                result.answer_markdown,
                evidence_ids=compiled.evidence_ids,
                food_ids=compiled.food_ids,
                model_ids=compiled.model_ids,
            )
        if not grounding.valid:
            raise RuntimeError("coach output failed grounding validation: " + "; ".join(grounding.issues))

        append_message(db, user_id, thread, "assistant", result.answer_markdown)
        feedback_context_id = None
        if result.recommendation_category != "none":
            exposure = create_recommendation_exposure(
                db,
                user_id,
                thread_id=thread.id,
                action=result.recommendation_category,
                context_digest=compiled.digest,
                feature_vector=compiled.personalization_features,
            )
            feedback_context_id = UUID(exposure.id)
        references = REFERENCE.findall(result.answer_markdown)
        evidence_ids = [UUID(value) for kind, value in references if kind == "ev"]
        food_ids = [UUID(value) for kind, value in references if kind == "food"]
        return ChatResponse(
            thread_id=UUID(thread.id),
            answer_markdown=result.answer_markdown,
            recommendation_category=result.recommendation_category,
            evidence_ids=list(dict.fromkeys(evidence_ids)),
            food_ids=list(dict.fromkeys(food_ids)),
            context_digest=compiled.digest,
            feedback_context_id=feedback_context_id,
        )


class PersonalizationService:
    def __init__(
        self,
        personalizer: OnlinePersonalizer | None = None,
        context_builder: ContextBuilder | None = None,
    ) -> None:
        self.personalizer = personalizer or OnlinePersonalizer()
        self.context_builder = context_builder or ContextBuilder(self.personalizer)

    def feedback(self, db: Session, user_id: str, request: FeedbackRequest) -> FeedbackResponse:
        # Model features always come from canonical server state. The client payload is
        # retained only as audit metadata and is never trusted as a training vector.
        row = load_personalization(db, user_id)
        state = row.state if row else None
        action = request.action
        context_digest: str | None = None
        source_id = str(request.source_evidence_id) if request.source_evidence_id else None
        feedback_context_id = str(request.feedback_context_id) if request.feedback_context_id else None

        if request.event_type == "session_rpe":
            if request.target_value is None or request.source_evidence_id is None:
                raise ValueError("session_rpe requires target_value and source_evidence_id")
            features = self.context_builder.features_for_session(
                db, user_id, str(request.source_evidence_id)
            )
            store_user_report(
                db,
                user_id,
                source_evidence_id=request.source_evidence_id,
                rpe=request.target_value,
                note=request.note,
            )
            state = self.personalizer.update_difficulty(state, features, request.target_value)
        elif request.event_type == "recommendation_reward":
            if request.feedback_context_id is None or request.reward is None:
                raise ValueError("recommendation_reward requires feedback_context_id and reward")
            exposure = consume_recommendation_exposure(
                db, user_id, request.feedback_context_id, request.reward
            )
            features = [float(value) for value in exposure.feature_vector]
            action = exposure.action
            context_digest = exposure.context_digest
            state = self.personalizer.update_reward(state, features, action, request.reward)
        else:
            features = self.context_builder.build(db, user_id).personalization_features
            state = state or self.personalizer.initial_state()

        saved = save_personalization(db, user_id, state)
        append_feedback(
            db,
            user_id,
            event_type=request.event_type,
            action=action,
            reward=request.reward,
            target_value=request.target_value,
            context={
                "client_metadata": request.context,
                "context_digest": context_digest,
                "feature_vector": features,
                "source_evidence_id": source_id,
                "feedback_context_id": feedback_context_id,
                "note": request.note or "",
            },
        )
        samples = int(saved.state["difficulty"].get("samples", 0)) + int(saved.state["bandit"].get("samples", 0))
        return FeedbackResponse(stored=True, personalization_samples=samples)


class HomeService:
    def __init__(self, context_builder: ContextBuilder | None = None) -> None:
        self.context_builder = context_builder or ContextBuilder()

    def home(self, db: Session, user_id: str) -> HomeResponse:
        compiled = self.context_builder.build(db, user_id)
        session = latest_evidence(db, user_id, "activity.session.v1")
        food = recent_food(db, user_id, days=7)
        latest_food = food[-1] if food else None
        return HomeResponse(
            latest_session={"id": session.id, "observed_to": session.observed_to, **session.payload} if session else None,
            latest_food={
                "id": latest_food.id,
                "captured_at": latest_food.captured_at,
                "calories_low": latest_food.calories_low,
                "calories_high": latest_food.calories_high,
                "items": latest_food.items,
            } if latest_food else None,
            suggested_action=compiled.suggested_action,
            predicted_difficulty=compiled.predicted_difficulty,
            prediction_confidence=compiled.prediction_confidence,
        )
