import Foundation
import Security

/// Secrets are scoped to connection ID AND canonical endpoint. Editing the URL never
/// silently sends an existing credential to a different endpoint.
///
/// The service prefix and the bundle identifier still read `app.nativechat.NativeChat`,
/// from the app's former name. They are opaque lookup keys: renaming them would orphan
/// every stored key and move the App Sandbox container, so they only change together
/// with a migration.
struct KeychainStore {
    private func query(_ connection: ProviderConnection) throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.nativechat.NativeChat.connection.\(connection.id.uuidString)",
         kSecAttrAccount as String: try EndpointPolicy.baseURL(connection.endpoint).absoluteString]
    }
    func read(_ connection: ProviderConnection) throws -> String? {
        var query = try query(connection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw error(status) }
        return String(data: data, encoding: .utf8)
    }
    /// Replaces rather than updates. An item written by a previous signature can be
    /// deleted but not updated, so deleting first makes re-entering a key a reliable
    /// repair instead of failing with the same authorisation error.
    func save(_ value: String, for connection: ProviderConnection) throws {
        let query = try query(connection)
        let deleted = SecItemDelete(query as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw error(deleted) }
        var new = query
        new[kSecValueData as String] = Data(value.utf8)
        new[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let inserted = SecItemAdd(new as CFDictionary, nil)
        guard inserted == errSecSuccess else { throw error(inserted) }
    }
    func deleteAll(for connectionID: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.nativechat.NativeChat.connection.\(connectionID.uuidString)"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
    private func error(_ status: OSStatus) -> ChatError {
        if status == errSecAuthFailed {
            return .storage("This key was stored by an earlier build of the app and can no longer be read. Open Settings, edit the connection and paste the key again to replace it.")
        }
        return .storage("Keychain access failed (\(status)). Check the app's signing and Keychain permissions.")
    }
}
