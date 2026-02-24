//
//  KeychainHelper.swift
//  RoleAutomator
//
//  Secure storage for Jamf Pro credentials (URL, username, password).
//

import Foundation
import Security

enum KeychainHelper {
    private static let service = "RoleAutomator-JamfPro"

    static func save(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status)
        }
    }

    static func load(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unableToLoad(status)
        }
        return string
    }

    static func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete(status)
        }
    }

    enum KeychainError: Error, LocalizedError {
        case unableToSave(OSStatus)
        case unableToLoad(OSStatus)
        case unableToDelete(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unableToSave(let s): return "Keychain save failed (\(s))"
            case .unableToLoad(let s): return "Keychain load failed (\(s))"
            case .unableToDelete(let s): return "Keychain delete failed (\(s))"
            }
        }
    }
}
