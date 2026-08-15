import Testing
@testable import AthleteIntelligence

@Test func groundingRejectsWrongNumber() {
    let facts = [GroundedFact(id: "active", value: "8", numericValue: 8)]
    let output = CoachOutput(claims: [CoachClaim(text: "999 blocks", factIDs: ["active"], epistemicType: .computed)])
    #expect(throws: GroundingError.numericMismatch("999 blocks")) { try GroundingValidator().validate(output, facts: facts) }
}

@Test func groundingAcceptsReferencedNumber() throws {
    let facts = [GroundedFact(id: "active", value: "8", numericValue: 8)]
    let output = CoachOutput(claims: [CoachClaim(text: "8 blocks", factIDs: ["active"], epistemicType: .computed)])
    try GroundingValidator().validate(output, facts: facts)
}

@Test func contextAssemblerProducesOnlyTypedLocalFacts() {
    let context = CoachContextAssembler().assemble(
        session: SessionFacts(activeMinutes: 12, activeBlocks: 3, coverage: 0.8),
        personalization: PersonalizationFacts(predictedDifficulty: 7.5),
        food: FoodFacts(caloriesMidpoint: nil)
    )
    #expect(context.facts.map(\.id) == ["session.active_minutes", "session.active_blocks", "session.coverage", "personalization.predicted_difficulty"])
    #expect(context.facts.last?.numericValue == 7.5)
}

@Test func unavailableCoachDoesNotFabricateAnswer() async {
    do {
        _ = try await UnavailableCoachGenerator().generate(request: CoachGenerationRequest(prompt: "test", facts: []))
        Issue.record("unavailable coach returned an answer")
    } catch {
        #expect(error as? CoachGenerationError == .unavailable)
    }
}
