import Foundation
import Security

struct APIKeyStore: Sendable {
    private let service = "org.averagedigital.baseline.responses-api"

    func save(_ value: String, providerID: UUID) throws {
        let data = Data(value.utf8)
        var query = baseQuery(providerID: providerID)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIKeyStoreError.status(status) }
    }

    func load(providerID: UUID) throws -> String? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIKeyStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    func delete(providerID: UUID) throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIKeyStoreError.status(status) }
    }

    private func baseQuery(providerID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.uuidString,
        ]
    }
}

enum APIKeyStoreError: Error, Equatable { case status(OSStatus) }
