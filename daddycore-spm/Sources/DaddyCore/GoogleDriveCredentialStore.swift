import Foundation
import LocalAuthentication
import Security

/// Holds the one secret this app needs to remember across launches: the
/// Google OAuth refresh token. The short-lived access token it mints is
/// never persisted — it expires in about an hour and is trivially re-derived
/// from the refresh token, so keeping it in memory only is simpler and one
/// less place for a stale credential to linger.
///
/// Touch ID guards the token, but through `authenticate()` in front of the
/// read rather than an ACL on the keychain item — see `saveRefreshToken` for
/// why the item itself cannot carry one without a provisioning profile.
///
/// Either way it depends on a stable code signature: the keychain binds its
/// ACLs to the signing identity, and an ad-hoc one changes every build, which
/// is what made this prompt for the login password constantly. See `bundle.sh`.
public final class GoogleDriveCredentialStore: @unchecked Sendable {
    private static let service = "com.daddy.app.googledrive"
    private static let account = "refresh_token"

    public init() {}

    public enum CredentialError: LocalizedError {
        case keychainError(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .keychainError(let status):
                return "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            }
        }
    }

    @discardableResult
    public func saveRefreshToken(_ token: String) -> Result<Void, CredentialError> {
        // A plain item, deliberately.
        //
        // The obvious design is `kSecAttrAccessControl` with `.userPresence`,
        // which puts Touch ID on the item itself. On macOS that cannot work
        // here: setting access control implicitly moves the item to the
        // data-protection keychain, which requires an `application-identifier`
        // entitlement — an App ID and an embedded provisioning profile. Without
        // one every write fails with -34018, and because the caller discards
        // this Result it fails invisibly, leaving the UI claiming "connected"
        // over a token that was never stored.
        //
        // So the fingerprint is enforced in front of the read instead, by
        // `authenticate()`. Same gate, no entitlement. What makes the plain
        // item safe to leave unprompted is the stable code signature from
        // `bundle.sh`: the keychain stops re-asking on every rebuild.
        SecItemDelete(baseQuery() as CFDictionary)

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = Data(token.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            let message = SecCopyErrorMessageString(addStatus, nil) as String? ?? "unknown"
            log("save failed (\(addStatus)): \(message)")
            return .failure(.keychainError(addStatus))
        }
        log("saved refresh token")
        return .success(())
    }

    /// Whether a token is stored, without reading it.
    ///
    /// Attributes only — no `kSecReturnData` — so this never prompts. Lets the
    /// UI say "connected" at launch without demanding a fingerprint from
    /// someone who only opened the settings drawer.
    public func hasStoredToken() -> Bool {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// The Touch ID gate, with the login password as the system's fallback.
    ///
    /// `.deviceOwnerAuthentication` rather than `…WithBiometrics`, so a Mac
    /// with no Touch ID — or a finger it will not read — still has a way in.
    public func authenticate(reason: String = "unlock your Google Drive connection") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password…"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            log("cannot authenticate: \(authError?.localizedDescription ?? "unknown")")
            return false
        }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            log("authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Why a load came back empty.
    ///
    /// The three cases used to be one `nil`, which made "you never connected"
    /// indistinguishable from "you cancelled Touch ID" — so a cancelled prompt
    /// looked exactly like a fresh install while the UI still said connected.
    public enum LoadFailure: Error, Equatable {
        case noStoredToken
        case authenticationFailed(OSStatus)
    }

    public func loadRefreshToken() -> String? {
        try? loadRefreshTokenOrFail().get()
    }

    public func loadRefreshTokenOrFail() -> Result<String, LoadFailure> {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                return .failure(.noStoredToken)
            }
            return .success(token)
        case errSecItemNotFound:
            log("no stored token")
            return .failure(.noStoredToken)
        default:
            // errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed
            // (a read attempted somewhere that cannot show a prompt) all land
            // here. Worth saying out loud — silently treating them as "not
            // connected" is what made this invisible.
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
            log("keychain read failed (\(status)): \(message)")
            return .failure(.authenticationFailed(status))
        }
    }

    /// stderr, not `print`.
    ///
    /// stdout is block-buffered when it is a pipe rather than a terminal, so
    /// running the app with `… | grep` held every diagnostic in the buffer
    /// until the process exited — which is precisely when they stop being
    /// useful. stderr is unbuffered.
    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[drive] \(message)\n".utf8))
    }

    public func deleteRefreshToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
            // Deliberately NOT `kSecUseDataProtectionKeychain`.
            //
            // The modern keychain looks like the right home for a
            // `.userPresence` item, but on macOS it requires an
            // `application-identifier` entitlement — which means registering an
            // App ID and embedding a provisioning profile. Without one,
            // `SecItemAdd` fails with -34018 (errSecMissingEntitlement) and,
            // because the caller discards the Result, the token silently never
            // saves while the UI still reports "connected".
            //
            // The legacy login keychain honours a `.userPresence` ACL with no
            // entitlement at all, and macOS satisfies it with Touch ID. That is
            // what a non-sandboxed personal Mac app wants.
        ]
    }
}
