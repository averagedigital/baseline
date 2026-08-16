# Optional local assets

- `FoodDetector.mlmodel` or `FoodDetector.mlpackage` — optional Core ML detector source. Xcode compiles it to the `FoodDetector` bundle resource.
- `nutrition.sqlite` — optional offline generated nutrition database.

The app remains usable without either asset: the detector reports `modelMissing`, and nutrition matching reports the local database as unavailable.
