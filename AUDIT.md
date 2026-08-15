# Audit of `averagedigital/baseline`

Date: 2026-08-15

## Executive conclusion

The repository has a strong evidence-first domain foundation, local GRDB persistence, and separable Swift modules. The current product path, however, is still a local prototype: person selection, motion quality, chat context, provider keys, and all analytical work sit in the iOS process. The requested product cannot be reached by a visual redesign alone.

The reference implementation changes the boundary rather than adding isolated patches:

- deterministic realtime safety remains on-device;
- canonical aggregation, food vision, LLM context, grounding, and personalization move to a backend;
- the app becomes one compact root screen plus short sheets;
- evidence remains immutable and usable offline.

## Findings

### Critical — person identity is not tracked

The original camera pipeline takes `observations.first`, then applies one shared smoother. When Vision changes result ordering, the application can silently treat another person as the same athlete. The later `multiplePeople` state does not undo the contaminated frame.

Resolution: evaluate every pose, acquire one subject over multiple frames, maintain an explicit track identifier, reject ambiguous crossings, refuse distant automatic switches, and reset all temporal state on identity changes.

### Critical — chat bypasses the evidence agents

The original chat sends conversation history directly to Responses API. Existing context/compiler/grounding types are not on the production request path, and session-memory generation sees envelope metadata rather than the full payload.

Resolution: backend context compilation from payloads, narratives, food, historical sessions, personalization state, and thread history; structured output; reference verification; one repair retry.

### High — intensity is frame-rate and identity sensitive

The original scalar is average normalized-coordinate displacement multiplied by eight. It is not divided by elapsed time or body scale, does not remove whole-body translation, shares state across identity jumps, and is passed directly to activity segmentation.

Resolution: time/body normalization, translation removal, median joint speed, moving fraction, robust MAD clipping, One Euro filtering, 0.92 ceiling, warm-up, twelve-second window, and explicit gaps for invalid frames.

### High — the application is not light-client/heavy-backend

There is no server package. Local code owns camera, LLM provider configuration, API keys, chat, evidence, and analysis.

Resolution: FastAPI/PostgreSQL/Alembic backend; iOS keeps only latency-sensitive and offline-safe functions. OpenAI and USDA credentials exist only on the server.

### High — calorie precision would be misleading

A single RGB frame can support approximate food labels, but portion mass and calorie totals remain uncertain. A single number would overstate the evidence.

Resolution: two-frame local gate, server multimodal parsing, USDA nutrient density, gram and calorie ranges, confidence, perceptual dedupe, no image persistence, explicit correction.

### Medium — personalization lacks a trustworthy label path

“Learning from usage” is underspecified. Implicit engagement would mix preference, novelty, and actual usefulness, while per-user LLM fine-tuning would start with too little data.

Resolution: online ridge calibration from explicit RPE and disjoint LinUCB ranking from explicit useful/not-useful feedback. RPE features are reconstructed as of the linked session. Advice feedback consumes a one-time server exposure, so it cannot be relabeled against a later context.

### Medium — visual hierarchy signals a prototype

The dark forced scheme, glows, glass, gradients, monospaced all-caps labels, and separate camera/chat tabs make the app look like a generic AI demo and fragment the product model.

Resolution: white neutral palette, one root screen, ordinary typography, no decorative “AI” motifs, restrained 180–240 ms transitions, and Reduce Motion support.

## Deliberate non-goals

- no medical diagnosis;
- no claim that camera motion equals physiological intensity;
- no exact calories from one image;
- no exercise identity or repetition count without a separately validated model;
- no autonomous LLM fine-tuning;
- no production claim for the included development authentication adapter.

## Residual risks requiring real-device validation

- gym lighting, occlusion, mirrored preview, and camera placement;
- threshold calibration across body sizes and exercise families;
- food false-positive rate of the built-in image classifier;
- multimodal portion-estimation bias;
- LLM grounding false rejects and repair latency;
- iOS thermal load when pose and food gates run for long sessions.

The implementation therefore includes deterministic unit tests, but release acceptance still requires recorded multi-person gym scenarios and an iOS device test matrix.
