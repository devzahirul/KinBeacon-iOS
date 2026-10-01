import Domain
import Foundation

// Parameters of the `kinbeacon` RPCs. Swift-cased properties, Postgres-cased wire names.

struct RespondParams: Encodable {
    let requestID: UUID
    let approve: Bool

    enum CodingKeys: String, CodingKey {
        case approve
        case requestID = "request_id"
    }
}

struct CreateFamilyParams: Encodable {
    let familyName: String
    let parentName: String
    let relationship: String?
    let avatarEmoji: String

    enum CodingKeys: String, CodingKey {
        case relationship
        case familyName = "family_name", parentName = "parent_name", avatarEmoji = "avatar_emoji"
    }
}

struct RedeemParams: Encodable {
    let pairingCode: String
    let deviceModel: String

    enum CodingKeys: String, CodingKey {
        case pairingCode = "pairing_code", deviceModel = "device_model"
    }
}

struct InviteParams: Encodable {
    let childName: String
    let age: Int?
    let grade: Int?
    let avatarEmoji: String
    let avatarPalette: Int
    let controls: ControlsConfiguration

    enum CodingKeys: String, CodingKey {
        case age, grade, controls
        case childName = "child_name", avatarEmoji = "avatar_emoji", avatarPalette = "avatar_palette"
    }
}

struct RefreshInviteParams: Encodable {
    let childMember: String

    enum CodingKeys: String, CodingKey {
        case childMember = "child_member"
    }
}
