# Baseline

Baseline — fully on-device evidence-first training companion.

## Stack

- SwiftUI and AVFoundation;
- Vision for local body pose;
- CoreML/Vision adapters for optional local food detection;
- Foundation Models when available;
- GRDB/SQLite as the canonical local store;
- local online personalization from explicit RPE and feedback.

The app does not require a server, login, internet connection, API keys or cloud sync. Raw video and food image bytes are never persisted.

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
