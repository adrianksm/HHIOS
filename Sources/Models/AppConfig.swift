import Foundation

/// App configuration from `GET /api/config` (public). Drives depot defaults
/// and pricing display.
struct AppConfig: Codable, Hashable {
    struct Depot: Codable, Hashable {
        let name: String?
        let postcode: String?
    }
    struct Pricing: Codable, Hashable {
        let base: Double?
        let perMile: Double?
    }
    struct CRMS: Codable, Hashable {
        let subdomain: String?
    }

    let defaultDepot: Depot?
    let pricing: Pricing?
    let crms: CRMS?
    /// Per-load furniture capacities, keyed by normalised transport (HGV/LGV/VAN)
    /// then furniture name → max units on one load. Drives the load allocator.
    let furnitureCapacities: [String: [String: Double]]?

    static let empty = AppConfig(defaultDepot: nil, pricing: nil, crms: nil, furnitureCapacities: nil)
}
