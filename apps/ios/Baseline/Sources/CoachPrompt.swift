import Foundation

enum CoachPrompt {
    static let version = "coach-v3"
    static let instructions: String = {
        guard let url = Bundle.main.url(forResource: "CoachPrompt", withExtension: "txt"),
              let prompt = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("CoachPrompt.txt is missing from the app bundle")
        }
        return prompt
    }()
}
