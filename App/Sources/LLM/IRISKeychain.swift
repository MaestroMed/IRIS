import Foundation
import Security

/// Helper Keychain pour stocker secrets sensibles (API keys, tokens).
/// Service : "app.iris.macos.secrets". Items stockés sous account="<service-name>".
///
/// API key Anthropic = item account="anthropic-api-key".
/// API key Gemini    = item account="gemini-api-key".  (v1.338)
/// Phases suivantes :
/// - v0.3 : tokens OAuth Gmail / Calendar / GitHub
/// - v0.5 : access tokens MCP server custom

public final class IRISKeychain: @unchecked Sendable {
    public static let shared = IRISKeychain()

    private let service = "app.iris.macos.secrets"
    private let anthropicAccount = "anthropic-api-key"
    private let geminiAccount = "gemini-api-key"

    private init() {}

    // MARK: — Anthropic API key

    public func setAnthropicAPIKey(_ key: String) -> Bool {
        store(value: key, account: anthropicAccount)
    }

    public func getAnthropicAPIKey() -> String? {
        retrieve(account: anthropicAccount)
    }

    public func deleteAnthropicAPIKey() -> Bool {
        delete(account: anthropicAccount)
    }

    public func hasAnthropicAPIKey() -> Bool {
        getAnthropicAPIKey() != nil
    }

    // MARK: — Gemini API key (v1.338)

    public func setGeminiAPIKey(_ key: String) -> Bool {
        store(value: key, account: geminiAccount)
    }

    public func getGeminiAPIKey() -> String? {
        retrieve(account: geminiAccount)
    }

    public func deleteGeminiAPIKey() -> Bool {
        delete(account: geminiAccount)
    }

    public func hasGeminiAPIKey() -> Bool {
        getGeminiAPIKey() != nil
    }

    // MARK: — Generic store / retrieve / delete

    @discardableResult
    public func store(value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing first (Keychain refuse l'overwrite via SecItemAdd)
        _ = delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func retrieve(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
