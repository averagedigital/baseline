import AthleteStore
import Foundation

enum StoreFactory {
    static func open() throws -> AthleteStore {
        let manager = FileManager.default
        let root = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "Baseline", directoryHint: .isDirectory)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        return try AthleteStore(path: root.appending(path: "baseline.sqlite").path)
    }
}

enum DeviceIdentity {
    private static let key = "baseline.device.user-id"

    static var userID: String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}
