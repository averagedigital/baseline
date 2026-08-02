import Foundation
import Security

enum APIKeyStoreError: Error, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidValue
}

struct APIKeyStore: Sendable {
    private let service = "org.averagedigital.baseline.responses-api"

    func save(_ key: String, providerID: UUID) throws {
        guard let data = key.data(using: .utf8) else {
            throw APIKeyStoreError.invalidValue
        }
        let query = baseQuery(providerID: providerID)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update = [kSecValueData: data] as CFDictionary
            let updateStatus = SecItemUpdate(query as CFDictionary, update)
            guard updateStatus == errSecSuccess else {
                throw APIKeyStoreError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecItemNotFound else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.unexpectedStatus(addStatus)
        }
    }

    func load(providerID: UUID) throws -> String? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidValue
        }
        return key
    }

    func delete(providerID: UUID) throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(providerID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: providerID.uuidString,
        ]
    }
}
