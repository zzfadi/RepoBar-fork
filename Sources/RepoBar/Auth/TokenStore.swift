import Foundation
import Security

struct OAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
}

enum TokenStoreError: Error {
    case saveFailed
    case loadFailed
}

struct TokenStore {
    static let shared = TokenStore()
    private let service = "com.steipete.repobar.auth"

    func save(tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.saveFailed }
    }

    func load() throws -> OAuthTokens? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw TokenStoreError.loadFailed }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func clear() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
