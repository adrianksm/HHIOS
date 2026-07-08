import Foundation

/// The signed-in user, from `POST /api/auth/login` and `GET /api/auth/me`.
struct AuthUser: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let roleRaw: String?
    let haulierId: Int?

    enum CodingKeys: String, CodingKey {
        case id, username
        case roleRaw = "role"
        case haulierId = "haulier_id"
    }

    var role: UserRole { UserRole(apiValue: roleRaw) }
}
