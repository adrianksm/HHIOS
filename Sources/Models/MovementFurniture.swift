import Foundation

/// A per-movement furniture override row, from `GET /api/jobs/:id/movement-furniture`.
/// Any rows here pin that load's contents; loads without rows auto-allocate.
struct MovementFurnitureRow: Codable, Hashable {
    let jobId: Int?
    let transportName: String?
    let movementIndex: Int
    let furnitureName: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case transportName = "transport_name"
        case movementIndex = "movement_index"
        case furnitureName = "furniture_name"
        case quantity
    }
}
