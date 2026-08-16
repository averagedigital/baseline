import Foundation
import Security

struct APIKeyStore: Sendable {
    func save(_ value: String, providerID: UUID) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: providerID.uuidString, kSecValueData as String: data]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw APIKeyStoreError.status(status) }
    }

    func load(providerID: UUID) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: providerID.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIKeyStoreError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    func delete(providerID: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: providerID.uuidString]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIKeyStoreError.status(status) }
    }
}

enum APIKeyStoreError: Error, Equatable { case status(OSStatus) }
