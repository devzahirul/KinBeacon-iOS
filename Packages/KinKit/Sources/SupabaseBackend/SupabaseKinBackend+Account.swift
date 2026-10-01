public import Domain
import Foundation
import KinCore
import Security
import Supabase

extension SupabaseKinBackend: AccountService {
    public func restore() async -> AccountState {
        guard client.auth.currentSession != nil else { return .signedOut }
        do {
            return try await .member(membership())
        } catch KinError.notFound {
            return .signedInWithoutFamily
        } catch {
            // Offline at launch: keep the cached membership if we have one; the UI retries later.
            if let cached = DeviceMembershipCache.load() {
                return .member(cached)
            }
            return .signedOut
        }
    }

    public func signUp(name: String, email: String, password: String) async throws -> AccountState {
        stopAllLive()
        resetCaches()
        let response = try await call {
            try await self.client.auth.signUp(email: email, password: password, data: ["display_name": .string(name)])
        }
        guard response.session != nil else {
            throw KinError.authentication(String(localized: "Check your inbox to confirm your email, then sign in."))
        }
        return .signedInWithoutFamily
    }

    public func signIn(email: String, password: String) async throws -> AccountState {
        stopAllLive()
        try await call { _ = try await self.client.auth.signIn(email: email, password: password) }
        resetCaches()
        do {
            return try await .member(remember(membership()))
        } catch KinError.notFound {
            return .signedInWithoutFamily
        }
    }

    public func createFamily(name: String, parentName: String, relationship: String?) async throws -> FamilyMembership {
        let emoji = Self.parentEmoji(for: relationship)
        try await call {
            _ = try await self.client.rpc(
                "create_family",
                params: CreateFamilyParams(familyName: name, parentName: parentName, relationship: relationship, avatarEmoji: emoji)
            ).execute()
        }
        resetCaches()
        return try await remember(membership())
    }

    /// A child device gets its own auth account (random credentials kept in the Keychain), then redeems the code.
    /// No email or password is ever shown to — or needed from — the child.
    public func pairDevice(code: String, deviceModel: String) async throws -> FamilyMembership {
        // Always pair with a fresh device account. A session left in the Keychain (a parent who signed in on this
        // phone, or a previous pairing before a reinstall) must never be reused for a child — that would join the
        // wrong account or fail with "already paired".
        if client.auth.currentSession != nil {
            stopAllLive()
            try? await client.auth.signOut()
        }
        resetCaches()
        let credentials = DeviceCredentials.createFresh()
        try await call { _ = try await self.client.auth.signUp(email: credentials.email, password: credentials.password) }
        let digits = code.filter(\.isNumber)
        try await call {
            _ = try await self.client.rpc("redeem_pairing_code", params: RedeemParams(pairingCode: digits, deviceModel: deviceModel))
                .execute()
        }
        resetCaches()
        return try await remember(membership())
    }

    public func inviteChild(_ child: NewChild) async throws -> ChildInvite {
        let params = InviteParams(
            childName: child.name,
            age: child.age,
            grade: child.grade,
            avatarEmoji: child.avatar.emoji,
            avatarPalette: child.avatar.palette,
            controls: .defaults(for: "pending")
        )
        let rows: [InviteRow] = try await call { try await self.client.rpc("create_child_invite", params: params).execute().value }
        guard let row = rows.first, let member = row.memberID else { throw KinError.invalidResponse }
        try? await refresh()
        return ChildInvite(code: row.code, memberID: MemberID(rawValue: member), expiresAt: row.expiresAt)
    }

    public func refreshInvite(for member: MemberID) async throws -> ChildInvite {
        let rows: [InviteRow] = try await call {
            try await self.client.rpc("refresh_child_invite", params: RefreshInviteParams(childMember: member.rawValue)).execute().value
        }
        guard let row = rows.first else { throw KinError.invalidResponse }
        return ChildInvite(code: row.code, memberID: member, expiresAt: row.expiresAt)
    }

    public func registerPushToken(_ token: String, sandbox: Bool) async {
        guard let userID else { return }
        let row = DeviceTokenRow(userID: userID, token: token, environment: sandbox ? "sandbox" : "production")
        try? await call {
            _ = try await self.client.from("device_tokens").upsert(row, onConflict: "user_id,token", returning: .minimal).execute()
        }
    }

    public func signOut() async {
        stopAllLive()
        resetCaches()
        DeviceMembershipCache.clear()
        try? await client.auth.signOut()
    }

    public func deleteAccount() async throws {
        try await call { _ = try await self.client.rpc("delete_my_account").execute() }
        DeviceCredentials.clear()
        await signOut()
    }

    static func parentEmoji(for relationship: String?) -> String {
        switch relationship?.lowercased() {
        case "mom", "mother", "mum": "👩"
        case "dad", "father": "👨"
        default: "🧑"
        }
    }

    private func resetCaches() {
        state.withLock {
            $0.membership = nil
            $0.placesFetchedAt = .distantPast
        }
    }

    private func remember(_ membership: FamilyMembership) -> FamilyMembership {
        DeviceMembershipCache.save(membership)
        return membership
    }
}

/// Last known membership, so a device that launches offline still opens in the right role.
enum DeviceMembershipCache {
    private static let key = "kin.membership"

    static func load() -> FamilyMembership? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(FamilyMembership.self, from: $0) }
    }

    static func save(_ membership: FamilyMembership) {
        UserDefaults.standard.set(try? JSONEncoder().encode(membership), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Random per-device credentials for a child device's auth account, stored in the Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: available to background launches, never synced or backed up).
struct DeviceCredentials {
    let email: String
    let password: String

    private static let service = "com.lynkto.kinbeacon.device-account"

    static func createFresh() -> DeviceCredentials {
        let id = UUID().uuidString.lowercased()
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let credentials = DeviceCredentials(email: "device-\(id)@devices.kinbeacon.app", password: Data(bytes).base64EncodedString())
        save(credentials)
        return credentials
    }

    static func load() -> DeviceCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let pair = try? JSONDecoder().decode([String: String].self, from: data),
              let email = pair["email"], let password = pair["password"] else { return nil }
        return DeviceCredentials(email: email, password: password)
    }

    static func save(_ credentials: DeviceCredentials) {
        let data = (try? JSONEncoder().encode(["email": credentials.email, "password": credentials.password])) ?? Data()
        clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
