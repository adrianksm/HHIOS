import Foundation

/// A haulier/driver, from `GET /api/hauliers`.
struct Haulier: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
    let activeRaw: Int?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case activeRaw = "active"
        case phone
    }

    var isActive: Bool { (activeRaw ?? 1) != 0 }

    var phoneDigits: String? { phone?.phoneDigits }
}
