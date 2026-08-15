# Baseline on-device architecture

```text
SwiftUI
  -> AthleteSensors / AthleteNutrition / AthleteIntelligence
  -> AthletePersonalization
  -> AthleteStore (GRDB)
```

The app has zero required server or runtime network dependency. SwiftUI only renders state, handles sheets and forwards user actions. Domain algorithms live in Swift packages.

`AthleteSensors` owns pose geometry, primary-subject tracking, optional appearance continuity, smoothing, robust intensity and activity segmentation. Ambiguous, lost, acquiring and warm-up frames are gaps, never motion metrics. A track change resets temporal state.

`AthleteNutrition` owns detector contracts, stable multi-object tracks, normalized boxes and local canonical-name matching. Detector assets are optional. Portion uncertainty produces a calorie range; missing portion data produces no fabricated calories. Raw image bytes are transient input only.

`AthletePersonalization` updates only from explicit RPE and one-use useful/not-useful rewards. Predictions are unavailable before the cold-start threshold. Evidence is immutable.

`AthleteIntelligence` compiles local facts, validates structured Coach claims and rejects unknown or numerically ungrounded claims. Foundation Models is an optional adapter. If unavailable, the app shows a calm local-unavailable state.

`AthleteStore` is the only database. Existing GRDB migrations and user data remain forward-safe; new local state is added through migrations, never by deleting legacy tables.

## Privacy and performance

No API credentials, server URLs, REST uploads, raw video or raw food frames exist in the app. Capture, pose, food and UI work are separated; late detector frames are dropped. Body tracking has priority over food overlays.
