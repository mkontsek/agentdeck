import Foundation
import LocalAuthentication
import Security

enum NoninteractiveKeychain {
    /// Called only by the serialized credential cache on its utility task.
    static func data(service: String) throws -> Data? {
        try withoutInteraction(
            getAllowed: {
                var allowed: DarwinBoolean = false
                guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess else { return nil }
                return allowed.boolValue
            }, setAllowed: { SecKeychainSetUserInteractionAllowed($0) == errSecSuccess },
            read: {
                let context = LAContext()
                context.interactionNotAllowed = true
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: context,
                ]
                var result: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
                return result as? Data
            })
    }

    // LAContext does not suppress legacy login-keychain ACL/unlock dialogs. The deprecated
    // Security framework interaction switch is still needed for those items on supported macOS.
    // Never leave it changed, never weaken an ACL, and never read if suppression fails.
    static func withoutInteraction<T>(getAllowed: () -> Bool?, setAllowed: (Bool) -> Bool, read: () throws -> T) throws
        -> T
    {
        guard let previous = getAllowed(), setAllowed(false) else {
            throw UsageParseError.unavailable("Keychain access could not be made noninteractive.")
        }
        defer { _ = setAllowed(previous) }
        return try read()
    }
}
