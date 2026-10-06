import Foundation
import Security

nonisolated enum ABSCredentialStoreError: Error {
    case keychain(OSStatus)
}

nonisolated struct ABSKeychainCredentialStore: ABSCredentialStoring {
    private let service = ABSKeychainCredentialStore.serviceName

    static var serviceName: String {
        #if DEBUG
        // E2E fixture runs keep their own login, so a test server never replaces a real one and
        // `-e2e-reset-fixture` can forget it without touching the user's connection.
        if ProcessInfo.processInfo.arguments.contains("-e2e-fixture") {
            return "andreibaludev.Pageless.audiobookshelf.e2e"
        }
        #endif
        return "andreibaludev.Pageless.audiobookshelf"
    }
    private let account = "connection"

    func load() throws -> ABSConnection? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ABSCredentialStoreError.keychain(status) }
        guard let data = result as? Data else { throw AudiobookshelfError.unreadableResponse }
        do { return try JSONDecoder().decode(ABSConnection.self, from: data) }
        catch { throw AudiobookshelfError.unreadableResponse }
    }

    func save(_ connection: ABSConnection) throws {
        let data = try JSONEncoder().encode(connection)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updated = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updated == errSecSuccess else { throw ABSCredentialStoreError.keychain(updated) }
        } else if status != errSecSuccess {
            throw ABSCredentialStoreError.keychain(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ABSCredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
