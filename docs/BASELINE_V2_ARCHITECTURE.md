# Baseline v2 architecture

## Product boundary

Baseline is a training evidence and coaching application, not a medical device. It may summarize motion, session timing, explicit RPE, and approximate food observations. It must not diagnose injury, disease, recovery disorders, or nutritional deficiency.

## One-screen product model

The iOS application has one root surface:

1. live camera and tracking quality;
2. workout start/stop and a twelve-second robust intensity trace;
3. the latest food observation with a calorie range and correction action;
4. one current coaching focus.

Coach, settings/privacy, and the post-session RPE form are sheets, not permanent tabs. The root screen remains useful when the backend is offline: camera tracking and local immutable session evidence continue to work.

## Responsibility split

### iOS, latency-sensitive and privacy-sensitive

- camera capture;
- all-person body-pose extraction;
- temporal primary-subject lock;
- per-identity smoothing;
- robust motion metrics and activity windows;
- local immutable evidence persistence;
- cheap food-positive gate and downscaled JPEG creation;
- compact UI and explicit corrections.

The client never stores raw video. It sends a still image only after two positive food-gate frames and never contains OpenAI or USDA API keys.

### Backend, heavy and canonical

- PostgreSQL persistence and migrations;
- canonical evidence aggregation;
- food image parsing and USDA nutrient lookup;
- context compilation for the Coach;
- structured Responses API calls;
- grounding verification and one repair retry;
- per-user online difficulty calibration;
- contextual-bandit recommendation ranking;
- chat and feedback persistence.

## Multi-person collision policy

`VNDetectHumanBodyPoseRequest` returns all candidates. The app never uses array order as identity.

`PrimarySubjectTracker` acquires one candidate over several frames using center, visible area, and confidence. After acquisition it ranks every candidate by temporal continuity: bounding-box IoU, normalized center displacement, normalized pose distance, and confidence.

Rules:

- close scores are ambiguous and invalidate metrics;
- a candidate outside the hard continuity gate cannot become the active subject;
- a lost identity is held instead of silently switching to a distant person;
- the UI exposes an explicit “lock me again” action;
- smoothing and intensity state reset whenever the track identifier changes;
- ambiguous, lost, acquiring, and warm-up frames are stored as tracking gaps, not movement.

This design prefers missing data over false data.

## Motion and activity quality

Motion is normalized by elapsed time and body scale. Whole-body translation is subtracted from joint displacement, so walking into position or camera-plane drift does not become internal articulation. The estimator uses:

- median joint speed;
- moving-joint fraction;
- a low-weight bounding-box-motion term;
- median/MAD outlier clipping;
- a One Euro filter;
- a hard intensity ceiling of 0.92;
- six valid warm-up frames after lock/gap;
- a twelve-second UI history rather than an unbounded sample count.

Camera-v2 segmentation requires sustained entry/exit evidence. Bounding-box motion cannot start an activity segment by itself. A short burst is converted to rest, and tracking collisions become explicit gaps.

The resulting “intensity” is a normalized motion signal, not physiological intensity, calories burned, exercise identity, repetition count, or training load. Coach instructions must preserve that distinction.

## Food observations

The client evaluates the image classifier no more often than every 1.5 seconds, requires two consecutive positive frames, and applies a twenty-second upload cooldown. The uploaded image is downscaled to at most 768 pixels on the longest edge.

The backend:

1. computes a perceptual difference hash and suppresses near-duplicates for 120 seconds;
2. requests structured food labels and gram ranges from a multimodal model;
3. looks up kcal per 100 g in USDA FoodData Central;
4. emits a calorie range widened by label and portion uncertainty;
5. stores labels, ranges, nutrient provenance, confidence, and image hash, but never image bytes;
6. accepts a “not food” correction and suppresses the same perceptual duplicate during the dedupe window.

A single RGB image cannot justify exact portion mass. The UI must always show a range and confidence-aware language.

## Personalization

Personalization never mutates evidence and never fine-tunes the Coach model on-device.

### Explicit RPE calibration

A per-user online ridge model predicts perceived session difficulty from eight normalized features. It updates only when the user explicitly submits RPE. The server recomputes features as of the linked session, so a later workout and a forged client feature vector cannot contaminate the label.

### Advice ranking

A disjoint LinUCB model ranks five coaching categories: technique, load, recovery, nutrition, and consistency. When Coach emits a category, the server stores a one-time recommendation exposure containing the exact feature vector and context digest. Useful/not-useful feedback consumes that exposure once. The client cannot substitute another category or a newer context.

Predictions remain hidden until at least three explicit RPE samples. Confidence is capped by sample count and is included in the Coach context.

## Coach context and grounding

For every request the backend compiles:

- latest session payload and tracking coverage;
- recent sessions from the last thirty days;
- explicit user-reported RPE and notes;
- food observations from the last seven days;
- the current personalization suggestion and calibrated difficulty state;
- the last messages in the selected thread.

Context is marked as data, not instructions. Allowed references use `[ev:<uuid>]`, `[food:<uuid>]`, and `[model:personalization-v1]`.

The response schema contains Markdown and one recommendation category. Every line containing an exact number must contain an allowed reference on the same line. Unknown references or unreferenced numbers trigger one repair request. A second failure returns an error rather than an ungrounded answer.

## Database tables

- `evidence_records`
- `food_observations`
- `chat_threads_v2`
- `chat_messages_v2`
- `feedback_events`
- `personalization_states`
- `recommendation_exposures`

Schema changes are applied through Alembic. `AUTO_CREATE_SCHEMA=true` exists only for tests and local development.

## API

- `GET /healthz`
- `GET /v1/home`
- `POST /v1/evidence`
- `POST /v1/food/analyze`
- `POST /v1/food/{id}/dismiss`
- `POST /v1/chat`
- `POST /v1/feedback`

## Authentication boundary

The included bearer token plus installation identifier is a development adapter, not production identity. Before external distribution, replace it with a real user identity flow and short-lived signed access tokens. Do not ship a shared production token in the app bundle.

## Verification commands

