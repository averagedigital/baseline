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

Food detection requires the optional `apps/ios/Baseline/Resources/FoodDetector.mlmodel` or `.mlpackage` asset. Nutrition matching requires a locally generated `apps/ios/Baseline/Resources/nutrition.sqlite` asset. Apple Foundation Models Coach requires a supported Apple Intelligence device and supported locale. Any missing asset is reported explicitly; bbox labels remain available without nutrition matching, and no remote or fake provider data is used.
