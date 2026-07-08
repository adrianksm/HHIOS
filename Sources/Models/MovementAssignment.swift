import Foundation

/// A per-movement assignment row, from `GET /api/jobs/:id/movements`.
/// A job's transport_items expand into movements; this overlays haulier/status/
/// notes/date onto a specific (transport_name, movement_index).
struct MovementAssignment: Codable, Identifiable, Hashable {
    let id: Int
    let jobId: Int
    let transportName: String?
    let movementIndex: Int
    let haulierId: Int?
    let notes: String?
    let statusRaw: String?
    let date: String?
    // Joined haulier fields, present in the /api/jobs?include_movements response.
    let haulierName: String?
    let haulierColor: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case transportName = "transport_name"
        case movementIndex = "movement_index"
        case haulierId = "haulier_id"
        case notes
        case statusRaw = "status"
        case date
        case haulierName = "haulier_name"
        case haulierColor = "haulier_color"
    }

    var status: JobStatus { JobStatus(apiValue: statusRaw) }
}
