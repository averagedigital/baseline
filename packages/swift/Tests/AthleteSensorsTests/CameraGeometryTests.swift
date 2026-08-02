import AthleteSensors
import Testing

@Test("Vision coordinates переводятся из lower-left в экранные top-left")
func convertsVisionCoordinates() {
    let point = NormalizedPosePoint(x: 0.2, y: 0.75, confidence: 0.9)

    let display = CameraGeometry(isMirrored: false).displayPoint(for: point)

    #expect(display.x == 0.2)
    #expect(display.y == 0.25)
}

@Test("Mirroring меняет только координату, а не left/right joint")
func mirroringPreservesJointIdentity() {
    let sample = PoseSample(
        joint: .leftShoulder,
        point: NormalizedPosePoint(x: 0.2, y: 0.75, confidence: 0.9)
    )

    let mirrored = CameraGeometry(isMirrored: true).displaySample(for: sample)

    #expect(mirrored.joint == .leftShoulder)
    #expect(mirrored.point.x == 0.8)
    #expect(mirrored.point.y == 0.25)
}

@Test("Causal smoother использует только прошлое и текущий frame")
func smoothsPoseCausally() {
    var smoother = PoseSmoother(alpha: 0.25)
    let first = PoseSample(
        joint: .root,
        point: NormalizedPosePoint(x: 0, y: 0, confidence: 1)
    )
    let second = PoseSample(
        joint: .root,
        point: NormalizedPosePoint(x: 1, y: 1, confidence: 0.8)
    )

    #expect(smoother.smooth(first).point.x == 0)
    let result = smoother.smooth(second)
    #expect(result.point.x == 0.25)
    #expect(result.point.y == 0.25)
    #expect(result.point.confidence == 0.8)
}
