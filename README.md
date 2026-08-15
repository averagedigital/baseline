# Baseline

Baseline is an evidence-first iOS training companion with a lightweight realtime client and a heavier analytical backend.

## Repository layout

- `apps/ios/Baseline` — camera, multi-person-safe subject lock, robust motion metrics, local evidence, compact white UI, food gate.
- `apps/backend` — FastAPI, PostgreSQL, Alembic, food/nutrition analysis, Coach context, grounding, personalization.
- `packages/swift` — shared domain, sensors, and local GRDB storage.
- `docs/BASELINE_V2_ARCHITECTURE.md` — data flow, quality rules, privacy, API, and verification.

## Core invariants

- Never choose a person by Vision result order.
- Never write ambiguous tracking frames into movement metrics.
- Never store raw video or food image bytes.
- Never expose provider API keys in the iOS bundle.
- Never present a single-image food estimate as exact calories.
- Never train personalization without explicit RPE or useful/not-useful feedback.
- Never give Coach exact user-specific numbers without evidence references.

## Verification
