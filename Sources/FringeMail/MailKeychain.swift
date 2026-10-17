import Foundation
import Security

/// The Gmail app password as a generic password item, one per address. The only place it is stored.
struct MailKeychain: Sendable {
    static let service = "local.daniil.fringe.gmail"
    var service = MailKeychain.service

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func save(password: String, account: String) throws(MailError) {
        let data = Data(password.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Fringe Gmail app password"
            // Available after the first unlock so the connection can come back after wake.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func password(account: String) throws(MailError) -> String {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw .missingPassword }
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw .keychain(status)
        }
        return password
    }

    /// Checks presence without reading the secret.
    func hasPassword(account: String) -> Bool {
        var query = query(account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
