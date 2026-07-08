import Foundation

/// Workflow status of a job/movement. Mirrors the `status` column
/// (pending | booked | completed). Unknown/missing values fall back to pending.
enum JobStatus: String, CaseIterable, Codable, Identifiable {
    case pending
    case booked
    case completed

    var id: String { rawValue }

    init(apiValue: String?) {
        self = JobStatus(rawValue: apiValue ?? "") ?? .pending
    }

    var label: String {
        switch self {
        case .pending:   return "Pending"
        case .booked:    return "Booked"
        case .completed: return "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .pending:   return "clock"
        case .booked:    return "checkmark.circle"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// Whether the job takes furniture out (delivery) or brings it back (collection).
enum JobType: String, CaseIterable, Codable, Identifiable {
    case delivery
    case collection

    var id: String { rawValue }

    init(apiValue: String?) {
        self = JobType(rawValue: apiValue ?? "") ?? .delivery
    }

    var label: String {
        switch self {
        case .delivery:   return "Delivery"
        case .collection: return "Collection"
        }
    }

    var systemImage: String {
        switch self {
        case .delivery:   return "arrow.up.right.circle.fill"
        case .collection: return "arrow.down.left.circle.fill"
        }
    }
}

/// User role from the session (admin | basic | haulier).
enum UserRole: String, Codable {
    case admin
    case basic
    case haulier
    case unknown

    init(apiValue: String?) {
        self = UserRole(rawValue: apiValue ?? "") ?? .unknown
    }

    var isAdmin: Bool { self == .admin }
}
