# Model decisions

| Model / API | Purpose | Checkpoint / license | Size and interface | Core ML / device cost | Decision | Reason |
|---|---|---|---|---|---|---|
| Apple Vision `VNDetectHumanBodyPoseRequest` | Body pose | System model, Apple platform API | 2D body joints with confidence | Native Vision path already used; measured by current 15 FPS pipeline | use | Existing supported dependency and direct observable signal. |
| Open Model Zoo `person-reidentification-retail-0288` | Person ReID | Official OMZ checkpoint; Apache-2.0 | 0.183 M parameters, 0.174 GFLOPs; BGR `1x3x256x128` to 256-float embedding | OpenVINO IR must be converted and benchmarked as Core ML on target iPhones | postpone | Best compact candidate, but no validated Core ML artifact or device latency/quality benchmark exists in this repository. |
| OSNet x0.25 / Torchreid | Person ReID | Official Torchreid weights; MIT code/model repository | Larger general ReID alternative | PyTorch to Core ML conversion and target-device benchmark required | reject for current slice | No demonstrated benefit over the much smaller OMZ candidate for Baseline crossings. |
| ST-GCN and generic skeleton action checkpoints | Exercise embedding | Public research checkpoints vary by dataset and terms | Fixed action taxonomies, typically trained on NTU-style actions | Conversion possible in principle; gym-domain quality unverified | reject | No checkpoint with a verified permissive weight license and demonstrated real-gym exercise quality was found. |
| Current deterministic pose representation + personal prototypes | Exercise and movement personalization | No external weights | Normalized local feature vectors, centroids, variance and robust rolling history | Negligible CPU; local only | use | Learns user-defined exercises without pretending to know unseen classes or requiring centralized training. |

ReID backbone inference remains gated: geometry handles clear association; an encoder may run only for ambiguous candidates after a converted artifact passes license verification, crossing tests, latency and energy checks on supported iPhones. The implemented personal gallery accepts only high-quality non-ambiguous embeddings.

Sources checked 2026-08-16:

- Apple Vision body pose: https://developer.apple.com/documentation/vision/detecthumanbodyposerequest
- Open Model Zoo ReID specification: https://docs.openvino.ai/2023.3/omz_models_model_person_reidentification_retail_0288.html
- Open Model Zoo repository and Apache-2.0 license: https://github.com/openvinotoolkit/open_model_zoo
- Torchreid/OSNet repository and model zoo: https://github.com/KaiyangZhou/deep-person-reid
