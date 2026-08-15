import AthleteNutrition
import CoreML
import Vision

struct FoodObjectDetector: @unchecked Sendable {
    enum Availability: Equatable, Sendable { case available, modelMissing, invalid }
    enum DetectorError: LocalizedError {
        case modelMissing
        case modelInvalid

        var errorDescription: String? {
            switch self {
            case .modelMissing: "Food detector model asset is missing."
            case .modelInvalid: "Food detector model could not be loaded."
            }
        }
    }

    private let model: VNCoreMLModel?
    let availability: Availability

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "FoodDetector", withExtension: "mlmodelc"),
              let coreMLModel = try? MLModel(contentsOf: url),
              let visionModel = try? VNCoreMLModel(for: coreMLModel) else {
            model = nil
            availability = bundle.url(forResource: "FoodDetector", withExtension: "mlmodelc") == nil ? .modelMissing : .invalid
            return
        }
        model = visionModel
        availability = .available
    }

    func detect(pixelBuffer: CVPixelBuffer) throws -> [FoodDetection] {
        guard let model else { throw DetectorError.modelMissing }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:]).perform([request])
        return (request.results as? [VNRecognizedObjectObservation] ?? []).compactMap { observation in
            guard let label = observation.labels.first, label.confidence > 0 else { return nil }
            let box = observation.boundingBox
            return FoodDetection(
                label: label.identifier,
                confidence: Double(label.confidence),
                boundingBox: NormalizedFoodRect(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height)
            )
        }
    }
}
