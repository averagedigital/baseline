"""Create Baseline v2 backend schema.

Revision ID: 20260815_0001
Revises: None
Create Date: 2026-08-15
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "20260815_0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "evidence_records",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("kind", sa.String(length=96), nullable=False),
        sa.Column("module_id", sa.String(length=128), nullable=False),
        sa.Column("observed_from", sa.DateTime(timezone=True), nullable=False),
        sa.Column("observed_to", sa.DateTime(timezone=True), nullable=False),
        sa.Column("epistemic_role", sa.String(length=32), nullable=False),
        sa.Column("content_digest", sa.String(length=96), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_evidence_records_user_id", "evidence_records", ["user_id"])
    op.create_index("ix_evidence_records_kind", "evidence_records", ["kind"])
    op.create_index("ix_evidence_records_observed_from", "evidence_records", ["observed_from"])
    op.create_index("ix_evidence_records_observed_to", "evidence_records", ["observed_to"])

    op.create_table(
        "food_observations",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("image_hash", sa.String(length=16), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("calories_low", sa.Float(), nullable=False),
        sa.Column("calories_high", sa.Float(), nullable=False),
        sa.Column("items", sa.JSON(), nullable=False),
        sa.Column("dismissed", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_food_observations_user_id", "food_observations", ["user_id"])
    op.create_index("ix_food_observations_captured_at", "food_observations", ["captured_at"])
    op.create_index("ix_food_observations_image_hash", "food_observations", ["image_hash"])

    op.create_table(
        "chat_threads_v2",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("title", sa.String(length=160), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_chat_threads_v2_user_id", "chat_threads_v2", ["user_id"])
    op.create_index("ix_chat_threads_v2_updated_at", "chat_threads_v2", ["updated_at"])

    op.create_table(
        "chat_messages_v2",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("thread_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_chat_messages_v2_thread_id", "chat_messages_v2", ["thread_id"])
    op.create_index("ix_chat_messages_v2_user_id", "chat_messages_v2", ["user_id"])
    op.create_index("ix_chat_messages_v2_created_at", "chat_messages_v2", ["created_at"])

    op.create_table(
        "feedback_events",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("event_type", sa.String(length=48), nullable=False),
        sa.Column("action", sa.String(length=48), nullable=True),
        sa.Column("reward", sa.Float(), nullable=True),
        sa.Column("target_value", sa.Float(), nullable=True),
        sa.Column("context", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_feedback_events_user_id", "feedback_events", ["user_id"])
    op.create_index("ix_feedback_events_event_type", "feedback_events", ["event_type"])
    op.create_index("ix_feedback_events_created_at", "feedback_events", ["created_at"])

    op.create_table(
        "personalization_states",
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("state", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("user_id"),
    )

    op.create_table(
        "recommendation_exposures",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.String(length=64), nullable=False),
        sa.Column("thread_id", sa.String(length=36), nullable=False),
        sa.Column("action", sa.String(length=48), nullable=False),
        sa.Column("context_digest", sa.String(length=96), nullable=False),
        sa.Column("feature_vector", sa.JSON(), nullable=False),
        sa.Column("rewarded", sa.Boolean(), nullable=False),
        sa.Column("reward", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("rewarded_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_recommendation_exposures_user_id", "recommendation_exposures", ["user_id"])
    op.create_index("ix_recommendation_exposures_thread_id", "recommendation_exposures", ["thread_id"])
    op.create_index("ix_recommendation_exposures_action", "recommendation_exposures", ["action"])
    op.create_index("ix_recommendation_exposures_rewarded", "recommendation_exposures", ["rewarded"])
    op.create_index("ix_recommendation_exposures_created_at", "recommendation_exposures", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_recommendation_exposures_created_at", table_name="recommendation_exposures")
    op.drop_index("ix_recommendation_exposures_rewarded", table_name="recommendation_exposures")
    op.drop_index("ix_recommendation_exposures_action", table_name="recommendation_exposures")
    op.drop_index("ix_recommendation_exposures_thread_id", table_name="recommendation_exposures")
    op.drop_index("ix_recommendation_exposures_user_id", table_name="recommendation_exposures")
    op.drop_table("recommendation_exposures")
    op.drop_table("personalization_states")
    op.drop_index("ix_feedback_events_created_at", table_name="feedback_events")
    op.drop_index("ix_feedback_events_event_type", table_name="feedback_events")
    op.drop_index("ix_feedback_events_user_id", table_name="feedback_events")
    op.drop_table("feedback_events")
    op.drop_index("ix_chat_messages_v2_created_at", table_name="chat_messages_v2")
    op.drop_index("ix_chat_messages_v2_user_id", table_name="chat_messages_v2")
    op.drop_index("ix_chat_messages_v2_thread_id", table_name="chat_messages_v2")
    op.drop_table("chat_messages_v2")
    op.drop_index("ix_chat_threads_v2_updated_at", table_name="chat_threads_v2")
    op.drop_index("ix_chat_threads_v2_user_id", table_name="chat_threads_v2")
    op.drop_table("chat_threads_v2")
    op.drop_index("ix_food_observations_image_hash", table_name="food_observations")
    op.drop_index("ix_food_observations_captured_at", table_name="food_observations")
    op.drop_index("ix_food_observations_user_id", table_name="food_observations")
    op.drop_table("food_observations")
    op.drop_index("ix_evidence_records_observed_to", table_name="evidence_records")
    op.drop_index("ix_evidence_records_observed_from", table_name="evidence_records")
    op.drop_index("ix_evidence_records_kind", table_name="evidence_records")
    op.drop_index("ix_evidence_records_user_id", table_name="evidence_records")
    op.drop_table("evidence_records")
