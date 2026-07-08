import Foundation

/// Result of `POST /api/sync` (Current-RMS sync).
struct SyncResult: Codable {
    let success: Bool?
    let synced: Int?
    let archived: Int?
    let message: String?

    var displayMessage: String {
        if let message, !message.isEmpty { return message }
        let parts = [synced.map { "\($0) synced" }, archived.map { "\($0) archived" }].compactMap { $0 }
        return parts.isEmpty ? "Sync complete." : parts.joined(separator: ", ")
    }
}
