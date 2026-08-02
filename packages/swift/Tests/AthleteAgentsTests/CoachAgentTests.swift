import AthleteAgents
import AthleteCore
import Testing

@Test("Coach создаёт proposal, но не меняет план")
func coachCreatesProposalWithoutActivation() async throws {
    let provider = MockProvider(responses: [AgentResponse(
        text: "Предлагаю сохранить отдых между подходами.",
        providerID: "mock",
        modelID: "mock-coach",
        planProposalMarkdown: "Отдых между тяжёлыми подходами: 180 секунд."
    )])
    let coach = CoachAgent(provider: provider)
    let ledger = PlanLedger()

    let turn = try await coach.respond(context: "Текущий план без изменений.", promptVersion: "coach-v1")
    if let proposal = turn.planProposal {
        await ledger.submit(proposal)
    }

    #expect(turn.planProposal != nil)
    #expect(await ledger.activePlan == nil)
}

@Test("План активируется только после явного approve")
func approvalActivatesPlan() async throws {
    let proposal = PlanProposal(markdown: "Отдых: 180 секунд.", evidenceIDs: [])
    let ledger = PlanLedger()
    await ledger.submit(proposal)

    let event = try await ledger.approve(proposalID: proposal.id)

    #expect(event.decision == .approved)
    #expect(await ledger.activePlan?.markdown == proposal.markdown)
}

@Test("Reject не меняет активный план")
func rejectionDoesNotActivatePlan() async throws {
    let proposal = PlanProposal(markdown: "Изменить объём.", evidenceIDs: [])
    let ledger = PlanLedger()
    await ledger.submit(proposal)

    let event = try await ledger.reject(proposalID: proposal.id)

    #expect(event.decision == .rejected)
    #expect(await ledger.activePlan == nil)
}
