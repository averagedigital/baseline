# Baseline

Baseline — fully on-device evidence-first training companion.

## Stack

- SwiftUI and AVFoundation;
- Vision for local body pose;
- CoreML/Vision adapters for optional local food detection;
- Foundation Models when available;
- GRDB/SQLite as the canonical local store;
- local online personalization from explicit RPE and feedback.

The local camera pipeline does not persist raw video frames. Images explicitly attached to Coach messages are stored in the app's local Application Support directory; cloud Coach is used only after the user configures a provider API key.

Optional runtime assets are documented in `apps/ios/Baseline/Resources/README.md`: food detection needs `FoodDetector`, nutrition matching needs generated `nutrition.sqlite`, and Foundation Models Coach needs a supported Apple Intelligence device and locale.

## Modules

- `AthleteSensors` — multi-person lock, appearance continuity, robust motion and activity segmentation;
- `AthleteNutrition` — food detections, tracking contracts and local nutrition matching;
- `AthletePersonalization` — explicit-feedback difficulty model and recommendation exposure;
- `AthleteIntelligence` — local Coach contracts and grounding validation;
- `AthleteStore` — GRDB evidence, history and migrations.

## Verification

```bash
cd packages/swift && swift test
cd ../../apps/ios/Baseline && xcodegen generate
```
