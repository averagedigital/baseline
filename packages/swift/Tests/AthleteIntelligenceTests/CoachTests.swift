import Testing
@testable import AthleteIntelligence

@Test func groundingRejectsWrongNumber() {
    let facts: [GroundedFact] = [.number("active", 8)]
    let output = CoachOutput(claims: [CoachClaim(text: "999 blocks", factIDs: ["active"], epistemicType: .computed)])
    #expect(throws: GroundingError.numericMismatch("999 blocks")) { try GroundingValidator().validate(output, facts: facts) }
}

@Test func groundingAcceptsReferencedNumber() throws {
    let facts: [GroundedFact] = [.number("active", 8)]
    let output = CoachOutput(claims: [CoachClaim(text: "8 blocks", factIDs: ["active"], epistemicType: .computed)])
    try GroundingValidator().validate(output, facts: facts)
}

@Test func contextAssemblerProducesOnlyTypedLocalFacts() {
    let context = CoachContextAssembler().assemble(
        session: SessionFacts(activeMinutes: 12, activeBlocks: 3, coverage: 0.8),
        personalization: PersonalizationFacts(predictedDifficulty: 7.5),
        food: FoodFacts(caloriesMidpoint: nil)
    )
    #expect(context.facts.map(\.id) == ["session:latest:active_minutes", "session:latest:active_blocks", "session:latest:tracking_coverage", "personalization.predicted_difficulty"])
    #expect(context.facts.last?.numberValue == 7.5)
}

@Test func unavailableCoachDoesNotFabricateAnswer() async {
    do {
        _ = try await UnavailableCoachGenerator().generate(request: CoachGenerationRequest(prompt: "test", facts: []))
        Issue.record("unavailable coach returned an answer")
    } catch {
        #expect(error as? CoachGenerationError == .unavailable)
    }
}

@Test func duplicateFactIDIsAControlledValidationError() {
    let output = CoachOutput(claims: [CoachClaim(text: "8", factIDs: ["same"], epistemicType: .observed)])
    #expect(throws: GroundingError.duplicateFactID("same")) {
        try GroundingValidator().validate(output, facts: [.number("same", 8), .number("same", 8)])
    }
}

@Test func percentageGroundingUsesFractionalCanonicalValue() throws {
    let validator = GroundingValidator()
    try validator.validate(
        CoachOutput(claims: [CoachClaim(text: "Покрытие составило 80%.", factIDs: ["coverage"], epistemicType: .observed)]),
        facts: [.number("coverage", 0.8)]
    )
    #expect(throws: GroundingError.numericMismatch("Покрытие составило 85%.")) {
        try validator.validate(
            CoachOutput(claims: [CoachClaim(text: "Покрытие составило 85%.", factIDs: ["coverage"], epistemicType: .observed)]),
            facts: [.number("coverage", 0.8)]
        )
    }
}

@Test func numericRangeRequiresBothGroundedEndpoints() throws {
    let validator = GroundingValidator()
    try validator.validate(
        CoachOutput(claims: [CoachClaim(text: "RPE был 8–10", factIDs: ["low", "high"], epistemicType: .computed)]),
        facts: [.number("low", 8), .number("high", 10)]
    )
    #expect(throws: GroundingError.numericMismatch("RPE был 8–10")) {
        try validator.validate(
            CoachOutput(claims: [CoachClaim(text: "RPE был 8–10", factIDs: ["low"], epistemicType: .computed)]),
            facts: [.number("low", 8)]
        )
    }
}

@Test func coachOrchestratorRepairsExactlyOnceWithPreviousOutput() async throws {
    let generator = ScriptedCoachGenerator(responses: [
        CoachOutput(claims: [CoachClaim(text: "999", factIDs: ["active"], epistemicType: .computed)]),
        CoachOutput(claims: [CoachClaim(text: "8", factIDs: ["active"], epistemicType: .computed)])
    ])
    let result = try await CoachOrchestrator(generator: generator).generate(
        request: CoachGenerationRequest(prompt: "Почему?", facts: [.number("active", 8)])
    )
    #expect(result.claims.first?.text == "8")
    let requests = await generator.requests
    #expect(requests.count == 2)
    #expect(requests[1].prompt.contains("PREVIOUS_OUTPUT"))
    #expect(requests[1].prompt.contains("numericMismatch"))
}

@Test func coachOrchestratorDoesNotRepairGenerationFailure() async {
    let generator = ScriptedCoachGenerator(error: .unsupportedLocale)
    await #expect(throws: CoachGenerationError.unsupportedLocale) {
        _ = try await CoachOrchestrator(generator: generator).generate(
            request: CoachGenerationRequest(prompt: "Запрос", facts: [])
        )
    }
    #expect(await generator.requests.count == 1)
}

@Test func coachOrchestratorRejectsSecondInvalidOutput() async {
    let generator = ScriptedCoachGenerator(responses: [
        CoachOutput(claims: [CoachClaim(text: "999", factIDs: ["active"], epistemicType: .computed)]),
        CoachOutput(claims: [CoachClaim(text: "1000", factIDs: ["active"], epistemicType: .computed)])
    ])
    await #expect(throws: GroundingError.self) {
        _ = try await CoachOrchestrator(generator: generator).generate(
            request: CoachGenerationRequest(prompt: "Сравни", facts: [.number("active", 8)])
        )
    }
    #expect(await generator.requests.count == 2)
}

private actor ScriptedCoachGenerator: CoachGenerating {
    var responses: [CoachOutput]
    let error: CoachGenerationError?
    private(set) var requests: [CoachGenerationRequest] = []

    init(responses: [CoachOutput] = [], error: CoachGenerationError? = nil) {
        self.responses = responses
        self.error = error
    }

    func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        requests.append(request)
        if let error { throw error }
        return responses.removeFirst()
    }
}
