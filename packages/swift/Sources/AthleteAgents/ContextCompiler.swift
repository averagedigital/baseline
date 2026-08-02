import AthleteCore

public struct CompiledContext: Equatable, Sendable {
    public let fragments: [ContextFragment]
    public let estimatedTokenCount: Int

    public init(fragments: [ContextFragment], estimatedTokenCount: Int) {
        self.fragments = fragments
        self.estimatedTokenCount = estimatedTokenCount
    }
}

public struct ContextCompiler: Sendable {
    public init() {}

    public func compile(fragments: [ContextFragment], tokenBudget: Int) throws -> CompiledContext {
        guard tokenBudget >= 0 else {
            throw ContextCompilerError.invalidTokenBudget
        }

        var seenIDs: Set<String> = []
        let unique = fragments.filter { seenIDs.insert($0.id).inserted }
        let prioritized = unique.enumerated().sorted { left, right in
            let leftCoverage = left.element.purpose == .coverage
            let rightCoverage = right.element.purpose == .coverage
            if leftCoverage != rightCoverage { return leftCoverage }
            return left.offset < right.offset
        }.map(\.element)

        let requiredCoverageTokens = prioritized
            .filter { $0.purpose == .coverage }
            .reduce(0) { $0 + $1.estimatedTokenCount }
        guard requiredCoverageTokens <= tokenBudget else {
            throw ContextCompilerError.insufficientCoverageBudget(
                required: requiredCoverageTokens,
                available: tokenBudget
            )
        }

        var selected: [ContextFragment] = []
        var total = 0
        for fragment in prioritized where total + fragment.estimatedTokenCount <= tokenBudget {
            selected.append(fragment)
            total += fragment.estimatedTokenCount
        }
        return CompiledContext(fragments: selected, estimatedTokenCount: total)
    }
}

public enum ContextCompilerError: Error, Equatable, Sendable {
    case invalidTokenBudget
    case insufficientCoverageBudget(required: Int, available: Int)
}
