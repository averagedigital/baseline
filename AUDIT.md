# Baseline on-device audit

Baseline is local-first. Camera, pose, tracking, motion, evidence, nutrition matching, personalization and history run on the device. The UI has no remote service boundary.

## Guarantees

- subject identity is selected from all pose candidates, never result order;
- ambiguity and identity gaps are excluded from metrics;
- appearance signatures are optional data passed to the pure tracker;
- motion is time/body-scale normalized, translation-invariant and capped;
- GRDB remains the canonical evidence store;
- RPE and recommendation reward are explicit local feedback;
- Coach output is structured and locally grounded;
- Foundation Models is optional; its absence does not disable training or history;
- raw video and food frames are not persisted.

## Optional assets

The CoreML food detector and Apple Foundation Models runtime may be unavailable on a build or device. The app reports unavailable status and retains all other local functionality; it does not silently use remote or fake provider data.
