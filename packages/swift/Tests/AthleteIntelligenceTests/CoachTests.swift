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
