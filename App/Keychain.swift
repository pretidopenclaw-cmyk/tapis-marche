import Foundation
import Security

/// The Notion integration token lives only here (spec: never in a file or UserDefaults).
enum Keychain {
    private static let service = "TapisMarche.notion"
    private static let account = "token"

    struct WriteError: Error { let status: OSStatus }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var item: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String) throws {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw WriteError(status: status) }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
